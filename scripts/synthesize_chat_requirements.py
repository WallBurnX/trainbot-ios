#!/usr/bin/env python3
"""Build a deterministic product-requirements index from every local chat source.

The script never sends chat content to an external model. It extracts user turns,
deduplicates exact normalized copies, assigns broad product domains, and writes a
compact audit ledger plus a machine-readable index.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sqlite3
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


TRANSCRIPT_USER_HEADING = re.compile(r"^##\s+👤\s+(?:You|Пользователь)\s*$", re.MULTILINE)
TRANSCRIPT_ANY_HEADING = re.compile(r"^##\s+(?:👤|🤖).*$", re.MULTILINE)
ARCHIVE_USER_HEADING = re.compile(
    r"^###\s+(?P<date>.+?)\s+-\s+Пользователь\s*$", re.MULTILINE
)
ARCHIVE_ANY_HEADING = re.compile(
    r"^###\s+.+?\s+-\s+(?:Пользователь|ИИ-Тренер|Ассистент)\s*$", re.MULTILINE
)

CATEGORIES = {
    "training_program": (
        "Тренировочная программа и прогрессия",
        ("трениров", "упражнен", "подход", "повтор", "вес", "тоннаж", "прогрес"),
    ),
    "equipment_library": (
        "Тренажёры, карточки и единый словарь",
        ("тренаж", "карточ", "ddx", "low row", "аналог", "оборудован"),
    ),
    "recovery_schedule": (
        "График, готовность и восстановление",
        ("расписан", "график", "сон", "восстанов", "устал", "боль", "готовност"),
    ),
    "nutrition_health": (
        "Питание, добавки и здоровье",
        ("питан", "белок", "калори", "добав", "карнит", "здоров", "жир", "пульс"),
    ),
    "crm_ui": (
        "CRM, UI и аналитика",
        ("crm", "срм", "ui", "интерфейс", "таблиц", "дашборд", "график", "темн"),
    ),
    "ai_models": (
        "ИИ-модели, маршрутизация и бюджет",
        ("gemini", "гемини", "gpt", "гпт", "opus", "опус", "claude", "дипсик", "deepseek", "модел", "токен"),
    ),
    "security_deployment": (
        "Безопасность, сервер и деплой",
        ("аутент", "авториза", "парол", "сервер", "vps", "депло", "deploy", "https", "бэкап"),
    ),
    "data_quality": (
        "Данные, импорт и история",
        ("excel", "эксел", "файл", "чат", "истори", "архив", "база", "словар"),
    ),
}

CURRENT_CONTRACT = (
    "Тренировки: 4 раза в неделю — 3 силовые и 1 интервальная или кроссфит; дни плавающие.",
    "Цель: рост мышц и силы с контролем восстановления, слабых мест и прогрессии весов.",
    "GPT — главный автор версий тренировочной программы; новая версия применяется только после согласования.",
    "Gemini Flash — первый гонец, DeepSeek — второй; дорогой GPT не используется для рутинной переписки.",
    "После утверждения плана визуальный движок создаёт карточки по дням; точные веса, подходы, повторы и RIR накладываются локально.",
    "Каждое упражнение имеет несколько взаимозаменяемых вариантов на случай занятого тренажёра.",
    "Карточка обязана показывать тренажёр целиком без обрезания.",
    "CRM работает в тёмной теме, хранит историю, прогресс, готовность, расписание, файлы и резервные копии.",
    "Деплой выполняется только после локальной проверки; секреты не попадают в интерфейс, логи и архив требований.",
)


@dataclass(frozen=True)
class Turn:
    source: str
    source_id: str
    text: str
    timestamp: str | None = None


def normalize(text: str) -> str:
    text = re.sub(r"\s+", " ", text).strip().lower()
    return text


def safe_excerpt(text: str, limit: int = 240) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def extract_transcript(path: Path) -> list[Turn]:
    raw = path.read_text(encoding="utf-8", errors="replace")
    turns: list[Turn] = []
    for index, match in enumerate(TRANSCRIPT_USER_HEADING.finditer(raw), start=1):
        next_heading = TRANSCRIPT_ANY_HEADING.search(raw, match.end())
        end = next_heading.start() if next_heading else len(raw)
        text = raw[match.end() : end].strip("\n -")
        if text:
            turns.append(Turn(path.name, f"{path.name}:{index}", text))
    return turns


def extract_archive(path: Path) -> list[Turn]:
    raw = path.read_text(encoding="utf-8", errors="replace")
    turns: list[Turn] = []
    for index, match in enumerate(ARCHIVE_USER_HEADING.finditer(raw), start=1):
        next_heading = ARCHIVE_ANY_HEADING.search(raw, match.end())
        end = next_heading.start() if next_heading else len(raw)
        text = raw[match.end() : end].strip("\n -")
        if text:
            turns.append(
                Turn(path.name, f"{path.name}:{index}", text, match.group("date").strip())
            )
    return turns


def extract_database(path: Path) -> list[Turn]:
    if not path.exists():
        return []
    with sqlite3.connect(path) as conn:
        rows = conn.execute(
            "SELECT id, content, timestamp FROM chat_history WHERE role = 'user' ORDER BY id"
        ).fetchall()
    return [
        Turn(path.name, f"{path.name}:chat_history:{row[0]}", row[1], row[2])
        for row in rows
        if row[1] and row[1].strip()
    ]


def classify(text: str) -> list[str]:
    lowered = text.lower()
    matches = [
        key
        for key, (_, keywords) in CATEGORIES.items()
        if any(keyword in lowered for keyword in keywords)
    ]
    return matches or ["other"]


def build_index(root: Path) -> dict:
    transcript_paths = [
        root / "chat_transcript.md",
        root / "chat_transcript1.md",
        root / "chat_transcript2.md",
    ]
    turns: list[Turn] = []
    for path in transcript_paths:
        if path.exists():
            turns.extend(extract_transcript(path))
    archive = root / "data" / "chat_archive.md"
    if archive.exists():
        turns.extend(extract_archive(archive))
    turns.extend(extract_database(root / "data" / "trainbot.db"))

    unique: dict[str, dict] = {}
    source_counts = Counter(turn.source for turn in turns)
    for turn in turns:
        normalized = normalize(turn.text)
        if not normalized:
            continue
        digest = hashlib.sha256(normalized.encode("utf-8")).hexdigest()
        record = unique.setdefault(
            digest,
            {
                "id": digest[:16],
                "text": turn.text.strip(),
                "excerpt": safe_excerpt(turn.text),
                "timestamp": turn.timestamp,
                "categories": classify(turn.text),
                "sources": [],
            },
        )
        record["sources"].append(turn.source_id)
        if turn.timestamp and not record["timestamp"]:
            record["timestamp"] = turn.timestamp

    category_records: dict[str, list[dict]] = defaultdict(list)
    for record in unique.values():
        for category in record["categories"]:
            category_records[category].append(record)

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "sources": dict(sorted(source_counts.items())),
        "raw_user_turns": len(turns),
        "unique_user_turns": len(unique),
        "duplicate_turns_removed": len(turns) - len(unique),
        "category_counts": {
            key: len(category_records.get(key, []))
            for key in (*CATEGORIES.keys(), "other")
        },
        "turns": sorted(unique.values(), key=lambda item: item["id"]),
    }


def render_ledger(index: dict) -> str:
    lines = [
        "# TrainBot — аудит требований из локальной истории",
        "",
        f"Сформировано: {index['generated_at']}",
        "",
        "Все источники обработаны локально. Текст чатов не отправлялся внешним моделям.",
        "",
        "## Покрытие",
        "",
        f"- Пользовательских сообщений до дедупликации: {index['raw_user_turns']}",
        f"- Уникальных сообщений: {index['unique_user_turns']}",
        f"- Удалено точных нормализованных дублей: {index['duplicate_turns_removed']}",
    ]
    for source, count in index["sources"].items():
        lines.append(f"- `{source}`: {count}")

    lines.extend(["", "## Текущий согласованный контракт", ""])
    lines.extend(f"{number}. {item}" for number, item in enumerate(CURRENT_CONTRACT, start=1))

    lines.extend(["", "## Карта доменов", ""])
    for key, (label, _) in CATEGORIES.items():
        lines.append(f"- **{label}:** {index['category_counts'].get(key, 0)} уникальных сообщений")
    lines.append(f"- **Прочее:** {index['category_counts'].get('other', 0)} уникальных сообщений")

    lines.extend(
        [
            "",
            "## Правила реализации",
            "",
            "- Исторические факты не удаляются при выпуске новой версии программы.",
            "- Названия упражнений нормализуются через единый словарь, исходная формулировка сохраняется.",
            "- Платные флагманские модели вызываются только для задач, которым нужна их роль.",
            "- Автообновление модели допускает только стабильного преемника того же семейства после проверки доступности.",
            "- FCC и другие шлюзы всегда показывают фактическую upstream-модель; имя уровня не выдаётся за модель.",
            "- Изменения программы проходят цикл: черновик → согласование → активация → неизменяемая история.",
            "",
            "## Машиночитаемый индекс",
            "",
            "Полный дедуплицированный индекс находится в `data/chat_requirements_index.json`. Он содержит идентификаторы источников, категории и компактные выдержки, но не секреты окружения.",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    root = args.root.resolve()
    index = build_index(root)

    index_path = root / "data" / "chat_requirements_index.json"
    ledger_path = root / "files" / "TrainBot_CRM_Требования.md"
    index_path.parent.mkdir(parents=True, exist_ok=True)
    ledger_path.parent.mkdir(parents=True, exist_ok=True)
    index_path.write_text(
        json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    ledger_path.write_text(render_ledger(index), encoding="utf-8")
    print(
        json.dumps(
            {
                "raw_user_turns": index["raw_user_turns"],
                "unique_user_turns": index["unique_user_turns"],
                "index": str(index_path),
                "ledger": str(ledger_path),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
