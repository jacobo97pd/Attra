"""Nombres de sitio para los scripts de mantenimiento (sin red).

MISMA normalizacion que `PlaceNames.normalize` (Dart), `normalizePlace`
(functions/src/travel.ts) y tool/gen_geo_assets.mjs: minusculas, sin acentos y
espacios colapsados. Si una copia cambia, los nombres guardados dejan de casar
con el dataset y los centros de viaje o los ISO2 salen mal sin que nada falle.

Lee los assets empaquetados en la app (assets/geo): el mapa nombre -> ISO2 y
las ciudades con su centro, alineadas indice a indice.
"""
from __future__ import annotations

import json
import re
from functools import lru_cache
from pathlib import Path

GEO_DIR = Path(__file__).resolve().parent.parent / "assets" / "geo"

DIACRITICS = {
    "á": "a", "à": "a", "â": "a", "ä": "a", "ã": "a", "å": "a", "ā": "a",
    "é": "e", "è": "e", "ê": "e", "ë": "e", "ē": "e",
    "í": "i", "ì": "i", "î": "i", "ï": "i", "ī": "i",
    "ó": "o", "ò": "o", "ô": "o", "ö": "o", "õ": "o", "ø": "o", "ō": "o",
    "ú": "u", "ù": "u", "û": "u", "ü": "u", "ū": "u",
    "ñ": "n", "ç": "c", "ß": "ss", "œ": "oe", "æ": "ae",
}


def normalize(value: object) -> str:
    lower = (value if isinstance(value, str) else "").lower().strip()
    if not lower:
        return ""
    out = "".join(DIACRITICS.get(ch, ch) for ch in lower)
    return re.sub(r"\s+", " ", out).strip()


def normalize_iso2(value: object) -> str:
    """ISO2 en mayusculas, o "" si no lo es."""
    s = value.strip().upper() if isinstance(value, str) else ""
    return s if re.fullmatch(r"[A-Z]{2}", s) else ""


@lru_cache(maxsize=1)
def _country_names() -> dict[str, str]:
    with open(GEO_DIR / "country_names.json", encoding="utf-8") as fh:
        return json.load(fh)


def iso2_for_country_name(name: object) -> str:
    """ISO2 de un nombre de pais en cualquier idioma del dataset, o ""."""
    key = normalize(name)
    return _country_names().get(key, "") if key else ""


@lru_cache(maxsize=None)
def _cities(iso2: str) -> tuple[list[str], list]:
    try:
        with open(GEO_DIR / "cities" / f"{iso2}.json", encoding="utf-8") as fh:
            names = json.load(fh)
        with open(GEO_DIR / "coords" / f"{iso2}.json", encoding="utf-8") as fh:
            coords = json.load(fh)
    except FileNotFoundError:
        return [], []
    return names, coords


def city_coordinates(iso2: object, city: object) -> tuple[float, float] | None:
    """Centro de `city` en el pais `iso2`, o None (inexistente o ambigua).

    Igual que `GeoRepository.cityCoordinates`: 'Cadiz' y 'Cádiz' dan lo mismo
    y, si nombres y coordenadas no estan alineados, no se da ninguno por bueno.
    """
    code = normalize_iso2(iso2)
    key = normalize(city)
    if not code or not key:
        return None
    names, coords = _cities(code)
    if len(names) != len(coords):
        return None
    for name, point in zip(names, coords):
        if normalize(name) == key:
            if not point:
                return None
            return point[0] / 100, point[1] / 100
    return None
