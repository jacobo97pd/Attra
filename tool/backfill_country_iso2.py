"""Rellena el pais COMPARABLE (ISO2) en `discovery` y `seed_profiles`.

Por que: el feed comparaba el pais por NOMBRE, y el nombre llega en el idioma
de cada telefono ('Espanya', 'Spanien') o del selector ('Greece' frente a
'Grecia'). Ahora el backend publica `countryIso2` en cada ficha y el feed
consulta discovery POR PAIS (`where countryIso2 == ...`): una ficha sin el
campo no sale en esa consulta hasta que su dueno vuelva a escribir su
documento. Este script lo deduce del nombre ya publicado para no esperar.

  - discovery/{uid}.countryIso2          (lo que lee el feed y la consulta)
  - seed_profiles/{id}.currentCountryIso2 (los perfiles de prueba)

Solo AÑADE el campo que falta (updateMask), nunca toca nada mas ni crea
documentos. Idempotente: lo que ya tiene codigo se salta.

Uso:
  $env:GTOKEN = gcloud auth print-access-token
  python tool/backfill_country_iso2.py --dry-run     # lee y enseña el plan
  python tool/backfill_country_iso2.py               # escribe
  python tool/backfill_country_iso2.py --collection discovery
"""
from __future__ import annotations

import argparse
import json

from firestore_rest import Rest, access_token, doc_path, from_fields
from geo_names import iso2_for_country_name, normalize_iso2

COLLECTIONS = {
    # coleccion -> campo que se escribe
    "discovery": "countryIso2",
    "seed_profiles": "currentCountryIso2",
}


def existing_iso2(data: dict) -> str:
    profile = data.get("profile") if isinstance(data.get("profile"), dict) else {}
    for value in (
        data.get("countryIso2"),
        data.get("currentCountryIso2"),
        profile.get("currentCountryIso2"),
        data.get("currentCountryCode"),
        profile.get("currentCountryCode"),
    ):
        code = normalize_iso2(value)
        if code:
            return code
    return ""


def plan_patch(collection: str, data: dict) -> tuple[str, dict | None]:
    """(motivo, parche) para un documento. Parche None = no se toca."""
    if existing_iso2(data):
        return "ya_tiene", None
    profile = data.get("profile") if isinstance(data.get("profile"), dict) else {}
    name = data.get("currentCountryName") or profile.get("currentCountryName")
    code = iso2_for_country_name(name)
    if not code:
        return ("sin_pais" if not name else "pais_desconocido"), None
    return "rellenar", {COLLECTIONS[collection]: code}


def main(argv: list[str] | None = None) -> dict:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true",
                        help="Lee y muestra el plan, sin escribir nada.")
    parser.add_argument("--collection", choices=[*COLLECTIONS, "all"],
                        default="all")
    args = parser.parse_args(argv)

    rest = Rest(access_token(), dry_run=args.dry_run)
    targets = list(COLLECTIONS) if args.collection == "all" else [args.collection]
    summary: dict = {}
    for collection in targets:
        patches: list[tuple[str, dict]] = []
        counts: dict[str, int] = {}
        for doc in rest.list_docs(collection):
            data = from_fields(doc.get("fields", {}))
            reason, patch = plan_patch(collection, data)
            counts[reason] = counts.get(reason, 0) + 1
            if patch is not None:
                patches.append((doc_path(doc), patch))
                print(json.dumps({"path": doc_path(doc), "set": patch,
                                  "from": data.get("currentCountryName")},
                                 ensure_ascii=True))
            elif reason == "pais_desconocido":
                print(json.dumps({"path": doc_path(doc), "skip": reason,
                                  "name": data.get("currentCountryName")},
                                 ensure_ascii=True))
        rest.commit_patches(patches)
        summary[collection] = {**counts, "escritos": 0 if args.dry_run
                               else len(patches)}
    print(("SIMULACION: " if args.dry_run else "") + json.dumps(summary))
    return summary


if __name__ == "__main__":
    main()
