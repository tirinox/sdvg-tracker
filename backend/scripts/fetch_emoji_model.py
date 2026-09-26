"""Download the emoji suggestion model: multilingual-e5-small (MIT), int8 ONNX, ~120 MB.

    python scripts/fetch_emoji_model.py DIR

Standard library only: the Docker build runs it before the app's dependencies are copied.
Files are pinned by revision and checked by SHA-256; ones already in DIR are kept.
"""

import hashlib
import sys
import urllib.request
from pathlib import Path

REPO = "Xenova/multilingual-e5-small"
REVISION = "761b726dd34fb83930e26aab4e9ac3899aa1fa78"
FILES = {
    "onnx/model_quantized.onnx": "f80102d3f2a1229f387d3c81909990d8945513e347b0eab049f7de3c6f98c193",
    "sentencepiece.bpe.model": "cfc8146abe2a0488e9e2a0c56de7952f7c11ab059eca145a0a727afce0db2865",
}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


def fetch(target: Path) -> None:
    target.mkdir(parents=True, exist_ok=True)
    for name, digest in FILES.items():
        path = target / Path(name).name
        if path.exists() and sha256(path) == digest:
            continue
        url = f"https://huggingface.co/{REPO}/resolve/{REVISION}/{name}"
        print(f"Downloading {url}")
        tmp = path.with_suffix(".part")
        with urllib.request.urlopen(url, timeout=60) as resp, tmp.open("wb") as out:
            while chunk := resp.read(1 << 20):
                out.write(chunk)
        if (got := sha256(tmp)) != digest:
            tmp.unlink()
            sys.exit(f"{name}: SHA-256 {got}, expected {digest}")
        tmp.replace(path)
    print(f"Model in {target}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    fetch(Path(sys.argv[1]))
