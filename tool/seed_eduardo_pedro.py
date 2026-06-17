"""Siembra los perfiles de prueba mock_eduardo y mock_pedro en seed_profiles
(attra-database) para probar el reconocimiento/IA visual.

Las fotos ya están subidas a mano en el bucket en:
  seed_profiles/public/mock_eduardo/<archivo>.png
  seed_profiles/public/mock_pedro/<archivo>.png

Este script:
  - localiza la imagen de cada uno y su token de descarga ACTUAL,
  - construye photoUrl (token vigente) + photos[0].storagePath (ruta real),
    para que el feed la muestre Y el backend de IA pueda descargarla via
    Admin SDK (embedding estético con Vertex).

Requiere env GTOKEN (gcloud auth print-access-token). Idempotente (PATCH por id).
"""
import os
import json
import urllib.parse
import urllib.request

TOKEN = os.environ["GTOKEN"]
PROJ = "attra-database"
BUCKET = "attra-database.firebasestorage.app"
HDR = {"Authorization": f"Bearer {TOKEN}", "x-goog-user-project": PROJ}

# (doc_id, nombre, edad, ciudad, pais, puesto, empresa, bio, intereses)
PROFILES = [
    ("mock_eduardo", "Eduardo", 30, "Madrid", "España", "Arquitecto", "Estudio EM",
     "Buen café, planes con amigos y escapadas a la montaña.",
     ["arquitectura", "montaña", "cafe"]),
    ("mock_pedro", "Pedro", 28, "Barcelona", "España", "Desarrollador", "Freelance",
     "Tecnología, gimnasio y conciertos los findes.",
     ["tech", "fitness", "musica"]),
]


def list_images(prefix):
    url = (f"https://storage.googleapis.com/storage/v1/b/{BUCKET}/o"
           f"?prefix={urllib.parse.quote(prefix)}")
    req = urllib.request.Request(url, headers=HDR)
    data = json.load(urllib.request.urlopen(req))
    out = []
    for it in data.get("items", []):
        if not it.get("contentType", "").startswith("image/"):
            continue
        tok = it.get("metadata", {}).get("firebaseStorageDownloadTokens", "")
        if not tok:
            continue
        out.append((it["name"], tok.split(",")[0]))
    out.sort(key=lambda x: x[0])
    return out


def download_url(path, token):
    enc = urllib.parse.quote(path, safe="")
    return (f"https://firebasestorage.googleapis.com/v0/b/{BUCKET}/o/{enc}"
            f"?alt=media&token={token}")


def to_value(v):
    if isinstance(v, bool):
        return {"booleanValue": v}
    if isinstance(v, int):
        return {"integerValue": str(v)}
    if isinstance(v, str):
        return {"stringValue": v}
    if isinstance(v, list):
        return {"arrayValue": {"values": [to_value(x) for x in v]}}
    if isinstance(v, dict):
        return {"mapValue": {"fields": {k: to_value(x) for k, x in v.items()}}}
    raise TypeError(f"tipo no soportado: {type(v)}")


def build(doc_id, name, age, city, country, job, company, bio, interests,
          photo_url, storage_path):
    return {
        "uid": doc_id,
        "isBot": True,
        "botProfileVersion": 1,
        "botScenario": "ai_visual_test",
        "seedQualityScore": 90,
        "displayName": name,
        "age": age,
        "gender": "male",
        # interestedIn vacío en la práctica = "lo quiere todo el mundo": el
        # filtro bidireccional del feed (theyWantMe) los deja pasar para
        # cualquier visor. Aquí ponemos ambos para que aparezcan siempre.
        "interestedIn": ["female", "male"],
        "orientation": ["bi"],
        "bio": bio,
        "currentCity": city,
        "currentCountryName": country,
        "jobTitle": job,
        "company": company,
        "interests": interests,
        "photoUrl": photo_url,
        "photos": [{
            "url": photo_url,
            # storagePath REAL para que el backend de IA (embeddingForUserPhoto)
            # descargue la imagen por Admin SDK y calcule el embedding.
            "storagePath": storage_path,
            "source": "manual",
            "order": 0,
        }],
    }


def patch(doc_id, fields_dict):
    fields = {k: to_value(v) for k, v in fields_dict.items()}
    mask = "&".join(f"updateMask.fieldPaths={k}" for k in fields_dict)
    url = (f"https://firestore.googleapis.com/v1/projects/{PROJ}/databases/"
           f"{PROJ}/documents/seed_profiles/{doc_id}?{mask}")
    req = urllib.request.Request(
        url, data=json.dumps({"fields": fields}).encode(),
        method="PATCH",
        headers={**HDR, "Content-Type": "application/json"})
    urllib.request.urlopen(req).read()


def main():
    for doc_id, *rest in PROFILES:
        name = doc_id.replace("mock_", "")
        imgs = (list_images(f"seed_profiles/public/{doc_id}/")
                or list_images(f"seed_profiles/public/{name}/"))
        if not imgs:
            print(f"-- {doc_id}: SIN foto en el bucket, omitido")
            continue
        path, tok = imgs[0]
        url = download_url(path, tok)
        d = build(doc_id, *rest, url, path)
        patch(doc_id, d)
        print(f"OK {doc_id}: sembrado con foto {path.rsplit('/', 1)[-1]}")

    print("\nListo. Eduardo y Pedro en seed_profiles (isBot=true).")


if __name__ == "__main__":
    main()
