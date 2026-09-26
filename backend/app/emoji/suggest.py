"""Emoji for a task title: the nearest descriptions in multilingual-e5-small's vector space.

Every emoji has a description from Unicode CLDR (catalog.tsv: name and keywords) and may
have task phrases (aliases.txt). An emoji scores as its closest description: a title only
has to match one of them.
"""

import hashlib
import logging
import threading
import time
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from app.emoji.encoder import MODEL_FILE, Encoder

HERE = Path(__file__).parent
# e5 expects a role prefix. Titles and descriptions are both short phrases, so both are
# "query" (symmetric matching): it beat "query"/"passage" on the task sets.
PREFIX = "query: "
# Bump when the vectors of the same texts would change (prefix, pooling, model).
INDEX_VERSION = 1

# uvicorn's logger: the one that reaches the container log.
log = logging.getLogger("uvicorn.error")


@dataclass(frozen=True)
class Suggestion:
    emoji: str
    score: float


def load_descriptions() -> tuple[list[str], list[int], list[str]]:
    """Emoji in catalog order, and every description as (emoji index, text), grouped by emoji."""
    emoji: list[str] = []
    texts: dict[int, list[str]] = {}
    for line in (HERE / "catalog.tsv").read_text().splitlines():
        if line and not line.startswith("#"):
            char, name, keywords = line.split("\t")
            texts[len(emoji)] = [f"{name}: {', '.join(keywords.split(' | '))}"]
            emoji.append(char)
    index = {char: i for i, char in enumerate(emoji)}
    for line in (HERE / "aliases.txt").read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            char, phrases = line.split(" ", 1)
            if char not in index:
                raise ValueError(f"aliases.txt: {char} is not in catalog.tsv")
            texts[index[char]] += [p.strip() for p in phrases.split(";") if p.strip()]
    owners = [i for i in range(len(emoji)) for _ in texts[i]]
    return emoji, owners, [t for i in range(len(emoji)) for t in texts[i]]


class EmojiSuggester:
    """Loads the model and the description vectors in the background; `ready` says when done.

    Encoding the ~1900 descriptions takes tens of seconds on one core, so their vectors are
    cached in `cache_dir` between restarts.
    """

    def __init__(self, model_dir: Path, cache_dir: Path, threads: int = 1):
        self.model_dir = model_dir
        self.cache_dir = cache_dir
        self.threads = threads
        self.ready = False
        self.failed = False

    def start(self) -> None:
        threading.Thread(target=self.load, name="emoji-load", daemon=True).start()

    def load(self) -> None:
        try:
            started = time.monotonic()
            encoder = Encoder(self.model_dir, self.threads)
            emoji, owners, texts = load_descriptions()
            vectors = self._load_vectors(encoder, texts)
            self._encoder, self._emoji, self._vectors = encoder, emoji, vectors
            # Descriptions are grouped by emoji: where each emoji's run starts, for reduceat.
            self._starts = np.searchsorted(owners, np.arange(len(emoji)))
            self.ready = True
            log.info("Emoji suggestions ready in %.1f s", time.monotonic() - started)
        except Exception:
            self.failed = True
            log.exception("Emoji suggestions failed to load from %s", self.model_dir)

    def suggest(self, text: str, limit: int) -> list[Suggestion]:
        query = self._encoder.encode([PREFIX + text])[0]
        scores = np.maximum.reduceat(self._vectors @ query, self._starts)
        best = np.argsort(-scores, kind="stable")[:limit]
        return [Suggestion(self._emoji[i], round(float(scores[i]), 4)) for i in best]

    def _load_vectors(self, encoder: Encoder, texts: list[str]) -> np.ndarray:
        key = hashlib.sha256(
            "\n".join(
                [str(INDEX_VERSION), PREFIX, str((self.model_dir / MODEL_FILE).stat().st_size)]
                + texts
            ).encode()
        ).hexdigest()[:16]
        path = self.cache_dir / f"emoji-vectors-{key}.npy"
        try:
            vectors = np.load(path)
            if vectors.shape[0] == len(texts):
                return vectors
        except (OSError, ValueError):
            pass  # not cached yet, or unreadable: encode again
        vectors = encoder.encode([PREFIX + t for t in texts])
        try:
            tmp = path.with_suffix(".tmp")
            with tmp.open("wb") as f:
                np.save(f, vectors)
            tmp.replace(path)
            for old in self.cache_dir.glob("emoji-vectors-*.npy"):
                if old != path:
                    old.unlink()
        except OSError as e:
            log.warning("Emoji vectors not cached: %s", e)
        return vectors
