"""Database maintenance, run next to the live server (make reset-db, make restore).

    python -m app.admin reset            empty the database under a new server_id
    python -m app.admin restore < file   replace the database with a backup, under a new epoch

A reset is a new data set: clients that knew the old one stop and ask before merging into it.
A restore keeps the data set's server_id, and the new epoch tells clients to push back what
the backup is missing.
"""

import os
import sqlite3
import sys
import uuid


def reset(path: str) -> str:
    server_id = str(uuid.uuid4())
    conn = sqlite3.connect(path, isolation_level=None)
    try:
        conn.execute("BEGIN IMMEDIATE")
        conn.execute("DELETE FROM records")
        _set(conn, "server_id", server_id)
        _set(conn, "epoch", str(uuid.uuid4()))
        conn.execute("COMMIT")
    finally:
        conn.close()
    return server_id


def restore(path: str, backup: bytes) -> str:
    image = bytearray(backup)
    if image[:16] != b"SQLite format 3\0":
        raise ValueError("not an SQLite database (gunzip the backup first)")
    # A copy of a WAL database says so in its header, and an in-memory one can't be written
    # in WAL mode: mark it as a rollback-journal file (header bytes 18-19).
    image[18:20] = b"\x01\x01"
    src = sqlite3.connect(":memory:")
    try:
        src.deserialize(bytes(image))
        _set(src, "epoch", str(uuid.uuid4()))
        src.commit()
        server_id = src.execute("SELECT value FROM meta WHERE key = 'server_id'").fetchone()[0]
        dst = sqlite3.connect(path)
        try:
            src.backup(dst)
        finally:
            dst.close()
    finally:
        src.close()
    return server_id


def _set(conn: sqlite3.Connection, key: str, value: str) -> None:
    conn.execute("INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", (key, value))


def main(argv: list[str]) -> None:
    path = os.environ["DATABASE_PATH"]
    match argv:
        case ["reset"]:
            print(f"Database emptied, new server_id {reset(path)}")
        case ["restore"]:
            print(f"Backup restored, server_id {restore(path, sys.stdin.buffer.read())}")
        case _:
            sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
