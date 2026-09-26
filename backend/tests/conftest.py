import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app

TEST_TOKEN = "test-token-0123456789abcdef"
AUTH = {"Authorization": f"Bearer {TEST_TOKEN}"}
SHARED = Path(__file__).resolve().parents[2] / "shared"


def load_shared(rel: str) -> dict:
    return json.loads((SHARED / rel).read_text())


@pytest.fixture
def settings(tmp_path) -> Settings:
    # No emoji model: tests that need it load it themselves (test_emoji.py).
    return Settings(
        api_token=TEST_TOKEN,
        database_path=str(tmp_path / "test.db"),
        emoji_model_dir=tmp_path / "no-emoji-model",
    )


@pytest.fixture
def client(settings):
    with TestClient(create_app(settings)) as c:
        yield c
