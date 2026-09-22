"""Wire models for /api/sync. Field-level validation lives in validation.py."""

from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

EntityName = Literal["task", "task_move", "routine", "routine_version", "routine_check", "settings"]

MAX_CHANGES = 5000


class Change(BaseModel):
    model_config = ConfigDict(extra="forbid")

    entity: EntityName
    id: str
    fields: dict[str, Any] = Field(min_length=1)
    clocks: dict[str, str] = Field(min_length=1)


class SyncRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    cursor: int = Field(ge=0)
    changes: list[Change] = Field(max_length=MAX_CHANGES)
    limit: int = Field(default=1000, ge=1, le=MAX_CHANGES)


class SyncResponse(BaseModel):
    server_id: str
    cursor: int
    changes: list[Change]
    has_more: bool
