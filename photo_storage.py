#!/usr/bin/env python3
"""Read and update the user's preferred photo folder."""

import json
import os
from pathlib import Path
import sys
import tempfile


SETTINGS = Path(os.environ.get(
    "CAMERA_PHOTO_SETTINGS",
    Path.home() / "Library" / "Application Support" / "每秒拍照" / "photo_settings.json",
))
FALLBACK = Path.home() / "Pictures" / "每秒拍照"


def current_folder() -> Path:
    if SETTINGS.is_file():
        try:
            saved = json.loads(SETTINGS.read_text(encoding="utf-8"))["default_folder"]
            if isinstance(saved, str) and saved.startswith("/"):
                return Path(saved).expanduser()
        except (OSError, ValueError, KeyError, TypeError):
            pass
    return FALLBACK


def validate(folder: Path) -> Path:
    folder = folder.expanduser().resolve(strict=True)
    if not folder.is_dir():
        raise ValueError("所选位置不是文件夹")
    # Actually writing catches permission and offline-volume failures that
    # os.access() can miss. Remove the probe immediately.
    fd, probe = tempfile.mkstemp(prefix=".camera-write-test-", dir=folder)
    os.close(fd)
    Path(probe).unlink()
    return folder


def main() -> None:
    action = sys.argv[1]
    if action == "get":
        print(current_folder())
    elif action in {"check", "set"}:
        folder = validate(Path(sys.argv[2]))
        if action == "set":
            SETTINGS.parent.mkdir(parents=True, exist_ok=True)
            fd, staged = tempfile.mkstemp(prefix=".photo-settings-", dir=SETTINGS.parent)
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as stream:
                    json.dump({"default_folder": str(folder)}, stream, ensure_ascii=False)
                    stream.write("\n")
                os.chmod(staged, 0o600)
                os.replace(staged, SETTINGS)
            finally:
                if os.path.exists(staged):
                    os.unlink(staged)
        print(folder)
    else:
        raise ValueError(f"未知操作：{action}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, IndexError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
