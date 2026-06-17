"""Despliega firestore.rules a la base con NOMBRE attra-database via la API
REST de firebaserules (firebase deploy no actualiza bases con nombre).

Pasos:
  1. Crea un ruleset con el contenido de firestore.rules.
  2. Apunta el release `cloud.firestore/attra-database` a ese ruleset
     (create; si ya existe -> patch).

Requiere env GTOKEN (gcloud auth print-access-token).
"""
import os
import json
import urllib.request
import urllib.error

TOKEN = os.environ["GTOKEN"]
PROJ = "attra-database"
DB = "attra-database"
RELEASE_ID = f"cloud.firestore/{DB}"
HDR = {
    "Authorization": f"Bearer {TOKEN}",
    "x-goog-user-project": PROJ,
    "Content-Type": "application/json",
}

with open("firestore.rules", "r", encoding="utf-8") as fh:
    rules_source = fh.read()


def call(method, url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers=HDR)
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")


# 1) Crear ruleset
status, ruleset = call(
    "POST",
    f"https://firebaserules.googleapis.com/v1/projects/{PROJ}/rulesets",
    {
        "source": {
            "files": [{"name": "firestore.rules", "content": rules_source}]
        }
    },
)
if status not in (200, 201):
    raise SystemExit(f"Fallo creando ruleset ({status}): {json.dumps(ruleset)}")
ruleset_name = ruleset["name"]
print(f"Ruleset creado: {ruleset_name}")

# 2) Apuntar el release al nuevo ruleset
release_name = f"projects/{PROJ}/releases/{RELEASE_ID}"
status, rel = call(
    "POST",
    f"https://firebaserules.googleapis.com/v1/projects/{PROJ}/releases",
    {"name": release_name, "rulesetName": ruleset_name},
)
if status == 409:
    # Ya existe -> patch
    status, rel = call(
        "PATCH",
        f"https://firebaserules.googleapis.com/v1/{release_name}",
        {"release": {"name": release_name, "rulesetName": ruleset_name}},
    )

if status not in (200, 201):
    raise SystemExit(f"Fallo actualizando release ({status}): {json.dumps(rel)}")

print(f"Release actualizado: {release_name}")
print(f"  -> rulesetName: {rel.get('rulesetName', ruleset_name)}")
print("OK: reglas desplegadas en attra-database.")
