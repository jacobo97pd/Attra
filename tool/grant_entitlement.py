"""Concede un tier (free|plus|pro) a un usuario escribiendo userEntitlements/{uid}
via Firestore REST con token de owner (bypassa reglas; el doc es write:false para
clientes — la concesión SIEMPRE es backend/admin, nunca el cliente).

Uso:
  GTOKEN=$(gcloud auth print-access-token) \
  python tool/grant_entitlement.py <uid> <free|plus|pro> [dias]

Sin [dias] => sin caducidad (para pruebas). Con dias => expiresAt = ahora+dias.
Para QUITAR el plan: grant <uid> free.
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

if len(sys.argv) < 3:
    print("uso: grant_entitlement.py <uid> <free|plus|pro> [dias]")
    sys.exit(1)

uid = sys.argv[1]
tier = sys.argv[2].lower()
if tier not in ("free", "plus", "pro"):
    print("tier inválido (free|plus|pro)")
    sys.exit(1)
days = int(sys.argv[3]) if len(sys.argv) > 3 else None

fields = {
    "tier": {"stringValue": tier},
    "source": {"stringValue": "admin"},
    "isLifetime": {"booleanValue": days is None and tier != "free"},
    "updatedAt": {"timestampValue": datetime.datetime.utcnow()
                  .strftime("%Y-%m-%dT%H:%M:%SZ")},
}
mask = ["tier", "source", "isLifetime", "updatedAt"]
if days is not None:
    exp = datetime.datetime.utcnow() + datetime.timedelta(days=days)
    fields["expiresAt"] = {"timestampValue": exp.strftime("%Y-%m-%dT%H:%M:%SZ")}
    mask.append("expiresAt")

base = (f"https://firestore.googleapis.com/v1/projects/{PROJ}/databases/"
        f"{PROJ}/documents/userEntitlements/{uid}")
qs = "&".join(f"updateMask.fieldPaths={m}" for m in mask)
req = urllib.request.Request(
    f"{base}?{qs}", data=json.dumps({"fields": fields}).encode(),
    method="PATCH", headers=HDR)
urllib.request.urlopen(req).read()
print(f"OK userEntitlements/{uid} -> tier={tier}"
      + (f", {days} días" if days else ", sin caducidad"))
