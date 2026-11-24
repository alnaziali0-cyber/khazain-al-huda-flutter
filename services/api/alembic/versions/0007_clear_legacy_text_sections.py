"""Clear legacy book, hadith, dua, and ziyara text from public storage.

Revision ID: 0007_clear_legacy_text_sections
Revises: 0006_radio_rights_evidence

This is intentionally irreversible: the user requested that the legacy text
collections and their saved reading positions be removed from the application.
Quran tables, Quran favorites, events, ethics, audio, prayer data, and settings
are not touched by this migration.
"""
from alembic import op

revision = "0007_clear_legacy_text_sections"
down_revision = "0006_radio_rights_evidence"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Remove only favorites that point to the collections being cleared.
    op.execute(
        "DELETE FROM favorites "
        "WHERE entity_type IN ('book', 'hadith', 'dua', 'visit')"
    )

    # Delete dependent records first to work with SQLite and PostgreSQL FKs.
    op.execute("DELETE FROM book_pages")
    op.execute("DELETE FROM book_reading_progress")
    op.execute("DELETE FROM books")
    op.execute("DELETE FROM hadith_gradings")
    op.execute("DELETE FROM hadith")
    op.execute("DELETE FROM duas")
    op.execute("DELETE FROM visits")
    op.execute("DELETE FROM hadith_sources")


def downgrade() -> None:
    # Content deletion is deliberate and cannot be reconstructed from a schema
    # downgrade. Restoring it requires a separately reviewed database backup.
    pass
