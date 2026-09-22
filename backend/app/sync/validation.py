"""Validates pushed changes against the shared JSON Schemas (single source of truth)."""

import json
import uuid
from collections.abc import Callable
from pathlib import Path

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

from app.sync.hlc import HLC_RE, Timestamp, wall_ms
from app.sync.schemas import Change

SETTINGS_ID = "settings"
IDS_NAMESPACE = uuid.uuid5(uuid.NAMESPACE_URL, "urn:sdvg-tracker:ids")

# Deterministic ids: entity -> fields that make up the uuidv5 name.
DETERMINISTIC_IDS = {
    "routine_check": ("routine_id", "date"),
    "task_move": ("task_id", "from_date"),
}


def deterministic_id(entity: str, *parts: str) -> str:
    return str(uuid.uuid5(IDS_NAMESPACE, ":".join((entity, *parts))))


class ChangeError(ValueError):
    pass


def _is_canonical_uuid(value: str) -> bool:
    try:
        return str(uuid.UUID(value)) == value
    except ValueError:
        return False


class ChangeValidator:
    def __init__(
        self,
        schema_dir: Path,
        max_future_skew_ms: int,
        now_ms: Callable[[], int] = wall_ms,
    ):
        schemas = {p.name: json.loads(p.read_text()) for p in schema_dir.glob("*.schema.json")}
        registry = Registry().with_resources(
            (name, Resource.from_contents(s)) for name, s in schemas.items()
        )
        entities = schemas["sync.schema.json"]["$defs"]["change"]["properties"]["entity"]["enum"]
        self._fields: dict[str, dict[str, Draft202012Validator]] = {
            entity: {
                prop: Draft202012Validator(
                    {"$ref": f"{entity}.schema.json#/properties/{prop}"}, registry=registry
                )
                for prop in schemas[f"{entity}.schema.json"]["properties"]
            }
            for entity in entities
        }
        self._max_future_skew_ms = max_future_skew_ms
        self._now_ms = now_ms

    def validate(self, change: Change) -> None:
        self._validate_id(change)
        if change.fields.keys() != change.clocks.keys():
            raise ChangeError("fields and clocks must have the same keys")
        props = self._fields[change.entity]
        limit = self._now_ms() + self._max_future_skew_ms
        for name, value in change.fields.items():
            if name not in props:
                raise ChangeError(f"unknown field {change.entity}.{name}")
            error = next(props[name].iter_errors(value), None)
            if error is not None:
                raise ChangeError(f"{change.entity}.{name}: {error.message}")
            clock = change.clocks[name]
            if not HLC_RE.match(clock):
                raise ChangeError(f"{change.entity}.{name}: invalid clock {clock!r}")
            if Timestamp.parse(clock).ms > limit:
                raise ChangeError(f"{change.entity}.{name}: clock is too far in the future")
        self._validate_deterministic_id(change)

    def _validate_id(self, change: Change) -> None:
        if change.entity == "settings":
            if change.id != SETTINGS_ID:
                raise ChangeError(f"settings id must be {SETTINGS_ID!r}")
        elif not _is_canonical_uuid(change.id):
            raise ChangeError(f"id must be a lowercase canonical UUID: {change.id!r}")

    def _validate_deterministic_id(self, change: Change) -> None:
        keys = DETERMINISTIC_IDS.get(change.entity)
        if keys is None or not all(k in change.fields for k in keys):
            return
        expected = deterministic_id(change.entity, *(change.fields[k] for k in keys))
        if change.id != expected:
            raise ChangeError(f"{change.entity} id must be {expected} for these fields")
