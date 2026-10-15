#!/usr/bin/env python3
"""Full training export and progress report.

Writes an Excel workbook with every logged set and a Markdown report that
compares the active phase with the last N weeks: what is trained, what is not,
per-exercise progress on the same machine, and data quality.

    python scripts/training_report.py --db data/trainbot.db --out-dir files/reports --recent-days 45
"""

from __future__ import annotations

import argparse
import os
import sys
from collections import defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "backend"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True)
    parser.add_argument("--out-dir", default="files/reports")
    parser.add_argument("--recent-days", type=int, default=45)
    parser.add_argument("--today")
    args = parser.parse_args()

    try:
        from run_tests import _install_google_genai_stub, _install_telegram_stub
        _install_google_genai_stub()
        _install_telegram_stub()
    except Exception:
        pass
    import database as db
    import training_analysis as ta
    import openpyxl
    from openpyxl.styles import Alignment, Font, PatternFill

    db.DB_PATH = os.path.abspath(args.db)
    today = datetime.strptime(args.today, "%Y-%m-%d").date() if args.today else date.today()
    recent_start = today - timedelta(days=args.recent_days)
    with db.db_connection() as conn:
        rows = [dict(row) for row in conn.execute(
            "SELECT id, date, time, weekday, exercise, exercise_raw, weight, sets, reps, tonnage, treadmill, pulse, comment "
            "FROM workouts ORDER BY date, id"
        ).fetchall()]
        weights = [dict(row) for row in conn.execute(
            "SELECT date, weight, smm, fat_pct, fat_kg, visceral, waist, abdomen, chest, arm FROM measurements ORDER BY date"
        ).fetchall()]
    audit = ta.analyze(today=today)

    # ---- per family, split by phase ------------------------------------
    fam_rows: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        key, label, group = ta.classify_exercise(row["exercise"])
        row["family"], row["family_label"], row["group"] = key, label, group
        row["sets_list"] = ta.expand_sets(row)
        fam_rows[key].append(row)

    def phase_sets(group: str, start: date, end: date) -> int:
        return sum(
            len(row["sets_list"]) for row in rows
            if row["group"] == group and start.isoformat() <= row["date"] <= end.isoformat()
        )

    first_day = datetime.strptime(rows[0]["date"], "%Y-%m-%d").date()
    active_start, active_end = max(first_day, date(2026, 6, 1)), date(2026, 7, 23)
    active_weeks = max(1, (active_end - active_start).days / 7)
    recent_weeks = max(1, args.recent_days / 7)
    groups = list(ta.TARGET_GROUPS) + ["conditioning"]
    group_rows = []
    for group in groups:
        a = phase_sets(group, active_start, active_end) / active_weeks
        r = phase_sets(group, recent_start, today) / recent_weeks
        group_rows.append((ta.MUSCLE_GROUP_LABELS.get(group, group), round(a, 1), round(r, 1)))

    sessions_recent = sorted({row["date"] for row in rows if row["date"] >= recent_start.isoformat()})
    sessions_active = sorted({row["date"] for row in rows if active_start.isoformat() <= row["date"] <= active_end.isoformat()})

    families = [item for item in audit["families"] if item["group"] not in {"cardio", "other"}]

    # ---- Excel ---------------------------------------------------------------
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp = today.strftime("%Y%m%d")
    wb = openpyxl.Workbook()
    header_font = Font(bold=True, color="FFFFFF")
    header_fill = PatternFill("solid", fgColor="1F3A68")

    def sheet(title, header, data, widths):
        ws = wb.create_sheet(title)
        ws.append(header)
        for cell in ws[1]:
            cell.font, cell.fill = header_font, header_fill
            cell.alignment = Alignment(vertical="center", wrap_text=True)
        for item in data:
            ws.append(list(item))
        for index, width in enumerate(widths, start=1):
            ws.column_dimensions[openpyxl.utils.get_column_letter(index)].width = width
        ws.freeze_panes = "A2"
        ws.auto_filter.ref = ws.dimensions
        return ws

    wb.remove(wb.active)
    sheet(
        "Все тренировки",
        ["Дата", "День", "Упражнение", "Как записано", "Группа", "Вес", "Подходы", "Повторы", "Тоннаж, кг", "Пульс", "Комментарий"],
        [
            (row["date"], row["weekday"], row["exercise"], row["exercise_raw"] or "", ta.MUSCLE_GROUP_LABELS.get(row["group"], row["group"]),
             row["weight"], row["sets"], row["reps"], round(row["tonnage"] or 0), row["pulse"], row["comment"])
            for row in rows
        ],
        [11, 13, 38, 30, 18, 22, 9, 22, 11, 10, 60],
    )
    sheet(
        "Прогресс упражнений",
        ["Упражнение", "Группа", "Сессий", "Первый", "Дата", "Лучший", "Дата", "Последний", "Дата", "Тренд 1ПМ", "Дней назад", "Подходов с помощью"],
        [
            (item["label"], item["group_label"], item["sessions"], item["first_top"], item["first_date"],
             item["best_top"], item["best_date"], item["last_top"], item["last_date"],
             f"{item['trend_pct']:+d}%" if item["trend_pct"] is not None else "—", item["days_since"], item["assisted_sets"])
            for item in families
        ],
        [40, 20, 8, 16, 11, 16, 11, 16, 11, 11, 11, 11],
    )
    sheet(
        "Группы мышц",
        ["Группа", f"Подходов/нед. {active_start:%d.%m}–{active_end:%d.%m}", f"Подходов/нед. последние {args.recent_days} дн.", "Норма для роста"],
        [(label, a, r, "10–20") for label, a, r in group_rows],
        [26, 22, 26, 16],
    )
    sheet(
        "Недели",
        ["Неделя", "Тренировок", "Подходов", "Тоннаж, кг"],
        [(item["week"], item["sessions"], item["sets"], item["tonnage"]) for item in audit["weekly"]],
        [12, 12, 12, 14],
    )
    sheet(
        "Замеры",
        ["Дата", "Вес", "Мышцы SMM", "Жир %", "Жир кг", "Висцеральный", "Талия", "Живот", "Грудь", "Рука"],
        [tuple(item.values()) for item in weights],
        [11, 8, 11, 8, 8, 12, 8, 8, 8, 8],
    )
    xlsx_path = out_dir / f"TrainBot_тренировки_{stamp}.xlsx"
    wb.save(xlsx_path)

    # ---- Markdown ------------------------------------------------------------
    freq = audit["frequency"]
    md = [
        f"# Аудит тренировок · {today:%d.%m.%Y}",
        "",
        f"Журнал: {len(rows)} строк, {audit['coverage']['sessions']} тренировочных дней, "
        f"{audit['coverage']['first_date']} — {audit['coverage']['last_date']}, тоннаж {audit['coverage']['tonnage'] / 1000:.1f} т.",
        "",
        f"Активная фаза {active_start:%d.%m}–{active_end:%d.%m}: {len(sessions_active)} тренировок "
        f"({len(sessions_active) / active_weeks:.1f} в неделю).",
        f"Последние {args.recent_days} дней: {len(sessions_recent)} тренировок "
        f"({len(sessions_recent) / recent_weeks:.1f} в неделю) — {', '.join(datetime.strptime(d, '%Y-%m-%d').strftime('%d.%m') for d in sessions_recent) or 'нет'}.",
        f"Перерыв без тренировок: {max((gap['days'] for gap in freq.get('gaps') or []), default=0)} дн.",
        "",
        "## Что качается и что нет (подходов в неделю)",
        "",
        f"| Группа | {active_start:%d.%m}–{active_end:%d.%m} | Последние {args.recent_days} дн. | Норма |",
        "|---|---:|---:|---:|",
    ]
    md += [f"| {label} | {a:g} | {r:g} | 10–20 |" for label, a, r in group_rows]
    md += ["", "## Упражнения: первый → лучший → последний (самостоятельные подходы)", "",
           "| Упражнение | Сессий | Первый | Лучший | Последний | Тренд | Дней назад |", "|---|---:|---|---|---|---:|---:|"]
    for item in families:
        trend = f"{item['trend_pct']:+d}%" if item["trend_pct"] is not None else "—"
        md.append(
            f"| {item['label']} | {item['sessions']} | {item['first_top']} ({item['first_date'][5:].replace('-', '.')}) | "
            f"{item['best_top']} ({item['best_date'][5:].replace('-', '.')}) | {item['last_top']} ({item['last_date'][5:].replace('-', '.')}) | "
            f"{trend} | {item['days_since']} |"
        )
    md += ["", "## Последние тренировки", ""]
    for day in sessions_recent:
        md.append(f"**{datetime.strptime(day, '%Y-%m-%d'):%d.%m.%Y}**")
        for row in (r for r in rows if r["date"] == day):
            md.append(f"- {row['exercise']}: {row['weight'] or '—'} кг × {row['reps'] or '—'}" + (f" — {row['comment']}" if row['comment'] else ""))
        md.append("")
    quality = audit["data_quality"]
    md += ["## Качество данных", "",
           f"- Подходов с помощью страховщика: {quality['assisted_sets']}; до отказа: {quality['failure_sets']}; в дроп-сетах: {quality['drop_sets']}.",
           f"- Строк без веса в силовых: {quality['rows_without_load']}.",
           f"- Вес тела: последний замер {weights[-1]['date'] if weights else '—'} — {weights[-1]['weight'] if weights else '—'} кг."]
    md_path = out_dir / f"Аудит_тренировок_{stamp}.md"
    md_path.write_text("\n".join(md), encoding="utf-8")
    print(xlsx_path)
    print(md_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
