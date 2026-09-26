from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

REPO_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=("../.env", ".env"), extra="ignore")

    api_token: str = Field(min_length=16)
    database_path: str = "data/sdvg.db"
    shared_dir: Path = REPO_DIR / "shared"
    # Clocks further ahead than this are rejected: a device with a broken clock would
    # otherwise win every future conflict.
    max_future_skew_ms: int = 24 * 3600 * 1000
    # Emoji suggestions: the model from `make emoji-model` (built into the Docker image).
    # Without it /api/suggest-emoji answers 503 and everything else works as before.
    emoji_model_dir: Path = REPO_DIR / "backend" / "models" / "multilingual-e5-small"
    # Description vectors cached between restarts; by default next to the database.
    emoji_cache_dir: Path | None = None
    emoji_threads: int = 1


@lru_cache
def get_settings() -> Settings:
    return Settings()
