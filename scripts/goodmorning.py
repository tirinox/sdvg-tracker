"""Morning videos: names every new .mp4 in video/ goodmorning-NNN.mp4 (next free numbers, oldest
first) and writes video/index.json, which the iOS app picks a random video from.

    python3 scripts/goodmorning.py [video]
"""

import json
import re
import sys
from pathlib import Path

NAME = re.compile(r"goodmorning-(\d{3,})\.mp4")


def main(folder: Path) -> None:
    files = [p for p in folder.iterdir() if p.is_file() and p.suffix.lower() == ".mp4"]
    taken = [int(m[1]) for p in files if (m := NAME.fullmatch(p.name))]
    number = max(taken, default=0)
    for p in sorted((p for p in files if not NAME.fullmatch(p.name)), key=lambda p: p.stat().st_mtime):
        number += 1
        target = folder / f"goodmorning-{number:03d}.mp4"
        p.rename(target)
        print(f"{p.name} -> {target.name}")

    videos = sorted(p for p in folder.iterdir() if NAME.fullmatch(p.name))
    index = {"videos": [{"file": p.name, "size": p.stat().st_size} for p in videos]}
    (folder / "index.json").write_text(json.dumps(index, indent=2) + "\n")
    print(f"index.json: {len(videos)} videos")


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "video"))
