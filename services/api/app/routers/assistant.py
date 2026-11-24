from __future__ import annotations

import json
import re
from typing import Any

import httpx
from fastapi import APIRouter, Depends, Header
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.dependencies import get_db
from app.core.security import keyed_hash
from app.models import Book, BookArtifact, BookPage, BookImportJob
from app.routers.library import (
    ImportPreviewPayload,
    get_import_status,
    library_status,
    list_import_jobs,
    list_library_sources,
    list_private_books,
    preview_book_import,
    search_library,
)

router = APIRouter(prefix="/api/v1/public/assistant", tags=["library-assistant"])


class AssistantChatPayload(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    message: str = Field(min_length=1, max_length=2000)
    history: list[dict[str, str]] = Field(default_factory=list, max_length=16)


def _device_hash(x_device_key: str = Header(default="", alias="X-Device-Key")) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_-]{32,128}", x_device_key or ""):
        from fastapi import HTTPException
        raise HTTPException(status_code=422, detail="A valid X-Device-Key header is required")
    return keyed_hash(x_device_key)


TOOLS = [
    {"type": "function", "function": {
        "name": "discover_sources",
        "description": "Return the actual library connectors, capabilities and rights restrictions.",
        "parameters": {"type": "object", "properties": {}, "additionalProperties": False},
    }},
    {"type": "function", "function": {
        "name": "search_books",
        "description": "Search the device's private library, reviewed public library and Internet Archive metadata. Does not download any file.",
        "parameters": {"type": "object", "properties": {"query": {"type": "string", "minLength": 2, "maxLength": 100}, "limit": {"type": "integer", "minimum": 1, "maximum": 10}}, "required": ["query"], "additionalProperties": False},
    }},
    {"type": "function", "function": {
        "name": "get_library_status",
        "description": "Return actual private book and import counts for this device.",
        "parameters": {"type": "object", "properties": {}, "additionalProperties": False},
    }},
    {"type": "function", "function": {
        "name": "get_import_status",
        "description": "Read an import job that belongs to this device.",
        "parameters": {"type": "object", "properties": {"job_id": {"type": "integer", "minimum": 1}}, "required": ["job_id"], "additionalProperties": False},
    }},
    {"type": "function", "function": {
        "name": "prepare_book_import",
        "description": "Fetch item metadata and assess rights, then create a preview. Never starts a download. Only Internet Archive supports this import connector.",
        "parameters": {"type": "object", "properties": {"source_key": {"type": "string", "enum": ["internet_archive"]}, "identifier": {"type": "string", "minLength": 5, "maxLength": 80}}, "required": ["source_key", "identifier"], "additionalProperties": False},
    }},
]


async def _run_tool(name: str, arguments: dict[str, Any], db: Session, device_hash: str) -> dict[str, Any]:
    if name == "discover_sources":
        return list_library_sources()
    if name == "search_books":
        query = str(arguments.get("query") or "").strip()
        limit = int(arguments.get("limit") or 8)
        if not 2 <= len(query) <= 100 or not 1 <= limit <= 10:
            return {"error": "invalid_search_arguments"}
        result = await search_library(query, limit, db, device_hash)
        return {"query": query, "local": result["local"][:limit], "remote": result["remote"][:limit], "remote_error": result["remote_error"]}
    if name == "get_library_status":
        return library_status(db, device_hash)
    if name == "get_import_status":
        return get_import_status(int(arguments["job_id"]), db, device_hash)
    if name == "prepare_book_import":
        payload = ImportPreviewPayload(source_key=str(arguments["source_key"]), identifier=str(arguments["identifier"]))
        return await preview_book_import(payload, db, device_hash)
    return {"error": "tool_not_allowed"}


def _extract_search_term(message: str) -> str:
    value = message.strip()
    value = re.sub(r"(من فضلك|لو سمحت|أرجوك|رجاءً|ممكن|هل يمكنك|قم|افتح|ابحث|البحث|استورد|استيراد|عن|في|داخل|المكتبة|الإسلامية|الشيعية|كتاب|كتب)", " ", value, flags=re.IGNORECASE)
    value = re.sub(r"\s+", " ", value).strip(" ؟?،,.؛;")
    return value[:100]


async def _fallback_command(message: str, db: Session, device_hash: str) -> dict[str, Any]:
    normalized = message.casefold()
    if any(word in normalized for word in ("المصادر", "اكتشف", "connector", "sources")):
        return {"answer": "هذه المصادر وحالة التكامل الفعلية وقيود كل مصدر:", "data": list_library_sources(), "mode": "tools_only"}
    if any(word in normalized for word in ("حالة", "استيراد", "استيرادات", "متوقفة", "استكمل", "resume")) and not any(word in normalized for word in ("استورد كتاب", "استيراد كتاب", "ابحث عن كتاب")):
        return {"answer": "هذه عمليات الاستيراد المسجلة على هذا الجهاز:", "data": list_import_jobs(30, db, device_hash), "mode": "tools_only"}
    if any(word in normalized for word in ("كتبى", "كتبي", "الكتب المستوردة", "اعرض الكتب", "مكتبتي")):
        return {"answer": "هذه الكتب المحفوظة في مساحة هذا الجهاز:", "data": list_private_books(50, db, device_hash), "mode": "tools_only"}
    if any(word in normalized for word in ("ابحث", "بحث", "كتاب", "الكافي", "الصحيفة", "search")):
        term = _extract_search_term(message)
        if len(term) < 2:
            term = message.strip()[:100]
        result = await search_library(term, 10, db, device_hash)
        return {"answer": "هذه نتائج البحث المحلية وبيانات المصادر الخارجية. نتائج Internet Archive وصفية فقط ولا تعني أن حقوق الكتاب قد اعتُمدت:", "data": result, "mode": "tools_only"}
    if "مساعد" in normalized or "مرحبا" in normalized or "السلام" in normalized:
        return {"answer": "وعليكم السلام. أستطيع البحث في الكتب، عرض المصادر، فحص حالة الترخيص، إعداد معاينة استيراد، ومتابعة عمليات جهازك. البحث والاستيراد المتاحان الآن يعملان بأدوات خادم حقيقية؛ المحادثة اللغوية الكاملة تحتاج ضبط مفتاح DeepSeek على الخادم.", "mode": "tools_only"}
    return {
        "answer": "لم أتعرف على الأمر بدقة. جرّب: ابحث عن كتاب الكافي، اكتشف المصادر، اعرض الكتب المستوردة، أو اعرض حالة الاستيراد. لا أنفذ أي تنزيل قبل معاينة المصدر وتأكيدك.",
        "mode": "tools_only",
    }


async def _deepseek_chat(message: str, history: list[dict[str, str]], db: Session, device_hash: str) -> str | None:
    settings = get_settings()
    if not settings.deepseek_api_key:
        return None
    messages: list[dict[str, Any]] = [{
        "role": "system",
        "content": (
            "أنت مساعد خزائن الهدى لمساعدة المستخدم في البحث عن الكتب الإسلامية والشيعية وإدارة مكتبته الخاصة. "
            "استخدم الأدوات المحددة فقط، ولا تختلق كتباً أو تراخيص أو نتائج. افصل بين بيانات المصدر وحكم صحة النص أو صحة النسبة. "
            "لا تقل إن كتاباً استورد حتى ترجع أداة حالة الاستيراد وتؤكد status=completed. "
            "لا تنفذ التنزيل من خلال الأدوات؛ prepare_book_import ينشئ معاينة فقط، ثم يجب أن يضغط المستخدم زر التأكيد بنفسه. "
            "لا توصي باستيراد محتوى من مصدر يمنع النسخ أو الكشط. أجب بالعربية الفصحى المختصرة مع ذكر حالة الحقوق كما أرجعتها الأدوات."
        ),
    }]
    for entry in history[-12:]:
        role = entry.get("role")
        content = entry.get("content")
        if role in {"user", "assistant"} and isinstance(content, str) and content.strip():
            messages.append({"role": role, "content": content[:2000]})
    messages.append({"role": "user", "content": message})
    async with httpx.AsyncClient(timeout=httpx.Timeout(35.0, connect=8.0)) as client:
        for _ in range(4):
            response = await client.post(
                f"{settings.deepseek_base_url}/chat/completions",
                headers={"Authorization": f"Bearer {settings.deepseek_api_key}", "Content-Type": "application/json"},
                json={"model": settings.deepseek_model, "messages": messages, "tools": TOOLS, "tool_choice": "auto", "temperature": 0.2},
            )
            response.raise_for_status()
            body = response.json()
            choices = body.get("choices") or []
            if not choices:
                return None
            assistant_message = choices[0].get("message") or {}
            tool_calls = assistant_message.get("tool_calls") or []
            if not tool_calls:
                content = assistant_message.get("content")
                return str(content).strip() if content else None
            messages.append(assistant_message)
            for call in tool_calls[:4]:
                function = call.get("function") or {}
                name = str(function.get("name") or "")
                try:
                    arguments = json.loads(function.get("arguments") or "{}")
                    if not isinstance(arguments, dict):
                        raise ValueError("tool arguments must be an object")
                    result = await _run_tool(name, arguments, db, device_hash)
                except Exception as exc:
                    result = {"error": str(exc)[:120], "tool": name}
                messages.append({
                    "role": "tool",
                    "tool_call_id": call.get("id", ""),
                    "content": json.dumps(result, ensure_ascii=False)[:12000],
                })
    return None


@router.post("/chat")
async def assistant_chat(
    payload: AssistantChatPayload,
    db: Session = Depends(get_db),
    device_hash: str = Depends(_device_hash),
):
    settings = get_settings()
    try:
        answer = await _deepseek_chat(payload.message, payload.history, db, device_hash)
    except (httpx.HTTPError, ValueError, KeyError):
        answer = None
    if answer:
        return {"answer": answer, "mode": "deepseek_tools", "deepseek_configured": True}
    fallback = await _fallback_command(payload.message, db, device_hash)
    fallback["deepseek_configured"] = bool(settings.deepseek_api_key)
    if settings.deepseek_api_key:
        fallback["provider_notice"] = "تعذر الوصول إلى خدمة المساعد مؤقتاً؛ عُرضت نتائج الأدوات المتاحة بدلاً من اختلاق إجابة."
    else:
        fallback["provider_notice"] = "وضع الأدوات الفعلية متاح. لضبط المحادثة اللغوية، أضف DEEPSEEK_API_KEY إلى أسرار الخادم فقط."
    return fallback
