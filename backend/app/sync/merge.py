"""Field-level last-writer-wins merge, see shared/README.md."""

from typing import Any


def merge_fields(
    fields: dict[str, Any],
    clocks: dict[str, str],
    change_fields: dict[str, Any],
    change_clocks: dict[str, str],
) -> bool:
    """Apply a change to a row in place. Returns True if any field was updated."""
    changed = False
    for name, value in change_fields.items():
        clock = change_clocks[name]
        current = clocks.get(name)
        if current is None or clock > current:
            fields[name] = value
            clocks[name] = clock
            changed = True
    return changed
