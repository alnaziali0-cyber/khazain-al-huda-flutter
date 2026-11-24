"""Safely rename the sole existing admin owner without changing its password.

This operator-only script is intentionally separate from application startup:
existing accounts are never silently overwritten by bootstrap settings.
"""
import argparse
from datetime import datetime, timezone
import re
import sys
from pathlib import Path

# Allow invocation as `python scripts/replace_admin_owner.py` from services/api.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlalchemy import func
from sqlalchemy.exc import SQLAlchemyError

from app.core.config import get_settings
from app.db.session import SessionLocal
from app.models import AdminAuditLog, AdminSession, AdminUser

_USERNAME = re.compile(r"[A-Za-z0-9_.-]{3,80}\Z")


def rename_existing_owner(db, expected_username: str, new_username: str) -> int:
    """Rename exactly one expected owner, retaining the stored password verifier.

    Returns the number of active sessions revoked. Raises ValueError without
    committing when the database state does not match the requested operation.
    """
    if not _USERNAME.fullmatch(expected_username) or not _USERNAME.fullmatch(new_username):
        raise ValueError("Usernames must be 3–80 ASCII letters, digits, dots, underscores, or hyphens")
    if expected_username.casefold() == new_username.casefold():
        raise ValueError("The new username must differ from the current username")

    try:
        if db.query(AdminUser).count() != 1:
            raise ValueError("Expected exactly one administrator account; no changes were made")

        owner = (
            db.query(AdminUser)
            .filter(func.lower(AdminUser.username) == expected_username.lower())
            .with_for_update()
            .one_or_none()
        )
        if owner is None or owner.role != "owner" or not owner.is_active:
            raise ValueError("The expected active owner account was not found; no changes were made")

        collision = db.query(AdminUser).filter(
            func.lower(AdminUser.username) == new_username.lower(),
            AdminUser.id != owner.id,
        ).first()
        if collision is not None:
            raise ValueError("The new username is already in use; no changes were made")

        previous_username = owner.username
        owner.username = new_username
        # This is an established password, not a one-time bootstrap credential.
        # Keep its existing Argon2id verifier and do not force the user to rotate it.
        owner.force_password_change = False
        now = datetime.now(timezone.utc)
        revoked_sessions = db.query(AdminSession).filter(
            AdminSession.admin_id == owner.id,
            AdminSession.revoked_at.is_(None),
        ).update({"revoked_at": now}, synchronize_session=False)
        db.add(AdminAuditLog(
            admin_id=owner.id,
            action="admin.username_replaced",
            resource_type="admin_user",
            resource_id=str(owner.id),
            details={
                "previous_username": previous_username,
                "new_username": new_username,
                "sessions_revoked": int(revoked_sessions or 0),
            },
        ))
        db.commit()
        return int(revoked_sessions or 0)
    except Exception:
        db.rollback()
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Rename the existing sole admin owner without changing its password.")
    parser.add_argument("--expected-username", required=True, help="Exact current owner username to replace")
    parser.add_argument("--new-username", required=True, help="Replacement owner username")
    parser.add_argument(
        "--confirm-owner-replacement",
        action="store_true",
        help="Confirm the explicitly authorized owner username change",
    )
    args = parser.parse_args(argv)
    if not args.confirm_owner_replacement:
        parser.error("pass --confirm-owner-replacement to authorize this database change")

    settings = get_settings()
    if settings.app_env.lower() != "production":
        print("Refusing to run outside APP_ENV=production.", file=sys.stderr)
        return 2
    try:
        settings.validate_production()
    except RuntimeError:
        print("Production configuration is incomplete; no database change was attempted.", file=sys.stderr)
        return 2
    if not settings.database_url.startswith("postgresql+psycopg://"):
        print("Refusing to modify a non-PostgreSQL database.", file=sys.stderr)
        return 2

    db = SessionLocal()
    try:
        revoked = rename_existing_owner(db, args.expected_username, args.new_username)
    except ValueError as exc:
        print(f"Owner username replacement aborted: {exc}", file=sys.stderr)
        return 1
    except SQLAlchemyError:
        db.rollback()
        print("Database transaction failed; no owner change was committed.", file=sys.stderr)
        return 1
    except Exception:
        db.rollback()
        print("Owner username replacement failed; no success was recorded.", file=sys.stderr)
        return 1
    finally:
        db.close()

    print(f"Owner username updated. Existing password verifier preserved; active sessions revoked: {revoked}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
