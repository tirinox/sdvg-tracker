from alembic import context
from app.config import get_settings
from app.db import create_db_engine, metadata

target_metadata = metadata


def run(connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata, render_as_batch=True)
    with context.begin_transaction():
        context.run_migrations()


connection = context.config.attributes.get("connection")
if connection is not None:
    run(connection)
else:
    # CLI usage: `uv run alembic revision --autogenerate -m ...`
    with create_db_engine(get_settings().database_path).begin() as conn:
        run(conn)
