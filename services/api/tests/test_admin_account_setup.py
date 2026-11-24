from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.core.security import verify_password
from app.models import AdminAuditLog, AdminSession, AdminUser
from app.main import _bootstrap_admin
from scripts.replace_admin_owner import rename_existing_owner


@pytest.fixture
def db_session():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    AdminUser.__table__.create(bind=engine)
    AdminSession.__table__.create(bind=engine)
    AdminAuditLog.__table__.create(bind=engine)
    try:
        with Session(engine, expire_on_commit=False) as db:
            yield db
    finally:
        engine.dispose()


def _owner(db, username="previous-owner", password_hash="existing-verifier-not-a-secret"):
    user = AdminUser(
        username=username,
        email="owner@example.invalid",
        password_hash=password_hash,
        role="owner",
        is_active=True,
        force_password_change=True,
    )
    db.add(user)
    db.commit()
    return user


def test_owner_rename_preserves_verifier_and_revokes_sessions(db_session):
    password_hash = "existing-verifier-not-a-secret"
    owner = _owner(db_session, password_hash=password_hash)
    active = AdminSession(
        admin_id=owner.id,
        token_hash="a" * 64,
        csrf_hash="b" * 64,
        expires_at=datetime.now(timezone.utc) + timedelta(hours=1),
    )
    db_session.add(active)
    db_session.commit()

    revoked = rename_existing_owner(db_session, "previous-owner", "aliaa")

    db_session.refresh(owner)
    db_session.refresh(active)
    audit = db_session.query(AdminAuditLog).one()
    assert revoked == 1
    assert owner.username == "aliaa"
    assert owner.password_hash == password_hash
    assert owner.force_password_change is False
    assert active.revoked_at is not None
    assert audit.action == "admin.username_replaced"
    assert audit.details == {
        "previous_username": "previous-owner",
        "new_username": "aliaa",
        "sessions_revoked": 1,
    }
    assert password_hash not in str(audit.details)


def test_owner_rename_refuses_wrong_current_name_without_changes(db_session):
    owner = _owner(db_session)

    with pytest.raises(ValueError, match="expected active owner"):
        rename_existing_owner(db_session, "not-the-owner", "aliaa")

    db_session.refresh(owner)
    assert owner.username == "previous-owner"
    assert db_session.query(AdminAuditLog).count() == 0


def test_owner_rename_refuses_multiple_accounts_without_changes(db_session):
    first = _owner(db_session)
    _owner(db_session, username="another-admin")

    with pytest.raises(ValueError, match="exactly one administrator"):
        rename_existing_owner(db_session, "previous-owner", "aliaa")

    db_session.refresh(first)
    assert first.username == "previous-owner"
    assert db_session.query(AdminAuditLog).count() == 0


def test_empty_database_bootstrap_can_preserve_explicitly_selected_password(monkeypatch, db_session):
    import app.main as main_module

    existing_password = "Existing-Admin-Password-2026!"
    monkeypatch.setattr(
        main_module,
        "settings",
        Settings(
            _env_file=None,
            app_env="test",
            admin_bootstrap_username="aliaa",
            admin_bootstrap_password=existing_password,
            admin_bootstrap_force_password_change=False,
        ),
    )

    _bootstrap_admin(db_session)

    created = db_session.query(AdminUser).one()
    assert created.username == "aliaa"
    assert verify_password(created.password_hash, existing_password)
    assert created.password_hash != existing_password
    assert created.force_password_change is False
