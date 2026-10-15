#!/usr/bin/env python3
"""Watch finished photos, OCR a selected rectangle, and email on a match."""

import argparse
import csv
from dataclasses import dataclass
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import time


NUMBER = re.compile(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)\Z")


def parse_number(text):
    text = text.strip()
    if not NUMBER.fullmatch(text):
        raise ValueError("请输入数字；小数使用英文句点，例如 -12.5")
    value = float(text)
    if not math.isfinite(value):
        raise ValueError("数值不能为无穷大")
    return value


@dataclass(frozen=True)
class Condition:
    mode: str
    values: tuple

    def match_key(self, value):
        if self.mode == "range":
            return "range" if self.values[0] <= value <= self.values[1] else None
        return next((target for target in self.values if value == target), None)

    def describe(self):
        if self.mode == "range":
            return f"[{self.values[0]:g}, {self.values[1]:g}]（含边界）"
        return "、".join(f"{target:g}" for target in self.values)


def parse_condition(text):
    text = text.strip().replace("−", "-").replace("＋", "+").replace("．", ".").replace("～", "~")
    if not text:
        raise ValueError("提醒条件不能为空")
    if "~" in text:
        parts = text.split("~")
        if len(parts) != 2:
            raise ValueError("范围请写成 10~20")
        low, high = (parse_number(part) for part in parts)
        if low > high:
            raise ValueError("范围下限不能大于上限")
        return Condition("range", (low, high))
    parts = re.split(r"[,，、;；]", text)
    if len(parts) > 100:
        raise ValueError("指定数值不能超过 100 个")
    values = tuple(dict.fromkeys(parse_number(part) for part in parts))
    return Condition("values", values)


def validate_region(text):
    try:
        x, y, width, height = (float(part) for part in text.split(","))
    except ValueError as exc:
        raise ValueError("识别区域格式错误") from exc
    if not all(math.isfinite(v) for v in (x, y, width, height)) or not (
        0 <= x < 1 and 0 <= y < 1 and width > 0 and height > 0
        and x + width <= 1.000002 and y + height <= 1.000002
    ):
        raise ValueError("识别区域超出照片范围")


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--check-condition":
        try:
            parse_condition(sys.argv[2])
        except ValueError as exc:
            print(exc, file=sys.stderr)
            return 1
        return 0
    parser = argparse.ArgumentParser()
    parser.add_argument("session", type=Path)
    parser.add_argument("region")
    parser.add_argument("condition")
    parser.add_argument("mail_settings", type=Path)
    parser.add_argument("parent_pid", type=int)
    parser.add_argument("ocr_helper")
    parser.add_argument("mail_tool")
    parser.add_argument("secret_tool")
    args = parser.parse_args()
    condition = parse_condition(args.condition)
    validate_region(args.region)
    log_path = args.session / "recognition.csv"
    error_path = args.session / "monitor.log"
    seq = 1
    candidate_key = None
    candidate_count = 0
    out_count = 0
    active_key = None
    retry_after = 0.0

    with log_path.open("w", newline="", encoding="utf-8") as log, error_path.open(
        "a", encoding="utf-8"
    ) as errors:
        writer = csv.writer(log)
        writer.writerow(["time", "photo", "value", "confidence", "state"])
        log.flush()
        while True:
            photo = args.session / f"IMG-{seq:05d}.jpg"
            if not photo.is_file():
                if (args.session / ".capture_finished").exists() or not alive(args.parent_pid):
                    break
                time.sleep(0.25)
                continue
            stamp = time.strftime("%Y-%m-%d %H:%M:%S")
            value = None
            confidence = ""
            state = "unreadable"
            try:
                result = subprocess.run(
                    [args.ocr_helper, str(photo), args.region],
                    capture_output=True, text=True, timeout=15, check=False,
                )
                if result.returncode == 0:
                    value_text, confidence = result.stdout.strip().split("\t", 1)
                    value = float(value_text)
                    if not math.isfinite(value):
                        value = None
                elif result.returncode != 2:
                    errors.write(f"{stamp} OCR error on {photo.name}: {result.stderr}\n")
                    errors.flush()
            except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
                errors.write(f"{stamp} OCR error on {photo.name}: {exc}\n")
                errors.flush()

            key = condition.match_key(value) if value is not None else None
            if key is None:
                candidate_key = None
                candidate_count = 0
                if value is None:
                    out_count = 0
                else:
                    out_count += 1
                    state = "outside"
                    if out_count >= 2 and active_key is not None:
                        active_key = None
                        state = "rearmed"
            else:
                out_count = 0
                state = "inside"
                if key == candidate_key:
                    candidate_count += 1
                else:
                    candidate_key = key
                    candidate_count = 1

            if key is not None and candidate_count >= 2 and key != active_key and time.monotonic() >= retry_after:
                state = "alert"
                subject = f"仪器读数提醒：{value:g} 命中条件"
                body = (
                    f"时间：{stamp}\n读数：{value:g}\n"
                    f"提醒条件：{condition.describe()}\n"
                    "识别区域：启动时圈选的方框\n"
                    f"照片：{photo.name}\n"
                    "已连续两张照片识别到同一提醒条件。"
                )
                try:
                    sent = subprocess.run(
                        [sys.executable, args.mail_tool, "send",
                         str(args.mail_settings), args.secret_tool, subject, body, str(photo)],
                        capture_output=True, text=True, timeout=45, check=False,
                    )
                    if sent.returncode == 0:
                        active_key = key
                    else:
                        state = "mail_failed"
                        errors.write(f"{stamp} Mail error: {sent.stderr}\n")
                        errors.flush()
                        retry_after = time.monotonic() + 300
                except (OSError, subprocess.TimeoutExpired) as exc:
                    state = "mail_failed"
                    errors.write(f"{stamp} Mail error: {exc}\n")
                    errors.flush()
                    retry_after = time.monotonic() + 300

            writer.writerow([stamp, photo.name, "" if value is None else value,
                             confidence, state])
            log.flush()
            seq += 1


if __name__ == "__main__":
    sys.exit(main())
