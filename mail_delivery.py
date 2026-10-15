#!/usr/bin/env python3
"""Send instrument alerts over authenticated, encrypted SMTP."""

import argparse
from email.message import EmailMessage
import json
from pathlib import Path
import smtplib
import ssl
import subprocess
import sys


def settings(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    for key in ("recipient", "sender", "host", "port", "security"):
        if key not in data:
            raise ValueError(f"missing mail setting: {key}")
    if data["security"] not in ("ssl", "starttls"):
        raise ValueError("SMTP security must be ssl or starttls")
    return data


def connect(cfg, secret_tool):
    token = subprocess.run(
        [secret_tool, "get", cfg["sender"]], capture_output=True,
        text=True, timeout=15, check=True,
    ).stdout.rstrip("\n")
    if not token:
        raise ValueError("SMTP authorization code is empty")
    context = ssl.create_default_context()
    # Python.org/Homebrew Python on macOS can have an empty OpenSSL CA store,
    # even while the OS trust bundle is available and the certificate is valid.
    # Add the system CA bundle without disabling TLS certificate verification.
    if sys.platform == "darwin":
        system_ca = Path("/etc/ssl/cert.pem")
        if system_ca.is_file():
            context.load_verify_locations(cafile=str(system_ca))
    if cfg["security"] == "ssl":
        server = smtplib.SMTP_SSL(cfg["host"], int(cfg["port"]),
                                  timeout=20, context=context)
    else:
        server = smtplib.SMTP(cfg["host"], int(cfg["port"]), timeout=20)
        server.ehlo()
        server.starttls(context=context)
        server.ehlo()
    try:
        server.login(cfg["sender"], token)
        return server
    except BaseException:
        server.close()
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("check", "test", "send"))
    parser.add_argument("settings_path")
    parser.add_argument("secret_tool")
    parser.add_argument("subject", nargs="?")
    parser.add_argument("body", nargs="?")
    parser.add_argument("photo", nargs="?")
    args = parser.parse_args()
    cfg = settings(args.settings_path)
    if args.action == "send" and not all((args.subject, args.body, args.photo)):
        parser.error("send requires subject, body and photo")
    with connect(cfg, args.secret_tool) as server:
        if args.action in ("test", "send"):
            msg = EmailMessage()
            msg["From"] = cfg["sender"]
            msg["To"] = cfg["recipient"]
            if args.action == "test":
                msg["Subject"] = "每秒拍照：测试邮件"
                msg.set_content("邮件提醒设置成功。这封邮件由每秒拍照 App 的设置功能发送。")
            else:
                photo = Path(args.photo)
                msg["Subject"] = args.subject
                msg.set_content(args.body)
                msg.add_attachment(photo.read_bytes(), maintype="image", subtype="jpeg",
                                   filename=photo.name)
            server.send_message(msg)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, smtplib.SMTPException,
            subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        # Never print the authorization code or mail body.
        print(f"SMTP error: {exc}", file=sys.stderr)
        sys.exit(1)
