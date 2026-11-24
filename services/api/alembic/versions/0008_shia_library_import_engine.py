"""Add device-scoped import jobs and private book artifacts.

Revision ID: 0008_shia_library_import_engine
Revises: 0007_clear_legacy_text_sections
"""
from alembic import op
import sqlalchemy as sa

revision = "0008_shia_library_import_engine"
down_revision = "0007_clear_legacy_text_sections"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "book_import_jobs",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("device_key_hash", sa.String(length=64), nullable=False),
        sa.Column("source_key", sa.String(length=40), nullable=False),
        sa.Column("source_item_id", sa.String(length=180), nullable=False),
        sa.Column("title", sa.String(length=250), nullable=False),
        sa.Column("author", sa.String(length=180), nullable=True),
        sa.Column("source_url", sa.String(length=2048), nullable=False),
        sa.Column("selected_file", sa.String(length=255), nullable=True),
        sa.Column("file_format", sa.String(length=16), nullable=True),
        sa.Column("license_url", sa.String(length=2048), nullable=True),
        sa.Column("rights_status", sa.String(length=24), nullable=False, server_default="unverified"),
        sa.Column("rights_evidence", sa.Text(), nullable=True),
        sa.Column("status", sa.String(length=32), nullable=False, server_default="awaiting_confirmation"),
        sa.Column("progress", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("error_code", sa.String(length=80), nullable=True),
        sa.Column("book_id", sa.Integer(), sa.ForeignKey("books.id", ondelete="SET NULL"), nullable=True),
        sa.Column("file_sha256", sa.String(length=64), nullable=True),
        sa.Column("details", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_book_import_jobs_device_created", "book_import_jobs", ["device_key_hash", "created_at"])
    op.create_index("ix_book_import_jobs_status", "book_import_jobs", ["status", "updated_at"])

    op.create_table(
        "book_artifacts",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("book_id", sa.Integer(), sa.ForeignKey("books.id", ondelete="CASCADE"), nullable=False),
        sa.Column("device_key_hash", sa.String(length=64), nullable=False),
        sa.Column("original_name", sa.String(length=255), nullable=False),
        sa.Column("storage_name", sa.String(length=120), nullable=False, unique=True),
        sa.Column("file_format", sa.String(length=16), nullable=False),
        sa.Column("mime_type", sa.String(length=100), nullable=False),
        sa.Column("byte_size", sa.Integer(), nullable=False),
        sa.Column("sha256", sa.String(length=64), nullable=False),
        sa.Column("source_url", sa.String(length=2048), nullable=True),
        sa.Column("license_url", sa.String(length=2048), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("device_key_hash", "book_id", name="uq_book_artifact_device_book"),
    )
    op.create_index("ix_book_artifacts_device_book", "book_artifacts", ["device_key_hash", "book_id"])
    op.create_index("ix_book_artifacts_device_sha", "book_artifacts", ["device_key_hash", "sha256"])


def downgrade() -> None:
    op.drop_index("ix_book_artifacts_device_sha", table_name="book_artifacts")
    op.drop_index("ix_book_artifacts_device_book", table_name="book_artifacts")
    op.drop_table("book_artifacts")
    op.drop_index("ix_book_import_jobs_status", table_name="book_import_jobs")
    op.drop_index("ix_book_import_jobs_device_created", table_name="book_import_jobs")
    op.drop_table("book_import_jobs")
