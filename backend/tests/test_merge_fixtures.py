import copy
import itertools
import json

import pytest

from app.sync.merge import merge_fields
from tests.conftest import SHARED

CASES = [
    pytest.param(case, id=f"{path.stem}: {case['name']}")
    for path in sorted((SHARED / "sync-fixtures").glob("*.json"))
    for case in json.loads(path.read_text())["cases"]
]


def apply(initial: list[dict], changes: list[dict]) -> list[dict]:
    rows: dict[tuple[str, str], dict] = {}
    for change in copy.deepcopy(initial) + copy.deepcopy(changes):
        key = (change["entity"], change["id"])
        row = rows.setdefault(
            key, {"entity": change["entity"], "id": change["id"], "fields": {}, "clocks": {}}
        )
        merge_fields(row["fields"], row["clocks"], change["fields"], change["clocks"])
    return [rows[k] for k in sorted(rows)]


@pytest.mark.parametrize("case", CASES)
def test_merge_fixture(case):
    orders = (
        itertools.permutations(case["changes"]) if case["order_independent"] else [case["changes"]]
    )
    for order in orders:
        assert apply(case["initial"], list(order)) == case["expected"]


def test_merge_reports_whether_anything_changed():
    fields, clocks = {"title": "a"}, {"title": "1790000000000-0000-aaaaaaaaaaaaaaaa"}
    older = {"title": "1780000000000-0000-aaaaaaaaaaaaaaaa"}
    newer = {"title": "1790000000001-0000-aaaaaaaaaaaaaaaa"}
    assert not merge_fields(fields, clocks, {"title": "b"}, older)
    assert not merge_fields(fields, clocks, {"title": "a"}, dict(clocks))
    assert merge_fields(fields, clocks, {"title": "c"}, newer)
    assert fields == {"title": "c"}
