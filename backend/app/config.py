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


@lru_cache
def get_settings() -> Settings:
    return Settings()
