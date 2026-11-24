from uuid import uuid4

from fastapi.testclient import TestClient

from app.main import app


def test_assistant_sources_command_uses_real_server_connectors(monkeypatch):
    import app.routers.assistant as assistant_module

    class _Settings:
        deepseek_api_key = ""

    async def no_provider(*args, **kwargs):
        return None

    monkeypatch.setattr(assistant_module, "get_settings", lambda: _Settings())
    monkeypatch.setattr(assistant_module, "_deepseek_chat", no_provider)
    device_key = uuid4().hex + uuid4().hex
    with TestClient(app) as client:
        response = client.post(
            "/api/v1/public/assistant/chat",
            headers={"X-Device-Key": device_key},
            json={"message": "اكتشف المصادر المتاحة"},
        )
    assert response.status_code == 200
    payload = response.json()
    assert payload["mode"] == "tools_only"
    assert payload["deepseek_configured"] is False
    sources = payload["data"]["items"]
    keys = {source["source_key"] for source in sources}
    assert {"internet_archive", "thaqalayn", "al_islam", "shia_research", "ablibrary_export"} <= keys


def test_assistant_requires_device_scoped_key():
    with TestClient(app) as client:
        response = client.post(
            "/api/v1/public/assistant/chat",
            json={"message": "اعرض الكتب المستوردة"},
        )
    assert response.status_code == 422


def test_assistant_tools_only_response_never_claims_import_completed(monkeypatch):
    import app.routers.assistant as assistant_module

    class _Settings:
        deepseek_api_key = ""

    async def no_provider(*args, **kwargs):
        return None

    monkeypatch.setattr(assistant_module, "get_settings", lambda: _Settings())
    monkeypatch.setattr(assistant_module, "_deepseek_chat", no_provider)
    device_key = uuid4().hex + uuid4().hex
    with TestClient(app) as client:
        response = client.post(
            "/api/v1/public/assistant/chat",
            headers={"X-Device-Key": device_key},
            json={"message": "ابحث عن كتاب الكافي"},
        )
    assert response.status_code == 200
    payload = response.json()
    assert payload["mode"] == "tools_only"
    assert "remote" in payload["data"]
    assert "لا تعني أن حقوق الكتاب قد اعتُمدت" in payload["answer"]
