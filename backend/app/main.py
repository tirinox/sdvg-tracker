from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.api import sync, system
from app.config import Settings, get_settings
from app.db import create_db_engine, migrate
from app.sync.validation import ChangeValidator


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        engine = create_db_engine(settings.database_path)
        migrate(engine)
        app.state.engine = engine
        app.state.validator = ChangeValidator(
            settings.shared_dir / "schema", settings.max_future_skew_ms
        )
        yield
        engine.dispose()

    app = FastAPI(title="SDVG Tracker", lifespan=lifespan)
    app.state.settings = settings
    app.include_router(system.router)
    app.include_router(sync.router)
    return app
