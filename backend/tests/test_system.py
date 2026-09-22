from tests.conftest import TEST_TOKEN


def test_health(client):
    resp = client.get("/api/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok", "api_version": 1}


def test_auth_check_with_token(client):
    resp = client.get("/api/auth/check", headers={"Authorization": f"Bearer {TEST_TOKEN}"})
    assert resp.status_code == 200
    assert resp.json() == {"ok": True}


def test_auth_check_without_token(client):
    resp = client.get("/api/auth/check")
    assert resp.status_code == 401


def test_auth_check_with_wrong_token(client):
    resp = client.get("/api/auth/check", headers={"Authorization": "Bearer nope"})
    assert resp.status_code == 401
