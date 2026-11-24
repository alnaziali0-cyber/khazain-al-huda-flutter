from __future__ import annotations

import json
from io import BytesIO
from pathlib import Path
import zipfile
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services.shia_library_import_engine import (
    _license_assessment,
    _is_allowed_archive_download_url,
    discover_sources,
    extract_import_file,
)


def test_source_connectors_report_real_capabilities_and_restrictions():
    sources = {item["source_key"]: item for item in discover_sources()}
    assert sources["internet_archive"]["search_supported"] is True
    assert sources["internet_archive"]["import_supported"] is True
    assert sources["thaqalayn"]["import_supported"] is False
    assert sources["al_islam"]["status"] == "manual_reading_only_permission_required"
    assert sources["shia_research"]["status"] == "no_public_api_bulk_copy_prohibited"
    assert sources["ablibrary_export"]["status"] == "local_user_file_import_json_txt_markdown_epub_pdf"


def test_rights_policy_only_accepts_explicit_allow_list_candidates():
    assert _license_assessment("https://creativecommons.org/publicdomain/zero/1.0/")["status"] == "public_domain"
    assert _license_assessment("https://creativecommons.org/licenses/by/4.0/")["status"] == "licensed"
    assert _license_assessment("https://creativecommons.org/licenses/by-nc/4.0/")["status"] == "unverified"
    assert _license_assessment(None)["status"] == "unverified"


def test_ablibrary_json_export_adapter_extracts_page_blocks(tmp_path):
    path = tmp_path / "export.json"
    path.write_text(json.dumps({
        "metadata": {"title": "كتاب تجريبي", "author": "مؤلف"},
        "table_of_contents": [{"title": "باب أول", "page_number": 1}],
        "pages": [{"page_number": 1, "full_text_blocks": [
            {"type": "heading", "text": "باب أول"},
            {"type": "text", "text": "نص عربي للاختبار."},
            {"type": "footnote", "text": "حاشية."},
        ]}],
    }, ensure_ascii=False), encoding="utf-8")
    pages, metadata = extract_import_file(path, "json")
    assert metadata["title"] == "كتاب تجريبي"
    assert metadata["author"] == "مؤلف"
    assert "نص عربي للاختبار" in pages[0]
    assert "حاشية" in pages[0]


def test_markdown_and_epub_text_are_extracted_without_path_extraction(tmp_path):
    md = tmp_path / "book.md"
    md.write_text("# باب\n\nنص عربي", encoding="utf-8")
    pages, _ = extract_import_file(md, "md")
    assert pages == ["# باب\n\nنص عربي"]


def test_epub_text_is_extracted_without_extracting_archive_paths(tmp_path):
    path = tmp_path / "sample.epub"
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("EPUB/chapter.xhtml", "<html><body><h1>باب الطهارة</h1><p>هذا نص عربي للاستخراج.</p></body></html>")
    pages, metadata = extract_import_file(path, "epub")
    assert pages and "نص عربي للاستخراج" in pages[0]
    assert metadata == {}


def test_local_export_upload_is_private_and_not_publicly_published():
    device_key = f"device-{uuid4().hex}-{uuid4().hex}"
    device_key = device_key.replace("-", "_")
    assert len(device_key) >= 32
    body = {
        "metadata": {"title": "كتاب رفع خاص", "author": "صاحب النسخة", "publisher": "ناشر تجريبي", "print_year": "2020"},
        "table_of_contents": [
            {"id": 10, "title": "المقدمة", "page_number": 1},
            {"id": 11, "parent_id": 10, "title": "تمهيد", "page_number": 1},
        ],
        "pages": [{"page_number": 1, "full_text_blocks": [{"type": "text", "text": "نص خاص"}]}],
    }
    with TestClient(app) as client:
        uploaded = client.post(
            "/api/v1/public/library/imports/upload",
            headers={"X-Device-Key": device_key},
            files={"file": ("my-book.json", json.dumps(body, ensure_ascii=False).encode(), "application/json")},
        )
        assert uploaded.status_code == 201, uploaded.text
        book = uploaded.json()["book"]
        assert book["title"] == "كتاب رفع خاص"
        assert book["rights_status"] == "unverified"
        assert book["visibility"] == "private_device"
        listed = client.get("/api/v1/public/library/books", headers={"X-Device-Key": device_key})
        assert listed.status_code == 200
        assert any(item["id"] == book["id"] for item in listed.json()["items"])
        other_device = client.get("/api/v1/public/library/books", headers={"X-Device-Key": "x" * 40})
        assert other_device.status_code == 200
        assert not any(item["id"] == book["id"] for item in other_device.json()["items"])
        page = client.get(f"/api/v1/public/library/books/{book['id']}/pages", headers={"X-Device-Key": device_key})
        assert page.status_code == 200
        assert "نص خاص" in page.json()["items"][0]["text_content"]
        toc = client.get(f"/api/v1/public/library/books/{book['id']}/toc", headers={"X-Device-Key": device_key})
        assert toc.status_code == 200
        assert toc.json()["items"][0]["title"] == "المقدمة"
        assert toc.json()["items"][1]["parent_id"] == toc.json()["items"][0]["id"]
        search = client.get(f"/api/v1/public/library/books/{book['id']}/search?q=نص خاص", headers={"X-Device-Key": device_key})
        assert search.status_code == 200
        assert search.json()["items"][0]["page_number"] == 1
        editions = client.get(f"/api/v1/public/library/books/{book['id']}/editions", headers={"X-Device-Key": device_key})
        assert editions.status_code == 200
        assert editions.json()["items"][0]["publisher"] == "ناشر تجريبي"
        not_public = client.get("/api/v1/public/catalog/book")
        assert not any(item.get("id") == book["id"] for item in not_public.json()["items"])

        epub_bytes = BytesIO()
        with zipfile.ZipFile(epub_bytes, "w") as archive:
            archive.writestr("EPUB/chapter.xhtml", "<html><body><p>متن كتاب EPUB التجريبي.</p></body></html>")
        epub_upload = client.post(
            "/api/v1/public/library/imports/upload",
            headers={"X-Device-Key": device_key},
            files={"file": ("test-book.epub", epub_bytes.getvalue(), "application/epub+zip")},
        )
        assert epub_upload.status_code == 201, epub_upload.text
        assert epub_upload.json()["book"]["rights_status"] == "unverified"


def test_import_preview_rejects_unsupported_source_without_network():
    device_key = "D" * 40
    with TestClient(app) as client:
        response = client.post(
            "/api/v1/public/library/imports/preview",
            headers={"X-Device-Key": device_key},
            json={"source_key": "shia_research", "identifier": "sample-book"},
        )
        assert response.status_code == 422


def test_archive_download_redirects_are_limited_to_https_archive_hosts():
    assert _is_allowed_archive_download_url("https://archive.org/download/item/book.pdf")
    assert _is_allowed_archive_download_url("https://ia801500.us.archive.org/file.pdf")
    assert not _is_allowed_archive_download_url("http://archive.org/download/item/book.pdf")
    assert not _is_allowed_archive_download_url("https://archive.org.evil.example/file.pdf")
    assert not _is_allowed_archive_download_url("https://127.0.0.1/file.pdf")
    assert not _is_allowed_archive_download_url("https://user:pass@archive.org/file.pdf")
