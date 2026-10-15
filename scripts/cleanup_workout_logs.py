#!/usr/bin/env python3
"""One-time, auditable cleanup of the confirmed 2026-06-18 duplicate cluster.

Dry-run is the default.  Removed rows are copied to maintenance_archive before
deletion, and heart-rate screenshot metadata is moved to wellness notes.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
from datetime import datetime


TARGET_DATE = "2026-06-18"
REMOVE_IDS = (56, 57, 58, 61, 62, 63, 64, 65, 66, 67, 68, 70)
EXPECTED_NAMES = {
    56: "Упражнение на кор",
    57: "Тренировка по графику пульса",
    58: "Круговая тренировка",
    61: "Берпи",
    62: "Бросок медбола вверх",
    63: "Выпады",
    64: "Упражнения с гирей",
    65: "Берпи",
    66: "Бросок медбола вверх",
    67: "Выпады с гантелями",
    68: "Бросок медбола вверх",
    70: "Упражнения с гирей",
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True, help="Path to trainbot.db")
    parser.add_argument("--apply", action="store_true", help="Commit the cleanup")
    args = parser.parse_args()

    conn = sqlite3.connect(args.db)
    conn.row_factory = sqlite3.Row
    try:
        integrity = conn.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise RuntimeError(f"Database integrity check failed: {integrity}")
        placeholders = ",".join("?" for _ in REMOVE_IDS)
        rows = conn.execute(
            f"SELECT * FROM workouts WHERE date=? AND id IN ({placeholders}) ORDER BY id",
            (TARGET_DATE, *REMOVE_IDS),
        ).fetchall()
        found = {row["id"]: row for row in rows}
        missing = sorted(set(REMOVE_IDS) - set(found))
        mismatched = {
            row_id: (found[row_id]["exercise"], EXPECTED_NAMES[row_id])
            for row_id in found
            if found[row_id]["exercise"] != EXPECTED_NAMES[row_id]
        }
        if missing or mismatched:
            raise RuntimeError(f"Safety check failed; missing={missing}, mismatched={mismatched}")

        before = conn.execute(
            "SELECT COUNT(*), COALESCE(SUM(tonnage),0) FROM workouts WHERE date=?",
            (TARGET_DATE,),
        ).fetchone()
        print(f"Before: rows={before[0]} tonnage={before[1]:.1f}")
        for row in rows:
            print(f"remove id={row['id']} {row['exercise']} {row['weight'] or ''} {row['sets'] or ''}x{row['reps'] or ''}")
        if not args.apply:
            print("Dry-run only; pass --apply to commit")
            return 0

        conn.execute("BEGIN IMMEDIATE")
        conn.execute("""
            CREATE TABLE IF NOT EXISTS maintenance_archive (
                table_name TEXT NOT NULL,
                record_id INTEGER NOT NULL,
                reason TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                archived_at TEXT NOT NULL,
                PRIMARY KEY (table_name, record_id, reason)
            )
        """)
        archived_at = datetime.now().isoformat()
        reason = "confirmed duplicate/meta workout cleanup 2026-07-14"
        for row in rows:
            conn.execute("""
                INSERT OR IGNORE INTO maintenance_archive
                    (table_name, record_id, reason, payload_json, archived_at)
                VALUES ('workouts', ?, ?, ?, ?)
            """, (row["id"], reason, json.dumps(dict(row), ensure_ascii=False), archived_at))

        wellness_note = (
            "График круговой тренировки: около 54–55 мин; 9 мин в экстремальной, "
            "11 мин в анаэробной, 14 мин в аэробной и 18 мин в жиросжигающей зоне; "
            "восстановление пульса 118→119 уд/мин."
        )
        current = conn.execute("SELECT notes FROM wellness WHERE date=?", (TARGET_DATE,)).fetchone()
        current_note = (current[0] if current else "") or ""
        merged_note = " | ".join(part for part in (current_note, wellness_note) if part)
        conn.execute("""
            INSERT INTO wellness (date, notes) VALUES (?, ?)
            ON CONFLICT(date) DO UPDATE SET notes=excluded.notes
        """, (TARGET_DATE, merged_note))
        conn.execute(
            f"DELETE FROM workouts WHERE date=? AND id IN ({placeholders})",
            (TARGET_DATE, *REMOVE_IDS),
        )
        conn.commit()
        after = conn.execute(
            "SELECT COUNT(*), COALESCE(SUM(tonnage),0) FROM workouts WHERE date=?",
            (TARGET_DATE,),
        ).fetchone()
        print(f"After: rows={after[0]} tonnage={after[1]:.1f}; archived={len(rows)}")
        return 0
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
