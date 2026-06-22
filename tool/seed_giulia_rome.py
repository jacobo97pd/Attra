"""Crea o actualiza el perfil mock de Giulia Rossi en Roma.

Requiere GTOKEN con un access token de gcloud. Las fotos se descargan desde
Random User y se realojan en Firebase Storage para evitar dependencias/CORS.
"""

import json
import os
import urllib.error
import urllib.parse
import urllib.request
import uuid


TOKEN = os.environ["GTOKEN"]
PROJECT = "attra-database"
BUCKET = "attra-database.firebasestorage.app"
DOC_ID = "mock_giulia_rossi"
PHOTO_IDS = (79, 82, 96)

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


def fetch_photo(photo_id):
    request = urllib.request.Request(
        f"https://randomuser.me/api/portraits/women/{photo_id}.jpg",
        headers={"User-Agent": "Attra mock profile seeder"},
    )
    return urllib.request.urlopen(request, timeout=30).read()


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
    boundary = "===attra_giulia_boundary==="
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
    return {
        "uid": DOC_ID,
        "isBot": True,
        "botProfileVersion": 2,
        "botScenario": "rome_local",
        "seedQualityScore": 96,
        "displayName": "Giulia Rossi",
        "age": 29,
        "gender": "female",
        "interestedIn": ["male"],
        "orientation": ["straight"],
        "relationshipIntent": "long_term",
        "bio": (
            "Arquitecta, amante del cine italiano y de perderme por Roma "
            "buscando la mejor carbonara."
        ),
        "currentCity": "Roma",
        "currentCityNormalized": "roma",
        "city": "Roma",
        "currentCountryCode": "IT",
        "currentCountryName": "Italia",
        "country": "Italia",
        "jobTitle": "Arquitecta",
        "company": "Studio Forma",
        "educationLevel": "master",
        "heightCm": 168,
        "smoking": "never",
        "drinking": "socially",
        "verified": True,
        "traveling": False,
        "interests": ["arquitectura", "cine", "gastronomia", "arte", "viajes"],
        "geo": {"lat": 41.9028, "lng": 12.4964},
        "location": {
            "latitude": 41.9028,
            "longitude": 12.4964,
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
        "profilePrompts": [
            {
                "question": "Mi rincón favorito de Roma es...",
                "answer": "El Giardino degli Aranci al atardecer.",
                "category": "lifestyle",
                "isActive": True,
            },
            {
                "question": "La cita perfecta sería...",
                "answer": "Un paseo por Trastevere y una cena sin mirar el reloj.",
                "category": "dating",
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
    photos = []
    for index, photo_id in enumerate(PHOTO_IDS):
        path = f"seed_profiles/public/{DOC_ID}/{index}.jpg"
        photos.append(upload_photo(path, fetch_photo(photo_id)))
        print(f"OK foto {index + 1}: {path}")
    patch_profile(profile_data(photos))
    print(f"OK {DOC_ID}: Giulia Rossi, Roma, Italia")


if __name__ == "__main__":
    main()
