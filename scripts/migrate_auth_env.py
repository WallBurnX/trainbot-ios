#!/usr/bin/env python3
"""Replace a legacy CRM_PASSWORD entry with a scrypt password hash in-place."""

import argparse
import base64
import getpass
import hashlib
import os
import secrets
import stat
import tempfile
from pathlib import Path


def encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    if hasattr(hashlib, "scrypt"):
        digest = hashlib.scrypt(
            password.encode("utf-8"), salt=salt, n=2**15, r=8, p=1, dklen=32
        )
        return f"scrypt_v1$32768$8$1${encode(salt)}${encode(digest)}"
    iterations = 600_000
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, iterations, dklen=32
    )
    return f"pbkdf2_sha256_v1${iterations}${encode(salt)}${encode(digest)}"


def env_value(lines: list[str], key: str) -> str:
    prefix = f"{key}="
    for line in lines:
        if line.startswith(prefix):
            value = line[len(prefix) :].strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
                value = value[1:-1]
            return value
    return ""


def compose_literal(value: str) -> str:
    """Keep dollar-delimited hashes literal when Docker Compose reads .env."""
    if "'" in value:
        raise ValueError("Environment value cannot contain a single quote")
    return f"'{value}'"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", type=Path, default=Path(".env"))
    parser.add_argument("--keep-plaintext", action="store_true")
    args = parser.parse_args()
    path = args.env_file.resolve()
    if not path.exists():
        raise SystemExit(f"Environment file not found: {path}")

    lines = path.read_text(encoding="utf-8").splitlines()
    existing_hash = env_value(lines, "CRM_PASSWORD_HASH")
    password = env_value(lines, "CRM_PASSWORD")
    if existing_hash and not password:
        os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
        print("CRM authentication already uses a password hash")
        return
    if not password:
        if not os.isatty(0):
            raise SystemExit("CRM_PASSWORD is missing and no interactive terminal is available")
        password = getpass.getpass("CRM password: ")
    if not password:
        raise SystemExit("Password must not be empty")

    encoded = hash_password(password)
    output: list[str] = []
    hash_written = False
    for line in lines:
        if line.startswith("CRM_PASSWORD_HASH="):
            output.append(f"CRM_PASSWORD_HASH={compose_literal(encoded)}")
            hash_written = True
        elif line.startswith("CRM_PASSWORD=") and not args.keep_plaintext:
            continue
        else:
            output.append(line)
    if not hash_written:
        output.append(f"CRM_PASSWORD_HASH={compose_literal(encoded)}")
    if not any(line.startswith("ALLOW_LEGACY_CRM_PASSWORD=") for line in output):
        output.append("ALLOW_LEGACY_CRM_PASSWORD=false")

    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write("\n".join(output).rstrip() + "\n")
        os.chmod(temporary_name, stat.S_IRUSR | stat.S_IWUSR)
        os.replace(temporary_name, path)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)
    print("CRM password migrated to a slow password hash; plaintext entry removed")


if __name__ == "__main__":
    main()
