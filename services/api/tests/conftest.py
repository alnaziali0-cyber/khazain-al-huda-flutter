"""Deterministic API test environment and per-test database isolation.

This file is loaded by pytest before importing test modules. Keeping environment
setup here prevents import-order bugs where ``app.main`` caches production-like
settings before test modules configure their test database and bootstrap admin.
"""
from __future__ import annotations

import os
import tempfile
from pathlib import Path

_TEST_ROOT = Path(tempfile.mkdtemp(prefix="khazain-api-tests-"))
_TEST_DB = _TEST_ROOT / "api-test.db"

# Test-only values; never read a developer's local .env while running tests.
os.environ["APP_ENV"] = "test"
os.environ["DATABASE_URL"] = f"sqlite:///{_TEST_DB}"
os.environ["APP_SECRET"] = "test-secret-value-longer-than-thirty-two-characters"
os.environ["ADMIN_BOOTSTRAP_USERNAME"] = "test-owner"
os.environ["ADMIN_BOOTSTRAP_PASSWORD"] = "Initial-Test-Password!2026"
os.environ["ADMIN_BOOTSTRAP_EMAIL"] = "owner@example.invalid"
os.environ["COOKIE_SECURE"] = "false"
os.environ["ALLOWED_ORIGINS"] = "http://testserver"
os.environ["MEDIA_ROOT"] = str(_TEST_ROOT / "media")

from app.core.config import get_settings  # noqa: E402

# The config module may have been imported by pytest plugins; force the app to
# construct settings from the isolated environment above.
get_settings.cache_clear()

from app.db.base import Base  # noqa: E402
from app.db.session import engine  # noqa: E402


import pytest  # noqa: E402


@pytest.fixture(autouse=True)
def isolate_api_database():
    """Start each API test with a clean schema and remove it afterwards."""
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    yield
    Base.metadata.drop_all(bind=engine)
