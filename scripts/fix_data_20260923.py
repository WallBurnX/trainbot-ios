#!/usr/bin/env python3
"""September 2026 data repair (idempotent, dry-run by default).

1. 03.09: the same workout was saved twice (restored log + a later resend).
   Rows 282–287 are archived to maintenance_archive and removed.
2. 13.09: drop sets were collapsed into single numbers ("12/6/36",
   "10/10/10/50"); rows 289 and 290 are rewritten set by set.
3. 14.07 row 215 was the Pull Down lever machine (chat 14.07 10:02), not the
   cable lat pulldown.
4. 05.09 weigh-in 81.7 kg was swallowed by the pending date question.
5. Stale dialogue state and memory facts that kept asking for dates.
6. Exercise names are re-canonicalised with the owner-confirmed aliases.

    docker exec trainbot-crm python /app/scripts/fix_data_20260923.py --db /app/data/trainbot.db --apply
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend"))

DUPLICATE_IDS = (282, 283, 284, 285, 286, 287)
ROW_FIXES = {
    289: {
        "expect_date": "2026-09-13",
        "exercise": "Upper Back — тяга на верх спины",
        "weight": "25/60/70/60/50/40/30/20",
        "sets": 3,
        "reps": "12/6/3/3/3/5/7/15",
        "tonnage": 1910.0,
        "comment": "Разминка 25×12, рабочий 60×6, затем дроп-сет 70→20 кг (3/3/3/5/7/15).",
    },
    290: {
        "expect_date": "2026-09-13",
        "exercise": "Low Row — рычажная горизонтальная тяга",
        "weight": "80/80/80/80/70/60/50/40",
        "sets": 4,
        "reps": "5+5/5+5/5+5/10/10/10/10/10",
        "tonnage": 5400.0,
        "comment": "3 подхода: 80×5 двумя руками + сразу 5 на каждую руку; 4-й — дроп-сет на руку 80→40 кг по 10.",
    },
    215: {
        "expect_date": "2026-07-14",
        "exercise": "Pull Down — рычажная тяга сверху",
        "exercise_raw": "Pull down тренажёр",
    },
}
LOST_WEIGHINS = (("2026-09-05", 81.7),)
STALE_MEMORY = ("training.next_date", "training.program_request", "training.completed_session.2026-08-28")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    os.environ["DB_PATH"] = os.path.abspath(args.db)
    import database as db

    db.DB_PATH = os.path.abspath(args.db)
    db.init_db()  # installs owner aliases
    now = datetime.now().isoformat()
    actions: list[str] = []
    with db.db_connection() as conn:
        if conn.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise SystemExit("integrity_check failed")
        placeholders = ",".join("?" for _ in DUPLICATE_IDS)
        dupes = conn.execute(
            f"SELECT * FROM workouts WHERE date = '2026-09-03' AND id IN ({placeholders})", DUPLICATE_IDS
        ).fetchall()
        for row in dupes:
            actions.append(f"archive+delete duplicate #{row['id']} {row['exercise']}")
            if args.apply:
                conn.execute(
                    "INSERT OR IGNORE INTO maintenance_archive (table_name, record_id, reason, payload_json, archived_at) "
                    "VALUES ('workouts', ?, 'duplicate_resend_20260903', ?, ?)",
                    (row["id"], json.dumps(dict(row), ensure_ascii=False), now),
                )
                conn.execute("DELETE FROM workouts WHERE id = ?", (row["id"],))
        for row_id, fix in ROW_FIXES.items():
            row = conn.execute("SELECT * FROM workouts WHERE id = ?", (row_id,)).fetchone()
            if not row or row["date"] != fix["expect_date"]:
                continue
            changes = {key: value for key, value in fix.items() if key != "expect_date" and row[key] != value}
            if not changes:
                continue
            actions.append(f"fix #{row_id}: {', '.join(changes)}")
            if args.apply:
                conn.execute(
                    "INSERT OR IGNORE INTO maintenance_archive (table_name, record_id, reason, payload_json, archived_at) "
                    "VALUES ('workouts', ?, 'fix_20260923', ?, ?)",
                    (row_id, json.dumps(dict(row), ensure_ascii=False), now),
                )
                if "exercise" in changes and "exercise_raw" not in changes and not row["exercise_raw"]:
                    changes["exercise_raw"] = row["exercise"]
                assignments = ", ".join(f"{key} = ?" for key in changes)
                conn.execute(f"UPDATE workouts SET {assignments} WHERE id = ?", (*changes.values(), row_id))
        for day, weight in LOST_WEIGHINS:
            existing = conn.execute("SELECT weight FROM measurements WHERE date = ?", (day,)).fetchone()
            if existing and existing["weight"]:
                continue
            actions.append(f"add weigh-in {day} {weight}")
        state = conn.execute("SELECT pending_intent FROM conversation_state WHERE conversation_id='owner'").fetchone()
        if state and state["pending_intent"]:
            actions.append(f"clear pending dialogue '{state['pending_intent']}'")
        for key in STALE_MEMORY:
            if conn.execute("SELECT 1 FROM conversation_memory WHERE memory_key = ? AND status='active'", (key,)).fetchone():
                actions.append(f"forget memory {key}")
        if args.apply:
            conn.commit()
    if args.apply:
        for day, weight in LOST_WEIGHINS:
            if f"add weigh-in {day} {weight}" in actions:
                db.save_measurement({"date": day, "weight": weight})
        db.set_conversation_state("", {}, channel="telegram")
        with db.db_connection() as conn:
            for key in STALE_MEMORY:
                conn.execute("UPDATE conversation_memory SET status='forgotten' WHERE memory_key = ?", (key,))
            conn.commit()
        renamed = db.refresh_workout_canonical_names()
        actions.append(f"canonicalised names in {renamed} rows")
    for line in actions:
        print(line)
    print("APPLIED" if args.apply else "DRY-RUN", len(actions), "actions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
