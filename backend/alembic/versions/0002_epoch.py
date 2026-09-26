"""epoch: changes when the database is restored from a backup

Revision ID: 0002
Revises: 0001
Create Date: 2026-09-26
"""

import uuid
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # server_id names the data set and survives backups; epoch changes on every restore, so
    # clients that synced past the restored point know to push their rows again.
    meta = sa.table("meta", sa.column("key", sa.String), sa.column("value", sa.String))
    op.bulk_insert(meta, [{"key": "epoch", "value": str(uuid.uuid4())}])


def downgrade() -> None:
    op.execute("DELETE FROM meta WHERE key = 'epoch'")
