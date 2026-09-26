"""Cliente minimo de Firestore REST para los backfills de geo (base CON nombre
`attra-database`, no la default).

Solo lo que necesitan backfill_country_iso2.py y backfill_travel_geo.py: listar
una coleccion, una consulta de igualdad y escrituras parciales (updateMask) en
lotes con `:commit`. En --dry-run se lee pero NUNCA se escribe.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

PROJECT = "attra-database"
DATABASE = "attra-database"
DOC_BASE = f"projects/{PROJECT}/databases/{DATABASE}/documents"
REST_BASE = f"https://firestore.googleapis.com/v1/{DOC_BASE}"
COMMIT_CHUNK = 400


def access_token() -> str:
    token = os.environ.get("GTOKEN", "").strip()
    if token:
        return token
    for executable in ("gcloud", "gcloud.cmd"):
        found = shutil.which(executable)
        if not found:
            continue
        try:
            return subprocess.check_output(
                [found, "auth", "print-access-token"], text=True,
                stderr=subprocess.PIPE).strip()
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue
    raise SystemExit("Falta GTOKEN (gcloud auth print-access-token).")


def from_value(value: dict) -> object:
    if "stringValue" in value:
        return value["stringValue"]
    if "integerValue" in value:
        return int(value["integerValue"])
    if "doubleValue" in value:
        return float(value["doubleValue"])
    if "booleanValue" in value:
        return bool(value["booleanValue"])
    if "timestampValue" in value:
        raw = value["timestampValue"].replace("Z", "+00:00")
        try:
            return datetime.fromisoformat(raw)
        except ValueError:
            return None
    if "arrayValue" in value:
        return [from_value(v) for v in value["arrayValue"].get("values", [])]
    if "mapValue" in value:
        return from_fields(value["mapValue"].get("fields", {}))
    return None


def from_fields(fields: dict) -> dict:
    return {key: from_value(v) for key, v in (fields or {}).items()}


def to_value(value: object) -> dict:
    if value is None:
        return {"nullValue": None}
    if isinstance(value, bool):
        return {"booleanValue": value}
    if isinstance(value, int):
        return {"integerValue": str(value)}
    if isinstance(value, float):
        return {"doubleValue": value}
    if isinstance(value, datetime):
        stamp = value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
        return {"timestampValue": stamp}
    return {"stringValue": str(value)}


def nested_fields(flat: dict) -> dict:
    """{'settings.travel.lat': 1.0} -> campos REST anidados."""
    root: dict = {}
    for path, value in flat.items():
        node = root
        parts = path.split(".")
        for part in parts[:-1]:
            node = node.setdefault(part, {})
        node[parts[-1]] = value

    def convert(node: dict) -> dict:
        return {
            key: ({"mapValue": {"fields": convert(v)}} if isinstance(v, dict)
                  else to_value(v))
            for key, v in node.items()
        }

    return convert(root)


class Rest:
    def __init__(self, token: str, dry_run: bool) -> None:
        self.dry_run = dry_run
        self.headers = {
            "Authorization": f"Bearer {token}",
            "x-goog-user-project": PROJECT,
            "Content-Type": "application/json",
        }
        self.writes = 0

    def _json(self, url: str, method: str = "GET", body: dict | None = None):
        data = None if body is None else json.dumps(body).encode("utf-8")
        request = urllib.request.Request(url, data=data, method=method,
                                         headers=self.headers)
        try:
            return json.load(urllib.request.urlopen(request, timeout=60))
        except urllib.error.HTTPError as error:
            details = error.read().decode(errors="replace")
            raise SystemExit(f"HTTP {error.code}: {details}") from error

    def list_docs(self, collection: str) -> list[dict]:
        docs: list[dict] = []
        token = ""
        while True:
            query = "?pageSize=300"
            if token:
                query += f"&pageToken={urllib.parse.quote(token)}"
            data = self._json(f"{REST_BASE}/{collection}{query}")
            docs.extend(data.get("documents", []))
            token = data.get("nextPageToken", "")
            if not token:
                return docs

    def query_equal(self, collection: str, field: str, value: object) -> list[dict]:
        """Documentos con `field == value`, paginando por nombre."""
        docs: list[dict] = []
        last = None
        while True:
            query: dict = {
                "from": [{"collectionId": collection}],
                "where": {"fieldFilter": {
                    "field": {"fieldPath": field},
                    "op": "EQUAL",
                    "value": to_value(value),
                }},
                "orderBy": [{"field": {"fieldPath": "__name__"}}],
                "limit": 300,
            }
            if last:
                query["startAt"] = {
                    "values": [{"referenceValue": last}], "before": False}
            rows = self._json(f"{REST_BASE}:runQuery", "POST",
                              {"structuredQuery": query})
            page = [r["document"] for r in rows if r.get("document")]
            docs.extend(page)
            if len(page) < 300:
                return docs
            last = page[-1]["name"]

    def commit_patches(self, patches: list[tuple[str, dict]]) -> int:
        """Escrituras parciales [(ruta, {campo.anidado: valor})]. Solo campos
        listados (updateMask) y solo si el documento existe: nunca crea ni pisa
        el resto. En --dry-run no escribe nada."""
        if self.dry_run or not patches:
            return 0
        for offset in range(0, len(patches), COMMIT_CHUNK):
            chunk = patches[offset:offset + COMMIT_CHUNK]
            writes = [{
                "update": {"name": f"{DOC_BASE}/{path}",
                           "fields": nested_fields(flat)},
                "updateMask": {"fieldPaths": list(flat.keys())},
                "currentDocument": {"exists": True},
            } for path, flat in chunk]
            self._json(f"{REST_BASE}:commit", "POST", {"writes": writes})
            self.writes += len(writes)
        return self.writes


def doc_path(doc: dict) -> str:
    return doc["name"].split("/documents/", 1)[1]
