"""Hybrid logical clock, see shared/README.md. Timestamps compare as plain strings."""

import re
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass

MAX_COUNTER = 9999
NODE_ID_RE = re.compile(r"^[0-9a-f]{16}$")
HLC_RE = re.compile(r"^(\d{13})-(\d{4})-([0-9a-f]{16})$")


def wall_ms() -> int:
    return time.time_ns() // 1_000_000


@dataclass(frozen=True, order=True)
class Timestamp:
    ms: int
    counter: int
    node_id: str

    @classmethod
    def parse(cls, value: str) -> "Timestamp":
        m = HLC_RE.match(value)
        if not m:
            raise ValueError(f"Invalid HLC timestamp: {value!r}")
        return cls(int(m[1]), int(m[2]), m[3])

    def __str__(self) -> str:
        return f"{self.ms:013d}-{self.counter:04d}-{self.node_id}"


class Clock:
    def __init__(
        self, node_id: str, now_ms: Callable[[], int] = wall_ms, ms: int = 0, counter: int = 0
    ):
        if not NODE_ID_RE.match(node_id):
            raise ValueError(f"Invalid node id: {node_id!r}")
        self.node_id = node_id
        self._now_ms = now_ms
        self._ms = ms
        self._counter = counter
        self._lock = threading.Lock()

    def now(self) -> str:
        """Timestamp for a local event."""
        with self._lock:
            pt = self._now_ms()
            if pt > self._ms:
                self._ms, self._counter = pt, 0
            else:
                self._counter += 1
            return self._emit()

    def receive(self, remote: str) -> str:
        """Advance past a timestamp received from another node."""
        r = Timestamp.parse(remote)
        with self._lock:
            pt = self._now_ms()
            ms = max(self._ms, r.ms, pt)
            if ms == self._ms and ms == r.ms:
                counter = max(self._counter, r.counter) + 1
            elif ms == self._ms:
                counter = self._counter + 1
            elif ms == r.ms:
                counter = r.counter + 1
            else:
                counter = 0
            self._ms, self._counter = ms, counter
            return self._emit()

    def _emit(self) -> str:
        if self._counter > MAX_COUNTER:
            self._ms, self._counter = self._ms + 1, 0
        return str(Timestamp(self._ms, self._counter, self.node_id))
