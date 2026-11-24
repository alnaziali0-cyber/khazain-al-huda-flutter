"""Add normalized book editions and hierarchical table of contents.

Revision ID: 0009_book_editions_and_toc
Revises: 0008_shia_library_import_engine
"""
from alembic import op
import sqlalchemy as sa

revision = "0009_book_editions_and_toc"
down_revision = "0008_shia_library_import_engine"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "book_editions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("book_id", sa.Integer(), sa.ForeignKey("books.id", ondelete="CASCADE"), nullable=False),
        sa.Column("edition_label", sa.String(length=180), nullable=True),
        sa.Column("publisher", sa.String(length=180), nullable=True),
        sa.Column("publication_year", sa.String(length=32), nullable=True),
        sa.Column("isbn", sa.String(length=32), nullable=True),
        sa.Column("printing_batch", sa.String(length=80), nullable=True),
        sa.Column("language", sa.String(length=40), nullable=True),
        sa.Column("source_url", sa.String(length=2048), nullable=True),
        sa.Column("rights_status", sa.String(length=24), nullable=False, server_default="unverified"),
        sa.Column("rights_evidence", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_book_editions_book_created", "book_editions", ["book_id", "created_at"])

    op.create_table(
        "book_toc_entries",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("book_id", sa.Integer(), sa.ForeignKey("books.id", ondelete="CASCADE"), nullable=False),
        sa.Column("edition_id", sa.Integer(), sa.ForeignKey("book_editions.id", ondelete="SET NULL"), nullable=True),
        sa.Column("parent_id", sa.Integer(), sa.ForeignKey("book_toc_entries.id", ondelete="CASCADE"), nullable=True),
        sa.Column("volume_number", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("title", sa.String(length=500), nullable=False),
        sa.Column("page_number", sa.Integer(), nullable=True),
        sa.Column("page_label", sa.String(length=80), nullable=True),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("source_entry_id", sa.String(length=80), nullable=True),
        sa.CheckConstraint("volume_number >= 1", name="ck_book_toc_volume_positive"),
        sa.CheckConstraint("page_number IS NULL OR page_number >= 1", name="ck_book_toc_page_positive"),
    )
    op.create_index("ix_book_toc_book_volume_order", "book_toc_entries", ["book_id", "volume_number", "sort_order"])


def downgrade() -> None:
    op.drop_index("ix_book_toc_book_volume_order", table_name="book_toc_entries")
    op.drop_table("book_toc_entries")
    op.drop_index("ix_book_editions_book_created", table_name="book_editions")
    op.drop_table("book_editions")
