"""A minimal in-memory client implementing the sync protocol from shared/README.md."""

import copy
from typing import Any

from fastapi.testclient import TestClient

from app.sync.hlc import Clock
from app.sync.merge import merge_fields
from tests.conftest import AUTH


class FakeTime:
    def __init__(self, ms: int):
        self.ms = ms

    def __call__(self) -> int:
        return self.ms

    def advance(self, ms: int) -> None:
        self.ms += ms


class SimClient:
    def __init__(self, node_id: str, time: FakeTime, limit: int = 1000):
        self.clock = Clock(node_id, now_ms=time)
        self.rows: dict[tuple[str, str], dict[str, dict]] = {}
        self.outbox: list[dict] = []
        self.cursor = 0
        self.server_id: str | None = None
        self.limit = limit

    def write(self, entity: str, id_: str, **fields: Any) -> None:
        clock = self.clock.now()
        change = {
            "entity": entity,
            "id": id_,
            "fields": fields,
            "clocks": dict.fromkeys(fields, clock),
        }
        self._merge(change)
        self.outbox.append(change)

    def get(self, entity: str, id_: str) -> dict:
        return self.rows[(entity, id_)]["fields"]

    def count(self, entity: str, **where: Any) -> int:
        return sum(
            1
            for (e, _), row in self.rows.items()
            if e == entity and all(row["fields"].get(k) == v for k, v in where.items())
        )

    def state(self) -> dict:
        return copy.deepcopy(self.rows)

    def sync(self, http: TestClient) -> None:
        while True:
            pushed = len(self.outbox)
            resp = http.post(
                "/api/sync",
                json={"cursor": self.cursor, "changes": self.outbox[:pushed], "limit": self.limit},
                headers=AUTH,
            )
            resp.raise_for_status()
            body = resp.json()
            del self.outbox[:pushed]

            if self.server_id is not None and body["server_id"] != self.server_id:
                # New server database: start over and hand it everything we have.
                self.server_id = body["server_id"]
                self.cursor = 0
                self.outbox = [
                    {"entity": e, "id": i, **copy.deepcopy(row)}
                    for (e, i), row in self.rows.items()
                ]
                continue
            self.server_id = body["server_id"]

            for change in body["changes"]:
                self.clock.receive(max(change["clocks"].values()))
                self._merge(change)
            self.cursor = body["cursor"]
            if not body["has_more"] and not self.outbox:
                return

    def _merge(self, change: dict) -> None:
        row = self.rows.setdefault((change["entity"], change["id"]), {"fields": {}, "clocks": {}})
        merge_fields(row["fields"], row["clocks"], change["fields"], change["clocks"])
