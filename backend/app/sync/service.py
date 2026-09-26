import sqlalchemy as sa
from sqlalchemy.dialects.sqlite import insert

from app.db import meta, records
from app.sync.merge import merge_fields
from app.sync.schemas import Change, SyncInfo, SyncRequest, SyncResponse
from app.sync.validation import ChangeError, ChangeValidator


class SyncError(ValueError):
    def __init__(self, index: int, error: ChangeError):
        super().__init__(f"changes[{index}]: {error}")
        self.index = index


class ServerChanged(Exception):
    """The client last synced with another database; nothing was applied."""

    def __init__(self, info: SyncInfo):
        super().__init__(f"server database is {info.server_id}")
        self.info = info


def _info(conn: sa.Connection) -> SyncInfo:
    ids = dict(conn.execute(sa.select(meta.c.key, meta.c.value)).tuples().all())
    counts = conn.execute(
        sa.select(records.c.entity, sa.func.count()).group_by(records.c.entity)
    ).tuples()
    return SyncInfo(server_id=ids["server_id"], epoch=ids["epoch"], counts=dict(counts.all()))


def info(engine: sa.Engine) -> SyncInfo:
    with engine.begin() as conn:
        return _info(conn)


def sync(engine: sa.Engine, validator: ChangeValidator, req: SyncRequest) -> SyncResponse:
    """Apply pushed changes and return rows changed after the client's cursor.

    Atomic: either every change is applied or none (a single invalid change rejects the request,
    and so does a client that last synced with another database).
    """
    with engine.begin() as conn:
        ids = dict(conn.execute(sa.select(meta.c.key, meta.c.value)).tuples().all())
        server_id, epoch = ids["server_id"], ids["epoch"]
        if req.server_id is not None and req.server_id != server_id:
            raise ServerChanged(_info(conn))

        for i, change in enumerate(req.changes):
            try:
                validator.validate(change)
            except ChangeError as e:
                raise SyncError(i, e) from e

        seq = conn.execute(sa.select(sa.func.coalesce(sa.func.max(records.c.seq), 0))).scalar_one()
        # Restored from a backup (new epoch) or older than the client's cursor: send everything
        # from the start, and the client pushes back what the backup lost.
        rewind = (req.epoch is not None and req.epoch != epoch) or req.cursor > seq
        cursor = 0 if rewind else req.cursor

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
            .where(records.c.seq > cursor)
            .order_by(records.c.seq)
            .limit(req.limit + 1)
        ).all()

    has_more = len(rows) > req.limit
    rows = rows[: req.limit]
    return SyncResponse(
        server_id=server_id,
        epoch=epoch,
        cursor=rows[-1].seq if rows else cursor,
        changes=[Change(entity=r.entity, id=r.id, fields=r.fields, clocks=r.clocks) for r in rows],
        has_more=has_more,
        rewind=rewind,
    )
