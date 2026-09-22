import pytest
from fastapi.testclient import TestClient

from app.config import Settings, get_settings
from app.main import create_app

TEST_TOKEN = "test-token-0123456789abcdef"


@pytest.fixture
def client() -> TestClient:
    app = create_app()
    app.dependency_overrides[get_settings] = lambda: Settings(api_token=TEST_TOKEN)
    return TestClient(app)
