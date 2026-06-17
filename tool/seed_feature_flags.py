"""Siembra/actualiza el documento config/featureFlags en attra-database via
Firestore REST con token de owner (bypassa reglas; el doc es write:false para
clientes). Sincronizado con MonetizationFeatureFlags.fromMap.

Requiere env GTOKEN (gcloud auth print-access-token).
"""
import os
import json
import urllib.request

TOKEN = os.environ["GTOKEN"]
PROJ = "attra-database"
HDR = {
    "Authorization": f"Bearer {TOKEN}",
    "x-goog-user-project": PROJ,
    "Content-Type": "application/json",
}

# Defaults seguros para lanzamiento: monetizacion e IA ON, kill switch OFF.
FLAGS = {
    "monetizationEnabled": ("booleanValue", True),
    "attrasEnabled": ("booleanValue", True),
    "plusEnabled": ("booleanValue", True),
    "premiumEnabled": ("booleanValue", True),
    "proAiEnabled": ("booleanValue", True),
    "visualSearchEnabled": ("booleanValue", True),
    "visualTraitFiltersEnabled": ("booleanValue", True),
    "aiProcessingEnabled": ("booleanValue", True),
    "aiKillSwitch": ("booleanValue", False),
    "weeklyFreeAttras": ("integerValue", "0"),
    "plusMonthlyAttras": ("integerValue", "3"),
    "premiumMonthlyAttras": ("integerValue", "10"),
    "proMonthlyAttras": ("integerValue", "15"),
}

fields = {k: {t: v} for k, (t, v) in FLAGS.items()}

base = (f"https://firestore.googleapis.com/v1/projects/{PROJ}/databases/"
        f"{PROJ}/documents/config/featureFlags")
mask = "&".join(f"updateMask.fieldPaths={k}" for k in FLAGS)

req = urllib.request.Request(
    f"{base}?{mask}",
    data=json.dumps({"fields": fields}).encode(),
    method="PATCH",
    headers=HDR,
)
resp = urllib.request.urlopen(req).read().decode()
print("OK config/featureFlags sembrado:")
print(json.dumps(json.loads(resp).get("fields", {}), indent=2)[:400])
