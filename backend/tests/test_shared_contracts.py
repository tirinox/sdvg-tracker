"""Checks that shared/ contracts are internally consistent: schemas are valid, fixtures conform."""

import json
import uuid
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

SHARED = Path(__file__).resolve().parents[2] / "shared"
ENTITIES = ["task", "task_move", "routine", "routine_version", "routine_check", "settings"]


def load(rel: str) -> dict:
    return json.loads((SHARED / rel).read_text())


def all_schemas() -> dict[str, dict]:
    return {p.name: json.loads(p.read_text()) for p in (SHARED / "schema").glob("*.json")}


REGISTRY = Registry().with_resources(
    (name, Resource.from_contents(schema)) for name, schema in all_schemas().items()
)


def validator(schema: dict) -> Draft202012Validator:
    return Draft202012Validator(schema, registry=REGISTRY)


def row_validator(entity: str, partial: bool) -> Draft202012Validator:
    schema = dict(load(f"schema/{entity}.schema.json"))
    if partial:
        schema.pop("required")
    return validator(schema)


def sync_def(name: str) -> Draft202012Validator:
    return validator({"$ref": f"sync.schema.json#/$defs/{name}"})


def ids_namespace() -> uuid.UUID:
    return uuid.UUID(load("vectors/ids.json")["namespace"])


def expected_id(entity: str, fields: dict) -> str | None:
    if entity == "routine_check":
        name = f"routine_check:{fields['routine_id']}:{fields['date']}"
    elif entity == "task_move":
        name = f"task_move:{fields['task_id']}:{fields['from_date']}"
    else:
        return None
    return str(uuid.uuid5(ids_namespace(), name))


@pytest.mark.parametrize("name", sorted(all_schemas()))
def test_schema_is_valid(name):
    Draft202012Validator.check_schema(all_schemas()[name])


def test_every_entity_has_schema():
    assert {f"{e}.schema.json" for e in ENTITIES} <= set(all_schemas())
    assert load("schema/sync.schema.json")["$defs"]["change"]["properties"]["entity"]["enum"] == (
        ENTITIES
    )


def test_ids_namespace_derivation():
    assert ids_namespace() == uuid.uuid5(uuid.NAMESPACE_URL, "urn:sdvg-tracker:ids")


@pytest.mark.parametrize("case", load("vectors/ids.json")["cases"], ids=lambda c: c["name"])
def test_ids_vectors(case):
    assert str(uuid.uuid5(ids_namespace(), case["name"])) == case["expect"]


def test_hlc_ordering_is_string_ordering():
    ordering = load("vectors/hlc.json")["ordering"]
    assert ordering == sorted(ordering)
    hlc = validator({"$ref": "common.schema.json#/$defs/hlc"})
    for value in ordering:
        hlc.validate(value)


SYNC_CASES = [
    pytest.param(case, id=f"{path.stem}: {case['name']}")
    for path in sorted((SHARED / "sync-fixtures").glob("*.json"))
    for case in json.loads(path.read_text())["cases"]
]


@pytest.mark.parametrize("case", SYNC_CASES)
def test_sync_fixture_conforms(case):
    change = sync_def("change")
    for row in case["initial"] + case["changes"] + case["expected"]:
        change.validate(row)
        assert row["fields"].keys() == row["clocks"].keys()
    for row in case["initial"] + case["expected"]:
        row_validator(row["entity"], partial=False).validate(row["fields"])
    for row in case["changes"]:
        row_validator(row["entity"], partial=True).validate(row["fields"])
    for row in case["expected"]:
        if (want := expected_id(row["entity"], row["fields"])) is not None:
            assert row["id"] == want
    keys = [(r["entity"], r["id"]) for r in case["expected"]]
    assert keys == sorted(keys)


@pytest.mark.parametrize(
    "path", sorted((SHARED / "domain-fixtures").glob("*.json")), ids=lambda p: p.stem
)
def test_domain_fixture_shape(path):
    data = json.loads(path.read_text())
    assert data["description"]
    assert data["cases"]
    for case in data["cases"]:
        assert set(case) == {"name", "input", "expect"}


def test_auto_rollover_move_ids():
    for case in load("domain-fixtures/auto_rollover.json")["cases"]:
        for move in case["expect"]["new_moves"]:
            assert move["id"] == expected_id("task_move", move)
            row_validator("task_move", partial=False).validate(
                {k: v for k, v in move.items() if k != "id"}
            )
