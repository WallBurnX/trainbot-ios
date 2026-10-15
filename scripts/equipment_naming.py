"""Canonical exercise and machine vocabulary for the DDX equipment catalog."""

from __future__ import annotations

import re
import unicodedata


PANATTA_CATALOG_URL = (
    "https://www.panattasport.com/download/panatta-general-catalogue.pdf"
)
MATRIX_TERMS_URL = (
    "https://us.matrixfitness.com/learning/post/aura-series-movement-videos"
)


def key_text(value: str) -> str:
    value = unicodedata.normalize("NFKC", value or "").lower().replace("ё", "е")
    value = value.replace("×", "x").replace("х", "x")
    return re.sub(r"[^a-zа-я0-9]+", " ", value).strip()


def result(
    exercise: str,
    machine_ru: str,
    machine_en: str,
    category: str,
    movement_code: str,
    aliases: list[str] | None = None,
    confidence: str = "high",
) -> dict:
    return {
        "exercise_canonical_ru": exercise,
        "equipment_canonical_ru": machine_ru,
        "equipment_name_en": machine_en,
        "search_aliases": aliases or [],
        "category": category,
        "movement_code": movement_code,
        "mapping_confidence": confidence,
    }


def classify(ddx_name: str) -> dict:
    k = key_text(ddx_name)

    if k == "гантели":
        return result(
            "Упражнения с гантелями",
            "Стойка с гантелями",
            "Dumbbell Rack",
            "Свободные веса",
            "free_weights",
            ["гантельный ряд", "dumbbells"],
        )

    if "беговая дорожка" in k:
        mechanical = "механическ" in k
        incline = "наклон" in k
        return result(
            "Ходьба / бег на беговой дорожке",
            (
                "Механическая беговая дорожка"
                if mechanical
                else "Беговая дорожка с увеличенным наклоном"
                if incline
                else "Беговая дорожка"
            ),
            (
                "Curved Manual Treadmill"
                if mechanical
                else "Incline Treadmill"
                if incline
                else "Treadmill"
            ),
            "Кардио",
            "cardio_run",
            ["treadmill", "дорожка"],
        )

    if "велотренажер" in k or "сайкл" in k:
        if "air bike" in k:
            machine_ru, machine_en = "Аэробайк", "Air Bike"
        elif "skill bike" in k:
            machine_ru, machine_en = "Спортивный велотренажёр", "Performance Bike"
        elif "сайкл" in k:
            machine_ru, machine_en = "Сайкл-тренажёр", "Indoor Cycle"
        elif "горизонтальн" in k:
            machine_ru, machine_en = (
                "Горизонтальный велотренажёр",
                "Recumbent Bike",
            )
        else:
            machine_ru, machine_en = (
                "Вертикальный велотренажёр",
                "Upright Bike",
            )
        return result(
            "Велотренировка",
            machine_ru,
            machine_en,
            "Кардио",
            "cardio_cycle",
            ["велосипед", machine_en.lower()],
        )

    if "эллиптическ" in k:
        return result(
            "Тренировка на эллипсоиде",
            "Эллиптический тренажёр",
            "Elliptical Trainer / Cross-Trainer",
            "Кардио",
            "cardio_elliptical",
            ["эллипсоид", "cross trainer"],
        )

    if "тренажер лестница" in k:
        return result(
            "Подъём по лестнице",
            "Лестничный тренажёр",
            "Stair Climber / StairMill",
            "Кардио",
            "cardio_stairs",
            ["лестница", "степмил", "stairmaster"],
        )

    if k == "степпер":
        return result(
            "Шаги на степпере",
            "Степпер",
            "Stepper",
            "Кардио",
            "cardio_stepper",
        )

    if "гребной тренажер" in k:
        return result(
            "Гребля на тренажёре",
            "Гребной тренажёр",
            "Rowing Machine / Indoor Rower",
            "Кардио",
            "cardio_row",
            ["гребля", "rower"],
        )

    if "лыжный тренажер" in k:
        return result(
            "Лыжная тяга",
            "Лыжный эргометр",
            "Ski Erg / Ski Trainer",
            "Кардио",
            "cardio_ski",
            ["SkiErg"],
        )

    if "горизонтальная тяга" in k or "тяга т грифа" in k:
        if "т грифа" in k:
            return result(
                "Тяга Т-грифа с упором грудью",
                "Тренажёр Т-гриф с упором грудью",
                "Chest-Supported T-Bar Row",
                "Силовой тренажёр",
                "horizontal_pull",
                ["T-Bar Row", "тяга с упором"],
            )
        if "на верх спины" in k:
            return result(
                "Тяга к груди на верх спины",
                "Тренажёр для высокой горизонтальной тяги",
                "High Row",
                "Силовой тренажёр",
                "horizontal_pull",
                ["High Row", "верхняя тяга к груди"],
            )
        if "рычаж" in k:
            low_row = "нижн" in k
            moving = "подвижн" in k
            return result(
                "Горизонтальная тяга в рычажном тренажёре",
                (
                    "Рычажный тренажёр для нижней горизонтальной тяги"
                    if low_row
                    else "Рычажный тренажёр с подвижными рукоятями для горизонтальной тяги"
                    if moving
                    else "Рычажный тренажёр для горизонтальной тяги"
                ),
                (
                    "Plate-Loaded Low Row"
                    if low_row
                    else "Diverging Seated Row"
                    if moving
                    else "Plate-Loaded Seated Row / Low Row"
                ),
                "Силовой тренажёр",
                "horizontal_pull",
                ["Low Row", "Seated Row", "тяга сидя"],
            )
        return result(
            "Тяга горизонтального блока сидя",
            "Блочный тренажёр для горизонтальной тяги сидя",
            "Seated Cable Row / Low Row",
            "Силовой тренажёр",
            "horizontal_pull",
            ["Low Row", "Seated Row", "тяга нижнего блока"],
        )

    if "вертикальная тяга" in k or "гибридная вертикальная тяга" in k:
        if "гибрид" in k:
            return result(
                "Вертикальная тяга в гибридном тренажёре",
                "Гибридный тренажёр для вертикальной тяги",
                "Hybrid Lat Pulldown",
                "Силовой тренажёр",
                "vertical_pull",
                ["Lat Pulldown"],
            )
        if "рычаж" in k:
            isolated = "изолирован" in k
            return result(
                "Вертикальная тяга в рычажном тренажёре",
                (
                    "Изолатеральный рычажный тренажёр для вертикальной тяги"
                    if isolated
                    else "Рычажный тренажёр для вертикальной тяги"
                ),
                "Iso-Lateral Lat Pulldown"
                if isolated
                else "Plate-Loaded Lat Pulldown / High Row",
                "Силовой тренажёр",
                "vertical_pull",
                ["Lat Pulldown", "тяга сверху"],
            )
        return result(
            "Тяга верхнего блока",
            "Блочный тренажёр для вертикальной тяги",
            "Lat Pulldown",
            "Силовой тренажёр",
            "vertical_pull",
            ["тяга верхнего блока", "Lat Machine"],
        )

    if "x тяга" in k:
        lever = "рычаж" in k
        supported = "упор" in k
        return result(
            "Вертикальная тяга независимыми руками",
            (
                "Рычажный тренажёр для независимой вертикальной тяги"
                if lever
                else "Блочный тренажёр для независимой вертикальной тяги"
            ),
            "Independent Lat Pulldown"
            if not supported
            else "Chest-Supported Independent Lat Pulldown",
            "Силовой тренажёр",
            "vertical_pull",
            ["X-Pulldown", "Dual Lat Pulldown"],
        )

    if "пулловер" in k:
        return result(
            "Пуловер в тренажёре",
            "Тренажёр для пуловера",
            "Pullover Machine",
            "Силовой тренажёр",
            "shoulder_extension",
            ["pullover"],
        )

    if "гравитрон" in k:
        return result(
            "Подтягивания / отжимания на брусьях с противовесом",
            "Гравитрон",
            "Assisted Chin / Dip Machine",
            "Силовой тренажёр",
            "assisted_bodyweight",
            ["гравитрон", "dip chin assist"],
        )

    if "жим ногами" in k:
        angled = "углом" in k
        lever = "рычаж" in k
        return result(
            "Жим ногами в тренажёре",
            (
                "Тренажёр для жима ногами под углом"
                if angled
                else "Рычажный тренажёр для жима ногами"
                if lever
                else "Блочный тренажёр для жима ногами"
            ),
            (
                "45-Degree Leg Press"
                if angled
                else "Plate-Loaded Leg Press"
                if lever
                else "Selectorized Leg Press"
            ),
            "Силовой тренажёр",
            "leg_press",
            ["Leg Press", "жим платформы"],
        )

    if "сгибание разгибание голени" in k:
        return result(
            "Сгибание / разгибание ног в тренажёре",
            "Комбинированный тренажёр для сгибания и разгибания ног",
            "Leg Extension / Leg Curl Combo",
            "Силовой тренажёр",
            "knee_flexion_extension",
            ["leg curl extension combo"],
        )

    if "сгибание голени" in k:
        if "лежа" in k:
            variant_ru, variant_en = "лёжа", "Lying Leg Curl"
        elif "стоя" in k:
            variant_ru, variant_en = "стоя", "Standing Leg Curl"
        else:
            variant_ru, variant_en = "сидя", "Seated Leg Curl"
        return result(
            f"Сгибание ног {variant_ru} в тренажёре",
            f"Тренажёр для сгибания ног {variant_ru}",
            variant_en,
            "Силовой тренажёр",
            "knee_flexion",
            ["Leg Curl", "сгибание бёдер"],
        )

    if "разгибание голени" in k:
        return result(
            "Разгибание ног в тренажёре",
            (
                "Изолатеральный тренажёр для разгибания ног"
                if "независим" in k
                else "Тренажёр для разгибания ног"
            ),
            "Iso-Lateral Leg Extension"
            if "независим" in k
            else "Leg Extension",
            "Силовой тренажёр",
            "knee_extension",
            ["Leg Extension", "разгибание колена"],
        )

    if "отведение приведение бедер" in k or "тренажер для бедер" in k:
        return result(
            "Отведение / приведение ног в тренажёре",
            "Комбинированный тренажёр для отведения и приведения бёдер",
            "Hip Abductor / Adductor Combo",
            "Силовой тренажёр",
            "hip_abduction_adduction",
            ["абдуктор аддуктор", "inner outer thigh"],
        )

    if "отведение бедер" in k:
        standing = "стоя" in k
        return result(
            "Отведение ноги в сторону в тренажёре"
            if standing
            else "Отведение бёдер в тренажёре",
            "Тренажёр для отведения бедра стоя"
            if standing
            else "Тренажёр для отведения бёдер",
            "Standing Hip Abductor" if standing else "Hip Abductor Machine",
            "Силовой тренажёр",
            "hip_abduction",
            ["Abductor", "отведение ног"],
        )

    if "приведение бедер" in k:
        return result(
            "Приведение бёдер в тренажёре",
            "Тренажёр для приведения бёдер",
            "Hip Adductor Machine",
            "Силовой тренажёр",
            "hip_adduction",
            ["Adductor", "сведение ног"],
        )

    if "разгибание бедра" in k:
        return result(
            "Разгибание бедра / отведение ноги назад",
            "Тренажёр для разгибания бедра стоя",
            "Standing Glute Kickback / Hip Extension",
            "Силовой тренажёр",
            "hip_extension",
            ["Glute Kickback", "ягодичная маховая машина"],
        )

    if "ягодичный мост" in k:
        standing = "стоя" in k
        return result(
            "Ягодичный мост / разгибание бедра"
            if not standing
            else "Разгибание бедра стоя",
            "Тренажёр для ягодичного моста"
            if not standing
            else "Рычажный тренажёр для разгибания бедра стоя",
            "Hip Thrust / Glute Drive"
            if not standing
            else "Standing Hip Thrust",
            "Силовой тренажёр",
            "hip_extension",
            ["Hip Thrust", "Glute Drive", "ягодичный мост"],
        )

    if "жим от плеч" in k and "подъем на носки" in k:
        return result(
            "Жим от плеч / подъём на носки",
            "Комбинированный тренажёр для жима от плеч и подъёма на носки",
            "Viking Press / Calf Raise",
            "Силовой тренажёр",
            "vertical_push_calf",
            ["Viking Press", "Calf Raise"],
        )

    if "гакк присед" in k and "подъем на носки" in k:
        return result(
            "Гакк-приседания / подъём на носки",
            "Комбинированный гакк-тренажёр для приседа и подъёма на носки",
            "Hack Squat / Calf Raise Combo",
            "Силовой тренажёр",
            "squat_calf",
            ["Hack Squat", "Calf Raise"],
        )

    if "подъем на носки" in k or "подъём на носки" in ddx_name.lower():
        return result(
            "Подъём на носки в тренажёре",
            "Тренажёр для подъёма на носки",
            "Calf Raise Machine",
            "Силовой тренажёр",
            "ankle_plantar_flexion",
            ["Calf Raise", "икры"],
        )

    if "сгибание разгибание стопы" in k:
        return result(
            "Сгибание / разгибание стопы в тренажёре",
            "Тренажёр для сгибания и разгибания стопы",
            "Ankle Flexion / Extension Machine",
            "Силовой тренажёр",
            "ankle_flexion_extension",
            ["голеностоп", "tibialis calf machine"],
        )

    if (
        "гакк присед" in k
        or "маятниковый присед" in k
        or "присед с поясом" in k
        or "тренажер для приседа" in k
    ):
        if "маятников" in k:
            machine_ru, machine_en = "Маятниковый гакк-тренажёр", "Pendulum Squat"
        elif "поясом" in k:
            machine_ru, machine_en = "Тренажёр для приседа с поясом", "Belt Squat"
        elif "становой" in k:
            machine_ru, machine_en = (
                "Комбинированный тренажёр для приседа, становой тяги и шрагов",
                "Squat / Deadlift / Shrug Machine",
            )
        else:
            machine_ru, machine_en = (
                "Комбинированный гакк-тренажёр",
                "Hack Squat / Reverse Hack Squat",
            )
        return result(
            "Приседания в тренажёре",
            machine_ru,
            machine_en,
            "Силовой тренажёр",
            "squat",
            ["Hack Squat", "гакк", "belt squat"],
        )

    if "скольжение выпады" in k or "тренажер для выпадов" in k:
        return result(
            "Выпады в тренажёре",
            "Тренажёр для выпадов",
            "Lunge Machine",
            "Силовой тренажёр",
            "lunge",
            ["Lunges", "выпады"],
        )

    if "становая тяга выпады" in k:
        return result(
            "Становая тяга / выпады в блочном тренажёре",
            "Блочный тренажёр для становой тяги и выпадов",
            "Cable Deadlift / Lunge Machine",
            "Силовой тренажёр",
            "hinge_lunge",
            ["Deadlift Lunge"],
        )

    if "зашагиван" in k:
        return result(
            "Зашагивания на платформу в тренажёре",
            "Тренажёр для зашагиваний",
            "Step-Up Machine",
            "Силовой тренажёр",
            "step_up",
            ["Step Up"],
        )

    if "жим от груди" in k or "мультивертикальный жим" in k:
        incline = "углом" in k or "наклон" in k
        lying = "лежа" in k
        standing = "стоя" in k
        lever = "рычаж" in k
        wide = "широк" in k
        exercise = (
            "Жим от груди в тренажёре под углом"
            if incline
            else "Жим от груди лёжа в тренажёре"
            if lying
            else "Жим от груди стоя в тренажёре"
            if standing
            else "Жим от груди в тренажёре"
        )
        machine_ru = (
            "Рычажный тренажёр для наклонного жима от груди"
            if lever and incline
            else "Рычажный тренажёр для жима от груди широким хватом"
            if lever and wide
            else "Рычажный тренажёр для жима от груди"
            if lever
            else "Тренажёр для жима от груди под углом"
            if incline
            else "Блочный тренажёр для жима от груди"
        )
        machine_en = (
            "Plate-Loaded Incline Chest Press"
            if lever and incline
            else "Plate-Loaded Chest Press"
            if lever
            else "Incline Chest Press"
            if incline
            else "Chest Press"
        )
        return result(
            exercise,
            machine_ru,
            machine_en,
            "Силовой тренажёр",
            "horizontal_push",
            ["Chest Press", "жим сидя"],
        )

    if "жим от плеч" in k:
        return result(
            "Жим от плеч в тренажёре",
            "Рычажный тренажёр для жима от плеч"
            if "рычаж" in k
            else "Блочный тренажёр для жима от плеч",
            "Plate-Loaded Shoulder Press"
            if "рычаж" in k
            else "Shoulder Press",
            "Силовой тренажёр",
            "vertical_push",
            ["Shoulder Press", "Deltoid Press"],
        )

    if "жим на брусья" in k:
        return result(
            "Отжимания на брусьях в тренажёре",
            "Рычажный тренажёр для отжиманий на брусьях"
            if "рычаж" in k
            else "Блочный тренажёр для отжиманий на брусьях",
            "Plate-Loaded Dip Press" if "рычаж" in k else "Dip Press",
            "Силовой тренажёр",
            "dip_push",
            ["Dips Press", "отжимания сидя"],
        )

    if "приведение плеча бабочка" in k:
        return result(
            "Сведение рук в тренажёре",
            "Тренажёр для сведения рук",
            "Pec Deck / Pectoral Machine",
            "Силовой тренажёр",
            "shoulder_horizontal_adduction",
            ["бабочка", "Chest Fly", "Pec Deck"],
        )

    if "приведение плеча лежа" in k:
        return result(
            "Сведение рук лёжа в тренажёре",
            "Рычажный тренажёр для сведения рук лёжа",
            "Lying Chest Fly Machine",
            "Силовой тренажёр",
            "shoulder_horizontal_adduction",
            ["Chest Fly"],
        )

    if "приведение отведение плеча" in k or "отведение приведение плеча" in k:
        return result(
            "Сведение / разведение рук в тренажёре",
            (
                "Рычажный комбинированный тренажёр для груди и задних дельт"
                if "рычаж" in k
                else "Комбинированный блочный тренажёр для груди и задних дельт"
            ),
            "Pec Deck / Rear Delt Combo",
            "Силовой тренажёр",
            "shoulder_horizontal_adduction_abduction",
            ["Pec Fly Rear Delt", "бабочка обратная бабочка"],
        )

    if "горизонтальное отведение плеча" in k:
        return result(
            "Разведение рук назад в тренажёре",
            "Тренажёр для задних дельт",
            "Rear Delt Fly / Reverse Pec Deck",
            "Силовой тренажёр",
            "shoulder_horizontal_abduction",
            ["Rear Delt", "обратная бабочка"],
        )

    if "отведение плеча" in k or k == "дельтоид":
        return result(
            "Отведение рук в стороны в тренажёре",
            "Тренажёр для средних дельт",
            "Lateral Raise Machine",
            "Силовой тренажёр",
            "shoulder_abduction",
            ["Lateral Deltoid", "махи в стороны"],
        )

    if "сгибание предплечья" in k and "скамья" not in k:
        return result(
            "Сгибание рук на бицепс в тренажёре",
            "Тренажёр для сгибания рук на бицепс",
            "Biceps Curl Machine",
            "Силовой тренажёр",
            "elbow_flexion",
            ["Biceps Curl", "бицепс машина"],
        )

    if "разгибание предплечья" in k:
        overhead = "из за головы" in k
        return result(
            "Разгибание рук на трицепс"
            if not overhead
            else "Разгибание рук из-за головы на трицепс",
            "Тренажёр для разгибания рук на трицепс",
            "Overhead Triceps Extension Machine"
            if overhead
            else "Triceps Extension Machine",
            "Силовой тренажёр",
            "elbow_extension",
            ["Triceps Extension", "French Press"],
        )

    if "разгибание спины" in k or "горизонтальная экстензия" in k:
        return result(
            "Разгибание спины в тренажёре",
            "Тренажёр для разгибания спины",
            "Lower Back Extension Machine",
            "Силовой тренажёр",
            "trunk_extension",
            ["Back Extension", "гиперэкстензия"],
        )

    if "обратная гиперэкстензия" in k:
        return result(
            "Обратная гиперэкстензия",
            "Тренажёр для обратной гиперэкстензии",
            "Reverse Hyperextension Machine",
            "Силовой тренажёр",
            "hip_extension",
            ["Reverse Hyper"],
        )

    if "наклонная скамья для экстензии" in k:
        loaded = "блочн" in k
        return result(
            "Гиперэкстензия",
            "Блочный тренажёр для гиперэкстензии"
            if loaded
            else "Скамья для гиперэкстензии 45°",
            "Selectorized Back Extension"
            if loaded
            else "45-Degree Hyperextension Bench",
            "Скамья / стойка",
            "trunk_extension",
            ["римский стул", "hyperextension"],
        )

    if "римская скамья" in k or "скамья для обратной экстензии" in k:
        return result(
            "Гиперэкстензия",
            "Римская скамья / скамья для гиперэкстензии",
            "Roman Chair / Hyperextension Bench",
            "Скамья / стойка",
            "trunk_extension",
            ["римский стул", "back extension bench"],
        )

    if (
        "скручиван" in k
        and "скамья" not in k
        and "стойка" not in k
    ):
        rail = "рельсов" in k
        return result(
            "Скручивания на пресс в тренажёре",
            "Рельсовый тренажёр для скручиваний"
            if rail
            else "Рычажный тренажёр для диагональных скручиваний"
            if "диагональ" in k
            else "Тренажёр для скручиваний",
            "Rail Ab Crunch"
            if rail
            else "Oblique Abdominal Crunch Machine"
            if "диагональ" in k
            else "Abdominal Crunch Machine",
            "Силовой тренажёр",
            "trunk_flexion",
            ["Ab Crunch", "пресс машина"],
        )

    if "скамья скотта" in k or "скамья для сгибания предплечья" in k:
        return result(
            "Сгибание рук на скамье Скотта",
            "Скамья Скотта",
            "Preacher Curl Bench",
            "Скамья / стойка",
            "elbow_flexion",
            ["Preacher Bench", "пюпитр"],
        )

    if "скамья для жима" in k:
        incline = "наклон" in k
        return result(
            "Жим штанги на наклонной скамье"
            if incline
            else "Жим штанги лёжа",
            "Олимпийская наклонная скамья для жима"
            if incline
            else "Олимпийская горизонтальная скамья для жима",
            "Olympic Incline Bench"
            if incline
            else "Olympic Flat Bench",
            "Скамья / стойка",
            "free_weight_press",
            ["Bench Press", "жимовая скамья"],
        )

    if "скамья для армейского жима" in k:
        return result(
            "Жим штанги сидя",
            "Скамья для армейского жима",
            "Military Press Bench",
            "Скамья / стойка",
            "free_weight_vertical_press",
            ["Military Bench"],
        )

    if "скамья для скручиваний" in k or "стойка для скручиваний" in k:
        return result(
            "Скручивания на пресс",
            "Скамья / стойка для скручиваний",
            "Abdominal Bench / Ab Isolator",
            "Скамья / стойка",
            "trunk_flexion",
            ["Sit-Up Bench", "Ab Bench"],
        )

    if "стойка для подъема ног" in k:
        return result(
            "Подъём коленей / ног в упоре",
            "Стойка для подъёма ног"
            + (" с турником и брусьями" if "турник" in k else ""),
            "Vertical Knee Raise / Power Tower",
            "Скамья / стойка",
            "trunk_flexion",
            ["Captain's Chair", "VKР", "Power Tower"],
        )

    if "силовая рама" in k or "силовая стойка" in k:
        return result(
            "Упражнения со штангой в силовой раме",
            "Двойная силовая рама"
            if "двойн" in k
            else "Силовая стойка с помостом и турником"
            if "помост" in k
            else "Силовая рама",
            "Double Power Rack"
            if "двойн" in k
            else "Power Rack with Platform"
            if "помост" in k
            else "Power Rack / Half Rack",
            "Скамья / стойка",
            "free_weights_station",
            ["Power Rack", "Squat Rack"],
        )

    if "скамья универсальная" in k or "стул универсальный" in k:
        return result(
            "Упражнения со свободными весами",
            "Универсальная регулируемая скамья"
            if "скамья" in k
            else "Универсальный тренировочный стул",
            "Adjustable Utility Bench"
            if "скамья" in k
            else "Utility Seat",
            "Скамья / стойка",
            "free_weights_accessory",
            ["Utility Bench", "регулируемая скамья"],
        )

    if "тренажер смита" in k:
        return result(
            "Упражнения в тренажёре Смита",
            "Тренажёр Смита с наклонной скамьёй"
            if "скамь" in k
            else "Тренажёр Смита",
            "Smith Machine with Incline Bench"
            if "скамь" in k
            else "Smith Machine",
            "Многофункциональная станция",
            "guided_barbell",
            ["Smith Machine"],
        )

    if "кроссовер" in k:
        return result(
            "Упражнения на кроссовере",
            "Кроссовер",
            "Cable Crossover",
            "Многофункциональная станция",
            "multi_cable",
            ["Functional Trainer", "блочная рама"],
        )

    if "мультистанция" in k:
        return result(
            "Упражнения на мультистанции",
            "Сдвоенная мультистанция",
            "Dual Multi-Station",
            "Многофункциональная станция",
            "multi_cable",
            ["Multi Gym", "Jungle Machine"],
        )

    if "kinesis" in k:
        return result(
            "Функциональные упражнения на тросах",
            "Многофункциональный комплекс Kinesis",
            "Kinesis Functional Trainer",
            "Многофункциональная станция",
            "multi_cable",
            ["Kinesis", "Functional Trainer"],
        )

    if "стретчинг" in k:
        chain = "передней" if "передн" in k else "задней" if "задн" in k else ""
        return result(
            "Стретчинг " + (f"{chain} цепи" if chain else "в тренажёре"),
            "Тренажёр для стретчинга"
            + (f" {chain} цепи" if chain else ""),
            "Stretching Flexor Bench"
            if chain == "передней"
            else "Stretching Extensor Bench"
            if chain == "задней"
            else "Stretching Machine",
            "Мобильность / стретчинг",
            "mobility",
            ["stretching bench"],
        )

    return result(
        ddx_name,
        ddx_name,
        "",
        "Требует классификации",
        "unclassified",
        [],
        "review",
    )


def enrich_record(record: dict) -> dict:
    enriched = dict(record)
    enriched.update(classify(record.get("ddx_name", "")))
    brand = record.get("brand", "")
    if brand == "Panatta":
        enriched["terminology_source_url"] = PANATTA_CATALOG_URL
    elif brand == "Matrix":
        enriched["terminology_source_url"] = MATRIX_TERMS_URL
    else:
        enriched["terminology_source_url"] = PANATTA_CATALOG_URL
    return enriched
