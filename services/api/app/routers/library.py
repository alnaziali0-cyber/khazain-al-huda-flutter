from __future__ import annotations

import asyncio
import json
import os
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote

from fastapi import APIRouter, Depends, File, Header, HTTPException, Query, UploadFile
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.dependencies import get_db
from app.core.security import keyed_hash
from app.models import Book, BookArtifact, BookEdition, BookImportJob, BookPage, BookTocEntry
from app.services.public_catalog import REUSABLE_RIGHTS_STATUSES
from app.services.shia_library_import_engine import (
    MAX_EXTRACTED_CHARS,
    MAX_IMPORT_BYTES,
    discover_sources,
    download_archive_file,
    extract_import_file,
    format_mime,
    safe_original_name,
    sha256_file,
    get_internet_archive_metadata,
    search_internet_archive,
)

router = APIRouter(prefix="/api/v1/public/library", tags=["public-library"])


def _device_hash(x_device_key: str = Header(default="", alias="X-Device-Key")) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_-]{32,128}", x_device_key or ""):
        raise HTTPException(status_code=422, detail="A valid X-Device-Key header is required")
    return keyed_hash(x_device_key)


class ImportPreviewPayload(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    source_key: str = Field(min_length=1, max_length=40)
    identifier: str = Field(min_length=5, max_length=180)


class ImportConfirmPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")
    confirm_personal_copy: bool


class LocalUploadMetadata(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    title: str = Field(min_length=1, max_length=250)
    author: str | None = Field(default=None, max_length=180)
    publisher: str | None = Field(default=None, max_length=180)
    source_url: str | None = Field(default=None, max_length=2048)


def _persist_edition_and_toc(
    db: Session,
    book: Book,
    metadata: dict,
    *,
    source_url: str | None,
    rights_status: str = "unverified",
    rights_evidence: str | None = None,
) -> None:
    edition = BookEdition(
        book_id=book.id,
        edition_label=metadata.get("edition_label"),
        publisher=metadata.get("publisher") or book.publisher,
        publication_year=metadata.get("publication_year") or metadata.get("year"),
        isbn=metadata.get("isbn"),
        printing_batch=metadata.get("printing_batch"),
        language=metadata.get("language"),
        source_url=source_url,
        rights_status=rights_status,
        rights_evidence=rights_evidence,
    )
    db.add(edition)
    db.flush()
    toc = metadata.get("table_of_contents")
    if not isinstance(toc, list):
        return
    source_ids: dict[str, int] = {}
    parent_sources: dict[int, str | None] = {}
    for index, raw in enumerate(toc[:1000]):
        if not isinstance(raw, dict):
            continue
        title = str(raw.get("title") or "").strip()[:500]
        if not title:
            continue
        volume = raw.get("volume_number", 1)
        volume_number = int(volume) if str(volume).isdigit() and int(volume) >= 1 else 1
        page = raw.get("page_number")
        page_number = int(page) if str(page or "").isdigit() and int(page) >= 1 else None
        source_id = str(raw.get("source_entry_id") or raw.get("id") or index)[:80]
        entry = BookTocEntry(
            book_id=book.id,
            edition_id=edition.id,
            volume_number=volume_number,
            title=title,
            page_number=page_number,
            page_label=str(raw.get("page_label") or "")[:80] or None,
            sort_order=int(raw.get("sort_order") or index),
            source_entry_id=source_id,
        )
        db.add(entry)
        db.flush()
        source_ids[source_id] = entry.id
        parent_value = raw.get("parent_source_entry_id", raw.get("parent_id"))
        parent_sources[entry.id] = str(parent_value) if parent_value is not None else None
    for entry_id, parent_source in parent_sources.items():
        if parent_source and parent_source in source_ids and source_ids[parent_source] != entry_id:
            db.query(BookTocEntry).filter(BookTocEntry.id == entry_id).update({"parent_id": source_ids[parent_source]}, synchronize_session=False)


def _job_json(row: BookImportJob) -> dict:
    return {
        "id": row.id,
        "source_key": row.source_key,
        "source_item_id": row.source_item_id,
        "title": row.title,
        "author": row.author,
        "source_url": row.source_url,
        "selected_file": row.selected_file,
        "file_format": row.file_format,
        "license_url": row.license_url,
        "rights_status": row.rights_status,
        "status": row.status,
        "progress": row.progress,
        "error_code": row.error_code,
        "book_id": row.book_id,
        "sha256": row.file_sha256,
        "details": row.details or {},
        "created_at": row.created_at.isoformat(),
        "updated_at": row.updated_at.isoformat(),
    }


def _private_library_query(db: Session, device_hash: str):
    return db.query(Book).join(BookArtifact, BookArtifact.book_id == Book.id).filter(
        BookArtifact.device_key_hash == device_hash
    )


@router.get("/sources")
def list_library_sources():
    return {"items": discover_sources()}


@router.get("/search")
async def search_library(
    q: str = Query(min_length=2, max_length=100),
    limit: int = 10,
    db: Session = Depends(get_db),
    device_hash: str = Depends(_device_hash),
):
    if not 1 <= limit <= 25:
        raise HTTPException(status_code=422, detail="Limit must be between 1 and 25")
    escaped_query = q.strip().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    pattern = f"%{escaped_query}%"
    public_query = db.query(Book).filter(
        Book.publication_status == "published",
        Book.rights_status.in_(REUSABLE_RIGHTS_STATUSES),
        Book.rights_evidence.is_not(None), Book.rights_evidence != "",
        Book.source_url.like("https://%"),
    )
    private_ids = [row[0] for row in _private_library_query(db, device_hash).with_entities(Book.id).all()]
    local_query = db.query(Book).filter(or_(Book.id.in_(private_ids), Book.id.in_([-1]))) if private_ids else db.query(Book).filter(Book.id == -1)
    public_query = public_query.filter(or_(Book.title.ilike(pattern, escape="\\"), Book.author.ilike(pattern, escape="\\")))
    local_query = local_query.filter(or_(Book.title.ilike(pattern, escape="\\"), Book.author.ilike(pattern, escape="\\")))
    local_rows = {book.id: book for book in public_query.order_by(Book.title.asc()).limit(limit).all()}
    local_rows.update({book.id: book for book in local_query.order_by(Book.title.asc()).limit(limit).all()})
    local_items = [{
        "id": book.id,
        "title": book.title,
        "author": book.author,
        "publisher": book.publisher,
        "source_url": book.source_url,
        "visibility": "private_device" if book.id in private_ids else "public_reviewed",
        "page_count": db.query(BookPage).filter(BookPage.book_id == book.id).count(),
    } for book in local_rows.values()]
    try:
        remote_items = await search_internet_archive(q, limit)
        remote_error = None
    except Exception as exc:
        remote_items = []
        remote_error = "internet_archive_unavailable"
    return {
        "query": q,
        "local": local_items,
        "remote": remote_items,
        "remote_error": remote_error,
        "source_policy": "Remote results are metadata only. Reuse rights must be checked before import.",
    }


@router.post("/imports/upload", status_code=201)
async def upload_local_book_export(
    file: UploadFile = File(...),
    title: str = "",
    author: str | None = None,
    db: Session = Depends(get_db),
    device_hash: str = Depends(_device_hash),
):
    """Import user-supplied ABLibrary JSON/TXT/MD exports as a private draft."""
    settings = get_settings()
    try:
        original_name = safe_original_name(file.filename or "")
    except ValueError as exc:
        raise HTTPException(status_code=422, detail="Invalid uploaded filename") from exc
    extension = Path(original_name).suffix.lower().lstrip(".")
    if extension not in {"json", "txt", "md", "epub", "pdf"}:
        raise HTTPException(status_code=415, detail="Supported formats: JSON, TXT, Markdown, EPUB, PDF")
    temporary_name = f"upload-{uuid.uuid4().hex}.{extension}"
    storage_name = f"{uuid.uuid4().hex}.{extension}"
    temporary_path = settings.media_path / "book_imports" / temporary_name
    stored_path = settings.media_path / "book_imports" / storage_name
    temporary_path.parent.mkdir(parents=True, exist_ok=True)
    written = 0
    stored_path_created = False
    try:
        with temporary_path.open("xb") as output:
            while chunk := await file.read(64 * 1024):
                written += len(chunk)
                if written > min(MAX_IMPORT_BYTES, settings.max_upload_bytes):
                    raise HTTPException(status_code=413, detail="Upload exceeds the configured size limit")
                output.write(chunk)
        pages, metadata = await asyncio.to_thread(extract_import_file, temporary_path, extension)
        if not pages or sum(len(page) for page in pages) > MAX_EXTRACTED_CHARS:
            raise HTTPException(status_code=422, detail="The file contains no readable book text")
        digest = await asyncio.to_thread(sha256_file, temporary_path)
        duplicate = db.query(BookArtifact).filter_by(device_key_hash=device_hash, sha256=digest).first()
        if duplicate:
            temporary_path.unlink(missing_ok=True)
            duplicate_book = db.get(Book, duplicate.book_id)
            return {"duplicate": True, "book": {"id": duplicate.book_id, "title": duplicate_book.title if duplicate_book else ""}}
        resolved_title = (title or metadata.get("title") or Path(original_name).stem).strip()[:250]
        resolved_author = (author or metadata.get("author") or None)
        book = Book(
            title=resolved_title or "كتاب مستورد",
            author=resolved_author[:180] if resolved_author else None,
            publisher=metadata.get("publisher"),
            description="ملف رفعه المستخدم من جهازه. حقوق النشر غير متحققة؛ المحتوى خاص بهذا الجهاز ومسودة غير منشورة.",
            source_url=None,
            rights_status="unverified",
            rights_evidence="User-supplied local export. Rights not independently verified.",
            offline_access_allowed=False,
            publication_status="draft",
        )
        db.add(book)
        db.flush()
        _persist_edition_and_toc(
            db, book, metadata,
            source_url=None,
            rights_status="unverified",
            rights_evidence="User-supplied export; edition metadata and TOC are imported as supplied, not independently verified.",
        )
        db.add_all([
            BookPage(book_id=book.id, volume_number=1, page_number=index, text_content=page[:25000])
            for index, page in enumerate(pages, start=1)
        ])
        os.replace(temporary_path, stored_path)
        stored_path_created = True
        db.add(BookArtifact(
            book_id=book.id,
            device_key_hash=device_hash,
            original_name=original_name,
            storage_name=storage_name,
            file_format=extension,
            mime_type=format_mime(extension),
            byte_size=written,
            sha256=digest,
            source_url=None,
            license_url=None,
        ))
        db.commit()
        return {"duplicate": False, "book": {"id": book.id, "title": book.title, "page_count": len(pages), "rights_status": "unverified", "visibility": "private_device"}}
    except HTTPException:
        db.rollback()
        temporary_path.unlink(missing_ok=True)
        if stored_path_created:
            stored_path.unlink(missing_ok=True)
        raise
    except ValueError as exc:
        db.rollback()
        temporary_path.unlink(missing_ok=True)
        if stored_path_created:
            stored_path.unlink(missing_ok=True)
        raise HTTPException(status_code=422, detail=str(exc)[:80]) from exc
    except Exception as exc:
        db.rollback()
        temporary_path.unlink(missing_ok=True)
        if stored_path_created:
            stored_path.unlink(missing_ok=True)
        raise HTTPException(status_code=422, detail="Unable to import this local book export") from exc
    finally:
        await file.close()


@router.post("/imports/preview", status_code=201)
async def preview_book_import(
    payload: ImportPreviewPayload,
    db: Session = Depends(get_db),
    device_hash: str = Depends(_device_hash),
):
    if payload.source_key != "internet_archive":
        raise HTTPException(status_code=422, detail="This connector does not support direct file import")
    try:
        metadata = await get_internet_archive_metadata(payload.identifier)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail="Invalid source identifier") from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail="Source metadata is temporarily unavailable") from exc
    assessment = metadata["rights_status"]
    files = metadata["files"]
    selected = next((item for item in files if item["extension"] == "pdf"), None)
    selected = selected or next((item for item in files if item["extension"] == "epub"), None)
    selected = selected or next((item for item in files if item["extension"] in {"txt", "md", "json"}), None)
    importable_rights = assessment in {"public_domain", "licensed"}
    status = "awaiting_confirmation" if importable_rights and selected else "blocked_rights"
    reasons = []
    if not importable_rights:
        reasons.append("rights_not_verified_or_supported")
    if not selected:
        reasons.append("no_supported_file_within_size_limit")
    now = datetime.now(timezone.utc)
    row = BookImportJob(
        device_key_hash=device_hash,
        source_key="internet_archive",
        source_item_id=metadata["identifier"],
        title=metadata["title"],
        author=metadata["author"],
        source_url=metadata["source_url"],
        selected_file=selected["name"] if selected else None,
        file_format=selected["extension"] if selected else None,
        license_url=metadata["license_url"],
        rights_status=assessment,
        rights_evidence=json.dumps({
            "provider_metadata_claim": metadata["rights_candidate"],
            "license_url": metadata["license_url"],
            "source_metadata_url": f"https://archive.org/metadata/{quote(metadata['identifier'], safe='')}",
            "review_state": "not_independently_verified",
        }, ensure_ascii=False),
        status=status,
        progress=0,
        details={
            "description": metadata["description"],
            "publisher": metadata["publisher"],
            "year": metadata["year"],
            "language": metadata["language"],
            "candidate_file": selected,
            "available_supported_files": files,
            "rights_message_ar": metadata["rights_message_ar"],
            "reasons": reasons,
            "public_publication_allowed": False,
        },
        created_at=now,
        updated_at=now,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return {
        "job": _job_json(row),
        "can_confirm": status == "awaiting_confirmation",
        "confirmation_notice_ar": "الاستيراد يحفظ نسخة شخصية خاصة بهذا الجهاز فقط. يبقى الكتاب مسودة غير منشورة ويحتاج مراجعة حقوق مستقلة قبل أي نشر عام.",
    }


@router.post("/imports/{job_id}/confirm")
async def confirm_book_import(
    job_id: int,
    payload: ImportConfirmPayload,
    db: Session = Depends(get_db),
    device_hash: str = Depends(_device_hash),
):
    job = db.query(BookImportJob).filter_by(id=job_id, device_key_hash=device_hash).first()
    if job is None:
        raise HTTPException(status_code=404, detail="Import job not found")
    if job.status == "completed":
        return {"job": _job_json(job), "book": {"id": job.book_id, "title": job.title}, "already_completed": True}
    if job.status != "awaiting_confirmation" or job.rights_status not in {"licensed", "public_domain"}:
        raise HTTPException(status_code=409, detail="This import is blocked pending a supported rights review")
    if not payload.confirm_personal_copy:
        raise HTTPException(status_code=400, detail="Explicit confirmation is required")
    if not job.selected_file or not job.file_format:
        raise HTTPException(status_code=409, detail="No supported source file was selected")

    settings = get_settings()
    import_dir = settings.media_path / "book_imports"
    storage_name = f"{uuid.uuid4().hex}.{job.file_format}"
    destination = import_dir / storage_name
    job.status = "downloading"
    job.progress = 5
    job.error_code = None
    job.updated_at = datetime.now(timezone.utc)
    db.commit()
    try:
        byte_size, digest = await download_archive_file(job.source_item_id, job.selected_file, destination)
        job.status = "extracting"
        job.progress = 45
        job.file_sha256 = digest
        job.updated_at = datetime.now(timezone.utc)
        db.commit()
        import asyncio
        pages, extracted_metadata = await asyncio.to_thread(extract_import_file, destination, job.file_format)
        if not pages or sum(len(page) for page in pages) > MAX_EXTRACTED_CHARS:
            raise ValueError("extracted_text_empty_or_too_large")
        existing_artifact = db.query(BookArtifact).filter_by(device_key_hash=device_hash, sha256=digest).first()
        if existing_artifact:
            job.book_id = existing_artifact.book_id
            job.status = "completed"
            job.progress = 100
            job.updated_at = datetime.now(timezone.utc)
            destination.unlink(missing_ok=True)
            db.commit()
            return {"job": _job_json(job), "book": {"id": job.book_id, "title": job.title}, "duplicate": True}

        book = Book(
            title=job.title,
            author=extracted_metadata.get("author") or job.author,
            publisher=extracted_metadata.get("publisher"),
            description=str(job.details.get("description") or "")[:5000],
            source_url=job.source_url,
            rights_status="unverified",
            rights_evidence=(job.rights_evidence or "") + "\nPersonal-copy import; independent rights review required.",
            offline_access_allowed=False,
            publication_status="draft",
        )
        db.add(book)
        db.flush()
        edition_metadata = {
            "publisher": job.details.get("publisher"),
            "publication_year": job.details.get("year"),
            "language": job.details.get("language"),
        }
        _persist_edition_and_toc(
            db, book, edition_metadata,
            source_url=job.source_url,
            rights_status="unverified",
            rights_evidence=(job.rights_evidence or "") + "\nProvider license claim requires independent review.",
        )
        db.add_all([
            BookPage(book_id=book.id, volume_number=1, page_number=index, text_content=page[:25000])
            for index, page in enumerate(pages, start=1)
        ])
        artifact = BookArtifact(
            book_id=book.id,
            device_key_hash=device_hash,
            original_name=job.selected_file,
            storage_name=storage_name,
            file_format=job.file_format,
            mime_type=format_mime(job.file_format),
            byte_size=byte_size,
            sha256=digest,
            source_url=job.source_url,
            license_url=job.license_url,
        )
        db.add(artifact)
        job.book_id = book.id
        job.status = "completed"
        job.progress = 100
        job.details = {
            **(job.details or {}),
            "extracted_pages": len(pages),
            "extracted_characters": sum(len(page) for page in pages),
            "artifact_id": None,
            "visibility": "private_device",
            "public_publication_allowed": False,
        }
        job.updated_at = datetime.now(timezone.utc)
        db.commit()
        return {
            "job": _job_json(job),
            "book": {"id": book.id, "title": book.title, "pages": len(pages), "sha256": digest},
            "rights_notice_ar": "تمت إضافة النسخة إلى مكتبتك الخاصة. لم تُنشر ولم تُمنح لها حالة ترخيص معتمدة؛ يلزم تدقيق مستقل قبل إتاحتها للآخرين.",
        }
    except Exception as exc:
        destination.unlink(missing_ok=True)
        job.status = "failed"
        job.progress = 0
        job.error_code = str(exc)[:80] if isinstance(exc, ValueError) else "source_import_failed"
        job.updated_at = datetime.now(timezone.utc)
        db.commit()
        if isinstance(exc, ValueError):
            raise HTTPException(status_code=422, detail=job.error_code) from exc
        raise HTTPException(status_code=502, detail="The source import failed safely; no partial book was published") from exc


@router.get("/imports")
def list_import_jobs(
    limit: int = 30,
    db: Session = Depends(get_db),
    device_hash: str = Depends(_device_hash),
):
    if not 1 <= limit <= 100:
        raise HTTPException(status_code=422, detail="Limit must be between 1 and 100")
    rows = db.query(BookImportJob).filter_by(device_key_hash=device_hash).order_by(BookImportJob.created_at.desc()).limit(limit).all()
    return {"items": [_job_json(row) for row in rows]}


@router.get("/imports/{job_id}")
def get_import_status(
    job_id: int,
    db: Session = Depends(get_db),
    device_hash: str = Depends(_device_hash),
):
    row = db.query(BookImportJob).filter_by(id=job_id, device_key_hash=device_hash).first()
    if row is None:
        raise HTTPException(status_code=404, detail="Import job not found")
    return {"job": _job_json(row)}


@router.post("/imports/{job_id}/resume")
def resume_import(
    job_id: int,
    db: Session = Depends(get_db),
    device_hash: str = Depends(_device_hash),
):
    row = db.query(BookImportJob).filter_by(id=job_id, device_key_hash=device_hash).first()
    if row is None:
        raise HTTPException(status_code=404, detail="Import job not found")
    if row.status == "completed":
        return {"job": _job_json(row), "resumed": False}
    if row.rights_status not in {"public_domain", "licensed"} or not row.selected_file:
        raise HTTPException(status_code=409, detail="Rights or source file do not permit resuming this import")
    row.status = "awaiting_confirmation"
    row.progress = 0
    row.error_code = None
    row.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(row)
    return {"job": _job_json(row), "resumed": True, "confirmation_required": True}


@router.get("/books")
def list_private_books(
    limit: int = 50,
    db: Session = Depends(get_db),
    device_hash: str = Depends(_device_hash),
):
    if not 1 <= limit <= 100:
        raise HTTPException(status_code=422, detail="Limit must be between 1 and 100")
    rows = _private_library_query(db, device_hash).order_by(Book.created_at.desc()).limit(limit).all()
    items = []
    for book in rows:
        artifact = db.query(BookArtifact).filter_by(device_key_hash=device_hash, book_id=book.id).first()
        items.append({
            "id": book.id, "title": book.title, "author": book.author,
            "publisher": book.publisher, "description": book.description,
            "source_url": book.source_url, "rights_status": book.rights_status,
            "publication_status": book.publication_status,
            "offline_access_allowed": book.offline_access_allowed,
            "artifact_format": artifact.file_format if artifact else None,
            "page_count": db.query(BookPage).filter(BookPage.book_id == book.id).count(),
            "edition_count": db.query(BookEdition).filter(BookEdition.book_id == book.id).count(),
            "toc_count": db.query(BookTocEntry).filter(BookTocEntry.book_id == book.id).count(),
        })
    return {"items": items, "total": len(items)}


@router.get("/books/{book_id}/pages")
def get_private_book_pages(
    book_id: int,
    volume_number: int = 1,
    limit: int = 40,
    offset: int = 0,
    db: Session = Depends(get_db),
    device_hash: str = Depends(_device_hash),
):
    artifact = db.query(BookArtifact).filter_by(device_key_hash=device_hash, book_id=book_id).first()
    if artifact is None:
        raise HTTPException(status_code=404, detail="Book not found in this device library")
    if not 1 <= volume_number <= 1000 or not 1 <= limit <= 100 or not 0 <= offset <= 100000:
        raise HTTPException(status_code=422, detail="Invalid book pagination values")
    query = db.query(BookPage).filter_by(book_id=book_id, volume_number=volume_number)
    total = query.count()
    rows = query.order_by(BookPage.page_number.asc()).offset(offset).limit(limit).all()
    return {"book_id": book_id, "items": [
        {"page_number": page.page_number, "text_content": page.text_content} for page in rows
    ], "total": total, "limit": limit, "offset": offset, "volume_number": volume_number}


@router.get("/books/{book_id}/search")
def search_private_book_text(
    book_id: int,
    q: str = Query(min_length=2, max_length=100),
    volume_number: int = 1,
    limit: int = 30,
    db: Session = Depends(get_db),
    device_hash: str = Depends(_device_hash),
):
    artifact = db.query(BookArtifact).filter_by(device_key_hash=device_hash, book_id=book_id).first()
    if artifact is None:
        raise HTTPException(status_code=404, detail="Book not found in this device library")
    if not 1 <= volume_number <= 1000 or not 1 <= limit <= 50:
        raise HTTPException(status_code=422, detail="Invalid book search values")
    term = q.strip()
    if len(term) < 2:
        raise HTTPException(status_code=422, detail="Search text must contain at least two characters")
    escaped = term.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    rows = db.query(BookPage).filter(
        BookPage.book_id == book_id,
        BookPage.volume_number == volume_number,
        BookPage.text_content.ilike(f"%{escaped}%", escape="\\"),
    ).order_by(BookPage.page_number.asc()).limit(limit).all()
    items = []
    for page in rows:
        content = page.text_content or ""
        position = content.casefold().find(term.casefold())
        start = max(0, position - 100) if position >= 0 else 0
        end = min(len(content), (position + len(term) + 160)) if position >= 0 else min(260, len(content))
        items.append({
            "page_number": page.page_number,
            "snippet": content[start:end],
            "match_count_in_page": content.casefold().count(term.casefold()),
        })
    return {"book_id": book_id, "query": term, "items": items, "total_returned": len(items)}


@router.get("/books/{book_id}/editions")
def get_private_book_editions(
    book_id: int,
    db: Session = Depends(get_db),
    device_hash: str = Depends(_device_hash),
):
    artifact = db.query(BookArtifact).filter_by(device_key_hash=device_hash, book_id=book_id).first()
    if artifact is None:
        raise HTTPException(status_code=404, detail="Book not found in this device library")
    rows = db.query(BookEdition).filter_by(book_id=book_id).order_by(BookEdition.created_at.asc()).all()
    return {"items": [{
        "id": row.id, "edition_label": row.edition_label, "publisher": row.publisher,
        "publication_year": row.publication_year, "isbn": row.isbn,
        "printing_batch": row.printing_batch, "language": row.language,
        "source_url": row.source_url, "rights_status": row.rights_status,
    } for row in rows], "total": len(rows)}


@router.get("/books/{book_id}/toc")
def get_private_book_toc(
    book_id: int,
    volume_number: int = 1,
    db: Session = Depends(get_db),
    device_hash: str = Depends(_device_hash),
):
    artifact = db.query(BookArtifact).filter_by(device_key_hash=device_hash, book_id=book_id).first()
    if artifact is None:
        raise HTTPException(status_code=404, detail="Book not found in this device library")
    rows = db.query(BookTocEntry).filter_by(book_id=book_id, volume_number=volume_number).order_by(BookTocEntry.sort_order.asc(), BookTocEntry.id.asc()).all()
    return {"items": [{
        "id": row.id, "parent_id": row.parent_id, "title": row.title,
        "page_number": row.page_number, "page_label": row.page_label,
        "volume_number": row.volume_number, "sort_order": row.sort_order,
    } for row in rows], "total": len(rows)}


@router.get("/books/{book_id}/export")
def export_private_book(
    book_id: int,
    format: str = "txt",
    db: Session = Depends(get_db),
    device_hash: str = Depends(_device_hash),
):
    if format not in {"txt", "md", "json"}:
        raise HTTPException(status_code=422, detail="Format must be txt, md or json")
    artifact = db.query(BookArtifact).filter_by(device_key_hash=device_hash, book_id=book_id).first()
    book = db.get(Book, book_id)
    if artifact is None or book is None:
        raise HTTPException(status_code=404, detail="Book not found in this device library")
    pages = db.query(BookPage).filter_by(book_id=book_id).order_by(BookPage.page_number.asc()).all()
    payload = {
        "metadata": {"title": book.title, "author": book.author, "publisher": book.publisher,
                     "source_url": book.source_url, "rights_status": book.rights_status},
        "pages": [{"page_number": row.page_number, "text_content": row.text_content} for row in pages],
    }
    if format == "json":
        content = json.dumps(payload, ensure_ascii=False, indent=2)
        media_type = "application/json"
    elif format == "md":
        content = f"# {book.title}\n\n"
        if book.author:
            content += f"**المؤلف:** {book.author}\n\n"
        content += "\n\n".join(f"## الصفحة {row.page_number}\n\n{row.text_content}" for row in pages)
        media_type = "text/markdown; charset=utf-8"
    else:
        content = f"عنوان الكتاب: {book.title}\nالمؤلف: {book.author or 'غير محدد'}\n\n"
        content += "\n\n".join(f"[صفحة {row.page_number}]\n{row.text_content}" for row in pages)
        media_type = "text/plain; charset=utf-8"
    return {"file_name": f"book-{book_id}.{format}", "media_type": media_type, "content": content}


@router.get("/status")
def library_status(db: Session = Depends(get_db), device_hash: str = Depends(_device_hash)):
    books_count = _private_library_query(db, device_hash).count()
    jobs = db.query(BookImportJob).filter_by(device_key_hash=device_hash).all()
    statuses: dict[str, int] = {}
    for job in jobs:
        statuses[job.status] = statuses.get(job.status, 0) + 1
    return {
        "private_books": books_count,
        "imports_total": len(jobs),
        "imports_by_status": statuses,
        "public_books_require_review": True,
    }
