"""Siembra perfiles de prueba con historias VIVAS en tres ciudades.

Para qué: probar a fondo Discover, el muro de historias, el filtro de radio y
el modo viaje con datos que se parecen a los de verdad. Tres ciudades bien
separadas a propósito:

  - Valencia (España)  -> cerca del usuario de pruebas: SÍ debe salir en el feed
  - Nueva York (EEUU)  -> otro país y a 6000 km: NO debe salir salvo modo viaje
  - São Paulo (Brasil) -> otro continente: igual que Nueva York

Esa separación es la gracia: si un perfil de Nueva York aparece estando en
Valencia, el filtro de radio o el de país está roto.

MEDIOS: se REUTILIZAN los ficheros que ya están en Storage en vez de subir
otros. Así las historias se reproducen de verdad (un vídeo inventado no se
reproduce) y no se engorda el bucket con material de prueba.

    GTOKEN=$(gcloud auth print-access-token) python tool/seed_test_cities.py
    # --dry-run para ver qué crearía sin escribir nada.
    # --clean  para BORRAR los perfiles e historias que sembró (prefijo test_).

Todo lo que crea lleva el prefijo `test_` en el id, así que se distingue de un
vistazo y se puede limpiar sin tocar a nadie real.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

TOKEN = os.environ["GTOKEN"]
PROJECT = "attra-database"
BASE = (
    f"https://firestore.googleapis.com/v1/projects/{PROJECT}"
    f"/databases/{PROJECT}/documents"
)
HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "x-goog-user-project": PROJECT,
    "Content-Type": "application/json",
}

DRY_RUN = "--dry-run" in sys.argv
CLEAN = "--clean" in sys.argv
PREFIX = "test_"

# 72 h es el TTL real de una historia (STORY_TTL_MS en functions/src/stories.ts).
# Se siembran con 60 h por delante para que sobrevivan a un par de días de
# pruebas sin caducar a mitad.
STORY_TTL_HOURS = 60

CIUDADES = (
    {
        "clave": "valencia",
        "ciudad": "Valencia",
        "pais": "España",
        "iso2": "ES",
        # Coordenadas redondeadas a 2 decimales, igual que las publica
        # DiscoveryPublisher: ~1,1 km de precisión y nunca la posición exacta.
        "lat": 39.47,
        "lng": -0.38,
    },
    {
        "clave": "nyc",
        "ciudad": "Nueva York",
        "pais": "Estados Unidos",
        "iso2": "US",
        "lat": 40.71,
        "lng": -74.01,
    },
    {
        "clave": "brasil",
        "ciudad": "São Paulo",
        "pais": "Brasil",
        "iso2": "BR",
        "lat": -23.55,
        "lng": -46.63,
    },
)

# Dos perfiles por ciudad, uno de cada género, para que la prueba sirva sea cual
# sea la preferencia de la cuenta con la que se pruebe.
PERSONAS = (
    {"sufijo": "f", "gender": "female", "interestedIn": ["male"]},
    {"sufijo": "m", "gender": "male", "interestedIn": ["female"]},
)

NOMBRES = {
    ("valencia", "f"): ("Marta Sanchis", 27),
    ("valencia", "m"): ("Hugo Ferrer", 30),
    ("nyc", "f"): ("Ashley Brooks", 28),
    ("nyc", "m"): ("Ethan Miller", 31),
    ("brasil", "f"): ("Larissa Souza", 26),
    ("brasil", "m"): ("Rafael Almeida", 29),
}


def valor(value):
    """Python -> formato de valor de la API REST de Firestore."""
    if value is None:
        return {"nullValue": None}
    if isinstance(value, bool):
        return {"booleanValue": value}
    if isinstance(value, int):
        return {"integerValue": str(value)}
    if isinstance(value, float):
        return {"doubleValue": value}
    if isinstance(value, str):
        return {"stringValue": value}
    if isinstance(value, list):
        return {"arrayValue": {"values": [valor(v) for v in value]}}
    if isinstance(value, dict):
        return {"mapValue": {"fields": {k: valor(v) for k, v in value.items()}}}
    raise TypeError(f"Tipo no soportado: {type(value)}")


def peticion(url, method="GET", body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=HEADERS, method=method)
    try:
        raw = urllib.request.urlopen(req).read().decode()
        return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return {}
        raise RuntimeError(f"{method} {url[:90]} -> {error.code} "
                           f"{error.read().decode()[:200]}") from error


def escribir(coleccion, doc_id, campos):
    if DRY_RUN:
        print(f"  [simulacro] {coleccion}/{doc_id}")
        return
    peticion(
        f"{BASE}/{coleccion}?documentId={doc_id}",
        "PATCH" if False else "POST",
        {"fields": {k: valor(v) for k, v in campos.items()}},
    )


def medios_existentes():
    """URLs de fotos y vídeos ya alojados, para reutilizarlos.

    Sin esto habría que subir material nuevo: más lento, más bucket, y un vídeo
    generado sintéticamente no se reproduce en el visor.
    """
    fotos, videos = [], []
    token = None
    while True:
        url = f"{BASE}/stories?pageSize=300"
        if token:
            url += f"&pageToken={token}"
        page = peticion(url)
        for doc in page.get("documents", []):
            campos = doc.get("fields", {})

            def leer(clave):
                item = campos.get(clave)
                return list(item.values())[0] if item else None

            if leer("videoUrl"):
                videos.append((leer("videoUrl"), leer("thumbnailUrl") or ""))
            elif leer("imageUrl"):
                fotos.append(leer("imageUrl"))
        token = page.get("nextPageToken")
        if not token:
            break
    return fotos, videos


def limpiar():
    """Borra lo sembrado por este script (y solo eso)."""
    borrados = 0
    for coleccion in ("stories", "discovery", "users"):
        token = None
        nombres = []
        while True:
            url = f"{BASE}/{coleccion}?pageSize=300"
            if token:
                url += f"&pageToken={token}"
            page = peticion(url)
            nombres += [d["name"] for d in page.get("documents", [])]
            token = page.get("nextPageToken")
            if not token:
                break
        for nombre in nombres:
            doc_id = nombre.rsplit("/", 1)[1]
            # Las historias llevan el uid del dueño dentro del id.
            if not (doc_id.startswith(PREFIX) or f"_{PREFIX}" in doc_id
                    or PREFIX in doc_id):
                continue
            if not DRY_RUN:
                peticion(f"https://firestore.googleapis.com/v1/{nombre}",
                         "DELETE")
            borrados += 1
    print(f"  {'se borrarían' if DRY_RUN else 'borrados'} {borrados} documentos "
          f"con prefijo {PREFIX}")


def main():
    if CLEAN:
        limpiar()
        return

    fotos, videos = medios_existentes()
    if not fotos or not videos:
        raise SystemExit(
            "No hay medios alojados que reutilizar: sube al menos una historia "
            "de foto y una de vídeo desde la app antes de sembrar."
        )
    print(f"Reutilizando {len(fotos)} fotos y {len(videos)} vídeos ya alojados.\n")

    ahora = datetime.now(timezone.utc)
    caduca = (ahora + timedelta(hours=STORY_TTL_HOURS)).isoformat().replace(
        "+00:00", "Z")

    creados = 0
    for ciudad in CIUDADES:
        print(f"{ciudad['ciudad']} ({ciudad['pais']}):")
        for persona in PERSONAS:
            clave = (ciudad["clave"], persona["sufijo"])
            nombre, edad = NOMBRES[clave]
            uid = f"{PREFIX}{ciudad['clave']}_{persona['sufijo']}"
            foto = fotos[creados % len(fotos)]

            comun = {
                "uid": uid,
                "displayName": nombre,
                "age": edad,
                "gender": persona["gender"],
                "interestedIn": persona["interestedIn"],
                "currentCity": ciudad["ciudad"],
                "currentCountryName": ciudad["pais"],
                "photoUrl": foto,
                "photos": [foto],
                "bio": f"Perfil de prueba en {ciudad['ciudad']}.",
                "isBot": True,
                "intentMode": "dating",
                "traveling": False,
                "verified": False,
                "showDistance": True,
                "showActiveStatus": True,
                "geo": {"lat": ciudad["lat"], "lng": ciudad["lng"]},
                "updatedAt": ahora.isoformat().replace("+00:00", "Z"),
            }

            escribir("users", uid, {
                "uid": uid,
                "displayName": nombre,
                "photoUrl": foto,
                "onboardingCompleted": True,
                "profileCompleted": True,
                "isBot": True,
                "profile": {
                    "currentCity": ciudad["ciudad"],
                    "currentCountryName": ciudad["pais"],
                    "currentCountryIso2": ciudad["iso2"],
                    "gender": persona["gender"],
                    "interestedIn": persona["interestedIn"],
                    "age": edad,
                },
                "location": {
                    "latitude": ciudad["lat"],
                    "longitude": ciudad["lng"],
                },
            })
            escribir("discovery", uid, comun)

            # Dos historias por persona: una FOTO y un VÍDEO. Con las dos se
            # prueba la pila (grosor 2), el paso entre historias y los dos
            # reproductores, que fallan por motivos distintos.
            for indice, tipo in enumerate(("image", "video")):
                marca = int(time.time() * 1000) + creados * 10 + indice
                story_id = f"{marca}_{uid}"
                base = {
                    "storyId": story_id,
                    "ownerUid": uid,
                    "displayName": nombre,
                    "status": "active",
                    "visibility": "discovery",
                    "mediaType": tipo,
                    "caption": "",
                    "viewsCount": 0,
                    "repliesCount": 0,
                    # createdAt separadas para que el orden sea determinista:
                    # la foto primero, el vídeo después.
                    "createdAt": (ahora + timedelta(seconds=indice)).isoformat()
                    .replace("+00:00", "Z"),
                    "expiresAt": caduca,
                }
                if tipo == "image":
                    base.update({
                        "imageUrl": fotos[(creados + indice) % len(fotos)],
                        "durationSeconds": 5,
                    })
                else:
                    url, miniatura = videos[(creados + indice) % len(videos)]
                    base.update({
                        "videoUrl": url,
                        "thumbnailUrl": miniatura,
                        "durationSeconds": 10,
                    })
                escribir("stories", story_id, base)

            print(f"  {nombre:18} {persona['gender']:6} "
                  f"({ciudad['lat']}, {ciudad['lng']})  + 2 historias")
            creados += 1

    print(f"\n{creados} perfiles con {creados * 2} historias vivas "
          f"({STORY_TTL_HOURS} h por delante).")
    if DRY_RUN:
        print("SIMULACRO: no se ha escrito nada.")


if __name__ == "__main__":
    main()
