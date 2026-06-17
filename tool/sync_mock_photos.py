"""Sincroniza las fotos de los perfiles mock (seed_profiles) con los archivos
que existan en el bucket, usando su token de descarga ACTUAL.

Para cada doc `mock_<name>` busca imágenes en:
  seed_profiles/public/<name>/      (prioridad)
  seed_profiles/public/mock_<name>/ (fallback)
y reescribe photoUrl + photos con las URLs correctas (token vigente).

Útil tras subir fotos a mano por la consola de Storage.
Requiere env GTOKEN (gcloud auth print-access-token).
"""
import os
import re
import json
import urllib.parse
import urllib.request

TOKEN = os.environ["GTOKEN"]
PROJ = "attra-database"
BUCKET = "attra-database.firebasestorage.app"
HDR = {"Authorization": f"Bearer {TOKEN}", "x-goog-user-project": PROJ}

DOCS = ["mock_lucia", "mock_sara", "mock_diego", "mock_marcos"]


def list_images(prefix):
    url = (f"https://storage.googleapis.com/storage/v1/b/{BUCKET}/o"
           f"?prefix={urllib.parse.quote(prefix)}")
    data = json.load(urllib.request.urlopen(urllib.request.Request(url, headers=HDR)))
    out = []
    for it in data.get("items", []):
        if not it.get("contentType", "").startswith("image/"):
            continue
        tok = it.get("metadata", {}).get("firebaseStorageDownloadTokens", "")
        if not tok:
            continue
        out.append((it["name"], tok.split(",")[0]))

    def keyfn(item):
        m = re.search(r"/(\d+)\.", item[0])
        return int(m.group(1)) if m else 999
    out.sort(key=keyfn)
    return out


def download_url(path, token):
    enc = urllib.parse.quote(path, safe="")
    return (f"https://firebasestorage.googleapis.com/v0/b/{BUCKET}/o/{enc}"
            f"?alt=media&token={token}")


def patch_doc(doc_id, photo_url, photos):
    fields = {
        "photoUrl": {"stringValue": photo_url},
        "photos": {"arrayValue": {"values": [
            {"mapValue": {"fields": {
                "url": {"stringValue": p["url"]},
                "storagePath": {"stringValue": p["path"]},
                "source": {"stringValue": "manual"},
                "order": {"integerValue": str(i)},
            }}} for i, p in enumerate(photos)
        ]}},
    }
    base = (f"https://firestore.googleapis.com/v1/projects/{PROJ}/databases/"
            f"{PROJ}/documents/seed_profiles/{doc_id}")
    qs = "updateMask.fieldPaths=photoUrl&updateMask.fieldPaths=photos"
    req = urllib.request.Request(
        f"{base}?{qs}", data=json.dumps({"fields": fields}).encode(),
        method="PATCH",
        headers={**HDR, "Content-Type": "application/json"})
    urllib.request.urlopen(req).read()


for doc_id in DOCS:
    name = doc_id.replace("mock_", "")
    imgs = (list_images(f"seed_profiles/public/{name}/")
            or list_images(f"seed_profiles/public/{doc_id}/"))
    if not imgs:
        print(f"-- {doc_id}: sin fotos en el bucket, omitido")
        continue
    photos = [{"url": download_url(path, tok), "path": path} for path, tok in imgs]
    patch_doc(doc_id, photos[0]["url"], photos)
    print(f"OK {doc_id}: {len(photos)} fotos sincronizadas desde {imgs[0][0].rsplit('/',1)[0]}/")
