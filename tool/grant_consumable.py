"""Fija el saldo de consumibles (Boosts y Swipes) de un usuario para pruebas,
escribiendo users/{uid}.wallet.{boosts,swipes} via Firestore REST con token de
owner (bypassa reglas; el saldo es backend-autoritativo).

Uso:
  GTOKEN=$(gcloud auth print-access-token) \
  python tool/grant_consumable.py <uid> <boosts> <swipes>

Ejemplo: python tool/grant_consumable.py abc123 5 50
(En producción los consumibles se abonan tras validar el recibo IAP; esto es
solo para desarrollo/QA.)
"""
import os
import sys
import json
import datetime
import urllib.request

TOKEN = os.environ["GTOKEN"]
PROJ = "attra-database"
HDR = {
    "Authorization": f"Bearer {TOKEN}",
    "x-goog-user-project": PROJ,
    "Content-Type": "application/json",
}

if len(sys.argv) < 4:
    print("uso: grant_consumable.py <uid> <boosts> <swipes>")
    sys.exit(1)

uid = sys.argv[1]
boosts = int(sys.argv[2])
swipes = int(sys.argv[3])
now = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

# wallet es un mapa anidado; la mask con field paths anidados actualiza solo
# esos campos sin pisar el resto del wallet.
fields = {
    "wallet": {"mapValue": {"fields": {
        "boosts": {"integerValue": str(boosts)},
        "swipes": {"integerValue": str(swipes)},
    }}},
    "updatedAt": {"timestampValue": now},
}
mask = ["wallet.boosts", "wallet.swipes", "updatedAt"]

base = (f"https://firestore.googleapis.com/v1/projects/{PROJ}/databases/"
        f"{PROJ}/documents/users/{uid}")
qs = "&".join(f"updateMask.fieldPaths={m}" for m in mask)
req = urllib.request.Request(
    f"{base}?{qs}", data=json.dumps({"fields": fields}).encode(),
    method="PATCH", headers=HDR)
urllib.request.urlopen(req).read()
print(f"OK users/{uid}.wallet -> boosts={boosts}, swipes={swipes}")
