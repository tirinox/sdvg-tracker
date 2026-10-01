import pytest

from app.sync.schemas import Change
from app.sync.validation import ChangeError, ChangeValidator, deterministic_id
from tests.conftest import SHARED, load_shared

NOW = 1790000000000
CLOCK = f"{NOW:013d}-0000-aaaaaaaaaaaaaaaa"
TASK = "0192f0a0-0000-7000-8000-000000000001"
ROUTINE = "0192f0a0-0000-7000-8000-000000000101"
DAY = 24 * 3600 * 1000


@pytest.fixture(scope="module")
def validator() -> ChangeValidator:
    return ChangeValidator(SHARED / "schema", max_future_skew_ms=DAY, now_ms=lambda: NOW)


def change(entity="task", id_=TASK, clock=CLOCK, **fields) -> Change:
    return Change(entity=entity, id=id_, fields=fields, clocks={k: clock for k in fields})


def test_deterministic_id_matches_vectors():
    for case in load_shared("vectors/ids.json")["cases"]:
        entity, *parts = case["name"].split(":")
        assert deterministic_id(entity, *parts) == case["expect"]


@pytest.mark.parametrize(
    "ch",
    [
        change(title="Починить коляску", color=3, date=None, time_kind="exact", time="09:30"),
        change(done_on="2026-09-22"),
        change(priority="high"),
        change("settings", "settings", day_start_hour=5, attention_thresholds=[1, 2, 3, 4]),
        change(
            "routine_check",
            deterministic_id("routine_check", ROUTINE, "2026-09-22"),
            routine_id=ROUTINE,
            date="2026-09-22",
            status="done",
        ),
        # Partial change of a deterministic row: id cannot be re-derived, accepted as is.
        change(
            "routine_check", deterministic_id("routine_check", ROUTINE, "2026-09-22"), status=None
        ),
        change(clock=f"{NOW + DAY:013d}-0000-aaaaaaaaaaaaaaaa", title="на границе"),
    ],
    ids=[
        "task",
        "partial",
        "priority",
        "settings",
        "routine_check",
        "partial deterministic",
        "max skew",
    ],
)
def test_valid_changes(validator, ch):
    validator.validate(ch)


@pytest.mark.parametrize(
    ("ch", "message"),
    [
        (change(nope=1), "unknown field"),
        (change(title=""), "task.title"),
        (change(color=12), "task.color"),
        (change(date="2026-13-01"), "task.date"),
        (change(time="9:30"), "task.time"),
        (change(time_kind="later"), "task.time_kind"),
        (change(priority="urgent"), "task.priority"),
        (change("routine_version", ROUTINE, priority=2), "routine_version.priority"),
        (change(clock="yesterday", title="x"), "invalid clock"),
        (change(clock=f"{NOW + DAY + 1:013d}-0000-aaaaaaaaaaaaaaaa", title="x"), "future"),
        (change(id_=TASK.upper(), title="x"), "lowercase canonical UUID"),
        (change(id_="settings", title="x"), "UUID"),
        (change("settings", TASK, day_start_hour=4), "settings id"),
        (
            change(
                "task_move",
                TASK,
                task_id=TASK,
                from_date="2026-09-21",
                to_date="2026-09-22",
                kind="auto",
            ),
            "task_move id must be",
        ),
    ],
    ids=lambda v: v if isinstance(v, str) else "",
)
def test_invalid_changes(validator, ch, message):
    with pytest.raises(ChangeError, match=message):
        validator.validate(ch)


def test_fields_and_clocks_must_match(validator):
    ch = Change(entity="task", id=TASK, fields={"title": "x"}, clocks={"color": CLOCK})
    with pytest.raises(ChangeError, match="same keys"):
        validator.validate(ch)
