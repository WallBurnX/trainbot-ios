#!/usr/bin/env python3
"""Read-only export of the owner's Telegram chat with @leotrainbot.

Uses the owner's existing Telethon session from the Mytelegram project and
writes every message (both directions, including edited bot replies that
contain voice transcripts) to JSON.  Nothing is sent or modified.

    python scripts/export_telegram_chat.py --out data/telegram_export/chat.json
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
from pathlib import Path

from telethon import TelegramClient

MYTELEGRAM = Path.home() / "Desktop" / "Проекты" / "Mytelegram"


def _load_env(path: Path) -> dict:
    env = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.strip().startswith("#"):
            key, value = line.split("=", 1)
            env[key.strip()] = value.strip().strip("'\"")
    return env


async def run(out: Path, bot: str) -> None:
    env = _load_env(MYTELEGRAM / ".env")
    session = next((MYTELEGRAM / "sessions").glob("*.session"))
    client = TelegramClient(str(session.with_suffix("")), int(env["TG_API_ID"]), env["TG_API_HASH"])
    await client.connect()
    if not await client.is_user_authorized():
        raise SystemExit("Telethon session is not authorized; nothing exported.")
    entity = await client.get_entity(bot)
    rows = []
    async for message in client.iter_messages(entity, reverse=True):
        media = None
        if message.photo:
            media = "photo"
        elif message.voice:
            media = "voice"
        elif message.document:
            media = "document"
        rows.append(
            {
                "id": message.id,
                "date": message.date.isoformat(),
                "edit_date": message.edit_date.isoformat() if message.edit_date else None,
                "from_bot": bool(message.out) is False,
                "text": message.message or "",
                "media": media,
            }
        )
    await client.disconnect()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"exported {len(rows)} messages → {out}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="data/telegram_export/chat.json")
    parser.add_argument("--bot", default="leotrainbot")
    args = parser.parse_args()
    asyncio.run(run(Path(args.out), args.bot))


if __name__ == "__main__":
    main()
