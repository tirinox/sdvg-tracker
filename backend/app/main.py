from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI

from app.api import emoji, sync, system
from app.config import Settings, get_settings
from app.db import create_db_engine, migrate
from app.emoji.encoder import MODEL_FILE
from app.emoji.suggest import EmojiSuggester
from app.sync.validation import ChangeValidator


def start_emoji(settings: Settings) -> EmojiSuggester | None:
    if not (settings.emoji_model_dir / MODEL_FILE).exists():
        return None
    suggester = EmojiSuggester(
        settings.emoji_model_dir,
        settings.emoji_cache_dir or Path(settings.database_path).parent,
        settings.emoji_threads,
    )
    suggester.start()
    return suggester


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
        app.state.emoji = start_emoji(settings)
        yield
        engine.dispose()

    app = FastAPI(title="SDVG Tracker", lifespan=lifespan)
    app.state.settings = settings
    app.include_router(system.router)
    app.include_router(sync.router)
    app.include_router(emoji.router)
    return app
