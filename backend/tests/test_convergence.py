"""Two simulated devices work offline and must converge after syncing."""

import sqlite3

import pytest

from app import admin
from app.sync.validation import deterministic_id
from tests.conftest import AUTH
from tests.sim import FakeTime, ServerChanged, SimClient

T0 = 1790000000000
TASK = "0192f0a0-0000-7000-8000-000000000001"
OTHER = "0192f0a0-0000-7000-8000-000000000002"
LUNCH = "0192f0a0-0000-7000-8000-000000000101"
NEW_TASK = {
    "title": "Починить коляску",
    "notes": "",
    "emoji": "🛠️",
    "color": 3,
    "date": "2026-09-20",
    "first_date": "2026-09-20",
    "time_kind": "none",
    "part_of_day": None,
    "time": None,
    "duration_min": None,
    "deadline_date": None,
    "deadline_time": None,
    "done_on": None,
    "deleted": False,
    "sort_key": "a0",
    "created_at": "2026-09-20T07:00:00Z",
}


def devices(phone_skew_ms: int = 0):
    web_time, phone_time = FakeTime(T0), FakeTime(T0 + phone_skew_ms)
    return (SimClient("a" * 16, web_time), web_time), (SimClient("b" * 16, phone_time), phone_time)


def converge(http, *clients):
    for c in clients:
        c.sync(http)
    for c in clients:
        c.sync(http)
    states = [c.state() for c in clients]
    assert all(s == states[0] for s in states)


def test_offline_edits_of_different_fields(client):
    (web, _), (phone, _) = devices()
    web.write("task", TASK, **NEW_TASK)
    converge(client, web, phone)

    phone.write("task", TASK, title="Починить колесо коляски")
    web.write("task", TASK, done_on="2026-09-22")
    converge(client, web, phone)

    assert phone.get("task", TASK)["title"] == "Починить колесо коляски"
    assert phone.get("task", TASK)["done_on"] == "2026-09-22"


def test_causality_beats_a_slow_clock(client):
    # The phone's wall clock is 10 minutes behind, yet an edit made after seeing the web's edit
    # must win: receiving the web's timestamp moves the phone's HLC past it.
    (web, _), (phone, _) = devices(phone_skew_ms=-10 * 60 * 1000)
    web.write("task", TASK, **NEW_TASK)
    web.write("task", TASK, color=1)
    converge(client, web, phone)

    phone.write("task", TASK, color=9)
    converge(client, web, phone)
    assert web.get("task", TASK)["color"] == 9


def test_two_lunches(client):
    (web, _), (phone, _) = devices()
    check = deterministic_id("routine_check", LUNCH, "2026-09-22")
    for device in (web, phone):
        device.write(
            "routine_check",
            check,
            routine_id=LUNCH,
            date="2026-09-22",
            status="done",
            done_at="2026-09-22T10:00:00Z",
            snapshot=None,
        )
    converge(client, web, phone)
    assert web.count("routine_check") == 1


def test_double_auto_rollover(client):
    (web, _), (phone, _) = devices()
    web.write("task", TASK, **NEW_TASK)
    converge(client, web, phone)

    for device in (web, phone):  # both roll 09-20 and 09-21 over while offline
        for d, nd in (("2026-09-20", "2026-09-21"), ("2026-09-21", "2026-09-22")):
            device.write(
                "task_move",
                deterministic_id("task_move", TASK, d),
                task_id=TASK,
                from_date=d,
                to_date=nd,
                kind="auto",
            )
        device.write("task", TASK, date="2026-09-22")
    converge(client, web, phone)
    assert web.count("task_move", task_id=TASK) == 2


def test_many_rows_with_small_pages(client):
    (web, _), _ = devices()
    web.write("task", TASK, **NEW_TASK)
    for i in range(2, 41):
        web.write("task", f"0192f0a0-0000-7000-8000-{i:012d}", **NEW_TASK)
    web.sync(client)

    fresh = SimClient("c" * 16, FakeTime(T0), limit=7)
    fresh.sync(client)
    assert fresh.state() == web.state()


def snapshot(path: str) -> bytes:
    """What make backup takes: a consistent copy of the live database."""
    src, dst = sqlite3.connect(path), sqlite3.connect(":memory:")
    src.backup(dst)
    return dst.serialize()


def test_reset_server_asks_before_merging(client, settings):
    (web, _), (phone, _) = devices()
    web.write("task", TASK, **NEW_TASK)
    converge(client, web, phone)

    admin.reset(settings.database_path)
    with pytest.raises(ServerChanged) as changed:
        web.sync(client)
    info = changed.value.info
    assert info["counts"] == {}
    assert client.get("/api/sync/info", headers=AUTH).json()["counts"] == {}

    # One device keeps its data and fills the new data set, the other takes it as it is.
    phone.merge_into(info["server_id"])
    phone.sync(client)
    web.take_server_data()
    web.sync(client)
    assert web.state() == phone.state()
    assert web.get("task", TASK)["title"] == NEW_TASK["title"]


def test_reset_server_can_be_taken_as_is(client, settings):
    (web, _), _ = devices()
    web.write("task", TASK, **NEW_TASK)
    web.sync(client)

    admin.reset(settings.database_path)
    with pytest.raises(ServerChanged):
        web.sync(client)
    web.take_server_data()
    web.sync(client)
    assert web.state() == {}
    assert client.get("/api/sync/info", headers=AUTH).json()["counts"] == {}


def test_restored_backup_gets_the_lost_rows_back(client, settings):
    (web, _), (phone, _) = devices()
    web.write("task", TASK, **NEW_TASK)
    converge(client, web, phone)
    backup = snapshot(settings.database_path)

    phone.write("task", TASK, title="Правка после бэкапа")
    phone.write("task", OTHER, **NEW_TASK)
    converge(client, web, phone)

    admin.restore(settings.database_path, backup)
    web.write("task", TASK, color=3)
    web.sync(client)  # rewind: pushes everything it has, including the phone's lost edits
    phone.sync(client)
    web.sync(client)
    assert web.state() == phone.state()
    assert web.get("task", TASK)["title"] == "Правка после бэкапа"
    assert web.get("task", TASK)["color"] == 3

    fresh = SimClient("c" * 16, FakeTime(T0))
    fresh.sync(client)
    assert fresh.state() == web.state()
