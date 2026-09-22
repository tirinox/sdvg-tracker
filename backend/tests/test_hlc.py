import pytest

from app.sync.hlc import Clock, Timestamp
from tests.conftest import load_shared

VECTORS = load_shared("vectors/hlc.json")


@pytest.mark.parametrize("case", VECTORS["cases"], ids=lambda c: c["name"])
def test_hlc_vectors(case):
    pt = {"value": 0}
    initial = case["initial"] or {"l": 0, "c": 0}
    clock = Clock(
        case["node_id"], now_ms=lambda: pt["value"], ms=initial["l"], counter=initial["c"]
    )
    for step in case["steps"]:
        pt["value"] = step["pt"]
        got = clock.now() if step["op"] == "now" else clock.receive(step["remote"])
        assert got == step["expect"]


def test_ordering_matches_timestamp_ordering():
    ordering = VECTORS["ordering"]
    assert sorted(ordering, key=Timestamp.parse) == ordering


def test_timestamps_are_monotonic_under_frozen_clock():
    clock = Clock("0123456789abcdef", now_ms=lambda: 1790000000000)
    values = [clock.now() for _ in range(20_000)]
    assert values == sorted(values)
    assert len(set(values)) == len(values)


@pytest.mark.parametrize("bad", ["", "1790000000000-0000-XYZ", "179-0000-aaaaaaaaaaaaaaaa"])
def test_parse_rejects_garbage(bad):
    with pytest.raises(ValueError):
        Timestamp.parse(bad)


def test_rejects_bad_node_id():
    with pytest.raises(ValueError):
        Clock("not-hex")
