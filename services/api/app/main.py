from contextlib import asynccontextmanager
import asyncio
from datetime import datetime, timedelta, timezone, date
from hashlib import sha256
import json
import os
import re
import secrets
import stat
import tempfile
import time
from pathlib import Path
from zoneinfo import ZoneInfo
from urllib.parse import urlparse
from uuid import uuid4

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, Request, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator, model_validator
from sqlalchemy import func, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.dependencies import get_db, current_admin, require_admin_csrf
from app.core.security import (
    fingerprint, hash_password, keyed_hash, new_secret, session_expiry, verify_password,
)
from app.db.base import Base
from app.db.session import engine
from app.models import (
    AdminAuditLog, AdminSession, AdminUser, ContentItem, Governorate, PrayerCity, LoginThrottle,
    MediaAsset, PrayerCache, QuranAyah, QuranImport, QuranSurah, RadioChannel,
    AudioFile, Book, BookPage, BookReadingProgress, Dua, EthicsLesson,
    Favorite, Hadith, HadithGrading, HadithSource, IslamicEvent, Visit,
)
from app.services.governorates import seed_governorates
from app.services.prayer_cities import seed_prayer_cities
from app.services.prayer_times import METHODS, calculate_prayer_times
from app.services.public_catalog import CATALOG_TYPES, get_book_pages, list_catalog
from app.services.wallpapers import list_wallpapers, set_wallpaper_published
from app.services.pdf_sandbox import safe_temp_root, sandbox_status, worker_command
from app.services.pdf_text_worker import MAX_PDF_BYTES

settings = get_settings()
_pdf_extraction_jobs: dict[str, dict] = {}
_PDF_EXTRACTION_TIMEOUT_SECONDS = 15
_PDF_EXTRACTION_MAX_ACTIVE_JOBS = 1
_PDF_EXTRACTION_RETENTION_SECONDS = 1800


def _normalise_datetime(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def _audit(db: Session, admin_id: int | None, action: str, resource_type: str,
           resource_id: str | None, request: Request, details: dict | None = None) -> None:
    db.add(AdminAuditLog(
        admin_id=admin_id, action=action, resource_type=resource_type,
        resource_id=resource_id, details=details or {},
        ip_fingerprint=fingerprint(request.client.host if request.client else None),
    ))


def _bootstrap_admin(db: Session) -> None:
    username = settings.admin_bootstrap_username.strip()
    password = settings.admin_bootstrap_password
    existing_count = db.query(AdminUser).count()
    if existing_count:
        return
    if not username or len(password) < 16:
        if settings.app_env.lower() == "production":
            raise RuntimeError("No administrator exists. Set one-time ADMIN_BOOTSTRAP_USERNAME and ADMIN_BOOTSTRAP_PASSWORD secrets.")
        return
    db.add(AdminUser(
        username=username, email=settings.admin_bootstrap_email or "",
        password_hash=hash_password(password), role="owner", is_active=True,
        force_password_change=settings.admin_bootstrap_force_password_change,
    ))
    db.commit()


def _seed_radio(db: Session) -> None:
    if db.query(RadioChannel).count() == 0:
        db.add(RadioChannel(
            name="إذاعة الروضة الحسينية المقدسة",
            description="المصدر الرسمي متاح للزيارة. لم يُضبط رابط بث مباشر داخل التطبيق بعد التحقق من عنوان البث المباشر وحقوق استخدامه.",
            stream_url=None,
            official_source_url="https://imamhussain-fm.com/",
            is_verified=False,
            is_enabled=False,
        ))
        db.commit()


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings.validate_production()
    # create_all is retained for local bootstrap only; production deployment runs Alembic first.
    if settings.app_env.lower() != "production":
        Base.metadata.create_all(bind=engine)
    from app.db.session import SessionLocal
    db = SessionLocal()
    try:
        seed_governorates(db)
        seed_prayer_cities(db)
        _bootstrap_admin(db)
        _seed_radio(db)
    finally:
        db.close()
    yield


app = FastAPI(
    title="Khazain Al-Huda API",
    version="0.1.0",
    description="API for the Khazain Al-Huda Islamic knowledge and worship application.",
    docs_url=None if settings.app_env.lower() == "production" else "/docs",
    redoc_url=None if settings.app_env.lower() == "production" else "/redoc",
    lifespan=lifespan,
)

from app.routers.library import router as library_router  # noqa: E402
from app.routers.assistant import router as assistant_router  # noqa: E402

app.include_router(library_router)
app.include_router(assistant_router)

@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("X-Frame-Options", "DENY")
    response.headers.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
    response.headers.setdefault("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
    if settings.app_env.lower() == "production":
        response.headers.setdefault("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
    if request.url.path.startswith("/api/v1/admin") or request.url.path == "/admin":
        response.headers["Cache-Control"] = "no-store"
    return response


app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.origins or ["http://localhost:8080", "http://127.0.0.1:8080"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "X-CSRF-Token", "X-Device-Key"],
)


class LoginPayload(BaseModel):
    username: str = Field(min_length=1, max_length=80)
    password: str = Field(min_length=1, max_length=256)


class ChangePasswordPayload(BaseModel):
    current_password: str = Field(min_length=1, max_length=256)
    new_password: str = Field(min_length=14, max_length=256)


class ContentPayload(BaseModel):
    content_type: str = Field(pattern="^(announcement|news|notice|ethics_lesson|event|radio_promo|app_update)$")
    title: str = Field(min_length=1, max_length=180)
    body_markdown: str = Field(default="", max_length=30000)
    target_url: str | None = Field(default=None, max_length=2048)
    button_label: str | None = Field(default=None, max_length=60)
    status: str = Field(default="draft", pattern="^(draft|scheduled|published|paused|archived)$")
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    image_asset_id: int | None = None

    @field_validator("target_url")
    @classmethod
    def validate_target_url(cls, value):
        if value:
            parsed = urlparse(value)
            if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
                raise ValueError("Only absolute HTTPS URLs without embedded credentials are accepted")
        return value

    @field_validator("ends_at")
    @classmethod
    def validate_dates(cls, value, info):
        starts = info.data.get("starts_at")
        if value and starts and _normalise_datetime(value) <= _normalise_datetime(starts):
            raise ValueError("ends_at must be later than starts_at")
        return value


class RadioPayload(BaseModel):
    name: str = Field(min_length=1, max_length=160)
    description: str = Field(default="", max_length=4000)
    stream_url: str | None = Field(default=None, max_length=2048)
    official_source_url: str | None = Field(default=None, max_length=2048)
    rights_evidence: str | None = Field(default=None, min_length=12, max_length=12000)
    is_verified: bool = False
    is_enabled: bool = False

    @field_validator("stream_url", "official_source_url")
    @classmethod
    def https_only(cls, value):
        if value:
            parsed = urlparse(value)
            if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
                raise ValueError("Only absolute HTTPS URLs are accepted")
        return value

    @field_validator("rights_evidence")
    @classmethod
    def clean_rights_evidence(cls, value):
        value = value.strip() if value else None
        return value or None

    @model_validator(mode="after")
    def require_radio_rights_evidence(self):
        if self.is_verified and not (
            self.stream_url and self.official_source_url and self.rights_evidence
        ):
            raise ValueError(
                "Verification requires an HTTPS stream, official source, and documented reuse-permission evidence"
            )
        if self.is_enabled and not self.is_verified:
            raise ValueError("A radio channel cannot be enabled before verification")
        return self


# Strict CMS payloads. The application never invents religious text; administrators
# must supply source and rights evidence before publishing records.
class StrictPayload(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class WallpaperVisibilityPayload(StrictPayload):
    published: bool


class DeviceFavoritePayload(StrictPayload):
    entity_type: str = Field(pattern="^(book|hadith|dua|visit|event|ethics_lesson|audio|quran_ayah)$")
    entity_id: str = Field(min_length=1, max_length=100)


class BookReadingProgressPayload(StrictPayload):
    volume_number: int = Field(ge=1, le=1000)
    page_number: int = Field(ge=1, le=100000)


class PrayerCoordinatesPayload(StrictPayload):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    day: date | None = None
    method: str = Field(default='jafari_qom', min_length=1, max_length=40)


def _https_only(value: str | None) -> str | None:
    if value is None or value == "":
        return None
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
        raise ValueError("Only absolute HTTPS URLs without embedded credentials are accepted")
    return value


class BookAdminPayload(StrictPayload):
    category_id: int | None = Field(default=None, ge=1)
    title: str = Field(min_length=1, max_length=250)
    author: str | None = Field(default=None, max_length=180)
    editor: str | None = Field(default=None, max_length=180)
    publisher: str | None = Field(default=None, max_length=180)
    volume_count: int | None = Field(default=None, ge=1, le=1000)
    description: str = Field(default="", max_length=50000)
    source_url: str | None = Field(default=None, max_length=2048)
    rights_status: str = Field(default="unverified", pattern="^(licensed|public_domain|permission_granted|unverified)$")
    rights_evidence: str | None = Field(default=None, max_length=12000)
    offline_access_allowed: bool = False
    publication_status: str = Field(default="draft", pattern="^(draft|in_review|published|archived)$")

    @field_validator("source_url")
    @classmethod
    def validate_source_url(cls, value):
        return _https_only(value)

    @model_validator(mode="after")
    def validate_publication(self):
        if self.publication_status == "published":
            if self.rights_status not in {"licensed", "public_domain", "permission_granted"}:
                raise ValueError("A published book requires an approved rights status")
            if not self.rights_evidence or not self.source_url:
                raise ValueError("A published book requires rights evidence and a source URL")
        if self.offline_access_allowed and (
            self.rights_status not in {"licensed", "public_domain", "permission_granted"}
            or not self.rights_evidence or not self.source_url
        ):
            raise ValueError("Offline book access requires an approved rights status, rights evidence and a source URL")
        return self


class BookPageInput(StrictPayload):
    volume_number: int = Field(default=1, ge=1, le=1000)
    page_number: int = Field(ge=1, le=100000)
    text_content: str = Field(min_length=1, max_length=25000)


class BookPagesPayload(StrictPayload):
    pages: list[BookPageInput] = Field(min_length=1, max_length=250)

    @model_validator(mode="after")
    def validate_batch_size(self):
        if sum(len(page.text_content) for page in self.pages) > 2_000_000:
            raise ValueError("The combined page text in one import cannot exceed 2,000,000 characters")
        return self


class HadithSourceAdminPayload(StrictPayload):
    title: str = Field(min_length=1, max_length=250)
    author: str | None = Field(default=None, max_length=180)
    edition: str | None = Field(default=None, max_length=120)
    source_url: str | None = Field(default=None, max_length=2048)
    citation_policy: str = Field(default="", max_length=12000)

    @field_validator("source_url")
    @classmethod
    def validate_source_url(cls, value):
        return _https_only(value)


class HadithAdminPayload(StrictPayload):
    source_id: int = Field(ge=1)
    speaker: str = Field(min_length=1, max_length=150)
    text: str = Field(min_length=1, max_length=50000)
    chain_text: str | None = Field(default=None, max_length=30000)
    volume: str | None = Field(default=None, max_length=40)
    page: str | None = Field(default=None, max_length=40)
    hadith_number: str | None = Field(default=None, max_length=60)
    topic: str | None = Field(default=None, max_length=100)
    publication_status: str = Field(default="draft", pattern="^(draft|in_review|published|archived)$")

    @model_validator(mode="after")
    def validate_locator(self):
        if self.publication_status == "published" and not (self.hadith_number or (self.volume and self.page)):
            raise ValueError("A published hadith requires a number or both volume and page")
        return self


class HadithGradingAdminPayload(StrictPayload):
    grading: str = Field(min_length=1, max_length=80)
    scholar: str = Field(min_length=1, max_length=180)
    methodology: str = Field(min_length=1, max_length=180)
    citation: str = Field(min_length=1, max_length=12000)
    reviewed_at: datetime | None = None


class DuaAdminPayload(StrictPayload):
    category_id: int | None = Field(default=None, ge=1)
    title: str = Field(min_length=1, max_length=180)
    text: str = Field(min_length=1, max_length=50000)
    attribution: str | None = Field(default=None, max_length=180)
    source_id: int | None = Field(default=None, ge=1)
    source_reference: str | None = Field(default=None, max_length=250)
    publication_status: str = Field(default="draft", pattern="^(draft|in_review|published|archived)$")

    @model_validator(mode="after")
    def validate_source(self):
        if self.publication_status == "published" and not self.source_reference:
            raise ValueError("A published dua requires a source reference")
        return self


class VisitAdminPayload(StrictPayload):
    title: str = Field(min_length=1, max_length=180)
    text: str = Field(min_length=1, max_length=50000)
    visited_person: str | None = Field(default=None, max_length=180)
    source_reference: str = Field(default="", max_length=12000)
    publication_status: str = Field(default="draft", pattern="^(draft|in_review|published|archived)$")

    @model_validator(mode="after")
    def validate_source(self):
        if self.publication_status == "published" and not self.source_reference:
            raise ValueError("A published visit requires a source reference")
        return self


class HistoricalSourcePayload(StrictPayload):
    title: str = Field(min_length=1, max_length=250)
    author: str | None = Field(default=None, max_length=180)
    edition: str | None = Field(default=None, max_length=120)
    locator: str | None = Field(default=None, max_length=250)
    source_url: str | None = Field(default=None, max_length=2048)

    @field_validator("source_url")
    @classmethod
    def validate_source_url(cls, value):
        return _https_only(value)

    @model_validator(mode="after")
    def validate_locator(self):
        if not self.locator and not self.source_url:
            raise ValueError("Each historical source requires a page/locator or HTTPS URL")
        return self


class EventAdminPayload(StrictPayload):
    title: str = Field(min_length=1, max_length=180)
    hijri_month: int | None = Field(default=None, ge=1, le=12)
    hijri_day: int | None = Field(default=None, ge=1, le=30)
    expected_gregorian_date: date | None = None
    date_certainty: str = Field(default="disputed_or_local", pattern="^(confirmed|approximate|disputed_or_local)$")
    event_type: str = Field(min_length=1, max_length=30)
    description: str = Field(default="", max_length=12000)
    historical_sources: list[HistoricalSourcePayload] = Field(default_factory=list, max_length=30)
    notification_enabled: bool = False
    is_published: bool = False

    @model_validator(mode="after")
    def validate_event(self):
        if (self.hijri_month is None) != (self.hijri_day is None):
            raise ValueError("Hijri month and day must be supplied together")
        if self.is_published:
            if not self.historical_sources:
                raise ValueError("A published event requires at least one historical source")
            if self.hijri_month is None and self.expected_gregorian_date is None:
                raise ValueError("A published event requires a Hijri or Gregorian date")
        return self


class EthicsLessonAdminPayload(StrictPayload):
    slug: str = Field(min_length=2, max_length=100, pattern="^[a-z0-9][a-z0-9-]+$")
    title: str = Field(min_length=1, max_length=180)
    level: str = Field(default="beginner", pattern="^(beginner|intermediate|advanced)$")
    order_index: int = Field(default=0, ge=0, le=100000)
    introduction: str = Field(default="", max_length=12000)
    body_markdown: str = Field(min_length=1, max_length=50000)
    quran_reference: str | None = Field(default=None, max_length=120)
    hadith_id: int | None = Field(default=None, ge=1)
    practical_action: str = Field(default="", max_length=12000)
    publication_status: str = Field(default="draft", pattern="^(draft|in_review|published|archived)$")

    @model_validator(mode="after")
    def validate_references(self):
        if self.publication_status == "published" and not (self.quran_reference or self.hadith_id):
            raise ValueError("A published ethics lesson requires a Quran or hadith reference")
        return self


class AudioAdminPayload(StrictPayload):
    title: str = Field(min_length=1, max_length=250)
    reciter_id: int | None = Field(default=None, ge=1)
    category: str = Field(min_length=1, max_length=60)
    duration_seconds: int | None = Field(default=None, ge=1, le=86400)
    mime_type: str = Field(pattern="^(audio/mpeg|audio/mp4|audio/aac|audio/ogg|audio/wav|audio/flac)$")
    source_url: str = Field(min_length=1, max_length=2048)
    download_url: str | None = Field(default=None, max_length=2048)
    rights_status: str = Field(default="unverified", pattern="^(licensed|public_domain|permission_granted|unverified)$")
    rights_evidence: str | None = Field(default=None, max_length=12000)
    streaming_allowed: bool = False
    download_allowed: bool = False
    offline_cache_allowed: bool = False
    is_published: bool = False

    @field_validator("source_url", "download_url")
    @classmethod
    def validate_urls(cls, value):
        checked = _https_only(value)
        if value and not checked:
            raise ValueError("An HTTPS URL is required")
        return checked

    @model_validator(mode="after")
    def validate_rights(self):
        if self.offline_cache_allowed and not self.download_allowed:
            raise ValueError("Offline caching requires download permission")
        if self.download_allowed and not self.download_url:
            raise ValueError("Download permission requires a download URL")
        if self.is_published:
            if self.rights_status not in {"licensed", "public_domain", "permission_granted"}:
                raise ValueError("Published audio requires an approved rights status")
            if not self.rights_evidence or not self.streaming_allowed:
                raise ValueError("Published public audio requires rights evidence and streaming permission")
        return self


ADMIN_CATALOG_SCHEMAS = {
    "book": (Book, BookAdminPayload),
    "hadith_source": (HadithSource, HadithSourceAdminPayload),
    "hadith": (Hadith, HadithAdminPayload),
    "dua": (Dua, DuaAdminPayload),
    "visit": (Visit, VisitAdminPayload),
    "event": (IslamicEvent, EventAdminPayload),
    "ethics_lesson": (EthicsLesson, EthicsLessonAdminPayload),
    "audio": (AudioFile, AudioAdminPayload),
}


def _validate_catalog_payload(catalog_type: str, payload: dict) -> dict:
    schema = ADMIN_CATALOG_SCHEMAS[catalog_type][1]
    try:
        return schema.model_validate(payload).model_dump()
    except ValidationError as exc:
        safe_errors = [{"loc": list(error["loc"]), "msg": error["msg"], "type": error["type"]} for error in exc.errors()]
        raise HTTPException(status_code=422, detail=safe_errors) from exc


def _serialize_admin_catalog(catalog_type: str, row, db: Session) -> dict:
    data = {"id": row.id}
    if catalog_type == "book":
        fields = ("category_id", "title", "author", "editor", "publisher", "volume_count", "description", "source_url", "rights_status", "rights_evidence", "offline_access_allowed", "publication_status", "created_at")
    elif catalog_type == "hadith_source":
        fields = ("title", "author", "edition", "source_url", "citation_policy")
    elif catalog_type == "hadith":
        fields = ("source_id", "speaker", "text", "chain_text", "volume", "page", "hadith_number", "topic", "publication_status")
        grades = db.query(HadithGrading).filter(HadithGrading.hadith_id == row.id).order_by(HadithGrading.id.asc()).all()
        data["gradings"] = [{"id": g.id, "grading": g.grading, "scholar": g.scholar, "methodology": g.methodology, "citation": g.citation, "reviewed_at": g.reviewed_at.isoformat() if g.reviewed_at else None} for g in grades]
    elif catalog_type == "dua":
        fields = ("category_id", "title", "text", "attribution", "source_id", "source_reference", "publication_status")
    elif catalog_type == "visit":
        fields = ("title", "text", "visited_person", "source_reference", "publication_status")
    elif catalog_type == "event":
        fields = ("title", "hijri_month", "hijri_day", "expected_gregorian_date", "date_certainty", "event_type", "description", "historical_sources", "notification_enabled", "is_published")
    elif catalog_type == "ethics_lesson":
        fields = ("slug", "title", "level", "order_index", "introduction", "body_markdown", "quran_reference", "hadith_id", "practical_action", "publication_status")
    else:
        fields = ("title", "reciter_id", "category", "duration_seconds", "mime_type", "source_url", "download_url", "rights_status", "rights_evidence", "streaming_allowed", "download_allowed", "offline_cache_allowed", "is_published")
    for field_name in fields:
        value = getattr(row, field_name)
        data[field_name] = value.isoformat() if isinstance(value, (datetime, date)) else value
    return data


@app.get("/health")
def health():
    """Liveness probe: confirms that the ASGI process can answer requests."""
    return {"status": "ok", "service": "khazain-al-huda-api", "version": app.version}


@app.get("/ready")
def readiness(db: Session = Depends(get_db)):
    """Readiness probe: confirms that the configured relational database is reachable."""
    try:
        db.execute(text("SELECT 1"))
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Database is not ready") from exc
    return {"status": "ready", "database": "connected", "version": app.version}


@app.get("/api/v1/public/reference/sources")
def get_reference_sources():
    source_file = Path(__file__).resolve().parent / "data" / "source_catalog.json"
    try:
        records = json.loads(source_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise HTTPException(status_code=503, detail="Reference source catalogue is unavailable") from exc
    if not isinstance(records, list):
        raise HTTPException(status_code=503, detail="Reference source catalogue has an invalid format")
    public_fields = (
        "source_id", "name", "category", "official_url", "observed",
        "use_for", "license_status", "notes",
    )
    return [{key: item.get(key) for key in public_fields} for item in records if isinstance(item, dict)]


@app.get("/api/v1/public/governorates")
def get_governorates(db: Session = Depends(get_db)):
    rows = db.query(Governorate).order_by(Governorate.name_ar).all()
    return [{
        "id": row.id, "name_ar": row.name_ar, "name_en": row.name_en,
        "latitude": row.latitude, "longitude": row.longitude,
        "timezone": row.timezone, "coordinates_quality": row.coordinates_quality,
    } for row in rows]


@app.get("/api/v1/public/prayer/cities")
def get_prayer_cities(
    governorate_id: str | None = None,
    q: str | None = None,
    db: Session = Depends(get_db),
):
    if q is not None and len(q) > 80:
        raise HTTPException(status_code=422, detail="Search term is too long")
    query = db.query(PrayerCity)
    if governorate_id:
        query = query.filter(PrayerCity.governorate_id == governorate_id)
    if q:
        term = q.strip()
        if term:
            query = query.filter(
                (PrayerCity.city_name_ar.contains(term))
                | (PrayerCity.city_name_en.ilike(f"%{term}%"))
                | (PrayerCity.governorate_name_ar.contains(term))
            )
    rows = query.order_by(PrayerCity.governorate_name_ar, PrayerCity.city_name_ar).all()
    return [{
        "city_id": row.city_id,
        "governorate_id": row.governorate_id,
        "governorate_name_ar": row.governorate_name_ar,
        "city_name_ar": row.city_name_ar,
        "city_name_en": row.city_name_en,
        "latitude": row.latitude,
        "longitude": row.longitude,
        "timezone": row.timezone,
        "coordinate_source": row.coordinate_source,
        "coordinate_accuracy": row.coordinate_accuracy,
        "verified": row.verified,
    } for row in rows]


@app.get("/api/v1/public/prayer/methods")
def get_prayer_methods():
    return [{
        "id": method.id, "label_ar": method.label_ar, "label_en": method.label_en,
        "parameters": {
            "fajr_degrees": method.fajr_angle,
            "maghrib_degrees": method.maghrib_angle,
            "isha_degrees": method.isha_angle,
        },
        "reference": method.source_url,
        "officially_verified": False,
        "verification_status": "reference_profile_not_officially_verified",
        "notice_ar": "ملف حساب فلكي مرجعي غير معتمد من مرجعية دينية ضمن الحزمة الحالية.",
    } for method in METHODS.values()]


@app.get("/api/v1/public/prayer/times")
def get_prayer_times(
    governorate_id: str | None = None,
    city_id: str | None = None,
    day: date | None = None,
    method: str = "jafari_qom",
    latitude: float | None = None,
    longitude: float | None = None,
    db: Session = Depends(get_db),
):
    if day is None:
        day = datetime.now(ZoneInfo("Asia/Baghdad")).date()
    timezone_name = "Asia/Baghdad"
    location = None
    city = None
    if city_id and governorate_id:
        raise HTTPException(status_code=422, detail="Provide either city_id or governorate_id, not both")
    if city_id:
        city = db.get(PrayerCity, city_id)
        if not city:
            raise HTTPException(status_code=404, detail="Prayer city not found")
        latitude, longitude, timezone_name = city.latitude, city.longitude, city.timezone
    elif governorate_id:
        location = db.get(Governorate, governorate_id)
        if not location:
            raise HTTPException(status_code=404, detail="Governorate not found")
        latitude, longitude, timezone_name = location.latitude, location.longitude, location.timezone
    if latitude is None or longitude is None:
        raise HTTPException(status_code=422, detail="Provide a governorate_id or both latitude and longitude")
    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        raise HTTPException(status_code=422, detail="Invalid coordinates")
    location_identity = (
        f"city:{city.city_id}" if city else
        f"governorate:{location.id}" if location else
        f"coordinates:{latitude:.4f}:{longitude:.4f}"
    )
    cacheable_location = city is not None or location is not None
    cache_key = f"{day}:{location_identity}:{latitude:.4f}:{longitude:.4f}:{method}:{timezone_name}"
    cached = db.get(PrayerCache, cache_key) if cacheable_location else None
    now = datetime.now(timezone.utc)
    if cached and (_normalise_datetime(cached.valid_until) > now):
        payload = dict(cached.payload)
        payload["cache_status"] = "cached"
        payload.setdefault("method", {})["officially_verified"] = False
        payload["method"]["verification_status"] = "reference_profile_not_officially_verified"
        payload["method"]["notice_ar"] = "ملف حساب فلكي مرجعي غير معتمد من مرجعية دينية ضمن الحزمة الحالية."
        return payload
    try:
        payload = calculate_prayer_times(day, latitude, longitude, method, timezone_name)
    except (ValueError, KeyError) as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    payload.setdefault("method", {})["officially_verified"] = False
    payload["method"]["verification_status"] = "reference_profile_not_officially_verified"
    payload["method"]["notice_ar"] = "ملف حساب فلكي مرجعي غير معتمد من مرجعية دينية ضمن الحزمة الحالية."
    payload["location"] = {
        "governorate_id": city.governorate_id if city else (location.id if location else None),
        "governorate_name_ar": city.governorate_name_ar if city else (location.name_ar if location else None),
        "city_id": city.city_id if city else None,
        "city_name_ar": city.city_name_ar if city else None,
        "name_ar": city.city_name_ar if city else (location.name_ar if location else None),
        "latitude": latitude,
        "longitude": longitude,
        "timezone": timezone_name,
        "coordinates_quality": city.coordinate_accuracy if city else (location.coordinates_quality if location else "user_supplied_coordinates"),
        "coordinate_source": city.coordinate_source if city else None,
        "verified": city.verified if city else None,
    }
    if not cacheable_location:
        # Exact user-provided coordinates are used for this calculation only and are not persisted in PrayerCache.
        payload["cache_status"] = "not_cached_user_coordinates"
        return payload
    payload["cache_status"] = "calculated"
    expiry = now + timedelta(seconds=max(60, settings.public_api_cache_seconds))
    record = cached or PrayerCache(cache_key=cache_key, payload=payload, valid_until=expiry)
    record.payload, record.valid_until, record.updated_at = payload, expiry, now
    db.add(record)
    try:
        db.commit()
    except IntegrityError:
        # Concurrent first requests may race to insert the same deterministic cache key.
        # Roll back this transaction and prefer the committed winner's value.
        db.rollback()
        winner = db.get(PrayerCache, cache_key)
        if winner is None:
            raise
        winner_payload = dict(winner.payload)
        winner_payload["cache_status"] = "cached"
        return winner_payload
    return payload


@app.post("/api/v1/public/prayer/times/coordinates")
def get_prayer_times_for_user_coordinates(
    payload: PrayerCoordinatesPayload,
    db: Session = Depends(get_db),
):
    return get_prayer_times(
        governorate_id=None,
        city_id=None,
        day=payload.day,
        method=payload.method,
        latitude=payload.latitude,
        longitude=payload.longitude,
        db=db,
    )


@app.get("/api/v1/public/quran/status")
def quran_status(db: Session = Depends(get_db)):
    count = db.query(QuranAyah).count()
    surah_count = db.query(QuranSurah).count()
    latest = db.query(QuranImport).order_by(QuranImport.imported_at.desc(), QuranImport.id.desc()).first()
    structure_count = db.query(QuranAyah).filter(
        QuranAyah.juz_number.is_not(None),
        QuranAyah.hizb_number.is_not(None),
        QuranAyah.page_number.is_not(None),
    ).count()
    structure_complete = structure_count == 6236
    approved = bool(latest and latest.approved_by is not None and latest.reviewer_name and latest.reviewer_credential and latest.reviewed_at)
    if count != 6236 or surah_count != 114 or not structure_complete or not approved:
        return {
            "status": ("imported_pending_review" if count == 6236 and surah_count == 114 and structure_complete and not approved
                       else "awaiting_structure" if count == 6236 and surah_count == 114 and not structure_complete
                       else "not_ready"),
            "message_ar": "لم يُستورد بعد نص قرآني موثّق ومراجع. لن يُعرض نص بديل أو مولّد.",
            "surah_count": surah_count,
            "ayah_count": count,
            "expected_surah_count": 114,
            "expected_ayah_count": 6236,
            "structural_metadata_ayah_count": structure_count,
            "review_required": count == 6236 and surah_count == 114 and structure_complete and not approved,
        }
    return {
        "status": "ready",
        "surah_count": surah_count,
        "ayah_count": count,
        "source": latest.source_name if latest else None,
        "source_version": latest.source_version if latest else None,
        "text_sha256": latest.text_sha256 if latest else None,
    }


@app.get("/api/v1/public/quran/surahs")
def quran_surahs(db: Session = Depends(get_db)):
    latest = db.query(QuranImport).order_by(QuranImport.imported_at.desc(), QuranImport.id.desc()).first()
    structure_count = db.query(QuranAyah).filter(QuranAyah.juz_number.is_not(None), QuranAyah.hizb_number.is_not(None), QuranAyah.page_number.is_not(None)).count()
    approval_complete = bool(latest and latest.approved_by is not None and latest.reviewer_name and latest.reviewer_credential and latest.reviewed_at)
    if db.query(QuranAyah).count() != 6236 or db.query(QuranSurah).count() != 114 or structure_count != 6236 or not approval_complete:
        raise HTTPException(status_code=503, detail="Quran dataset has not passed import and scholarly review")
    rows = db.query(QuranSurah).order_by(QuranSurah.number).all()
    return [{"number": r.number, "name_ar": r.name_ar, "name_en": r.name_en, "ayah_count": r.ayah_count} for r in rows]


@app.get("/api/v1/public/quran/surahs/{surah_number}/ayahs")
def quran_surah_ayahs(
    surah_number: int,
    limit: int = 100,
    offset: int = 0,
    db: Session = Depends(get_db),
):
    """Return Uthmani ayah text only after the complete imported dataset is approved."""
    if not 1 <= surah_number <= 114:
        raise HTTPException(status_code=422, detail="Surah number must be between 1 and 114")
    if not 1 <= limit <= 300 or not 0 <= offset <= 286:
        raise HTTPException(status_code=422, detail="Invalid Quran pagination parameters")

    latest = _approved_quran_import(db)
    if latest is None:
        raise HTTPException(status_code=503, detail="Quran dataset has not passed complete import and scholarly review")

    surah = db.get(QuranSurah, surah_number)
    if surah is None:
        raise HTTPException(status_code=404, detail="Surah not found")
    all_ayahs = db.query(QuranAyah).filter(
        QuranAyah.surah_number == surah_number,
    ).order_by(QuranAyah.ayah_number.asc()).all()
    if (
        len(all_ayahs) != surah.ayah_count
        or not all_ayahs
        or any(row.ayah_number != index for index, row in enumerate(all_ayahs, start=1))
        or any(not row.text_uthmani.strip() for row in all_ayahs)
    ):
        raise HTTPException(status_code=503, detail="Surah text failed sequential integrity validation")

    selected = all_ayahs[offset:offset + limit]
    return {
        "surah": {
            "number": surah.number,
            "name_ar": surah.name_ar,
            "name_en": surah.name_en,
            "ayah_count": surah.ayah_count,
        },
        "items": [{
            "surah_number": row.surah_number,
            "ayah_number": row.ayah_number,
            "text_uthmani": row.text_uthmani,
            "juz_number": row.juz_number,
            "hizb_number": row.hizb_number,
            "page_number": row.page_number,
            "sajdah": row.sajdah,
        } for row in selected],
        "total": surah.ayah_count,
        "limit": limit,
        "offset": offset,
        "source": latest.source_name,
        "source_version": latest.source_version,
        "text_sha256": latest.text_sha256,
    }


@app.get("/api/v1/public/radio")
def public_radio(db: Session = Depends(get_db)):
    channel = db.query(RadioChannel).filter(
        RadioChannel.is_enabled.is_(True), RadioChannel.is_verified.is_(True),
        RadioChannel.rights_evidence.is_not(None),
        func.length(func.trim(RadioChannel.rights_evidence)) >= 12,
        RadioChannel.rights_reviewed_at.is_not(None),
        RadioChannel.stream_url.is_not(None), RadioChannel.official_source_url.is_not(None),
    ).first()
    if not channel or not channel.stream_url:
        return {
            "status": "not_configured",
            "name": "إذاعة الروضة الحسينية المقدسة",
            "stream_url": None,
            "official_source_url": "https://imamhussain-fm.com/",
            "message_ar": "رابط البث المباشر لم يُتحقق منه بعد؛ افتح المصدر الرسمي للاستماع.",
        }
    return {
        "status": "available", "name": channel.name,
        "description": channel.description, "stream_url": channel.stream_url,
        "official_source_url": channel.official_source_url,
    }


@app.get("/api/v1/public/wallpapers")
def public_wallpapers(db: Session = Depends(get_db)):
    return {
        "items": [
            {"id": item["id"]}
            for item in list_wallpapers(db)
            if item["published"]
        ]
    }


@app.get("/api/v1/public/catalog/{catalog_type}")
def public_catalog(
    catalog_type: str,
    search: str | None = None,
    limit: int = 30,
    offset: int = 0,
    db: Session = Depends(get_db),
):
    if catalog_type not in CATALOG_TYPES:
        raise HTTPException(status_code=404, detail="Catalog section not found")
    if search is not None and len(search) > 100:
        raise HTTPException(status_code=422, detail="Search term is too long")
    if not 1 <= limit <= 100 or not 0 <= offset <= 100000:
        raise HTTPException(status_code=422, detail="Invalid pagination parameters")
    return list_catalog(db, catalog_type, search=search, limit=limit, offset=offset)


@app.get("/api/v1/public/books/{book_id}/pages")
def public_book_pages(
    book_id: int,
    volume_number: int = 1,
    limit: int = 40,
    offset: int = 0,
    start_page_number: int | None = None,
    db: Session = Depends(get_db),
):
    if (book_id < 1 or volume_number < 1 or not 1 <= limit <= 100 or not 0 <= offset <= 100000
            or (start_page_number is not None and not 1 <= start_page_number <= 100000)):
        raise HTTPException(status_code=422, detail="Invalid book pagination parameters")
    raise HTTPException(status_code=404, detail="The books section has been cleared")


def _require_device_hash(x_device_key: str = Header(default="", alias="X-Device-Key")) -> str:
    # The device key namespaces low-sensitivity anonymous preferences only. It is
    # not an account credential and never authorizes access to private records.
    if not re.fullmatch(r"[A-Za-z0-9_-]{32,128}", x_device_key or ""):
        raise HTTPException(status_code=422, detail="A valid X-Device-Key header is required")
    return keyed_hash(x_device_key)


def _approved_quran_import(db: Session) -> QuranImport | None:
    """Return only the latest fully approved import after whole-dataset checks."""
    latest = db.query(QuranImport).order_by(QuranImport.imported_at.desc(), QuranImport.id.desc()).first()
    if latest is None:
        return None
    total_ayahs = db.query(QuranAyah).count()
    total_surahs = db.query(QuranSurah).count()
    structural_ayahs = db.query(QuranAyah).filter(
        QuranAyah.juz_number.is_not(None),
        QuranAyah.hizb_number.is_not(None),
        QuranAyah.page_number.is_not(None),
    ).count()
    approved = bool(
        latest.approved_by is not None and latest.reviewer_name
        and latest.reviewer_credential and latest.reviewed_at
    )
    if total_ayahs != 6236 or total_surahs != 114 or structural_ayahs != 6236 or not approved:
        return None
    return latest


def _resolve_favorite_item(
    db: Session, entity_type: str, entity_id: str, *, quran_ready: bool | None = None,
) -> dict | None:
    reusable_rights = {"licensed", "public_domain", "permission_granted"}
    if entity_type in {"book", "hadith", "dua", "visit"}:
        return None
    if entity_type == "quran_ayah":
        match = re.fullmatch(r"([1-9][0-9]{0,2}):([1-9][0-9]{0,2})", entity_id)
        if not match:
            return None
        surah_number, ayah_number = map(int, match.groups())
        is_ready = _approved_quran_import(db) is not None if quran_ready is None else quran_ready
        if not is_ready or not 1 <= surah_number <= 114:
            return None
        surah = db.get(QuranSurah, surah_number)
        if not surah or not 1 <= ayah_number <= surah.ayah_count:
            return None
        ayah = db.query(QuranAyah).filter(
            QuranAyah.surah_number == surah_number, QuranAyah.ayah_number == ayah_number,
        ).first()
        if not ayah:
            return None
        return {"title": f"{surah.name_ar} · الآية {ayah_number}", "subtitle": "المصحف الشريف"}

    if not re.fullmatch(r"[1-9][0-9]{0,8}", entity_id):
        return None
    row_id = int(entity_id)
    if entity_type == "book":
        row = db.get(Book, row_id)
        if not row or row.publication_status != "published" or row.rights_status not in reusable_rights or not row.rights_evidence or not _https_only(row.source_url):
            return None
        return {"title": row.title, "subtitle": row.author or "كتاب"}
    if entity_type == "hadith":
        row = db.get(Hadith, row_id)
        if not row or row.publication_status != "published" or not (row.hadith_number or (row.volume and row.page)):
            return None
        source = db.get(HadithSource, row.source_id)
        if not source:
            return None
        return {"title": row.topic or row.speaker, "subtitle": f"{source.title} · {row.hadith_number or (row.volume + '/' + row.page)}"}
    if entity_type == "dua":
        row = db.get(Dua, row_id)
        if not row or row.publication_status != "published" or not row.source_reference:
            return None
        return {"title": row.title, "subtitle": row.source_reference}
    if entity_type == "visit":
        row = db.get(Visit, row_id)
        if not row or row.publication_status != "published" or not row.source_reference:
            return None
        return {"title": row.title, "subtitle": row.source_reference}
    if entity_type == "event":
        row = db.get(IslamicEvent, row_id)
        if not row or not row.is_published or not isinstance(row.historical_sources, list) or not row.historical_sources:
            return None
        return {"title": row.title, "subtitle": f"مناسبة · {row.date_certainty}"}
    if entity_type == "ethics_lesson":
        row = db.get(EthicsLesson, row_id)
        if not row or row.publication_status != "published":
            return None
        return {"title": row.title, "subtitle": row.level}
    if entity_type == "audio":
        row = db.get(AudioFile, row_id)
        if not row or not row.is_published or row.rights_status not in reusable_rights or not row.rights_evidence or not row.streaming_allowed or not _https_only(row.source_url):
            return None
        return {"title": row.title, "subtitle": row.category}
    return None


@app.get("/api/v1/user/favorites")
def list_device_favorites(
    device_hash: str = Depends(_require_device_hash), db: Session = Depends(get_db),
):
    rows = db.query(Favorite).filter(
        Favorite.user_id.is_(None), Favorite.device_key_hash == device_hash,
    ).order_by(Favorite.created_at.desc(), Favorite.id.desc()).limit(100).all()
    items = []
    quran_ready = _approved_quran_import(db) is not None if any(row.entity_type == "quran_ayah" for row in rows) else False
    for row in rows:
        resolved = _resolve_favorite_item(db, row.entity_type, row.entity_id, quran_ready=quran_ready)
        items.append({
            "entity_type": row.entity_type,
            "entity_id": row.entity_id,
            "title": resolved["title"] if resolved else "مادة لم تعد متاحة",
            "subtitle": resolved["subtitle"] if resolved else "قد تكون أُرشفت أو سُحبت صلاحية نشرها",
            "available": resolved is not None,
            "created_at": row.created_at.isoformat(),
        })
    return {"items": items, "total": len(items), "limit": 100}


@app.post("/api/v1/user/favorites", status_code=200)
def add_device_favorite(
    payload: DeviceFavoritePayload,
    device_hash: str = Depends(_require_device_hash), db: Session = Depends(get_db),
):
    quran_ready = _approved_quran_import(db) is not None if payload.entity_type == "quran_ayah" else False
    resolved = _resolve_favorite_item(db, payload.entity_type, payload.entity_id, quran_ready=quran_ready)
    if not resolved:
        raise HTTPException(status_code=404, detail="Published and provenance-approved content was not found")
    existing = db.query(Favorite).filter(
        Favorite.user_id.is_(None), Favorite.device_key_hash == device_hash,
        Favorite.entity_type == payload.entity_type, Favorite.entity_id == payload.entity_id,
    ).first()
    if not existing:
        favorite_count = db.query(Favorite).filter(
            Favorite.user_id.is_(None), Favorite.device_key_hash == device_hash,
        ).count()
        if favorite_count >= 100:
            raise HTTPException(status_code=409, detail="A device can keep at most 100 favorites")
        db.add(Favorite(
            user_id=None, device_key_hash=device_hash,
            entity_type=payload.entity_type, entity_id=payload.entity_id,
        ))
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            existing = db.query(Favorite).filter(
                Favorite.user_id.is_(None), Favorite.device_key_hash == device_hash,
                Favorite.entity_type == payload.entity_type, Favorite.entity_id == payload.entity_id,
            ).first()
            if not existing:
                raise HTTPException(status_code=409, detail="Favorite could not be saved; retry safely")
    return {"saved": True, "entity_type": payload.entity_type, "entity_id": payload.entity_id, **resolved}


@app.delete("/api/v1/user/favorites/{entity_type}/{entity_id}")
def remove_device_favorite(
    entity_type: str, entity_id: str,
    device_hash: str = Depends(_require_device_hash), db: Session = Depends(get_db),
):
    if entity_type not in {"book", "hadith", "dua", "visit", "event", "ethics_lesson", "audio", "quran_ayah"}:
        raise HTTPException(status_code=404, detail="Favorite not found")
    row = db.query(Favorite).filter(
        Favorite.user_id.is_(None), Favorite.device_key_hash == device_hash,
        Favorite.entity_type == entity_type, Favorite.entity_id == entity_id,
    ).first()
    if row:
        db.delete(row)
        db.commit()
    return {"removed": row is not None}


@app.get("/api/v1/user/books/{book_id}/reading-progress")
def get_device_book_progress(
    book_id: int, device_hash: str = Depends(_require_device_hash),
):
    raise HTTPException(status_code=404, detail="The books section has been cleared")


@app.put("/api/v1/user/books/{book_id}/reading-progress")
def save_device_book_progress(
    book_id: int, payload: BookReadingProgressPayload,
    device_hash: str = Depends(_require_device_hash),
):
    raise HTTPException(status_code=404, detail="The books section has been cleared")


@app.get("/api/v1/public/content")
def public_content(content_type: str | None = None, db: Session = Depends(get_db)):
    now = datetime.now(timezone.utc)
    query = db.query(ContentItem).filter(ContentItem.status == "published")
    if content_type:
        query = query.filter(ContentItem.content_type == content_type)
    rows = query.order_by(ContentItem.created_at.desc()).limit(50).all()
    output = []
    for row in rows:
        starts = _normalise_datetime(row.starts_at)
        ends = _normalise_datetime(row.ends_at)
        if starts and starts > now:
            continue
        if ends and ends <= now:
            continue
        image_url = None
        if row.content_type == "announcement" and row.image_asset_id is not None:
            asset = db.get(MediaAsset, row.image_asset_id)
            if asset and asset.mime_type in {"image/jpeg", "image/png", "image/webp"}:
                asset_path = settings.media_path / asset.storage_name
                try:
                    if asset_path.resolve().parent == settings.media_path.resolve() and asset_path.is_file():
                        image_url = f"/api/v1/public/content-assets/{asset.id}"
                except OSError:
                    image_url = None
        output.append({
            "id": row.id, "content_type": row.content_type, "title": row.title,
            "body_markdown": row.body_markdown, "target_url": row.target_url,
            "button_label": row.button_label, "image_url": image_url,
            "created_at": row.created_at.isoformat(),
        })
    return output


@app.get("/api/v1/public/content-assets/{asset_id}")
def public_content_asset(asset_id: int, db: Session = Depends(get_db)):
    """Serve only image assets attached to a currently active published ad."""
    now = datetime.now(timezone.utc)
    asset = db.get(MediaAsset, asset_id)
    if not asset or asset.mime_type not in {"image/jpeg", "image/png", "image/webp"}:
        raise HTTPException(status_code=404, detail="Content asset not found")
    rows = db.query(ContentItem).filter(
        ContentItem.content_type == "announcement",
        ContentItem.status == "published",
        ContentItem.image_asset_id == asset_id,
    ).all()
    active = any(
        (_normalise_datetime(row.starts_at) is None or _normalise_datetime(row.starts_at) <= now)
        and (_normalise_datetime(row.ends_at) is None or _normalise_datetime(row.ends_at) > now)
        for row in rows
    )
    if not active:
        raise HTTPException(status_code=404, detail="Content asset not found")
    try:
        media_root = settings.media_path.resolve()
        asset_path = (media_root / asset.storage_name).resolve(strict=True)
        if asset_path.parent != media_root or not asset_path.is_file() or asset_path.stat().st_size != asset.byte_size:
            raise HTTPException(status_code=404, detail="Content asset not found")
    except OSError as exc:
        raise HTTPException(status_code=404, detail="Content asset not found") from exc
    return FileResponse(
        asset_path,
        media_type=asset.mime_type,
        headers={
            "Cache-Control": "public, max-age=300",
            "X-Content-Type-Options": "nosniff",
            "Content-Disposition": "inline",
        },
    )


def _validate_admin_origin(request: Request) -> None:
    origin = request.headers.get("origin")
    if origin and settings.origins and origin.rstrip("/") not in settings.origins:
        raise HTTPException(status_code=403, detail="Origin not allowed")


def _client_fingerprint(request: Request) -> str:
    host = request.client.host if request.client else "unknown"
    return keyed_hash(host)


def _apply_login_failure(db: Session, key_hash: str, now: datetime) -> None:
    row = db.get(LoginThrottle, key_hash)
    if row is None:
        row = LoginThrottle(key_hash=key_hash, failures=1, window_started_at=now)
    else:
        started = _normalise_datetime(row.window_started_at)
        if now - started > timedelta(minutes=15):
            row.failures, row.window_started_at, row.blocked_until = 1, now, None
        else:
            row.failures += 1
        if row.failures >= 5:
            row.blocked_until = now + timedelta(minutes=15)
    db.add(row)
    db.commit()


@app.post("/api/v1/admin/auth/login")
def admin_login(payload: LoginPayload, request: Request, db: Session = Depends(get_db)):
    _validate_admin_origin(request)
    now = datetime.now(timezone.utc)
    throttle_key = keyed_hash(f"{payload.username.lower()}:{_client_fingerprint(request)}")
    throttle = db.get(LoginThrottle, throttle_key)
    if throttle and throttle.blocked_until and _normalise_datetime(throttle.blocked_until) > now:
        raise HTTPException(status_code=429, detail="Too many attempts. Try again later.")
    admin = db.query(AdminUser).filter(func.lower(AdminUser.username) == payload.username.lower()).first()
    valid = bool(admin and admin.is_active and verify_password(admin.password_hash, payload.password))
    if not valid:
        _apply_login_failure(db, throttle_key, now)
        raise HTTPException(status_code=401, detail="Invalid username or password")
    if throttle:
        db.delete(throttle)
    raw_token, raw_csrf = new_secret(), new_secret()
    session = AdminSession(
        admin_id=admin.id, token_hash=keyed_hash(raw_token), csrf_hash=keyed_hash(raw_csrf),
        expires_at=session_expiry(), ip_fingerprint=fingerprint(request.client.host if request.client else None),
        user_agent_fingerprint=fingerprint(request.headers.get("user-agent")),
    )
    admin.last_login_at = now
    db.add(session)
    _audit(db, admin.id, "admin.login", "admin_session", None, request)
    db.commit()
    response = {
        "authenticated": True,
        "csrf_token": raw_csrf,
        "user": {"username": admin.username, "role": admin.role, "force_password_change": admin.force_password_change},
    }
    from fastapi.responses import JSONResponse
    result = JSONResponse(response)
    result.set_cookie(
        "kh_admin_session", raw_token, httponly=True, secure=settings.cookie_secure,
        samesite="strict", max_age=8 * 60 * 60, path="/api/v1/admin",
    )
    result.set_cookie(
        "kh_admin_csrf", raw_csrf, httponly=False, secure=settings.cookie_secure,
        samesite="strict", max_age=8 * 60 * 60, path="/",
    )
    return result


@app.get("/api/v1/admin/auth/me")
def admin_me(admin: AdminUser = Depends(current_admin)):
    return {"username": admin.username, "role": admin.role, "force_password_change": admin.force_password_change}


@app.post("/api/v1/admin/auth/logout")
def admin_logout(request: Request, admin: AdminUser = Depends(require_admin_csrf), db: Session = Depends(get_db)):
    session = request.state.admin_session
    session.revoked_at = datetime.now(timezone.utc)
    _audit(db, admin.id, "admin.logout", "admin_session", str(session.id), request)
    db.commit()
    from fastapi.responses import JSONResponse
    result = JSONResponse({"logged_out": True})
    result.delete_cookie("kh_admin_session", path="/api/v1/admin")
    result.delete_cookie("kh_admin_csrf", path="/")
    return result


@app.post("/api/v1/admin/auth/change-password")
def admin_change_password(payload: ChangePasswordPayload, request: Request,
                          admin: AdminUser = Depends(require_admin_csrf), db: Session = Depends(get_db)):
    if not verify_password(admin.password_hash, payload.current_password):
        raise HTTPException(status_code=400, detail="Current password is incorrect")
    if payload.current_password == payload.new_password:
        raise HTTPException(status_code=422, detail="Choose a different password")
    try:
        admin.password_hash = hash_password(payload.new_password)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    admin.force_password_change = False
    now = datetime.now(timezone.utc)
    db.query(AdminSession).filter(AdminSession.admin_id == admin.id, AdminSession.revoked_at.is_(None)).update({"revoked_at": now})
    _audit(db, admin.id, "admin.password_changed", "admin_user", str(admin.id), request)
    db.commit()
    from fastapi.responses import JSONResponse
    result = JSONResponse({"password_changed": True, "message": "Sign in again with the new password."})
    result.delete_cookie("kh_admin_session", path="/api/v1/admin")
    result.delete_cookie("kh_admin_csrf", path="/")
    return result


def _require_password_rotated(admin: AdminUser):
    if admin.force_password_change:
        raise HTTPException(status_code=403, detail="Initial password must be changed before using the dashboard")


@app.get("/api/v1/admin/overview")
def admin_overview(admin: AdminUser = Depends(current_admin), db: Session = Depends(get_db)):
    _require_password_rotated(admin)
    return {
        "governorates": db.query(Governorate).count(),
        "content_total": db.query(ContentItem).count(),
        "content_published": db.query(ContentItem).filter(ContentItem.status == "published").count(),
        "media_assets": db.query(MediaAsset).count(),
        "quran_surahs": db.query(QuranSurah).count(),
        "quran_ayahs": db.query(QuranAyah).count(),
        "admin_users": db.query(AdminUser).filter(AdminUser.is_active.is_(True)).count(),
    }


@app.get("/api/v1/admin/content")
def admin_list_content(admin: AdminUser = Depends(current_admin), db: Session = Depends(get_db)):
    _require_password_rotated(admin)
    rows = db.query(ContentItem).order_by(ContentItem.updated_at.desc()).limit(200).all()
    return [{
        "id": r.id, "content_type": r.content_type, "title": r.title,
        "body_markdown": r.body_markdown, "target_url": r.target_url,
        "button_label": r.button_label, "status": r.status,
        "starts_at": r.starts_at.isoformat() if r.starts_at else None,
        "ends_at": r.ends_at.isoformat() if r.ends_at else None,
        "created_at": r.created_at.isoformat(), "updated_at": r.updated_at.isoformat(),
    } for r in rows]


def _content_values(payload: ContentPayload) -> dict:
    return {
        "content_type": payload.content_type, "title": payload.title.strip(),
        "body_markdown": payload.body_markdown, "target_url": payload.target_url,
        "button_label": payload.button_label, "status": payload.status,
        "starts_at": _normalise_datetime(payload.starts_at), "ends_at": _normalise_datetime(payload.ends_at),
        "image_asset_id": payload.image_asset_id,
    }


@app.post("/api/v1/admin/content", status_code=201)
def admin_create_content(payload: ContentPayload, request: Request,
                         admin: AdminUser = Depends(require_admin_csrf), db: Session = Depends(get_db)):
    _require_password_rotated(admin)
    if payload.image_asset_id and not db.get(MediaAsset, payload.image_asset_id):
        raise HTTPException(status_code=422, detail="Media asset not found")
    row = ContentItem(**_content_values(payload), created_by=admin.id)
    db.add(row)
    db.flush()
    _audit(db, admin.id, "content.created", "content_item", str(row.id), request, {"status": row.status})
    db.commit()
    return {"id": row.id, "status": row.status}


@app.put("/api/v1/admin/content/{item_id}")
def admin_update_content(item_id: int, payload: ContentPayload, request: Request,
                         admin: AdminUser = Depends(require_admin_csrf), db: Session = Depends(get_db)):
    _require_password_rotated(admin)
    row = db.get(ContentItem, item_id)
    if not row:
        raise HTTPException(status_code=404, detail="Content item not found")
    if payload.image_asset_id and not db.get(MediaAsset, payload.image_asset_id):
        raise HTTPException(status_code=422, detail="Media asset not found")
    for key, value in _content_values(payload).items():
        setattr(row, key, value)
    _audit(db, admin.id, "content.updated", "content_item", str(row.id), request, {"status": row.status})
    db.commit()
    return {"id": row.id, "status": row.status}


@app.delete("/api/v1/admin/content/{item_id}")
def admin_archive_content(item_id: int, request: Request,
                          admin: AdminUser = Depends(require_admin_csrf), db: Session = Depends(get_db)):
    _require_password_rotated(admin)
    row = db.get(ContentItem, item_id)
    if not row:
        raise HTTPException(status_code=404, detail="Content item not found")
    row.status = "archived"
    _audit(db, admin.id, "content.archived", "content_item", str(row.id), request)
    db.commit()
    return {"id": row.id, "status": "archived"}


@app.get("/api/v1/admin/wallpapers")
def admin_list_wallpapers(
    admin: AdminUser = Depends(current_admin),
    db: Session = Depends(get_db),
):
    _require_password_rotated(admin)
    return {
        "items": [
            {
                "id": item["id"],
                "title": item["title"],
                "creator": item["creator"],
                "license": item["license"],
                "sha256": item["sha256"],
                "published": item["published"],
            }
            for item in list_wallpapers(db)
        ]
    }


@app.put("/api/v1/admin/wallpapers/{wallpaper_id}")
def admin_set_wallpaper_visibility(
    wallpaper_id: str,
    payload: WallpaperVisibilityPayload,
    request: Request,
    admin: AdminUser = Depends(require_admin_csrf),
    db: Session = Depends(get_db),
):
    _require_password_rotated(admin)
    updated = set_wallpaper_published(db, wallpaper_id, payload.published)
    if updated is None:
        raise HTTPException(status_code=404, detail="Wallpaper asset not found")
    _audit(
        db,
        admin.id,
        "wallpaper.published" if payload.published else "wallpaper.hidden",
        "bundled_wallpaper",
        wallpaper_id,
        request,
        {"published": payload.published},
    )
    db.commit()
    return {"id": wallpaper_id, "published": payload.published}


@app.get("/api/v1/admin/catalog/{catalog_type}")
def admin_catalog_list(
    catalog_type: str,
    limit: int = 50,
    offset: int = 0,
    admin: AdminUser = Depends(current_admin),
    db: Session = Depends(get_db),
):
    _require_password_rotated(admin)
    if catalog_type not in ADMIN_CATALOG_SCHEMAS:
        raise HTTPException(status_code=404, detail="Catalog section not found")
    if not 1 <= limit <= 100 or not 0 <= offset <= 100000:
        raise HTTPException(status_code=422, detail="Limit must be 1-100 and offset must be between 0 and 100000")
    model = ADMIN_CATALOG_SCHEMAS[catalog_type][0]
    query = db.query(model)
    total = query.count()
    rows = query.order_by(model.id.desc()).offset(offset).limit(limit).all()
    return {
        "items": [_serialize_admin_catalog(catalog_type, row, db) for row in rows],
        "total": total,
        "limit": limit,
        "offset": offset,
    }


def _validate_catalog_relationships(catalog_type: str, values: dict, db: Session) -> None:
    if catalog_type == "book" and values.get("category_id") is not None:
        from app.models import BookCategory
        if db.get(BookCategory, values["category_id"]) is None:
            raise HTTPException(status_code=422, detail="Book category not found")
    if catalog_type == "hadith":
        source = db.get(HadithSource, values["source_id"])
        if source is None:
            raise HTTPException(status_code=422, detail="Hadith source not found")
        if values["publication_status"] == "published" and not source.edition:
            raise HTTPException(status_code=422, detail="A published hadith requires a source edition")
    if catalog_type == "dua":
        if values.get("source_id") is not None and db.get(HadithSource, values["source_id"]) is None:
            raise HTTPException(status_code=422, detail="Dua source not found")
        if values.get("category_id") is not None:
            from app.models import DuaCategory
            if db.get(DuaCategory, values["category_id"]) is None:
                raise HTTPException(status_code=422, detail="Dua category not found")
    if catalog_type == "ethics_lesson" and values.get("hadith_id") is not None:
        if db.get(Hadith, values["hadith_id"]) is None:
            raise HTTPException(status_code=422, detail="Referenced hadith not found")
    if catalog_type == "audio" and values.get("reciter_id") is not None:
        from app.models import Reciter
        if db.get(Reciter, values["reciter_id"]) is None:
            raise HTTPException(status_code=422, detail="Reciter not found")


def _catalog_integrity_error(db: Session, exc: IntegrityError) -> HTTPException:
    db.rollback()
    return HTTPException(status_code=409, detail="The record conflicts with existing data or a referenced record")


@app.post("/api/v1/admin/catalog/{catalog_type}", status_code=201)
def admin_catalog_create(
    catalog_type: str,
    payload: dict,
    request: Request,
    admin: AdminUser = Depends(require_admin_csrf),
    db: Session = Depends(get_db),
):
    _require_password_rotated(admin)
    if catalog_type not in ADMIN_CATALOG_SCHEMAS:
        raise HTTPException(status_code=404, detail="Catalog section not found")
    values = _validate_catalog_payload(catalog_type, payload)
    _validate_catalog_relationships(catalog_type, values, db)
    model = ADMIN_CATALOG_SCHEMAS[catalog_type][0]
    row = model(**values)
    db.add(row)
    try:
        db.flush()
        _audit(db, admin.id, f"catalog.{catalog_type}.created", catalog_type, str(row.id), request,
               {"publication_status": values.get("publication_status"), "is_published": values.get("is_published")})
        db.commit()
    except IntegrityError as exc:
        raise _catalog_integrity_error(db, exc) from exc
    return {"id": row.id, "catalog_type": catalog_type, "record": _serialize_admin_catalog(catalog_type, row, db)}


@app.put("/api/v1/admin/catalog/{catalog_type}/{item_id}")
def admin_catalog_update(
    catalog_type: str,
    item_id: int,
    payload: dict,
    request: Request,
    admin: AdminUser = Depends(require_admin_csrf),
    db: Session = Depends(get_db),
):
    _require_password_rotated(admin)
    if catalog_type not in ADMIN_CATALOG_SCHEMAS:
        raise HTTPException(status_code=404, detail="Catalog section not found")
    model = ADMIN_CATALOG_SCHEMAS[catalog_type][0]
    row = db.get(model, item_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Catalog record not found")
    values = _validate_catalog_payload(catalog_type, payload)
    _validate_catalog_relationships(catalog_type, values, db)
    for field_name, value in values.items():
        setattr(row, field_name, value)
    try:
        db.flush()
        _audit(db, admin.id, f"catalog.{catalog_type}.updated", catalog_type, str(row.id), request,
               {"publication_status": values.get("publication_status"), "is_published": values.get("is_published")})
        db.commit()
    except IntegrityError as exc:
        raise _catalog_integrity_error(db, exc) from exc
    return {"id": row.id, "catalog_type": catalog_type, "record": _serialize_admin_catalog(catalog_type, row, db)}


@app.delete("/api/v1/admin/catalog/{catalog_type}/{item_id}")
def admin_catalog_archive(
    catalog_type: str,
    item_id: int,
    request: Request,
    admin: AdminUser = Depends(require_admin_csrf),
    db: Session = Depends(get_db),
):
    _require_password_rotated(admin)
    if catalog_type not in ADMIN_CATALOG_SCHEMAS:
        raise HTTPException(status_code=404, detail="Catalog section not found")
    if catalog_type == "hadith_source":
        raise HTTPException(status_code=409, detail="Bibliographic source records are retained for citation integrity")
    model = ADMIN_CATALOG_SCHEMAS[catalog_type][0]
    row = db.get(model, item_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Catalog record not found")
    if hasattr(row, "publication_status"):
        row.publication_status = "archived"
    elif hasattr(row, "is_published"):
        row.is_published = False
    else:
        raise HTTPException(status_code=409, detail="This record type cannot be archived")
    _audit(db, admin.id, f"catalog.{catalog_type}.archived", catalog_type, str(row.id), request)
    db.commit()
    return {"id": row.id, "archived": True}


class HadithGradingCollectionPayload(StrictPayload):
    gradings: list[HadithGradingAdminPayload] = Field(min_length=1, max_length=50)


@app.post("/api/v1/admin/hadith/{hadith_id}/gradings", status_code=201)
def admin_add_hadith_grading(
    hadith_id: int,
    payload: HadithGradingAdminPayload,
    request: Request,
    admin: AdminUser = Depends(require_admin_csrf),
    db: Session = Depends(get_db),
):
    _require_password_rotated(admin)
    hadith = db.get(Hadith, hadith_id)
    if hadith is None:
        raise HTTPException(status_code=404, detail="Hadith not found")
    row = HadithGrading(
        hadith_id=hadith_id,
        grading=payload.grading,
        scholar=payload.scholar,
        methodology=payload.methodology,
        citation=payload.citation,
        reviewed_at=_normalise_datetime(payload.reviewed_at),
    )
    db.add(row)
    db.flush()
    _audit(db, admin.id, "hadith.grading.appended", "hadith_grading", str(row.id), request,
           {"hadith_id": hadith_id, "scholar": row.scholar})
    db.commit()
    return {"id": row.id, "hadith_id": hadith_id, "grading": row.grading, "scholar": row.scholar}


class BookPageTextPayload(StrictPayload):
    text_content: str = Field(min_length=1, max_length=25000)


@app.get("/api/v1/admin/books/{book_id}/pages")
def admin_list_book_pages(
    book_id: int,
    volume_number: int | None = None,
    limit: int = 200,
    offset: int = 0,
    admin: AdminUser = Depends(current_admin),
    db: Session = Depends(get_db),
):
    _require_password_rotated(admin)
    book = db.get(Book, book_id)
    if book is None:
        raise HTTPException(status_code=404, detail="Book not found")
    if not 1 <= limit <= 1000 or not 0 <= offset <= 100000:
        raise HTTPException(status_code=422, detail="Limit must be 1-1000 and offset must be between 0 and 100000")
    query = db.query(BookPage).filter(BookPage.book_id == book_id)
    if volume_number is not None:
        if not 1 <= volume_number <= 1000:
            raise HTTPException(status_code=422, detail="Volume number must be between 1 and 1000")
        query = query.filter(BookPage.volume_number == volume_number)
    total = query.count()
    rows = query.order_by(BookPage.volume_number.asc(), BookPage.page_number.asc()).offset(offset).limit(limit).all()
    return {"book_id": book_id, "items": [
        {"volume_number": row.volume_number, "page_number": row.page_number, "text_content": row.text_content}
        for row in rows
    ], "total": total, "limit": limit, "offset": offset}


@app.post("/api/v1/admin/books/{book_id}/pages", status_code=201)
def admin_import_book_pages(
    book_id: int,
    payload: BookPagesPayload,
    request: Request,
    admin: AdminUser = Depends(require_admin_csrf),
    db: Session = Depends(get_db),
):
    _require_password_rotated(admin)
    book = db.get(Book, book_id)
    if book is None:
        raise HTTPException(status_code=404, detail="Book not found")
    if book.publication_status == "published":
        raise HTTPException(status_code=409, detail="Archive the book before changing its published page set")
    if book.volume_count is not None and any(page.volume_number > book.volume_count for page in payload.pages):
        raise HTTPException(status_code=422, detail="A page volume exceeds the book volume_count")
    page_keys = [(page.volume_number, page.page_number) for page in payload.pages]
    if len(page_keys) != len(set(page_keys)):
        raise HTTPException(status_code=422, detail="Duplicate volume/page pairs are not allowed in one import")
    rows = [BookPage(book_id=book_id, **page.model_dump()) for page in payload.pages]
    db.add_all(rows)
    try:
        db.flush()
        _audit(db, admin.id, "book.pages.imported", "book", str(book_id), request,
               {"page_count": len(rows), "volumes": sorted({page.volume_number for page in payload.pages})})
        db.commit()
    except IntegrityError as exc:
        raise _catalog_integrity_error(db, exc) from exc
    return {"book_id": book_id, "inserted": len(rows)}


@app.put("/api/v1/admin/books/{book_id}/pages/{volume_number}/{page_number}")
def admin_update_book_page(
    book_id: int,
    volume_number: int,
    page_number: int,
    payload: BookPageTextPayload,
    request: Request,
    admin: AdminUser = Depends(require_admin_csrf),
    db: Session = Depends(get_db),
):
    _require_password_rotated(admin)
    book = db.get(Book, book_id)
    if book is None:
        raise HTTPException(status_code=404, detail="Book not found")
    if book.publication_status == "published":
        raise HTTPException(status_code=409, detail="Archive the book before changing published pages")
    if not 1 <= volume_number <= 1000 or not 1 <= page_number <= 100000 or (book.volume_count is not None and volume_number > book.volume_count):
        raise HTTPException(status_code=422, detail="Page volume and number are outside the book bounds")
    row = db.query(BookPage).filter_by(book_id=book_id, volume_number=volume_number, page_number=page_number).first()
    if row is None:
        raise HTTPException(status_code=404, detail="Book page not found")
    row.text_content = payload.text_content
    _audit(db, admin.id, "book.page.updated", "book_page", str(row.id), request,
           {"book_id": book_id, "volume_number": volume_number, "page_number": page_number})
    db.commit()
    return {"id": row.id, "updated": True}


@app.get("/api/v1/admin/radio")
def admin_get_radio(admin: AdminUser = Depends(current_admin), db: Session = Depends(get_db)):
    _require_password_rotated(admin)
    row = db.query(RadioChannel).order_by(RadioChannel.id.asc()).first()
    if not row:
        return None
    return {
        "id": row.id, "name": row.name, "description": row.description,
        "stream_url": row.stream_url, "official_source_url": row.official_source_url,
        "rights_evidence": row.rights_evidence,
        "rights_reviewed_at": row.rights_reviewed_at.isoformat() if row.rights_reviewed_at else None,
        "is_verified": row.is_verified, "is_enabled": row.is_enabled,
    }


@app.put("/api/v1/admin/radio")
def admin_update_radio(payload: RadioPayload, request: Request,
                       admin: AdminUser = Depends(require_admin_csrf), db: Session = Depends(get_db)):
    _require_password_rotated(admin)
    if payload.is_enabled and not (
        payload.is_verified and payload.stream_url and payload.official_source_url and payload.rights_evidence
    ):
        raise HTTPException(
            status_code=422,
            detail="A verified HTTPS stream, official source, and documented reuse-permission evidence are required before enabling radio",
        )
    row = db.query(RadioChannel).order_by(RadioChannel.id.asc()).first()
    if row is None:
        row = RadioChannel(name=payload.name)
    row.name = payload.name.strip()
    row.description = payload.description
    row.stream_url = payload.stream_url
    row.official_source_url = payload.official_source_url
    row.rights_evidence = payload.rights_evidence
    row.rights_reviewed_at = datetime.now(timezone.utc) if payload.is_verified else None
    row.is_verified = payload.is_verified
    row.is_enabled = payload.is_enabled
    db.add(row)
    db.flush()
    _audit(db, admin.id, "radio.updated", "radio_channel", str(row.id), request,
           {"enabled": row.is_enabled, "verified": row.is_verified,
            "rights_evidence_present": bool(row.rights_evidence),
            "rights_reviewed_at": row.rights_reviewed_at.isoformat() if row.rights_reviewed_at else None})
    db.commit()
    return {"id": row.id, "is_enabled": row.is_enabled, "is_verified": row.is_verified}


@app.post("/api/v1/admin/media", status_code=201)
async def admin_upload_media(request: Request, file: UploadFile = File(...),
                             admin: AdminUser = Depends(require_admin_csrf), db: Session = Depends(get_db)):
    _require_password_rotated(admin)
    if not file.filename:
        raise HTTPException(status_code=422, detail="File name is required")
    max_bytes = settings.max_upload_bytes
    contents = bytearray()
    while True:
        chunk = await file.read(1024 * 1024)
        if not chunk:
            break
        contents.extend(chunk)
        if len(contents) > max_bytes:
            raise HTTPException(status_code=413, detail="File exceeds the upload limit")
    data = bytes(contents)
    signatures = [
        (b"\xff\xd8\xff", "image/jpeg", ".jpg"),
        (b"\x89PNG\r\n\x1a\n", "image/png", ".png"),
        (b"RIFF", "image/webp", ".webp"),
        (b"ID3", "audio/mpeg", ".mp3"),
        (b"\xff\xfb", "audio/mpeg", ".mp3"),
        (b"\xff\xf3", "audio/mpeg", ".mp3"),
        (b"\xff\xf2", "audio/mpeg", ".mp3"),
        (b"%PDF-", "application/pdf", ".pdf"),
    ]
    detected = None
    for signature, mime, suffix in signatures:
        if data.startswith(signature) or (mime == "image/webp" and data.startswith(b"RIFF") and data[8:12] == b"WEBP"):
            detected = (mime, suffix)
            break
    if not detected:
        raise HTTPException(status_code=415, detail="Unsupported file type")
    if not data:
        raise HTTPException(status_code=422, detail="Empty file")
    storage_name = f"{uuid4().hex}{detected[1]}"
    destination = settings.media_path / storage_name
    destination.write_bytes(data)
    row = MediaAsset(
        original_name=Path(file.filename).name[:255], storage_name=storage_name,
        mime_type=detected[0], byte_size=len(data), sha256=sha256(data).hexdigest(),
        created_by=admin.id,
    )
    db.add(row)
    try:
        db.flush()
        _audit(db, admin.id, "media.uploaded", "media_asset", str(row.id), request,
               {"mime_type": row.mime_type, "byte_size": row.byte_size, "sha256": row.sha256})
        db.commit()
    except Exception:
        db.rollback()
        destination.unlink(missing_ok=True)
        raise
    return {"id": row.id, "original_name": row.original_name, "mime_type": row.mime_type,
            "byte_size": row.byte_size, "sha256": row.sha256}


@app.get("/api/v1/admin/media")
def admin_list_media(admin: AdminUser = Depends(current_admin), db: Session = Depends(get_db)):
    _require_password_rotated(admin)
    rows = db.query(MediaAsset).order_by(MediaAsset.created_at.desc()).limit(200).all()
    return [{"id": r.id, "original_name": r.original_name, "mime_type": r.mime_type,
             "byte_size": r.byte_size, "sha256": r.sha256, "created_at": r.created_at.isoformat()} for r in rows]


def _pdf_extraction_availability() -> tuple[bool, str | None]:
    if not settings.pdf_text_extraction_enabled:
        return False, "استخراج نص PDF معطّل بإعداد الخادم."
    ready, _bwrap = sandbox_status()
    if not ready:
        return False, "استخراج نص PDF غير متاح لأن عزل التنفيذ المطلوب غير جاهز."
    return True, None


@app.get("/api/v1/admin/media/pdf-extraction-capabilities")
def admin_pdf_extraction_capabilities(admin: AdminUser = Depends(current_admin)):
    _require_password_rotated(admin)
    enabled, reason = _pdf_extraction_availability()
    return {"enabled": enabled, "reason": reason}


def _pdf_job_public_result(job_id: str, job: dict) -> dict:
    result = {"id": job_id, "status": job["status"]}
    if job.get("status") == "completed":
        result.update({
            "text": job.get("text", ""),
            "page_count": job.get("page_count", 0),
            "has_text": bool(job.get("has_text")),
        })
    if job.get("error"):
        result["error"] = job["error"]
    return result


def _write_private_file(path: Path, contents: bytes, mode: int = 0o400) -> None:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    try:
        offset = 0
        while offset < len(contents):
            written = os.write(fd, contents[offset:])
            if written <= 0:
                raise OSError("Could not write the temporary PDF worker file")
            offset += written
    finally:
        os.close(fd)


def _copy_pdf_to_private_temp(source: Path, destination: Path, expected_size: int) -> None:
    source_fd = os.open(source, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    destination_fd = None
    try:
        source_stat = os.fstat(source_fd)
        if not stat.S_ISREG(source_stat.st_mode):
            raise ValueError("PDF source is not a regular file")
        if source_stat.st_size <= 0 or source_stat.st_size > MAX_PDF_BYTES or source_stat.st_size != expected_size:
            raise ValueError("PDF source size changed")
        destination_fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o400)
        total = 0
        while True:
            chunk = os.read(source_fd, 1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_PDF_BYTES:
                raise ValueError("PDF source exceeds the extraction limit")
            view = memoryview(chunk)
            while view:
                written = os.write(destination_fd, view)
                view = view[written:]
        if total != expected_size:
            raise ValueError("PDF source size changed")
    finally:
        os.close(source_fd)
        if destination_fd is not None:
            os.close(destination_fd)


async def _read_limited_pdf_output(reader, limit: int) -> tuple[bytes, bool]:
    output = bytearray()
    while True:
        chunk = await reader.read(min(64 * 1024, limit + 1 - len(output)))
        if not chunk:
            return bytes(output), False
        output.extend(chunk)
        if len(output) > limit:
            return bytes(output[:limit + 1]), True


async def _stop_pdf_worker(process) -> None:
    if process.returncode is None:
        try:
            process.kill()
        except ProcessLookupError:
            pass
    try:
        await asyncio.wait_for(process.wait(), timeout=2)
    except (asyncio.TimeoutError, ProcessLookupError):
        pass


async def _run_pdf_extraction(job_id: str, path: Path) -> None:
    job = _pdf_extraction_jobs.get(job_id)
    if job is None:
        return
    process = None
    stdout_task = None
    wait_task = None
    try:
        enabled, _reason = _pdf_extraction_availability()
        ready, bwrap = sandbox_status()
        if not enabled or not ready or not bwrap:
            job["status"] = "failed"
            job["error"] = "استخراج نص PDF غير متاح لأن العزل المطلوب غير جاهز."
            return

        worker_source = Path(__file__).resolve().parent / "services" / "pdf_text_worker.py"
        with tempfile.TemporaryDirectory(prefix="khazain-pdf-job-", dir=safe_temp_root()) as temp_dir:
            work_dir = Path(temp_dir)
            await asyncio.to_thread(
                _copy_pdf_to_private_temp,
                path,
                work_dir / "input.pdf",
                int(job["byte_size"]),
            )
            worker_code = await asyncio.to_thread(worker_source.read_bytes)
            _write_private_file(work_dir / "pdf_text_worker.py", worker_code)
            process = await asyncio.create_subprocess_exec(
                *worker_command(bwrap, work_dir),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
                env={"LANG": "C.UTF-8", "LC_ALL": "C.UTF-8"},
                start_new_session=True,
            )
            job["process"] = process
            if job.get("cancel_requested"):
                await _stop_pdf_worker(process)
            stdout_task = asyncio.create_task(_read_limited_pdf_output(process.stdout, 4 * 1024 * 1024))
            wait_task = asyncio.create_task(process.wait())
            done, pending = await asyncio.wait(
                {stdout_task, wait_task},
                timeout=_PDF_EXTRACTION_TIMEOUT_SECONDS,
                return_when=asyncio.ALL_COMPLETED,
            )
            if len(done) != 2:
                await _stop_pdf_worker(process)
                for task in pending:
                    task.cancel()
                await asyncio.gather(*pending, return_exceptions=True)
                if job.get("cancel_requested"):
                    job["status"] = "cancelled"
                    return
                job["status"] = "failed"
                job["error"] = "انتهت مهلة استخراج النص؛ لم يُحفظ ناتج جزئي."
                return

            stdout, output_too_large = stdout_task.result()
            if job.get("cancel_requested"):
                job["status"] = "cancelled"
                return
            if output_too_large:
                job["status"] = "failed"
                job["error"] = "تجاوز ناتج استخراج PDF الحد المسموح."
                return
            if process.returncode != 0:
                job["status"] = "failed"
                job["error"] = "تعذر استخراج النص. تحقق من أن الملف PDF صالح وغير مشفّر."
                return
            payload = json.loads(stdout.decode("utf-8"))
            if payload.get("ok") is not True or not isinstance(payload.get("text"), str):
                job["status"] = "failed"
                job["error"] = "تعذر استخراج النص من الملف."
                return
            job.update({
                "status": "completed",
                "text": payload["text"],
                "page_count": int(payload.get("page_count", 0)),
                "has_text": bool(payload.get("has_text")),
                "error": None,
            })
    except asyncio.CancelledError:
        if process is not None:
            await _stop_pdf_worker(process)
        for task in (stdout_task, wait_task):
            if task is not None and not task.done():
                task.cancel()
        await asyncio.gather(*(task for task in (stdout_task, wait_task) if task is not None), return_exceptions=True)
        job["status"] = "cancelled"
        raise
    except Exception:
        if process is not None:
            await _stop_pdf_worker(process)
        job["status"] = "failed"
        job["error"] = "تعذر إكمال استخراج النص."
    finally:
        job["process"] = None


@app.post("/api/v1/admin/media/{media_id}/extract-text", status_code=202)
async def admin_start_pdf_extraction(
    media_id: int,
    request: Request,
    admin: AdminUser = Depends(require_admin_csrf),
    db: Session = Depends(get_db),
):
    _require_password_rotated(admin)
    enabled, reason = _pdf_extraction_availability()
    if not enabled:
        raise HTTPException(status_code=503, detail=reason or "PDF extraction is unavailable")
    asset = db.get(MediaAsset, media_id)
    if not asset:
        raise HTTPException(status_code=404, detail="PDF asset not found")
    if asset.mime_type != "application/pdf":
        raise HTTPException(status_code=415, detail="Only PDF files can be extracted")
    if asset.byte_size <= 0 or asset.byte_size > min(settings.max_upload_bytes, MAX_PDF_BYTES):
        raise HTTPException(status_code=413, detail="PDF exceeds the extraction size limit")
    try:
        media_root = settings.media_path.resolve()
        asset_path = (media_root / asset.storage_name).resolve(strict=True)
        if asset_path.parent != media_root or not asset_path.is_file() or asset_path.stat().st_size != asset.byte_size:
            raise HTTPException(status_code=404, detail="PDF asset not found")
    except OSError as exc:
        raise HTTPException(status_code=404, detail="PDF asset not found") from exc

    now = time.monotonic()
    for old_id, old_job in list(_pdf_extraction_jobs.items()):
        if old_job["status"] != "processing" and now - old_job["created_at"] > _PDF_EXTRACTION_RETENTION_SECONDS:
            del _pdf_extraction_jobs[old_id]
    if sum(job["status"] == "processing" for job in _pdf_extraction_jobs.values()) >= _PDF_EXTRACTION_MAX_ACTIVE_JOBS:
        raise HTTPException(status_code=429, detail="An extraction job is already running")

    job_id = uuid4().hex
    _pdf_extraction_jobs[job_id] = {
        "admin_id": admin.id,
        "media_id": media_id,
        "byte_size": asset.byte_size,
        "status": "processing",
        "created_at": now,
        "cancel_requested": False,
        "process": None,
        "text": "",
    }
    db.flush()
    _audit(db, admin.id, "pdf.text_extraction.started", "media_asset", str(media_id), request,
           {"max_pages": 300, "max_characters": 500000, "timeout_seconds": _PDF_EXTRACTION_TIMEOUT_SECONDS,
            "sandbox": "bubblewrap"})
    db.commit()
    _pdf_extraction_jobs[job_id]["task"] = asyncio.create_task(_run_pdf_extraction(job_id, asset_path))
    return {"id": job_id, "status": "processing"}


@app.get("/api/v1/admin/media/pdf-extractions/{job_id}")
def admin_pdf_extraction_status(
    job_id: str,
    admin: AdminUser = Depends(current_admin),
):
    _require_password_rotated(admin)
    job = _pdf_extraction_jobs.get(job_id)
    if not job or job["admin_id"] != admin.id:
        raise HTTPException(status_code=404, detail="Extraction job not found")
    return _pdf_job_public_result(job_id, job)


@app.delete("/api/v1/admin/media/pdf-extractions/{job_id}", status_code=202)
def admin_cancel_pdf_extraction(
    job_id: str,
    request: Request,
    admin: AdminUser = Depends(require_admin_csrf),
    db: Session = Depends(get_db),
):
    _require_password_rotated(admin)
    job = _pdf_extraction_jobs.get(job_id)
    if not job or job["admin_id"] != admin.id:
        raise HTTPException(status_code=404, detail="Extraction job not found")
    if job["status"] == "processing":
        job["cancel_requested"] = True
        process = job.get("process")
        if process is not None and process.returncode is None:
            process.kill()
        job["status"] = "cancelled"
        db.flush()
        _audit(db, admin.id, "pdf.text_extraction.cancelled", "media_asset", str(job["media_id"]), request)
        db.commit()
    return _pdf_job_public_result(job_id, job)


@app.get("/api/v1/admin/audit")
def admin_audit(admin: AdminUser = Depends(current_admin), db: Session = Depends(get_db)):
    _require_password_rotated(admin)
    rows = db.query(AdminAuditLog).order_by(AdminAuditLog.created_at.desc()).limit(200).all()
    return [{"id": r.id, "action": r.action, "resource_type": r.resource_type,
             "resource_id": r.resource_id, "details": r.details,
             "created_at": r.created_at.isoformat()} for r in rows]


@app.get("/api/v1/admin/services")
def admin_services(admin: AdminUser = Depends(current_admin), db: Session = Depends(get_db)):
    _require_password_rotated(admin)
    radio = db.query(RadioChannel).first()
    quran_count = db.query(QuranAyah).count()
    return {
        "api": "ok", "database": "connected", "prayer_engine": "available",
        "quran_dataset": "ready" if quran_count == 6236 else "not_imported_or_unverified",
        "radio": "ready" if radio and radio.is_enabled and radio.is_verified and radio.stream_url and radio.official_source_url and radio.rights_evidence and len(radio.rights_evidence.strip()) >= 12 and radio.rights_reviewed_at else "not_configured",
        "media_storage": "available" if settings.media_path.exists() else "unavailable",
        "notification_provider": "not_configured",
    }


# Admin UI: no secret data or admin credentials are embedded in this page.
ADMIN_ASSETS = Path(__file__).resolve().parents[3] / "apps" / "admin"
ADMIN_UI = ADMIN_ASSETS / "index.html"


@app.get("/admin-assets/{asset_name}", include_in_schema=False)
def admin_asset(asset_name: str):
    if asset_name not in {"admin.css", "admin.js"}:
        raise HTTPException(status_code=404, detail="Asset not found")
    target = ADMIN_ASSETS / asset_name
    return FileResponse(target, headers={"X-Content-Type-Options": "nosniff", "Cache-Control": "no-cache"})


@app.get("/admin", include_in_schema=False)
def admin_dashboard():
    if not ADMIN_UI.exists():
        raise HTTPException(status_code=404, detail="Dashboard assets not installed")
    return FileResponse(ADMIN_UI, media_type="text/html", headers={
        "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
        "X-Content-Type-Options": "nosniff",
        "Referrer-Policy": "no-referrer",
        "Cache-Control": "no-store",
    })
