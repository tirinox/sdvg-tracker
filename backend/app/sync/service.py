import sqlalchemy as sa
from sqlalchemy.dialects.sqlite import insert

from app.db import meta, records
from app.sync.merge import merge_fields
from app.sync.schemas import Change, SyncRequest, SyncResponse
from app.sync.validation import ChangeError, ChangeValidator


class SyncError(ValueError):
    def __init__(self, index: int, error: ChangeError):
        super().__init__(f"changes[{index}]: {error}")
        self.index = index


def sync(engine: sa.Engine, validator: ChangeValidator, req: SyncRequest) -> SyncResponse:
    """Apply pushed changes and return rows changed after the client's cursor.

    Atomic: either every change is applied or none (a single invalid change rejects the request).
    """
    for i, change in enumerate(req.changes):
        try:
            validator.validate(change)
        except ChangeError as e:
            raise SyncError(i, e) from e

    with engine.begin() as conn:
        server_id = conn.execute(
            sa.select(meta.c.value).where(meta.c.key == "server_id")
        ).scalar_one()
        seq = conn.execute(sa.select(sa.func.coalesce(sa.func.max(records.c.seq), 0))).scalar_one()

        for change in req.changes:
            key = (records.c.entity == change.entity) & (records.c.id == change.id)
            row = conn.execute(sa.select(records.c.fields, records.c.clocks).where(key)).first()
            fields, clocks = (dict(row.fields), dict(row.clocks)) if row else ({}, {})
            if not merge_fields(fields, clocks, change.fields, change.clocks):
                continue
            seq += 1
            values = {"fields": fields, "clocks": clocks, "seq": seq}
            conn.execute(
                insert(records)
                .values(entity=change.entity, id=change.id, **values)
                .on_conflict_do_update(index_elements=["entity", "id"], set_=values)
            )

        rows = conn.execute(
            sa.select(records)
            .where(records.c.seq > req.cursor)
            .order_by(records.c.seq)
            .limit(req.limit + 1)
        ).all()

    has_more = len(rows) > req.limit
    rows = rows[: req.limit]
    return SyncResponse(
        server_id=server_id,
        cursor=rows[-1].seq if rows else req.cursor,
        changes=[Change(entity=r.entity, id=r.id, fields=r.fields, clocks=r.clocks) for r in rows],
        has_more=has_more,
    )
