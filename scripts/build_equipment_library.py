#!/usr/bin/env python3
"""Extract DDX equipment cards from iPhone screenshots.

The screenshots use a fixed two-column grid.  Apple Vision OCR supplies the
text coordinates; this script keeps the last two complete grid rows, crops
each card, and removes repeated cards caused by overlapping screenshots.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
import unicodedata
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from equipment_naming import enrich_record


CARD_WIDTH = 645
CARD_HEIGHT = 850
LABEL_TARGET_Y = 680
MIN_CONTENT_Y = 805
LABEL_BOTTOM_MARGIN = 165
NAME_X_RANGES = ((35, 95), (635, 705))

BRAND_PATTERNS = (
    (re.compile(r"MATRIX", re.I), "Matrix"),
    (re.compile(r"PANATTA", re.I), "Panatta"),
    (re.compile(r"FOREMAN", re.I), "Foreman"),
    (re.compile(r"(TECH|LECH|ECHN).{0,4}GYM", re.I), "Technogym"),
    (re.compile(r"YOUSTEEL", re.I), "YouSteel"),
    (re.compile(r"HAST+INGS?", re.I), "Hasttings"),
    (re.compile(r"BOOTY\\s*BUIL", re.I), "Booty Builder"),
    (re.compile(r"NAUTILUS", re.I), "Nautilus"),
    (re.compile(r"PRECOR", re.I), "Precor"),
)


@dataclass
class NameGroup:
    y: float
    observations: list[dict]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--ocr-jsonl", type=Path)
    parser.add_argument("--overrides", type=Path)
    return parser.parse_args()


def normalize_text(value: str) -> str:
    value = unicodedata.normalize("NFKC", value or "")
    value = value.replace("–", "—").replace("-", "—")
    value = re.sub(r"\s+", " ", value).strip(" .,;:")
    value = re.sub(r"\s*—\s*", " — ", value)
    value = re.sub(r"\bтренажер\b", "тренажёр", value, flags=re.I)
    value = re.sub(r"\bПодьем\b", "Подъём", value, flags=re.I)
    value = re.sub(r"\bПодъем\b", "Подъём", value, flags=re.I)
    value = re.sub(r"\bбедер\b", "бёдер", value, flags=re.I)
    value = re.sub(r"\bСТОЯ\b", "стоя", value, flags=re.I)
    value = re.sub(r"\b([XХ])\s*—\s*тяга\b", r"\1-тяга", value, flags=re.I)
    value = re.sub(r"\bТ\s*—\s*грифа\b", "Т-грифа", value, flags=re.I)
    value = re.sub(r"\bиз\s*—\s*за\b", "из-за", value, flags=re.I)
    value = re.sub(r"\bВ трех\b", "в трёх", value)
    if value:
        value = value[0].upper() + value[1:]
    return value


def key_text(value: str) -> str:
    value = normalize_text(value).lower().replace("ё", "е")
    return re.sub(r"[^a-zа-я0-9]+", " ", value).strip()


def load_overrides(path: Path | None) -> dict[str, dict]:
    if not path or not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def run_ocr(source_files: list[Path], output_path: Path) -> None:
    repo_root = Path(__file__).resolve().parent.parent
    swift_source = repo_root / "scripts" / "ocr_ddx.swift"
    with tempfile.TemporaryDirectory(prefix="trainbot-ddx-ocr-") as temp_dir:
        binary = Path(temp_dir) / "ocr_ddx"
        subprocess.run(
            ["swiftc", str(swift_source), "-o", str(binary)],
            check=True,
        )
        with output_path.open("w", encoding="utf-8") as handle:
            subprocess.run(
                [str(binary), *(str(path) for path in source_files)],
                check=True,
                stdout=handle,
            )


def load_ocr(path: Path) -> dict[str, dict]:
    result: dict[str, dict] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        record = json.loads(line)
        result[Path(record["file"]).name] = record
    return result


def is_name_start_x(x: float) -> bool:
    return any(low <= x <= high for low, high in NAME_X_RANGES)


def complete_row_groups(observations: list[dict]) -> list[NameGroup]:
    candidates = [
        item
        for item in observations
        if item["y"] >= 780
        and is_name_start_x(item["x"])
        and len(item["text"].strip()) >= 3
        and item["text"].strip() not in {"Бренды v", "Категория"}
    ]
    candidates.sort(key=lambda item: (item["y"], item["x"]))
    groups: list[NameGroup] = []
    for item in candidates:
        if groups and item["y"] - max(
            observation["y"] for observation in groups[-1].observations
        ) <= 110:
            groups[-1].observations.append(item)
        else:
            groups.append(NameGroup(y=item["y"], observations=[item]))
    return groups[-2:]


def group_name(group: NameGroup, column: int) -> str:
    low, high = NAME_X_RANGES[column]
    observations = [
        item
        for item in group.observations
        if low <= item["x"] <= high and item["y"] <= group.y + 125
    ]
    observations.sort(key=lambda item: (item["y"], item["x"]))
    return normalize_text(" ".join(item["text"].strip() for item in observations))


def detect_brand(
    observations: list[dict],
    column: int,
    row_y: float,
) -> str:
    x0 = column * CARD_WIDTH
    x1 = x0 + CARD_WIDTH
    y0 = max(MIN_CONTENT_Y, row_y - 680)
    y1 = row_y - 70
    text = " ".join(
        item["text"]
        for item in observations
        if x0 <= item["x"] < x1 and y0 <= item["y"] <= y1
    )
    for pattern, brand in BRAND_PATTERNS:
        if pattern.search(text):
            return brand
    return ""


def crop_card(image: Image.Image, column: int, row_y: float) -> Image.Image:
    source_top = max(MIN_CONTENT_Y, int(round(row_y - LABEL_TARGET_Y)))
    source_bottom = min(image.height, int(round(row_y + LABEL_BOTTOM_MARGIN)))
    source_left = column * CARD_WIDTH
    source_right = min(image.width, source_left + CARD_WIDTH)
    source = image.crop((source_left, source_top, source_right, source_bottom))
    result = Image.new("RGB", (CARD_WIDTH, CARD_HEIGHT), "white")
    paste_y = LABEL_TARGET_Y - int(round(row_y - source_top))
    result.paste(source.convert("RGB"), (0, paste_y))
    return result


def perceptual_hash(image: Image.Image, hash_size: int = 16) -> int:
    resized = image.convert("L").resize(
        (hash_size + 1, hash_size),
        Image.Resampling.LANCZOS,
    )
    pixels = list(resized.getdata())
    value = 0
    row_width = hash_size + 1
    for y in range(hash_size):
        row_start = y * row_width
        for x in range(hash_size):
            left = pixels[row_start + x]
            right = pixels[row_start + x + 1]
            value = (value << 1) | int(left > right)
    return value


def hamming(left: int, right: int) -> int:
    return bin(left ^ right).count("1")


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def slug(value: str) -> str:
    table = str.maketrans(
        {
            "а": "a",
            "б": "b",
            "в": "v",
            "г": "g",
            "д": "d",
            "е": "e",
            "ё": "e",
            "ж": "zh",
            "з": "z",
            "и": "i",
            "й": "y",
            "к": "k",
            "л": "l",
            "м": "m",
            "н": "n",
            "о": "o",
            "п": "p",
            "р": "r",
            "с": "s",
            "т": "t",
            "у": "u",
            "ф": "f",
            "х": "h",
            "ц": "c",
            "ч": "ch",
            "ш": "sh",
            "щ": "sch",
            "ъ": "",
            "ы": "y",
            "ь": "",
            "э": "e",
            "ю": "yu",
            "я": "ya",
        }
    )
    value = value.lower().translate(table)
    value = re.sub(r"[^a-z0-9]+", "-", value).strip("-")
    return value[:64] or "equipment"


def make_contact_sheets(records: list[dict], output_dir: Path) -> None:
    review_dir = output_dir / "review"
    if review_dir.exists():
        shutil.rmtree(review_dir)
    review_dir.mkdir(parents=True, exist_ok=True)
    columns = 5
    rows = 3
    thumb_width = 258
    thumb_height = 340
    label_height = 30
    font = ImageFont.load_default(size=18)
    per_sheet = columns * rows
    for start in range(0, len(records), per_sheet):
        batch = records[start : start + per_sheet]
        sheet = Image.new(
            "RGB",
            (
                columns * thumb_width,
                rows * (thumb_height + label_height),
            ),
            "white",
        )
        draw = ImageDraw.Draw(sheet)
        for index, record in enumerate(batch):
            card = Image.open(output_dir / record["image_file"]).convert("RGB")
            card.thumbnail((thumb_width, thumb_height), Image.Resampling.LANCZOS)
            x = (index % columns) * thumb_width
            y = (index // columns) * (thumb_height + label_height)
            sheet.paste(card, (x, y + label_height))
            draw.text(
                (x + 6, y + 5),
                f'{record["id"]} · {record["source_file"]}',
                fill="#111111",
                font=font,
            )
        sheet.save(
            review_dir / f"contact_{start // per_sheet + 1:02d}.jpg",
            quality=90,
        )


def main() -> None:
    args = parse_args()
    source_files = sorted(args.source.glob("IMG_*.PNG"))
    if not source_files:
        raise SystemExit(f"No IMG_*.PNG files in {args.source}")

    args.output.mkdir(parents=True, exist_ok=True)
    ocr_path = args.ocr_jsonl or args.output / "ocr.jsonl"
    if not args.ocr_jsonl:
        run_ocr(source_files, ocr_path)
    ocr = load_ocr(ocr_path)
    overrides = load_overrides(args.overrides)

    cards_dir = args.output / "cards"
    if cards_dir.exists():
        shutil.rmtree(cards_dir)
    cards_dir.mkdir(parents=True)

    source_hashes: dict[str, str] = {}
    raw_records: list[dict] = []
    source_duplicates: list[dict] = []
    sequence = 0

    for source_path in source_files:
        source_hash = file_sha256(source_path)
        if source_hash in source_hashes:
            source_duplicates.append(
                {
                    "duplicate_file": source_path.name,
                    "kept_file": source_hashes[source_hash],
                    "reason": "identical source image",
                }
            )
            continue
        source_hashes[source_hash] = source_path.name

        record = ocr.get(source_path.name)
        if not record:
            raise SystemExit(f"OCR record missing for {source_path.name}")
        row_groups = complete_row_groups(record["observations"])
        if len(row_groups) != 2:
            raise SystemExit(
                f"Expected two complete rows in {source_path.name}, "
                f"found {len(row_groups)}"
            )

        image = Image.open(source_path).convert("RGB")
        for row_index, row_group in enumerate(row_groups, start=1):
            for column in range(2):
                sequence += 1
                override_key = f"{source_path.name}:{row_index}:{column + 1}"
                override = overrides.get(override_key, {})
                ddx_name = normalize_text(
                    override.get("ddx_name") or group_name(row_group, column)
                )
                brand = override.get("brand") or detect_brand(
                    record["observations"],
                    column,
                    row_group.y,
                )
                card = crop_card(image, column, row_group.y)
                temp_name = f"raw_{sequence:04d}.png"
                temp_path = cards_dir / temp_name
                card.save(temp_path, optimize=True)
                raw_records.append(
                    {
                        "sequence": sequence,
                        "source_file": source_path.name,
                        "source_row": row_index,
                        "source_column": column + 1,
                        "source_ref": override_key,
                        "ddx_name": ddx_name,
                        "brand": brand,
                        "image_file": f"cards/{temp_name}",
                        "perceptual_hash": f"{perceptual_hash(card):064x}",
                        "needs_name_review": not bool(ddx_name)
                        or "..." in ddx_name
                        or len(ddx_name) < 4,
                    }
                )

    unique_records: list[dict] = []
    crop_duplicates: list[dict] = []
    for record in raw_records:
        record_hash = int(record["perceptual_hash"], 16)
        duplicate = None
        for kept in unique_records:
            distance = hamming(record_hash, int(kept["perceptual_hash"], 16))
            same_name = key_text(record["ddx_name"]) == key_text(kept["ddx_name"])
            if distance <= 4 or (same_name and distance <= 10):
                duplicate = (kept, distance)
                break
        if duplicate:
            kept, distance = duplicate
            kept.setdefault("additional_sources", []).append(record["source_ref"])
            crop_duplicates.append(
                {
                    "duplicate_source": record["source_ref"],
                    "kept_source": kept["source_ref"],
                    "perceptual_hash_distance": distance,
                }
            )
            (args.output / record["image_file"]).unlink(missing_ok=True)
            continue
        unique_records.append(record)

    for index, record in enumerate(unique_records, start=1):
        record["id"] = f"eq-{index:03d}"
        old_path = args.output / record["image_file"]
        new_name = f'{record["id"]}__{slug(record["ddx_name"])}.png'
        new_path = cards_dir / new_name
        old_path.rename(new_path)
        record["image_file"] = f"cards/{new_name}"
        record.pop("perceptual_hash", None)

    make_contact_sheets(unique_records, args.output)
    (args.output / "raw_catalog.json").write_text(
        json.dumps(unique_records, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    catalog_records = [enrich_record(record) for record in unique_records]
    (args.output / "catalog.json").write_text(
        json.dumps(catalog_records, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (args.output / "duplicates.json").write_text(
        json.dumps(
            {
                "source_duplicates": source_duplicates,
                "card_duplicates": crop_duplicates,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    summary = {
        "source_files": len(source_files),
        "identical_source_files_skipped": len(source_duplicates),
        "raw_cards": len(raw_records),
        "duplicate_cards_skipped": len(crop_duplicates),
        "unique_cards": len(unique_records),
        "cards_needing_name_review": sum(
            bool(record["needs_name_review"]) for record in unique_records
        ),
        "unclassified_cards": sum(
            record["movement_code"] == "unclassified"
            for record in catalog_records
        ),
    }
    (args.output / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()
