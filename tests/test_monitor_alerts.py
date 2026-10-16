"""Exercise alert episodes without a camera or SMTP account."""

import csv
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


MONITOR = Path(__file__).resolve().parents[1] / "monitor_instrument.py"


class MonitorAlertTests(unittest.TestCase):
    def run_case(self, condition, readings):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            session = root / "session"
            session.mkdir()
            for number in range(1, len(readings) + 1):
                (session / f"IMG-{number:05d}.jpg").write_bytes(b"test")
            (session / ".capture_finished").touch()
            ocr = root / "ocr.py"
            ocr.write_text(
                "#!/usr/bin/env python3\n"
                "import json, os, pathlib, sys\n"
                "readings = json.loads(os.environ['FAKE_READINGS'])\n"
                "value = readings[int(pathlib.Path(sys.argv[1]).stem.split('-')[1]) - 1]\n"
                "if value is None: sys.exit(2)\n"
                "print(f'{value}\\t1.0')\n",
                encoding="utf-8",
            )
            ocr.chmod(0o755)
            mail = root / "mail.py"
            mail.write_text(
                "import os, pathlib, sys\n"
                "with open(os.environ['FAKE_MAIL_LOG'], 'a') as log:\n"
                "    log.write(pathlib.Path(sys.argv[-1]).name + '\\n')\n",
                encoding="utf-8",
            )
            mail_log = root / "mail.log"
            environment = os.environ.copy()
            environment["FAKE_READINGS"] = json.dumps(readings)
            environment["FAKE_MAIL_LOG"] = str(mail_log)
            result = subprocess.run(
                [sys.executable, str(MONITOR), str(session), "0,0,1,1",
                 condition, str(root / "mail-settings.json"), "0", str(ocr),
                 str(mail), str(root / "secret")],
                env=environment, capture_output=True, text=True, timeout=20,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            with (session / "recognition.csv").open(newline="") as stream:
                states = [row["state"] for row in csv.DictReader(stream)]
            emails = mail_log.read_text().splitlines() if mail_log.exists() else []
            return emails, states

    def test_single_value_rearms_after_outside(self):
        emails, states = self.run_case("31", [31, 31, 31, None, 31, 30, 31, 31, 31])
        self.assertEqual(emails, ["IMG-00001.jpg", "IMG-00002.jpg",
                                  "IMG-00007.jpg", "IMG-00008.jpg"])
        self.assertEqual(states[0:3], ["alert_1", "alert_2", "inside"])
        self.assertEqual(states[5], "rearmed")

    def test_range_treats_different_values_as_one_episode(self):
        emails, _ = self.run_case("10~20", [10, 12, 18, 21, 19, 20, 20])
        self.assertEqual(emails, ["IMG-00001.jpg", "IMG-00002.jpg",
                                  "IMG-00005.jpg", "IMG-00006.jpg"])

    def test_multiple_targets_share_one_episode(self):
        emails, _ = self.run_case("31、32", [31, 32, 31, None, 32, 40, 31])
        self.assertEqual(emails, ["IMG-00001.jpg", "IMG-00002.jpg",
                                  "IMG-00007.jpg"])


if __name__ == "__main__":
    unittest.main()
