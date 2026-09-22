"""records and meta

Revision ID: 0001
Revises:
Create Date: 2026-09-22
"""

import uuid
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "records",
        sa.Column("entity", sa.String, primary_key=True),
        sa.Column("id", sa.String, primary_key=True),
        sa.Column("fields", sa.JSON, nullable=False),
        sa.Column("clocks", sa.JSON, nullable=False),
        sa.Column("seq", sa.Integer, nullable=False),
    )
    op.create_index("ix_records_seq", "records", ["seq"], unique=True)
    meta = op.create_table(
        "meta",
        sa.Column("key", sa.String, primary_key=True),
        sa.Column("value", sa.String, nullable=False),
    )
    # Identifies this database: clients reset their cursor when it changes.
    op.bulk_insert(meta, [{"key": "server_id", "value": str(uuid.uuid4())}])


def downgrade() -> None:
    op.drop_table("meta")
    op.drop_index("ix_records_seq", table_name="records")
    op.drop_table("records")
