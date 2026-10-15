#!/usr/bin/python3
"""Build the disk-space hint shown before entering the capture duration."""

import os
from pathlib import Path
import shutil
import sys


GIB = 1024 ** 3
RESERVE = 10 * GIB
FALLBACK_PHOTO_BYTES = 1_000_000


def recent_photo_sizes(root: Path) -> list[int]:
    if not root.is_dir():
        return []
    sessions = sorted(
        (path for path in root.iterdir() if path.is_dir()),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    for session in sessions:
        photos = sorted(session.glob("IMG-*.jpg"))[-200:]
        sizes = [photo.stat().st_size for photo in photos if photo.is_file() and photo.stat().st_size > 0]
        if sizes:
            return sizes
    return []


def main() -> None:
    interval_text = sys.argv[1]
    interval = float(interval_text)
    root = Path(os.environ.get("CAMERA_OUTPUT_ROOT", Path.home() / "Pictures" / "每秒拍照")).expanduser()
    disk_path = root
    while not disk_path.exists():
        disk_path = disk_path.parent
    free_bytes = shutil.disk_usage(disk_path).free
    probe_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else None
    probe = [p.stat().st_size for p in probe_dir.glob("*.jpg") if p.stat().st_size > 0] if probe_dir and probe_dir.is_dir() else []
    history = recent_photo_sizes(root)
    # The current camera is measured first. A 50% margin covers changing JPEG detail.
    reference = max(probe) if probe else (max(history) if history else FALLBACK_PHOTO_BYTES)
    photo_bytes = int(reference * 1.5)
    available_for_photos = max(0, free_bytes - RESERVE)
    max_photos = available_for_photos // photo_bytes
    max_minutes = int(max_photos * interval // 60)
    hours, minutes = divmod(max_minutes, 60)
    duration = f"{hours} 小时 {minutes} 分钟" if max_minutes else "不足 1 分钟"
    source = "当前摄像头试拍" if probe else ("最近照片" if history else "默认值")

    print(
        "总拍照时长（分钟）：\n"
        f"磁盘剩余 {free_bytes / GIB:.1f} GiB；预留 10 GiB。\n"
        f"按{source} {reference / 1_000_000:.2f} MB/张，加入 50% 波动余量，\n"
        f"每 {interval_text} 秒 1 张估算，"
        f"最长约 {duration}（约 {max_photos:,} 张）。\n"
        "仅为当前磁盘容量估算；其他程序写入磁盘或场景变化会缩短时长。"
    )


if __name__ == "__main__":
    main()
