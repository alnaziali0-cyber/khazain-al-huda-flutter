import asyncio
from io import BytesIO
from pathlib import Path

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from starlette.datastructures import UploadFile
from starlette.requests import Request

from app import main
from app.core.config import Settings
from app.db.base import Base
from app.models import AdminAuditLog, AdminUser, MediaAsset
from app.services.pdf_text_worker import extract_pdf_text


PROJECT_ROOT = Path(__file__).resolve().parents[3]


def _sample_searchable_pdf() -> bytes:
    stream = b"BT /F1 12 Tf 24 100 Td (Hello PDF text) Tj ET\n"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 144] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"endstream",
    ]
    output = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = [0]
    for index, obj in enumerate(objects, start=1):
        offsets.append(len(output))
        output.extend(f"{index} 0 obj\n".encode())
        output.extend(obj)
        output.extend(b"\nendobj\n")
    xref_offset = len(output)
    output.extend(b"xref\n0 6\n0000000000 65535 f \n")
    for offset in offsets[1:]:
        output.extend(f"{offset:010d} 00000 n \n".encode())
    output.extend(b"trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n")
    output.extend(f"{xref_offset}\n%%EOF\n".encode())
    return bytes(output)


@pytest.fixture
def isolated_api_store(tmp_path, monkeypatch):
    root = tmp_path.resolve()
    assert not (root == PROJECT_ROOT or PROJECT_ROOT in root.parents)
    media_root = root / "media"
    settings = Settings(
        _env_file=None,
        app_env="test",
        database_url=f"sqlite:///{root / 'pdf-test.sqlite3'}",
        media_root=str(media_root),
        max_upload_bytes=15 * 1024 * 1024,
        pdf_text_extraction_enabled=True,
    )
    monkeypatch.setattr(main, "settings", settings)
    engine = create_engine(settings.database_url)
    Base.metadata.create_all(engine, tables=[AdminUser.__table__, MediaAsset.__table__, AdminAuditLog.__table__])
    session_factory = sessionmaker(bind=engine, expire_on_commit=False)
    db = session_factory()
    admin = AdminUser(
        username="pdf-test-owner",
        email="pdf-test@example.invalid",
        password_hash="unused-test-hash",
        force_password_change=False,
    )
    db.add(admin)
    db.commit()
    main._pdf_extraction_jobs.clear()
    main.sandbox_status.cache_clear()
    yield root, settings, db, admin
    for job in list(main._pdf_extraction_jobs.values()):
        task = job.get("task")
        if task is not None and not task.done():
            task.cancel()
    db.close()
    engine.dispose()
    main._pdf_extraction_jobs.clear()
    main.sandbox_status.cache_clear()


def _request() -> Request:
    return Request({
        "type": "http",
        "method": "POST",
        "path": "/api/v1/admin/media",
        "headers": [],
        "client": ("127.0.0.1", 12345),
        "server": ("testserver", 80),
        "scheme": "http",
        "query_string": b"",
    })


def test_pdf_worker_extracts_searchable_text_and_rejects_invalid_signature(isolated_api_store):
    root, _settings, _db, _admin = isolated_api_store
    work = root / "worker-test"
    work.mkdir()
    pdf_path = work / "sample.pdf"
    pdf_path.write_bytes(_sample_searchable_pdf())

    result = extract_pdf_text(pdf_path)
    assert result == {"ok": True, "page_count": 1, "text": "Hello PDF text", "page_texts": ["Hello PDF text"], "has_text": True}

    invalid_path = work / "not-a-pdf.pdf"
    invalid_path.write_bytes(b"not a PDF")
    with pytest.raises(ValueError, match="signature"):
        extract_pdf_text(invalid_path)


def test_upload_then_pdf_extraction_route_runs_in_isolated_worker(isolated_api_store):
    root, settings, db, admin = isolated_api_store
    ready, _bwrap = main.sandbox_status()
    if not ready:
        pytest.skip("Bubblewrap isolation is unavailable in this environment")
    assert root.is_relative_to(Path("/tmp").resolve())
    preexisting_job_dirs = set(Path("/tmp").glob("khazain-pdf-job-*"))
    request = _request()
    upload = UploadFile(filename="searchable.pdf", file=BytesIO(_sample_searchable_pdf()))

    async def upload_and_extract():
        uploaded = await main.admin_upload_media(request, upload, admin, db)
        started = await main.admin_start_pdf_extraction(uploaded["id"], request, admin, db)
        await main._pdf_extraction_jobs[started["id"]]["task"]
        return started["id"], main.admin_pdf_extraction_status(started["id"], admin)

    job_id, result = asyncio.run(upload_and_extract())
    assert result["status"] == "completed"
    assert result["text"] == "Hello PDF text"
    assert result["page_count"] == 1
    assert result["has_text"] is True
    assert main._pdf_extraction_jobs[job_id]["process"] is None
    assert set(Path("/tmp").glob("khazain-pdf-job-*")) <= preexisting_job_dirs
    assert settings.media_path.resolve().is_relative_to(root)


def test_pdf_route_fails_closed_when_disabled(isolated_api_store):
    _root, settings, db, admin = isolated_api_store
    settings.pdf_text_extraction_enabled = False
    with pytest.raises(HTTPException) as error:
        asyncio.run(main.admin_start_pdf_extraction(999, _request(), admin, db))
    assert error.value.status_code == 503
    assert main.admin_pdf_extraction_capabilities(admin) == {
        "enabled": False,
        "reason": "استخراج نص PDF معطّل بإعداد الخادم.",
    }


def test_pdf_route_fails_closed_when_sandbox_probe_fails(isolated_api_store):
    _root, _settings, db, admin = isolated_api_store
    with pytest.MonkeyPatch.context() as patch:
        patch.setattr(main, "sandbox_status", lambda: (False, None))
        with pytest.raises(HTTPException) as error:
            asyncio.run(main.admin_start_pdf_extraction(999, _request(), admin, db))
        assert error.value.status_code == 503
        assert main.admin_pdf_extraction_capabilities(admin) == {
            "enabled": False,
            "reason": "استخراج نص PDF غير متاح لأن عزل التنفيذ المطلوب غير جاهز.",
        }
