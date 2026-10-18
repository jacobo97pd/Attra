"""Crea o actualiza el perfil mock de Lucía, surfista de Cádiz.

Las fotos son de una persona FICTICIA generada con IA: no hay nadie real detrás
de este perfil. Se leen de una carpeta local (por defecto
`build/seed-photos/mock_lucia_cadiz/`, ignorada por Git), en el orden de la
ficha: 0.jpg es la principal. Se realojan en Firebase Storage con token de
descarga, como el resto de mocks (las URLs externas fallan por CORS en web).

Es un doc aparte de `mock_lucia` (Lucía, 27, Madrid), que ya existía: este no
lo toca.

Uso:
    GTOKEN=$(gcloud auth print-access-token) python tool/seed_lucia_cadiz.py
    python tool/seed_lucia_cadiz.py --dry-run   # enseña el doc, sin escribir
    ... --fotos <carpeta>                       # otra carpeta de fotos
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid


PROJECT = "attra-database"
BUCKET = "attra-database.firebasestorage.app"
DOC_ID = "mock_lucia_cadiz"
DRY = "--dry-run" in sys.argv


def _arg(name, default):
    if name in sys.argv:
        return sys.argv[sys.argv.index(name) + 1]
    return default


PHOTOS_DIR = _arg("--fotos", os.path.join("build", "seed-photos", DOC_ID))
TOKEN = os.environ.get("GTOKEN", "")

AUTH_HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "x-goog-user-project": PROJECT,
}


def firestore_value(value):
    if isinstance(value, bool):
        return {"booleanValue": value}
    if isinstance(value, int):
        return {"integerValue": str(value)}
    if isinstance(value, float):
        return {"doubleValue": value}
    if isinstance(value, str):
        return {"stringValue": value}
    if isinstance(value, list):
        return {"arrayValue": {"values": [firestore_value(v) for v in value]}}
    if isinstance(value, dict):
        return {
            "mapValue": {
                "fields": {key: firestore_value(item) for key, item in value.items()}
            }
        }
    raise TypeError(f"Tipo no soportado: {type(value)}")


def local_photos():
    names = sorted(
        (n for n in os.listdir(PHOTOS_DIR) if n.lower().endswith(".jpg")),
        key=lambda n: int(os.path.splitext(n)[0]),
    )
    if not names:
        raise SystemExit(f"No hay fotos .jpg en {PHOTOS_DIR}")
    return [os.path.join(PHOTOS_DIR, n) for n in names]


def delete_object_if_present(path):
    encoded = urllib.parse.quote(path, safe="")
    request = urllib.request.Request(
        f"https://storage.googleapis.com/storage/v1/b/{BUCKET}/o/{encoded}",
        method="DELETE",
        headers=AUTH_HEADERS,
    )
    try:
        urllib.request.urlopen(request, timeout=30).read()
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise


def upload_photo(path, data):
    delete_object_if_present(path)
    download_token = str(uuid.uuid4())
    boundary = "===attra_lucia_cadiz_boundary==="
    metadata = {
        "name": path,
        "contentType": "image/jpeg",
        "metadata": {"firebaseStorageDownloadTokens": download_token},
    }
    body = (
        f"--{boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"
    ).encode()
    body += json.dumps(metadata).encode() + b"\r\n"
    body += f"--{boundary}\r\nContent-Type: image/jpeg\r\n\r\n".encode()
    body += data + b"\r\n"
    body += f"--{boundary}--".encode()

    request = urllib.request.Request(
        f"https://storage.googleapis.com/upload/storage/v1/b/{BUCKET}/o?uploadType=multipart",
        data=body,
        method="POST",
        headers={
            **AUTH_HEADERS,
            "Content-Type": f"multipart/related; boundary={boundary}",
        },
    )
    urllib.request.urlopen(request, timeout=60).read()
    encoded = urllib.parse.quote(path, safe="")
    return {
        "url": (
            f"https://firebasestorage.googleapis.com/v0/b/{BUCKET}/o/{encoded}"
            f"?alt=media&token={download_token}"
        ),
        "storagePath": path,
    }


def profile_data(photos):
    # Valores con el vocabulario del onboarding y de los filtros (el de
    # `seed_identity_matrix.py` usa otro para "qué busca" y hábitos, y con ese
    # los filtros de Plus no la encontrarían).
    #
    # Sin `verified`: la insignia dice que hay una persona comprobada detrás, y
    # aquí no la hay. Sin etnia ni religión: en la app solo viajan con
    # consentimiento explícito y un mock no consiente.
    return {
        "uid": DOC_ID,
        "isBot": True,
        "botProfileVersion": 2,
        "botScenario": "cadiz_surf",
        "seedQualityScore": 96,
        "displayName": "Lucía",
        "age": 26,
        "gender": "female",
        "interestedIn": ["male"],
        "orientation": ["straight"],
        "intentMode": "dating",
        "relationshipIntent": "serious_relationship",
        "bio": (
            "Fisio de día y surfista cuando el Atlántico deja. Cádiz me tiene "
            "enamorada, pero en cuanto puedo me escapo al norte a subir montes. "
            "Busco a alguien con quien compartir planes sencillos y atardeceres."
        ),
        "currentCity": "Cádiz",
        "currentCityNormalized": "cadiz",
        "currentCountryCode": "ES",
        "currentCountryName": "España",
        "jobTitle": "Fisioterapeuta",
        "company": "Clínica La Caleta",
        "educationLevel": "bachelor",
        "heightCm": 166,
        "lifestyle": {"smoking": "never", "drinking": "socially"},
        "verified": False,
        "traveling": False,
        "showDistance": True,
        "showActiveStatus": True,
        "interests": ["surf", "senderismo", "playa", "viajes", "naturaleza"],
        "socialInterests": ["surf", "senderismo"],
        "geo": {"lat": 36.5271, "lng": -6.2886},
        "location": {
            "latitude": 36.5271,
            "longitude": -6.2886,
            "permissionGranted": True,
            "permissionStatus": "granted",
        },
        "photoUrl": photos[0]["url"],
        "photos": [
            {
                "url": photo["url"],
                "storagePath": photo["storagePath"],
                "source": "mock",
                "order": index,
            }
            for index, photo in enumerate(photos)
        ],
        # Preguntas del catálogo (profile_prompt_catalog.dart), con su id.
        "profilePrompts": [
            {
                "id": "dates_01",
                "question": "Mi cita ideal sería…",
                "answer": (
                    "Surf al amanecer en La Caleta, desayuno con vistas y el "
                    "resto del día sin mirar el móvil."
                ),
                "category": "dates",
                "isActive": True,
            },
            {
                "id": "pers_06",
                "question": "La gente se sorprende cuando descubre que…",
                "answer": "Me levanto a las 6 un sábado por gusto. Si hay olas, claro.",
                "category": "personality",
                "isActive": True,
            },
            {
                "id": "dates_06",
                "question": "Me apunto sin pensarlo a…",
                "answer": "Una ruta por los Picos de Europa con bocata en la cima.",
                "category": "dates",
                "isActive": True,
            },
        ],
    }


def patch_profile(data):
    fields = {key: firestore_value(value) for key, value in data.items()}
    mask = "&".join(f"updateMask.fieldPaths={key}" for key in data)
    url = (
        f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/"
        f"{PROJECT}/documents/seed_profiles/{DOC_ID}?{mask}"
    )
    request = urllib.request.Request(
        url,
        data=json.dumps({"fields": fields}).encode(),
        method="PATCH",
        headers={**AUTH_HEADERS, "Content-Type": "application/json"},
    )
    urllib.request.urlopen(request, timeout=60).read()


def main():
    files = local_photos()
    if DRY:
        fake = [
            {"url": f"<{os.path.basename(f)}>", "storagePath": f"<{f}>"}
            for f in files
        ]
        print(json.dumps(profile_data(fake), ensure_ascii=False, indent=2))
        return
    if not TOKEN:
        raise SystemExit("Falta GTOKEN (gcloud auth print-access-token).")
    photos = []
    for index, file in enumerate(files):
        path = f"seed_profiles/public/{DOC_ID}/{index}.jpg"
        with open(file, "rb") as handle:
            photos.append(upload_photo(path, handle.read()))
        print(f"OK foto {index + 1}/{len(files)}: {path}")
    patch_profile(profile_data(photos))
    print(f"OK {DOC_ID}: Lucía, 26, Cádiz")


if __name__ == "__main__":
    main()
