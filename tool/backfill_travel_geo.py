"""Pone CENTRO a los viajes activos guardados sin coordenadas y apaga los
caducados.

Por que: el feed del viajero se mide desde el centro de la ciudad de destino
(`settings.travel.lat/lng`) y la ficha publica se publica ahi. Los viajes
guardados por versiones anteriores no lo tienen: quien estaba en Madrid y
viajaba a Cadiz seguia viendo (y siendo visto por) toda Espana, Madrid
incluido. La app nueva los repara sola al abrirse; esto repara ya tambien a
quien no la abre, y apaga los viajes cuya fecha ya paso (lo mismo que hace el
barrido horario `sweepTravelModes`).

Por cada `users/{uid}` con `settings.travel.active == true`:
  - viaje caducado (la mas tardia de `untilAt`/`until` en el pasado, o a mas
    de 90 dias vista) -> active=false y se borran centro y LAS DOS fechas
    (pais, ciudad e ISO2 se CONSERVAN, como en la app).
  - sin centro valido y con ciudad -> lat/lng del dataset offline
    (assets/geo), con geoSource='asset' y `geoCity`/`geoIso2` (el destino para
    el que se resolvio). Ciudad ambigua o desconocida: se deja a nivel de pais.
Nunca escribe coordenadas REALES: solo el centro de la ciudad de destino.

Ya NO añade `untilAt` a los viajes que solo tienen el `until` ISO: el backend
y la app ya lo leen, y las versiones anteriores de la app (las unicas que
dejan viajes asi) nunca lo reescriben. Un `untilAt` añadido aqui se quedaba
fijo: al reactivar o alargar el viaje desde esa version, la fecha vieja
mandaba y el barrido cortaba el viaje semanas antes.

Cada escritura en users/{uid} dispara onUserWrittenSyncDiscovery, que
republica la ficha: no hace falta llamar a backfillDiscovery.

Uso:
  $env:GTOKEN = gcloud auth print-access-token
  python tool/backfill_travel_geo.py --dry-run      # lee y enseña el plan
  python tool/backfill_travel_geo.py                # escribe
"""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timedelta, timezone

from firestore_rest import Rest, access_token, doc_path, from_fields
from geo_names import (city_coordinates, iso2_for_country_name, normalize,
                       normalize_iso2)

T = "settings.travel"

# Igual que MAX_TRAVEL_MS del backend (discovery.ts) y TravelRules del
# cliente: la app escribe 30 dias; un fin mas lejano no es creible.
MAX_TRAVEL = timedelta(days=90)


def _as_utc(value: object) -> datetime | None:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, str) and value.strip():
        try:
            parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
        except ValueError:
            return None
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    return None


def _parse_until(travel: dict) -> datetime | None:
    """La MAS TARDIA de `untilAt` y `until` (como travelUntilMs del backend).

    Antes mandaba `untilAt`: con una version antigua que solo renueva `until`,
    la fecha vieja ganaba.
    """
    dates = [d for d in (_as_utc(travel.get("untilAt")),
                         _as_utc(travel.get("until"))) if d is not None]
    return max(dates) if dates else None


def _has_valid_center(travel: dict) -> bool:
    """Centro creible Y del destino actual (travelCenter del backend).

    Sin ciudad no hay centro, y si `geoCity`/`geoIso2` existen tienen que casar
    con `city`/`iso2`: una version antigua que cambia de ciudad no toca
    lat/lng, y ese centro viejo no puede contar como situado.
    """
    lat, lng = travel.get("lat"), travel.get("lng")
    if not (isinstance(lat, (int, float)) and isinstance(lng, (int, float))
            and not isinstance(lat, bool) and not isinstance(lng, bool)
            and abs(lat) <= 90 and abs(lng) <= 180):
        return False
    city = normalize(travel.get("city"))
    if not city:
        return False
    geo_city = travel.get("geoCity")
    if isinstance(geo_city, str) and normalize(geo_city) != city:
        return False
    geo_iso2 = travel.get("geoIso2")
    if (isinstance(geo_iso2, str)
            and normalize_iso2(geo_iso2) != normalize_iso2(travel.get("iso2"))):
        return False
    return True


def plan_travel_patch(travel: dict, now: datetime) -> tuple[str, dict | None]:
    """(accion, parche con rutas completas) para un `settings.travel`."""
    if travel.get("active") is not True:
        return "inactivo", None
    until = _parse_until(travel)
    if until is not None and (until <= now or until > now + MAX_TRAVEL):
        # Mismo parche que travelDeactivationPatch del backend: tambien el
        # `until` ISO, o reactivar el viaje (version antigua, seed de la demo)
        # lo dejaba caducado otra vez.
        return "apagar", {
            f"{T}.active": False,
            f"{T}.until": None,
            f"{T}.untilAt": None,
            f"{T}.lat": None,
            f"{T}.lng": None,
            f"{T}.geoCity": None,
            f"{T}.geoIso2": None,
            f"{T}.geoSource": "none",
            f"{T}.updatedAt": now,
        }
    patch: dict = {}
    actions: list[str] = []
    city = travel.get("city") if isinstance(travel.get("city"), str) else ""
    if not _has_valid_center(travel) and city.strip():
        iso2 = (normalize_iso2(travel.get("iso2"))
                or iso2_for_country_name(travel.get("country")))
        center = city_coordinates(iso2, city)
        if center is not None:
            patch[f"{T}.lat"] = round(center[0], 4)
            patch[f"{T}.lng"] = round(center[1], 4)
            # El destino para el que vale este centro (ver _has_valid_center).
            patch[f"{T}.geoCity"] = city.strip()
            patch[f"{T}.geoIso2"] = normalize_iso2(travel.get("iso2"))
            patch[f"{T}.geoSource"] = "asset"
            actions.append("situar")
        else:
            actions.append("sin_centro")
    if not patch:
        return ("+".join(actions) or "al_dia"), None
    patch[f"{T}.updatedAt"] = now
    return "+".join(actions), patch


def main(argv: list[str] | None = None, now: datetime | None = None) -> dict:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true",
                        help="Lee y muestra el plan, sin escribir nada.")
    args = parser.parse_args(argv)
    now = now or datetime.now(timezone.utc)

    rest = Rest(access_token(), dry_run=args.dry_run)
    patches: list[tuple[str, dict]] = []
    counts: dict[str, int] = {}
    for doc in rest.query_equal("users", f"{T}.active", True):
        data = from_fields(doc.get("fields", {}))
        settings = data.get("settings") if isinstance(data.get("settings"), dict) else {}
        travel = settings.get("travel") if isinstance(settings.get("travel"), dict) else {}
        action, patch = plan_travel_patch(travel, now)
        counts[action] = counts.get(action, 0) + 1
        if patch is None:
            continue
        patches.append((doc_path(doc), patch))
        printable = {k: (v.isoformat() if isinstance(v, datetime) else v)
                     for k, v in patch.items()}
        print(json.dumps({"path": doc_path(doc), "action": action,
                          "city": travel.get("city"), "set": printable},
                         ensure_ascii=True))
    rest.commit_patches(patches)
    summary = {**counts, "escritos": 0 if args.dry_run else len(patches)}
    print(("SIMULACION: " if args.dry_run else "") + json.dumps(summary))
    return summary


if __name__ == "__main__":
    main()
