"""Rights-aware Shia library discovery, import, extraction and export helpers.

Only documented/read-only metadata endpoints are queried. Remote files are
fetched from fixed Internet Archive hosts after explicit user confirmation and
only where the item's metadata declares an allow-listed reuse licence. Imported
books stay private to the requesting device until reviewed and published by an
administrator through the existing CMS.
"""
from __future__ import annotations

import asyncio
import hashlib
import html
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile
from typing import Any
from urllib.parse import quote, urljoin, urlparse

import httpx

from app.core.config import get_settings
from app.services.pdf_sandbox import safe_temp_root, sandbox_status, worker_command

IA_ORIGIN = "https://archive.org"
IA_SEARCH_URL = f"{IA_ORIGIN}/advancedsearch.php"
IA_METADATA_URL = f"{IA_ORIGIN}/metadata"
MAX_IMPORT_BYTES = 15 * 1024 * 1024
MAX_EXTRACTED_CHARS = 500_000
MAX_EPUB_FILES = 500
MAX_EPUB_UNCOMPRESSED_BYTES = 50 * 1024 * 1024
MAX_EPUB_SINGLE_FILE_BYTES = 10 * 1024 * 1024
ALLOWED_EXTENSIONS = {"pdf", "epub", "txt", "md", "json"}


SOURCE_CATALOG: tuple[dict[str, Any], ...] = (
    {
        "source_key": "internet_archive",
        "name_ar": "Internet Archive",
        "kind": "documented_metadata_api",
        "status": "search_and_metadata_available",
        "search_supported": True,
        "import_supported": True,
        "source_url": "https://archive.org/",
        "policy_ar": "تُراجع licenseurl وبيانات الملف قبل عرض خيار الاستيراد؛ لا يكفي وجود ملف للتنزيل لإثبات حق إعادة الاستخدام.",
    },
    {
        "source_key": "thaqalayn",
        "name_ar": "Thaqalayn API",
        "kind": "documented_read_only_hadith_api",
        "status": "hadith_search_only",
        "search_supported": True,
        "import_supported": False,
        "source_url": "https://www.thaqalayn-api.net/api-docs/",
        "policy_ar": "يُستخدم للبحث والاستشهاد بالروايات؛ ليس مستودع ملفات كتب، ولا يُعاد استيراد مجموعة الروايات إلى المكتبة دون ترخيص بيانات واضح.",
    },
    {
        "source_key": "al_islam",
        "name_ar": "Al-Islam.org",
        "kind": "official_website_linkout",
        "status": "manual_reading_only_permission_required",
        "search_supported": False,
        "import_supported": False,
        "source_url": "https://al-islam.org/",
        "policy_ar": "الموقع ينص على أن المحتوى للاستخدام غير التجاري وبإذن أصحاب حقوق النشر الأصليين؛ لا يوجد هنا موصل تنزيل أو كشط.",
    },
    {
        "source_key": "shia_research",
        "name_ar": "Shia Research Library",
        "kind": "official_website_linkout",
        "status": "no_public_api_bulk_copy_prohibited",
        "search_supported": False,
        "import_supported": False,
        "source_url": "https://shiaresearch.org/",
        "policy_ar": "شروط الخدمة تمنع الكشط والتنزيل الجماعي وإعادة التوزيع، وتوضح أن واجهات API مخصصة للموقع والتطبيقين الرسميين.",
    },
    {
        "source_key": "ablibrary_export",
        "name_ar": "ABLibrary user export",
        "kind": "user_supplied_export_adapter",
        "status": "local_user_file_import_json_txt_markdown_epub_pdf",
        "search_supported": False,
        "import_supported": True,
        "source_url": "https://github.com/aliabd97/ablibrary-books-extractor",
        "policy_ar": "يقبل ملفات JSON/TXT/Markdown التي يملك المستخدم حق تصديرها؛ لا يقرأ مجلد تثبيت ABLibrary ولا يشغّل سكربت استخراج خارجي.",
    },
)


def _clean_text(value: Any, maximum: int = 250) -> str:
    text = " ".join(str(value or "").split()).strip()
    return text[:maximum]


def _ia_identifier(value: str) -> str:
    value = value.strip()
    if not re.fullmatch(r"[A-Za-z0-9_-]{5,80}", value):
        raise ValueError("invalid_archive_identifier")
    return value


def _license_assessment(license_url: str | None) -> dict[str, str]:
    """Treat source-supplied license fields as candidates, never legal approval."""
    url = (license_url or "").strip().lower().rstrip("/") + "/" if license_url else ""
    if not url.startswith("https://creativecommons.org/"):
        return {
            "status": "unverified",
            "candidate": "",
            "message_ar": "لم يقدّم العنصر رابط ترخيص موثوقاً ضمن قائمة التراخيص المقبولة؛ يمنع الاستيراد.",
        }
    if "/publicdomain/zero/1.0/" in url or "/publicdomain/mark/1.0/" in url:
        return {
            "status": "public_domain",
            "candidate": "CC0/PD",
            "message_ar": "بيانات المصدر تعلن CC0 أو Public Domain؛ يلزم فحص بشري لمطابقة العنصر قبل النشر.",
        }
    if "/licenses/by/4.0/" in url or "/licenses/by-sa/4.0/" in url:
        return {
            "status": "licensed",
            "candidate": "CC-BY-4.0" if "/licenses/by/4.0/" in url else "CC-BY-SA-4.0",
            "message_ar": "بيانات المصدر تعلن ترخيصاً إبداعياً يتطلب الإسناد، والمشاركة بالمثل عند انطباقه؛ يلزم تدقيق بشري.",
        }
    return {
        "status": "unverified",
        "candidate": "",
        "message_ar": "نوع الترخيص غير مدعوم في سياسة الاستيراد الحالية؛ لم يُسمح بالتنزيل.",
    }


def discover_sources() -> list[dict[str, Any]]:
    return [dict(source) for source in SOURCE_CATALOG]


async def search_internet_archive(query: str, limit: int = 10) -> list[dict[str, Any]]:
    query = _clean_text(query, 100)
    if len(query) < 2:
        return []
    # The value is passed as a quoted Lucene phrase; never accept raw query syntax.
    safe_query = query.replace('"', " ").replace("\\", " ")
    params = [
        ("q", f'title:("{safe_query}") AND mediatype:text'),
        ("output", "json"),
        ("rows", str(max(1, min(limit, 25)))),
        ("page", "1"),
    ]
    for field in ("identifier", "title", "creator", "year", "description", "licenseurl", "language"):
        params.append(("fl[]", field))
    async with httpx.AsyncClient(timeout=httpx.Timeout(12.0, connect=5.0), follow_redirects=False) as client:
        response = await client.get(IA_SEARCH_URL, params=params, headers={"Accept": "application/json"})
        response.raise_for_status()
        payload = response.json()
    docs = payload.get("response", {}).get("docs", [])
    results: list[dict[str, Any]] = []
    for doc in docs if isinstance(docs, list) else []:
        identifier = str(doc.get("identifier") or "")
        if not re.fullmatch(r"[A-Za-z0-9_-]{5,80}", identifier):
            continue
        license_url = doc.get("licenseurl")
        assessment = _license_assessment(license_url if isinstance(license_url, str) else None)
        creator = doc.get("creator")
        if isinstance(creator, list):
            creator = ", ".join(str(item) for item in creator[:3])
        results.append({
            "source_key": "internet_archive",
            "identifier": identifier,
            "title": _clean_text(doc.get("title"), 250) or identifier,
            "author": _clean_text(creator, 180) or None,
            "year": _clean_text(doc.get("year"), 20) or None,
            "description": _clean_text(doc.get("description"), 1200),
            "language": _clean_text(doc.get("language"), 40) or None,
            "source_url": f"{IA_ORIGIN}/details/{identifier}",
            "license_url": license_url if isinstance(license_url, str) else None,
            "rights_status": assessment["status"],
            "rights_candidate": assessment["candidate"],
            "import_allowed_pending_user_confirmation": assessment["status"] in {"public_domain", "licensed"},
        })
    return results


async def get_internet_archive_metadata(identifier: str) -> dict[str, Any]:
    identifier = _ia_identifier(identifier)
    async with httpx.AsyncClient(timeout=httpx.Timeout(12.0, connect=5.0), follow_redirects=False) as client:
        response = await client.get(f"{IA_METADATA_URL}/{quote(identifier, safe='')}", headers={"Accept": "application/json"})
        response.raise_for_status()
        payload = response.json()
    metadata = payload.get("metadata") if isinstance(payload, dict) else None
    files = payload.get("files") if isinstance(payload, dict) else None
    if not isinstance(metadata, dict) or not isinstance(files, list):
        raise ValueError("archive_metadata_invalid")
    normalized_files: list[dict[str, Any]] = []
    for item in files:
        if not isinstance(item, dict):
            continue
        name = str(item.get("name") or "")
        if not name or "/" in name or "\\" in name or name in {".", ".."} or ".." in Path(name).parts:
            continue
        ext = Path(name).suffix.lower().lstrip(".")
        fmt = str(item.get("format") or "").lower()
        if ext not in ALLOWED_EXTENSIONS:
            continue
        if item.get("private") in {True, "true", "1", 1}:
            continue
        size = int(item.get("size") or 0) if str(item.get("size") or "0").isdigit() else 0
        if size <= 0 or size > MAX_IMPORT_BYTES:
            continue
        normalized_files.append({
            "name": name,
            "extension": ext,
            "format": fmt,
            "size": size,
            "sha1": _clean_text(item.get("sha1"), 64) or None,
            "md5": _clean_text(item.get("md5"), 32) or None,
        })
    license_url = metadata.get("licenseurl") if isinstance(metadata.get("licenseurl"), str) else None
    assessment = _license_assessment(license_url)
    creator = metadata.get("creator")
    if isinstance(creator, list):
        creator = ", ".join(str(item) for item in creator[:3])
    title = _clean_text(metadata.get("title"), 250) or identifier
    return {
        "identifier": identifier,
        "title": title,
        "author": _clean_text(creator, 180) or None,
        "publisher": _clean_text(metadata.get("publisher"), 180) or None,
        "year": _clean_text(metadata.get("year") or metadata.get("date"), 32) or None,
        "description": _clean_text(metadata.get("description"), 5000),
        "language": _clean_text(metadata.get("language"), 40) or None,
        "source_url": f"{IA_ORIGIN}/details/{identifier}",
        "license_url": license_url,
        "rights_status": assessment["status"],
        "rights_candidate": assessment["candidate"],
        "rights_message_ar": assessment["message_ar"],
        "files": normalized_files,
    }


class _VisibleTextParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self._ignored = 0

    def handle_starttag(self, tag: str, attrs) -> None:
        if tag.lower() in {"script", "style", "svg", "noscript"}:
            self._ignored += 1
        elif not self._ignored and tag.lower() in {"p", "div", "br", "li", "h1", "h2", "h3", "tr"}:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() in {"script", "style", "svg", "noscript"} and self._ignored:
            self._ignored -= 1
        elif not self._ignored and tag.lower() in {"p", "div", "li", "h1", "h2", "h3", "tr"}:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        if not self._ignored and data.strip():
            self.parts.append(data.strip())


def _split_text_pages(text: str, max_chars: int = 15000) -> list[str]:
    text = text.replace("\x00", "").strip()
    if len(text) > MAX_EXTRACTED_CHARS:
        raise ValueError("extracted_text_too_large")
    if not text:
        return []
    form_pages = [part.strip() for part in text.split("\f") if part.strip()]
    pages: list[str] = []
    for part in form_pages or [text]:
        while len(part) > max_chars:
            split_at = part.rfind("\n", 0, max_chars)
            if split_at < int(max_chars * .55):
                split_at = max_chars
            pages.append(part[:split_at].strip())
            part = part[split_at:].strip()
        if part:
            pages.append(part)
    if len(pages) > 1000:
        raise ValueError("too_many_extracted_pages")
    return pages


def _extract_pdf_pages(path: Path) -> list[str]:
    ready, bwrap = sandbox_status()
    if not ready or not bwrap:
        raise ValueError("safe_pdf_sandbox_unavailable")
    worker_source = Path(__file__).resolve().parent / "pdf_text_worker.py"
    with tempfile.TemporaryDirectory(prefix="khazain-library-pdf-", dir=safe_temp_root()) as tmp:
        work = Path(tmp)
        input_path = work / "input.pdf"
        with path.open("rb") as source, input_path.open("xb") as target:
            total = 0
            while chunk := source.read(1024 * 1024):
                total += len(chunk)
                if total > MAX_IMPORT_BYTES:
                    raise ValueError("source_file_too_large")
                target.write(chunk)
        input_path.chmod(0o400)
        (work / "pdf_text_worker.py").write_bytes(worker_source.read_bytes())
        (work / "pdf_text_worker.py").chmod(0o400)
        completed = subprocess.run(
            worker_command(bwrap, work),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=18,
            check=False,
            env={"LANG": "C.UTF-8", "LC_ALL": "C.UTF-8"},
        )
        if completed.returncode != 0 or len(completed.stdout) > 4 * 1024 * 1024:
            raise ValueError("pdf_extraction_failed")
        data = json.loads(completed.stdout.decode("utf-8"))
        page_texts = data.get("page_texts")
        if not data.get("ok") or not isinstance(page_texts, list):
            text = str(data.get("text") or "")
            return _split_text_pages(text)
        pages = [str(item).strip() for item in page_texts if str(item).strip()]
        if sum(len(page) for page in pages) > MAX_EXTRACTED_CHARS:
            raise ValueError("extracted_text_too_large")
        return pages


def extract_import_file(path: Path, file_format: str) -> tuple[list[str], dict[str, Any]]:
    """Extract bounded text from supported imports without archive path extraction."""
    file_format = file_format.lower().lstrip(".")
    size = path.stat().st_size
    if size <= 0 or size > MAX_IMPORT_BYTES:
        raise ValueError("source_file_too_large")
    if file_format == "pdf":
        pages = _extract_pdf_pages(path)
    elif file_format in {"txt", "md"}:
        raw = path.read_bytes()
        text = raw.decode("utf-8-sig", errors="strict")
        pages = _split_text_pages(text)
    elif file_format == "json":
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        if not isinstance(data, dict):
            raise ValueError("unsupported_json_structure")
        meta = data.get("metadata") if isinstance(data.get("metadata"), dict) else data
        raw_pages = data.get("pages")
        if not isinstance(raw_pages, list):
            raise ValueError("json_pages_missing")
        pages = []
        for page in raw_pages:
            if not isinstance(page, dict):
                continue
            blocks = page.get("full_text_blocks") or page.get("blocks")
            if isinstance(blocks, list):
                body = "\n\n".join(
                    str(block.get("text") or "") for block in blocks if isinstance(block, dict)
                )
            else:
                body = str(page.get("text_content") or page.get("text") or "")
            if body.strip():
                pages.append(body.strip())
        if not pages:
            raise ValueError("json_has_no_text_pages")
        if len(pages) > 1000 or sum(len(page) for page in pages) > MAX_EXTRACTED_CHARS:
            raise ValueError("extracted_text_too_large")
        raw_toc = data.get("table_of_contents")
        toc: list[dict[str, Any]] = []
        if isinstance(raw_toc, list):
            for index, entry in enumerate(raw_toc[:1000]):
                if not isinstance(entry, dict):
                    continue
                title = _clean_text(entry.get("title"), 500)
                if not title:
                    continue
                page_value = entry.get("page_number")
                page_number = int(page_value) if str(page_value or "").isdigit() and int(page_value) >= 1 else None
                parent_value = entry.get("parent_id")
                toc.append({
                    "source_entry_id": str(entry.get("id"))[:80] if entry.get("id") is not None else str(index),
                    "parent_source_entry_id": str(parent_value)[:80] if parent_value is not None else None,
                    "title": title,
                    "page_number": page_number,
                    "page_label": _clean_text(entry.get("page_label"), 80) or None,
                    "volume_number": int(entry.get("volume_number") or 1) if str(entry.get("volume_number") or "1").isdigit() else 1,
                    "sort_order": index,
                })
        metadata = {
            "title": _clean_text(meta.get("title") or meta.get("name"), 250),
            "author": _clean_text(meta.get("author") or meta.get("creator"), 180) or None,
            "publisher": _clean_text(meta.get("publisher"), 180) or None,
            "edition_label": _clean_text(meta.get("edition") or meta.get("edition_label"), 180) or None,
            "publication_year": _clean_text(meta.get("print_year") or meta.get("publication_year"), 32) or None,
            "isbn": _clean_text(meta.get("isbn"), 32) or None,
            "printing_batch": _clean_text(meta.get("printing_batch_no"), 80) or None,
            "language": _clean_text(meta.get("language"), 40) or None,
            "table_of_contents": toc,
        }
        return pages, metadata
    elif file_format == "epub":
        pages = []
        total_uncompressed = 0
        with zipfile.ZipFile(path, "r") as archive:
            infos = archive.infolist()
            if len(infos) > MAX_EPUB_FILES or archive.testzip() is not None:
                raise ValueError("epub_archive_invalid")
            html_files = []
            for info in infos:
                name = info.filename.replace("\\", "/")
                parts = Path(name).parts
                if name.startswith("/") or ".." in parts or "\x00" in name:
                    raise ValueError("epub_unsafe_member_path")
                if info.is_dir():
                    continue
                total_uncompressed += info.file_size
                if info.file_size > MAX_EPUB_SINGLE_FILE_BYTES or total_uncompressed > MAX_EPUB_UNCOMPRESSED_BYTES:
                    raise ValueError("epub_uncompressed_size_limit")
                if Path(name).suffix.lower() in {".xhtml", ".html", ".htm"}:
                    html_files.append(info)
            for info in sorted(html_files, key=lambda item: item.filename.lower()):
                parser = _VisibleTextParser()
                parser.feed(archive.read(info).decode("utf-8", errors="replace"))
                text = html.unescape(" ".join(parser.parts))
                if text.strip():
                    pages.extend(_split_text_pages(text))
                    if len(pages) > 1000:
                        raise ValueError("too_many_extracted_pages")
        if not pages:
            raise ValueError("epub_has_no_readable_text")
    else:
        raise ValueError("unsupported_file_format")
    if sum(len(page) for page in pages) > MAX_EXTRACTED_CHARS:
        raise ValueError("extracted_text_too_large")
    return pages, {}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def safe_original_name(value: str) -> str:
    name = Path(value.replace("\\", "/")).name
    name = re.sub(r"[^A-Za-z0-9._\-\u0600-\u06FF ]", "_", name).strip(" .")
    if not name or len(name) > 255:
        raise ValueError("invalid_file_name")
    return name


def _is_allowed_archive_download_url(value: str) -> bool:
    try:
        parsed = urlparse(value)
        host = (parsed.hostname or "").lower()
        allowed_host = host == "archive.org" or host.endswith(".archive.org")
        return (
            parsed.scheme == "https"
            and allowed_host
            and not parsed.username
            and not parsed.password
            and parsed.port in {None, 443}
        )
    except ValueError:
        return False


async def download_archive_file(identifier: str, file_name: str, destination: Path) -> tuple[int, str]:
    identifier = _ia_identifier(identifier)
    safe_name = safe_original_name(file_name)
    if safe_name != file_name or Path(file_name).suffix.lower().lstrip(".") not in ALLOWED_EXTENSIONS:
        raise ValueError("unsupported_archive_filename")
    current_url = f"{IA_ORIGIN}/download/{quote(identifier, safe='')}/{quote(file_name, safe='')}"
    settings = get_settings()
    maximum = min(MAX_IMPORT_BYTES, settings.max_upload_bytes)
    destination.parent.mkdir(parents=True, exist_ok=True)
    written = 0
    digest = hashlib.sha256()
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(25.0, connect=8.0), follow_redirects=False) as client:
            for redirect_count in range(6):
                if not _is_allowed_archive_download_url(current_url):
                    raise ValueError("archive_redirect_host_not_allowed")
                async with client.stream("GET", current_url, headers={"Accept": "application/octet-stream"}) as response:
                    if response.is_redirect:
                        location = response.headers.get("location")
                        if not location or redirect_count >= 5:
                            raise ValueError("archive_redirect_limit_exceeded")
                        current_url = urljoin(current_url, location)
                        continue
                    response.raise_for_status()
                    content_length = response.headers.get("content-length")
                    if content_length and content_length.isdigit() and int(content_length) > maximum:
                        raise ValueError("source_file_too_large")
                    with destination.open("xb") as output:
                        async for chunk in response.aiter_bytes(64 * 1024):
                            written += len(chunk)
                            if written > maximum:
                                raise ValueError("source_file_too_large")
                            digest.update(chunk)
                            output.write(chunk)
                    break
            else:
                raise ValueError("archive_redirect_limit_exceeded")
        if written <= 0:
            raise ValueError("source_file_empty")
        return written, digest.hexdigest()
    except Exception:
        destination.unlink(missing_ok=True)
        raise


def format_mime(extension: str) -> str:
    return {
        "pdf": "application/pdf",
        "epub": "application/epub+zip",
        "txt": "text/plain; charset=utf-8",
        "md": "text/markdown; charset=utf-8",
        "json": "application/json",
    }.get(extension, "application/octet-stream")
