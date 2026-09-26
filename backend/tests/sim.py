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


class ServerChanged(Exception):
    """The server holds another data set; the client paused and waits for a decision."""

    def __init__(self, info: dict):
        super().__init__(info["server_id"])
        self.info = info


class SimClient:
    def __init__(self, node_id: str, time: FakeTime, limit: int = 1000):
        self.clock = Clock(node_id, now_ms=time)
        self.rows: dict[tuple[str, str], dict[str, dict]] = {}
        self.outbox: list[dict] = []
        self.cursor = 0
        self.server_id: str | None = None
        self.epoch: str | None = None
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
            request = {"cursor": self.cursor, "changes": self.outbox[:pushed], "limit": self.limit}
            if self.server_id is not None:
                request |= {"server_id": self.server_id, "epoch": self.epoch}
            resp = http.post("/api/sync", json=request, headers=AUTH)
            if resp.status_code == 409:
                raise ServerChanged(resp.json()["detail"])
            resp.raise_for_status()
            body = resp.json()
            del self.outbox[:pushed]

            for change in body["changes"]:
                self.clock.receive(max(change["clocks"].values()))
                self._merge(change)
            if body["rewind"]:
                # The server was restored from a backup: hand it back everything we have.
                self.outbox = self._all_rows()
            self.server_id, self.epoch = body["server_id"], body["epoch"]
            self.cursor = body["cursor"]
            if not body["has_more"] and not self.outbox:
                return

    def take_server_data(self) -> None:
        """Answer to ServerChanged: drop the local data and download the server's."""
        self.rows.clear()
        self.outbox.clear()
        self.cursor, self.server_id, self.epoch = 0, None, None

    def merge_into(self, server_id: str) -> None:
        """Answer to ServerChanged: push every local row into the new data set."""
        self.outbox = self._all_rows()
        self.cursor, self.server_id, self.epoch = 0, server_id, None

    def _all_rows(self) -> list[dict]:
        return [{"entity": e, "id": i, **copy.deepcopy(row)} for (e, i), row in self.rows.items()]

    def _merge(self, change: dict) -> None:
        row = self.rows.setdefault((change["entity"], change["id"]), {"fields": {}, "clocks": {}})
        merge_fields(row["fields"], row["clocks"], change["fields"], change["clocks"])
