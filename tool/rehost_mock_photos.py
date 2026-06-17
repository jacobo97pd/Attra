"""Descarga caras (server-side, sin CORS) y las re-aloja en el bucket de
Firebase Storage del proyecto (que sí tiene CORS), con token de descarga.
Luego actualiza los perfiles mock de seed_profiles con foto principal + galería.

Token de acceso: variable de entorno GTOKEN (gcloud auth print-access-token).
"""
import os
import json
import uuid
import urllib.parse
import urllib.request

TOKEN = os.environ["GTOKEN"]
PROJ = "attra-database"
BUCKET = "attra-database.firebasestorage.app"

# Caras por perfil (randomuser.me: género correcto). Re-alojadas en el bucket.
PROFILES = {
    "mock_lucia": ["women/68", "women/65", "women/90"],
    "mock_sara": ["women/44", "women/12", "women/33"],
    "mock_diego": ["men/32", "men/45", "men/11"],
    "mock_marcos": ["men/75", "men/23", "men/57"],
}


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    return urllib.request.urlopen(req, timeout=30).read()


def upload(path, data):
    tok = str(uuid.uuid4())
    boundary = "===attra_boundary==="
    meta = {
        "name": path,
        "contentType": "image/jpeg",
        "metadata": {"firebaseStorageDownloadTokens": tok},
    }
    body = b""
    body += f"--{boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".encode()
    body += json.dumps(meta).encode() + b"\r\n"
    body += f"--{boundary}\r\nContent-Type: image/jpeg\r\n\r\n".encode()
    body += data + b"\r\n"
    body += f"--{boundary}--".encode()
    url = f"https://storage.googleapis.com/upload/storage/v1/b/{BUCKET}/o?uploadType=multipart"
    req = urllib.request.Request(url, data=body, method="POST", headers={
        "Authorization": f"Bearer {TOKEN}",
        "x-goog-user-project": PROJ,
        "Content-Type": f"multipart/related; boundary={boundary}",
    })
    urllib.request.urlopen(req, timeout=60).read()
    enc = urllib.parse.quote(path, safe="")
    return (
        f"https://firebasestorage.googleapis.com/v0/b/{BUCKET}/o/{enc}?alt=media&token={tok}",
        path,
    )


def patch_doc(doc_id, photo_url, photos):
    fields = {
        "photoUrl": {"stringValue": photo_url},
        "photos": {"arrayValue": {"values": [
            {"mapValue": {"fields": {
                "url": {"stringValue": p["url"]},
                "storagePath": {"stringValue": p["storagePath"]},
                "source": {"stringValue": "mock"},
                "order": {"integerValue": str(i)},
            }}} for i, p in enumerate(photos)
        ]}},
    }
    base = (f"https://firestore.googleapis.com/v1/projects/{PROJ}/databases/"
            f"{PROJ}/documents/seed_profiles/{doc_id}")
    qs = "updateMask.fieldPaths=photoUrl&updateMask.fieldPaths=photos"
    req = urllib.request.Request(
        f"{base}?{qs}",
        data=json.dumps({"fields": fields}).encode(),
        method="PATCH",
        headers={"Authorization": f"Bearer {TOKEN}",
                 "x-goog-user-project": PROJ,
                 "Content-Type": "application/json"},
    )
    urllib.request.urlopen(req, timeout=30).read()


for doc_id, faces in PROFILES.items():
    uploaded = []
    for idx, face in enumerate(faces):
        data = fetch(f"https://randomuser.me/api/portraits/{face}.jpg")
        path = f"seed_profiles/public/{doc_id}/{idx}.jpg"
        url, storage_path = upload(path, data)
        uploaded.append({"url": url, "storagePath": storage_path})
    patch_doc(doc_id, uploaded[0]["url"], uploaded)
    print(f"OK {doc_id}: {len(uploaded)} fotos re-alojadas")
