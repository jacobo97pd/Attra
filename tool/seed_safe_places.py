"""Siembra lugares recomendados de ejemplo en `safePlaces` (Attra SafeDate F7).

Sitios públicos y concurridos para una primera cita. NUNCA se etiqueta un lugar
como "seguro al 100%": solo "lugar público recomendado" / "colaborador" /
"personal informado del protocolo Attra". Idempotente (PATCH por id).

Requiere env GTOKEN (gcloud auth print-access-token, cuenta con permiso de
escritura en Firestore). Uso:
  GTOKEN=$(gcloud auth print-access-token) python tool/seed_safe_places.py
"""
import os
import json
import urllib.request
from datetime import datetime, timezone


TOKEN = os.environ["GTOKEN"]
PROJ = "attra-database"
HDR = {
    "Authorization": f"Bearer {TOKEN}",
    "x-goog-user-project": PROJ,
    "Content-Type": "application/json",
}
NOW = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class Ts:
    def __init__(self, iso):
        self.iso = iso


def to_value(v):
    if isinstance(v, Ts):
        return {"timestampValue": v.iso}
    if isinstance(v, bool):
        return {"booleanValue": v}
    if isinstance(v, int):
        return {"integerValue": str(v)}
    if isinstance(v, float):
        return {"doubleValue": v}
    if isinstance(v, str):
        return {"stringValue": v}
    if isinstance(v, list):
        return {"arrayValue": {"values": [to_value(x) for x in v]}}
    if isinstance(v, dict):
        return {"mapValue": {"fields": {k: to_value(x) for k, x in v.items()}}}
    raise TypeError(f"tipo no soportado: {type(v)}")


def patch(collection, doc_id, data):
    fields = {k: to_value(v) for k, v in data.items()}
    mask = "&".join(f"updateMask.fieldPaths={k}" for k in data)
    url = (f"https://firestore.googleapis.com/v1/projects/{PROJ}/databases/"
           f"{PROJ}/documents/{collection}/{doc_id}?{mask}")
    req = urllib.request.Request(
        url, data=json.dumps({"fields": fields}).encode(),
        method="PATCH", headers=HDR)
    urllib.request.urlopen(req).read()


# (id, nombre, dirección, lat, lng, categoría, colaborador, protocolo, features)
PLACES = [
    ("madrid_cafe_central", "Café Central", "Plaza del Ángel, 10, Madrid",
     40.4145, -3.7005, "cafe", True, False,
     ["Zona muy concurrida", "Buena iluminación", "Personal cercano"]),
    ("madrid_mercado_sanmiguel", "Mercado de San Miguel",
     "Plaza de San Miguel, s/n, Madrid", 40.4155, -3.7090, "mercado", False,
     False, ["Muy concurrido", "Espacio abierto", "Bien comunicado"]),
    ("madrid_retiro_kiosco", "Kiosco del Retiro",
     "Parque del Retiro, Madrid", 40.4153, -3.6844, "parque", False, False,
     ["Espacio público abierto", "Mucha gente de día"]),
    ("bcn_cafe_federal", "Federal Café", "Carrer del Parlament, 39, Barcelona",
     41.3757, 2.1636, "cafe", True, False,
     ["Zona concurrida", "Terraza a la calle"]),
    ("bcn_bunkers", "Mirador (zona concurrida)",
     "Carrer de Marià Labèrnia, Barcelona", 41.4195, 2.1620, "mirador", False,
     False, ["Espacio público", "Recomendado ir de día"]),
    ("valencia_mercado_colon", "Mercado de Colón",
     "Carrer de Jorge Juan, 19, València", 39.4690, -0.3690, "mercado", True,
     False, ["Muy concurrido", "Espacio abierto", "Céntrico"]),
]


def main():
    for pid, name, addr, lat, lng, cat, partner, protocol, feats in PLACES:
        doc = {
            "name": name,
            "address": addr,
            "latitude": lat,
            "longitude": lng,
            "category": cat,
            "isPartner": partner,
            "staffProtocolEnabled": protocol,
            "safetyFeatures": feats,
            "verificationStatus": "verified" if partner else "listed",
            "updatedAt": Ts(NOW),
        }
        patch("safePlaces", pid, doc)
        print(f"OK safePlace {pid}: {name}")
    print(f"\n{len(PLACES)} lugares recomendados sembrados en safePlaces.")


if __name__ == "__main__":
    main()
