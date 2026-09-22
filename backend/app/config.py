from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=("../.env", ".env"), extra="ignore")

    api_token: str = Field(min_length=16)
    database_path: str = "/data/sdvg.db"


@lru_cache
def get_settings() -> Settings:
    return Settings()
