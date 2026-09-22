import json

import pytest
from fastapi.testclient import TestClient

from app.main import create_app
from tests.conftest import AUTH, SHARED

T0 = 1790000000000
TASK = "0192f0a0-0000-7000-8000-000000000001"


def clock(offset: int = 0, node: str = "a" * 16) -> str:
    return f"{T0 + offset:013d}-0000-{node}"


def task_change(offset=0, id_=TASK, **fields) -> dict:
    fields = fields or {"title": "Починить коляску"}
    return {
        "entity": "task",
        "id": id_,
        "fields": fields,
        "clocks": dict.fromkeys(fields, clock(offset)),
    }


def sync(client, cursor=0, changes=(), **extra):
    resp = client.post(
        "/api/sync", json={"cursor": cursor, "changes": list(changes), **extra}, headers=AUTH
    )
    assert resp.status_code == 200, resp.text
    return resp.json()


def test_requires_token(client):
    assert client.post("/api/sync", json={"cursor": 0, "changes": []}).status_code == 401


def test_empty_server(client):
    body = sync(client)
    assert body["cursor"] == 0
    assert body["changes"] == []
    assert body["has_more"] is False
    assert len(body["server_id"]) == 36


def test_push_then_pull(client):
    pushed = sync(client, changes=[task_change()])
    assert pushed["cursor"] == 1
    assert pushed["changes"] == [task_change()]

    edit = task_change(10, color=4)
    after = sync(client, cursor=1, changes=[edit])
    assert after["cursor"] == 2
    assert after["changes"][0]["fields"] == {"title": "Починить коляску", "color": 4}

    assert sync(client, cursor=2)["changes"] == []


def test_repeat_push_is_idempotent(client):
    first = sync(client, changes=[task_change()])
    again = sync(client, cursor=first["cursor"], changes=[task_change()])
    assert again["cursor"] == first["cursor"]
    assert again["changes"] == []


def test_stale_change_does_not_bump_seq(client):
    sync(client, changes=[task_change(100, title="новое")])
    body = sync(client, cursor=1, changes=[task_change(50, title="старое")])
    assert body["changes"] == []
    assert sync(client)["changes"][0]["fields"]["title"] == "новое"


def test_pagination(client):
    ids = [f"0192f0a0-0000-7000-8000-{i:012d}" for i in range(1, 26)]
    sync(client, changes=[task_change(i, id_=id_) for i, id_ in enumerate(ids)])

    seen, cursor = [], 0
    while True:
        body = sync(client, cursor=cursor, limit=10)
        seen += [c["id"] for c in body["changes"]]
        cursor = body["cursor"]
        if not body["has_more"]:
            break
    assert seen == ids


def test_invalid_change_rejects_whole_request(client):
    resp = client.post(
        "/api/sync",
        json={"cursor": 0, "changes": [task_change(), task_change(id_="not-a-uuid")]},
        headers=AUTH,
    )
    assert resp.status_code == 422
    assert resp.json()["detail"]["change_index"] == 1
    assert sync(client)["changes"] == []


@pytest.mark.parametrize(
    "payload",
    [
        {"changes": []},
        {"cursor": -1, "changes": []},
        {"cursor": 0, "changes": [], "limit": 0},
        {"cursor": 0, "changes": [], "extra": 1},
        {"cursor": 0, "changes": [{**task_change(), "entity": "mood"}]},
        {"cursor": 0, "changes": [{**task_change(), "fields": {}, "clocks": {}}]},
    ],
)
def test_malformed_requests(client, payload):
    assert client.post("/api/sync", json=payload, headers=AUTH).status_code == 422


def test_server_id_survives_restart(settings):
    with TestClient(create_app(settings)) as c:
        first = sync(c, changes=[task_change()])
    with TestClient(create_app(settings)) as c:
        second = sync(c)
    assert second["server_id"] == first["server_id"]
    assert second["changes"] == first["changes"]


def test_new_database_gets_new_server_id(settings, tmp_path):
    with TestClient(create_app(settings)) as c:
        first = sync(c)["server_id"]
    other = settings.model_copy(update={"database_path": str(tmp_path / "other.db")})
    with TestClient(create_app(other)) as c:
        assert sync(c)["server_id"] != first


SYNC_CASES = [
    pytest.param(case, id=f"{path.stem}: {case['name']}")
    for path in sorted((SHARED / "sync-fixtures").glob("*.json"))
    for case in json.loads(path.read_text())["cases"]
]


@pytest.mark.parametrize("case", SYNC_CASES)
def test_fixture_through_api(client, case):
    # Fixture clocks are fixed in 2026-09; they are in the past relative to the skew check.
    sync(client, changes=case["initial"])
    for change in reversed(case["changes"]):  # arrival order must not matter
        sync(client, changes=[change])
    rows = sorted(sync(client)["changes"], key=lambda r: (r["entity"], r["id"]))
    assert rows == case["expected"]


def test_concurrent_pushes_are_serialized(client):
    from concurrent.futures import ThreadPoolExecutor

    def push(worker: int) -> None:
        for i in range(20):
            id_ = f"0192f0a0-0000-7000-9000-{worker:06d}{i:06d}"
            # Every worker also bumps the same row: lost updates would show up here.
            shared = task_change(worker * 100 + i, id_=TASK, color=(worker + i) % 12)
            sync(client, changes=[task_change(i, id_=id_), shared])

    with ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(push, range(8)))

    rows = sync(client, limit=5000)["changes"]
    assert len(rows) == 8 * 20 + 1
    top = max(w * 100 + i for w in range(8) for i in range(20))
    shared_row = next(r for r in rows if r["id"] == TASK)
    assert shared_row["clocks"]["color"] == clock(top)
