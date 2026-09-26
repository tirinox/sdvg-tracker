# Build context: repository root (the backend needs shared/schema).
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_NO_DEV=1
WORKDIR /app

# The emoji model (~120 MB) first: pinned, it outlives dependency and code changes.
COPY backend/scripts/fetch_emoji_model.py ./scripts/
RUN python scripts/fetch_emoji_model.py /app/models/multilingual-e5-small

COPY backend/pyproject.toml backend/uv.lock backend/.python-version ./
RUN uv sync --locked --no-install-project

COPY backend/alembic.ini ./
COPY backend/alembic ./alembic
COPY backend/app ./app
COPY shared/schema ./shared/schema

ENV PATH="/app/.venv/bin:$PATH" SHARED_DIR=/app/shared \
    EMOJI_MODEL_DIR=/app/models/multilingual-e5-small
EXPOSE 8000
CMD ["uvicorn", "--factory", "app.main:create_app", "--host", "0.0.0.0", "--port", "8000"]
