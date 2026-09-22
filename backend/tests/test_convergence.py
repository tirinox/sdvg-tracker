"""Two simulated devices work offline and must converge after syncing."""

from fastapi.testclient import TestClient

from app.main import create_app
from app.sync.validation import deterministic_id
from tests.sim import FakeTime, SimClient

T0 = 1790000000000
TASK = "0192f0a0-0000-7000-8000-000000000001"
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


def test_server_database_replaced(settings, tmp_path):
    (web, _), (phone, _) = devices()
    with TestClient(create_app(settings)) as old_server:
        web.write("task", TASK, **NEW_TASK)
        converge(old_server, web, phone)

    new = settings.model_copy(update={"database_path": str(tmp_path / "restored.db")})
    with TestClient(create_app(new)) as new_server:
        phone.write("task", TASK, title="Правка после переезда")
        web.sync(new_server)  # sees a new server_id, re-uploads everything it has
        phone.sync(new_server)
        web.sync(new_server)
        assert web.state() == phone.state()
        assert web.get("task", TASK)["title"] == "Правка после переезда"

        fresh = SimClient("c" * 16, FakeTime(T0))
        fresh.sync(new_server)
        assert fresh.state() == web.state()
