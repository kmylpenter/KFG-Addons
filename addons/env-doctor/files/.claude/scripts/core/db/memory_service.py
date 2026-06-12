"""SQLite memory service (async, aiosqlite).

Reconstructed 2026-06-12 for the PRoot/Android environment: the original
memory_service.py never made it to this device, which broke store_learning.py
(sqlite backend). Schema matches what recall_learnings.py::search_learnings_sqlite
reads: archival_memory + archival_fts (FTS5, content-synced) at
~/.claude/cache/memory.db.

Embeddings are accepted but NOT stored — this device has no vector stack;
recall here is FTS5/BM25 text search. search_vector() does exact-content
dedup only (returns similarity 1.0 on identical content, else []).
"""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import aiosqlite

DEFAULT_DB_PATH = Path.home() / ".claude" / "cache" / "memory.db"

SCHEMA = """
CREATE TABLE IF NOT EXISTS archival_memory (
    id TEXT PRIMARY KEY,
    session_id TEXT,
    content TEXT NOT NULL,
    metadata_json TEXT,
    created_at REAL
);
CREATE VIRTUAL TABLE IF NOT EXISTS archival_fts USING fts5(
    content,
    content='archival_memory',
    content_rowid='rowid'
);
CREATE TRIGGER IF NOT EXISTS archival_ai AFTER INSERT ON archival_memory BEGIN
    INSERT INTO archival_fts(rowid, content) VALUES (new.rowid, new.content);
END;
CREATE TRIGGER IF NOT EXISTS archival_ad AFTER DELETE ON archival_memory BEGIN
    INSERT INTO archival_fts(archival_fts, rowid, content)
    VALUES ('delete', old.rowid, old.content);
END;
CREATE TRIGGER IF NOT EXISTS archival_au AFTER UPDATE ON archival_memory BEGIN
    INSERT INTO archival_fts(archival_fts, rowid, content)
    VALUES ('delete', old.rowid, old.content);
    INSERT INTO archival_fts(rowid, content) VALUES (new.rowid, new.content);
END;
CREATE TABLE IF NOT EXISTS core_memory (
    session_id TEXT,
    key TEXT,
    value TEXT,
    PRIMARY KEY (session_id, key)
);
"""


class MemoryService:
    """Minimal sqlite implementation of the MemoryBackend protocol."""

    def __init__(self, session_id: str = "default", db_path: str | Path | None = None):
        self.session_id = session_id
        self.db_path = Path(db_path) if db_path else DEFAULT_DB_PATH
        self._db: aiosqlite.Connection | None = None

    async def connect(self) -> None:
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._db = await aiosqlite.connect(str(self.db_path))
        self._db.row_factory = aiosqlite.Row
        await self._db.executescript(SCHEMA)
        await self._db.commit()

    async def close(self) -> None:
        if self._db is not None:
            await self._db.close()
            self._db = None

    # --- archival memory ---

    async def store(
        self,
        content: str,
        metadata: dict[str, Any] | None = None,
        embedding: list[float] | None = None,
    ) -> str:
        memory_id = str(uuid.uuid4())
        await self._db.execute(
            "INSERT INTO archival_memory (id, session_id, content, metadata_json, created_at)"
            " VALUES (?, ?, ?, ?, ?)",
            (
                memory_id,
                self.session_id,
                content,
                json.dumps(metadata or {}, ensure_ascii=False),
                # reader contract: recall_learnings.py does datetime.fromtimestamp(created_at)
                datetime.now(timezone.utc).timestamp(),
            ),
        )
        await self._db.commit()
        return memory_id

    async def search(self, query: str, limit: int = 10) -> list[dict[str, Any]]:
        import re

        words = re.findall(r"\w+", query.lower())
        fts_query = " OR ".join(words) if words else query
        cursor = await self._db.execute(
            """
            SELECT a.id, a.session_id, a.content, a.metadata_json, a.created_at,
                   bm25(archival_fts) AS rank
            FROM archival_memory a
            JOIN archival_fts f ON a.rowid = f.rowid
            WHERE archival_fts MATCH ?
            ORDER BY rank LIMIT ?
            """,
            (fts_query, limit),
        )
        rows = await cursor.fetchall()
        results = []
        for row in rows:
            try:
                metadata = json.loads(row["metadata_json"] or "{}")
            except json.JSONDecodeError:
                metadata = {}
            results.append(
                {
                    "id": row["id"],
                    "session_id": row["session_id"],
                    "content": row["content"],
                    "metadata": metadata,
                    "created_at": row["created_at"],
                    "score": min(1.0, max(0.0, -(row["rank"] or 0) / 25.0)),
                }
            )
        return results

    async def search_vector(
        self, embedding: list[float], limit: int = 1, content: str | None = None
    ) -> list[dict[str, Any]]:
        # No vector index on this device; only exact-content dedup is possible.
        if not content:
            return []
        cursor = await self._db.execute(
            "SELECT id FROM archival_memory WHERE content = ? LIMIT ?",
            (content, limit),
        )
        rows = await cursor.fetchall()
        return [{"id": row["id"], "similarity": 1.0} for row in rows]

    async def recall(self, limit: int = 10) -> list[dict[str, Any]]:
        cursor = await self._db.execute(
            "SELECT id, session_id, content, metadata_json, created_at"
            " FROM archival_memory ORDER BY created_at DESC LIMIT ?",
            (limit,),
        )
        rows = await cursor.fetchall()
        return [dict(row) for row in rows]

    async def delete_archival(self, memory_id: str) -> None:
        await self._db.execute("DELETE FROM archival_memory WHERE id = ?", (memory_id,))
        await self._db.commit()

    async def to_context(self, max_archival: int = 10) -> str:
        rows = await self.recall(limit=max_archival)
        return "\n".join(f"- {r['content']}" for r in rows)

    # --- core memory (key/value per session) ---

    async def set_core(self, key: str, value: str) -> None:
        await self._db.execute(
            "INSERT OR REPLACE INTO core_memory (session_id, key, value) VALUES (?, ?, ?)",
            (self.session_id, key, value),
        )
        await self._db.commit()

    async def get_core(self, key: str) -> str | None:
        cursor = await self._db.execute(
            "SELECT value FROM core_memory WHERE session_id = ? AND key = ?",
            (self.session_id, key),
        )
        row = await cursor.fetchone()
        return row["value"] if row else None

    async def list_core_keys(self) -> list[str]:
        cursor = await self._db.execute(
            "SELECT key FROM core_memory WHERE session_id = ?", (self.session_id,)
        )
        return [row["key"] for row in await cursor.fetchall()]

    async def delete_core(self, key: str) -> None:
        await self._db.execute(
            "DELETE FROM core_memory WHERE session_id = ? AND key = ?",
            (self.session_id, key),
        )
        await self._db.commit()

    async def get_all_core(self) -> dict[str, str]:
        cursor = await self._db.execute(
            "SELECT key, value FROM core_memory WHERE session_id = ?",
            (self.session_id,),
        )
        return {row["key"]: row["value"] for row in await cursor.fetchall()}
