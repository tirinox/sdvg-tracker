from pathlib import Path

import sqlalchemy as sa
from alembic.config import Config

from alembic import command

BACKEND_DIR = Path(__file__).resolve().parents[1]

metadata = sa.MetaData()

# All synced entities share one table: the server merges and relays rows, it never queries
# individual fields. Field-level validation happens against shared/schema on push.
records = sa.Table(
    "records",
    metadata,
    sa.Column("entity", sa.String, primary_key=True),
    sa.Column("id", sa.String, primary_key=True),
    sa.Column("fields", sa.JSON, nullable=False),
    sa.Column("clocks", sa.JSON, nullable=False),
    sa.Column("seq", sa.Integer, nullable=False, index=True, unique=True),
)

meta = sa.Table(
    "meta",
    metadata,
    sa.Column("key", sa.String, primary_key=True),
    sa.Column("value", sa.String, nullable=False),
)


def create_db_engine(path: str) -> sa.Engine:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    engine = sa.create_engine(f"sqlite+pysqlite:///{path}")

    @sa.event.listens_for(engine, "connect")
    def on_connect(dbapi_conn, _record):
        # Let SQLAlchemy emit BEGIN itself (see "begin" below) instead of pysqlite.
        dbapi_conn.isolation_level = None
        cur = dbapi_conn.cursor()
        cur.execute("PRAGMA journal_mode=WAL")
        cur.execute("PRAGMA synchronous=NORMAL")
        cur.execute("PRAGMA busy_timeout=5000")
        cur.close()

    @sa.event.listens_for(engine, "begin")
    def on_begin(conn):
        # Take the write lock up front: a sync is read-merge-write and must be serialized.
        conn.exec_driver_sql("BEGIN IMMEDIATE")

    return engine


def migrate(engine: sa.Engine) -> None:
    cfg = Config(BACKEND_DIR / "alembic.ini")
    cfg.set_main_option("script_location", str(BACKEND_DIR / "alembic"))
    with engine.begin() as conn:
        cfg.attributes["connection"] = conn
        command.upgrade(cfg, "head")
