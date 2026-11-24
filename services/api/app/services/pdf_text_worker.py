"""Bounded, text-only PDF extraction worker for the admin CMS.

The API launches this script only inside a Bubblewrap sandbox. It does not
perform OCR, fetch URLs, or write extracted text to disk.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

MAX_PDF_BYTES = 15 * 1024 * 1024
MAX_PAGES = 300
MAX_TEXT_CHARACTERS = 500_000


def _apply_resource_limits() -> None:
    """Apply hard process limits; fail rather than silently parsing unbounded."""
    import resource

    limits = (
        (resource.RLIMIT_CPU, 10),
        (resource.RLIMIT_AS, 384 * 1024 * 1024),
        (resource.RLIMIT_FSIZE, 0),
        (resource.RLIMIT_NOFILE, 32),
        (resource.RLIMIT_CORE, 0),
    )
    for resource_id, requested in limits:
        _soft, hard = resource.getrlimit(resource_id)
        effective = requested if hard == resource.RLIM_INFINITY else min(requested, hard)
        resource.setrlimit(resource_id, (effective, effective))


def extract_pdf_text(path: Path) -> dict[str, object]:
    if not path.is_file():
        raise ValueError("PDF file is unavailable")
    size = path.stat().st_size
    if size <= 0 or size > MAX_PDF_BYTES:
        raise ValueError("PDF size is outside the allowed limit")
    with path.open("rb") as stream:
        if stream.read(5) != b"%PDF-":
            raise ValueError("Invalid PDF signature")

    from pypdf import PdfReader

    reader = PdfReader(str(path), strict=True)
    if reader.is_encrypted:
        raise ValueError("Encrypted PDFs are not supported")
    page_count = len(reader.pages)
    if page_count < 1 or page_count > MAX_PAGES:
        raise ValueError("PDF page count is outside the allowed limit")

    pages: list[str] = []
    total_characters = 0
    for page in reader.pages:
        text = page.extract_text() or ""
        total_characters += len(text)
        if total_characters > MAX_TEXT_CHARACTERS:
            raise ValueError("Extracted text exceeds the allowed limit")
        pages.append(text.strip())

    extracted = "\n\n".join(text for text in pages if text)
    return {
        "ok": True,
        "page_count": page_count,
        "text": extracted,
        "page_texts": pages,
        "has_text": bool(extracted.strip()),
    }


def main(argv: list[str]) -> int:
    try:
        _apply_resource_limits()
        if len(argv) != 2 or Path(argv[1]) != Path("/work/input.pdf"):
            return 2
        result = extract_pdf_text(Path(argv[1]))
    except Exception:
        # Do not emit paths, document fragments, or parser internals to logs.
        sys.stderr.write("PDF extraction failed\n")
        return 1
    sys.stdout.write(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
