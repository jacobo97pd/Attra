"""Siembra perfiles mock VARIADOS para probar a mano la IA visual.

Por que hace falta: la IA visual ordena por parecido de CARA, y sin variedad
real de caras no se puede saber si funciona. Los mocks anteriores eran
miniaturas de 128 px que se agrupaban entre ellas por compresion y encuadre, no
por parecido: medir con ellos daba numeros bonitos y falsos.

DE DONDE SALEN LAS FOTOS: Wikimedia Commons, retratos con licencia libre, a
700 px. Se curaron A MANO viendolas una a una y descartando fotos de grupo,
retratos pintados, imagenes movidas y caras tapadas, que son justo las que
ensucian una prueba de parecido facial. Aun asi los perfiles quedan marcados
`isBot: true` y con prefijo `test_v`, para que nunca se confundan con gente
real.

SOBRE LOS NOMBRES: son nombres internacionales variados asignados SIN ninguna
correspondencia con la persona de la foto. Aqui no se deduce el origen de nadie
a partir de su cara, ni en este script ni en el codigo de la app.

    GTOKEN=$(gcloud auth print-access-token) python tool/seed_visual_test_profiles.py
    # --dry-run  ver que haria, sin escribir
    # --clean    borrar SOLO lo que sembro este script

Requiere las fotos ya descargadas en ~/attra_ia/caras con los nombres de las
listas HOMBRES / MUJERES.
"""

import json
import os
import sys
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timezone

TOKEN = os.environ["GTOKEN"]
PROJ = "attra-database"
BUCKET = "attra-database.firebasestorage.app"
BASE = f"https://firestore.googleapis.com/v1/projects/{PROJ}/databases/{PROJ}/documents"
HDR = {
    "Authorization": f"Bearer {TOKEN}",
    "x-goog-user-project": PROJ,
    "Content-Type": "application/json",
}
CARAS = os.path.expanduser("~/attra_ia/caras")
PREFIX = "test_v"
DRY = "--dry-run" in sys.argv
CLEAN = "--clean" in sys.argv

# Curadas a mano tras verlas: solo retratos individuales y nitidos.
HOMBRES = ["h01", "h02", "h05", "h06", "h07", "h08", "h10",
           "h11", "h13", "h14", "h15", "h16", "h18", "h20"]
MUJERES = ["m01", "m02", "m03", "m04", "m05", "m06", "m08",
           "m09", "m11", "m12", "m15", "m16", "m18", "m19"]

NOMBRES_H = ["Adam Keller", "Rashid Nasser", "Tomas Vidal", "Marcus Bell",
             "Imran Qureshi", "Nikos Andreou", "Lukas Berg", "Dario Costa",
             "Henrik Sund", "Pavel Novak", "Owen Clarke", "Mateo Rivas",
             "Yusuf Demir", "Andre Laurent"]
NOMBRES_M = ["Ingrid Holm", "Yasmin Haddad", "Clara Wehner", "Nadia Petrova",
             "Elena Marchetti", "Zoe Fischer", "Mei Tanaka", "Astrid Lund",
             "Nora Bianchi", "Sofia Lindqvist", "Paula Ferrer", "Rita Alves",
             "Hanna Weiss", "Lin Zhao"]

# Tres ciudades cercanas entre si: aqui interesa probar el PARECIDO, no el
# filtro de radio, asi que todas deben caer dentro del alcance habitual.
CIUDADES = [
    ("Valencia", "Espana", "ES", 39.47, -0.38),
    ("Madrid", "Espana", "ES", 40.42, -3.70),
    ("Barcelona", "Espana", "ES", 41.39, 2.17),
]


def valor(v):
    if v is None:
        return {"nullValue": None}
    if isinstance(v, bool):
        return {"booleanValue": v}
    if isinstance(v, int):
        return {"integerValue": str(v)}
    if isinstance(v, float):
        return {"doubleValue": v}
    if isinstance(v, str):
        return {"stringValue": v}
    if isinstance(v, list):
        return {"arrayValue": {"values": [valor(x) for x in v]}}
    if isinstance(v, dict):
        return {"mapValue": {"fields": {k: valor(x) for k, x in v.items()}}}
    raise TypeError(str(type(v)))


def pedir(url, method="GET", body=None, headers=None, raw=None):
    data = raw if raw is not None else (
        json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, method=method,
                                 headers=headers or HDR)
    texto = urllib.request.urlopen(req, timeout=90).read().decode()
    return json.loads(texto) if texto else {}


def subir(path, data):
    """Sube a Storage con token de descarga, igual que rehost_mock_photos.py."""
    token = str(uuid.uuid4())
    limite = "===attra_boundary==="
    meta = {
        "name": path,
        "contentType": "image/jpeg",
        "metadata": {"firebaseStorageDownloadTokens": token},
    }
    cuerpo = (
        f"--{limite}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".encode()
        + json.dumps(meta).encode() + b"\r\n"
        + f"--{limite}\r\nContent-Type: image/jpeg\r\n\r\n".encode()
        + data + b"\r\n"
        + f"--{limite}--".encode()
    )
    pedir(
        f"https://storage.googleapis.com/upload/storage/v1/b/{BUCKET}/o?uploadType=multipart",
        "POST",
        raw=cuerpo,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "x-goog-user-project": PROJ,
            "Content-Type": f"multipart/related; boundary={limite}",
        },
    )
    enc = urllib.parse.quote(path, safe="")
    return (f"https://firebasestorage.googleapis.com/v0/b/{BUCKET}/o/{enc}"
            f"?alt=media&token={token}")


def limpiar():
    total = 0
    for coleccion in ("discovery", "users"):
        token = None
        nombres = []
        while True:
            url = f"{BASE}/{coleccion}?pageSize=300"
            if token:
                url += f"&pageToken={token}"
            pagina = pedir(url)
            nombres += [d["name"] for d in pagina.get("documents", [])]
            token = pagina.get("nextPageToken")
            if not token:
                break
        for nombre in nombres:
            if not nombre.rsplit("/", 1)[1].startswith(PREFIX):
                continue
            if not DRY:
                pedir(f"https://firestore.googleapis.com/v1/{nombre}", "DELETE")
            total += 1
    print(f"  {'se borrarian' if DRY else 'borrados'} {total} perfiles {PREFIX}*")


def main():
    if CLEAN:
        limpiar()
        return

    ahora = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    creados = 0
    for genero, claves, nombres in (("male", HOMBRES, NOMBRES_H),
                                    ("female", MUJERES, NOMBRES_M)):
        for indice, clave in enumerate(claves):
            ruta = os.path.join(CARAS, f"{clave}.jpg")
            if not os.path.exists(ruta):
                print(f"  FALTA {ruta}")
                continue
            nombre = nombres[indice % len(nombres)]
            uid = f"{PREFIX}_{clave}"
            ciudad, pais, iso2, lat, lng = CIUDADES[creados % len(CIUDADES)]
            edad = 23 + (creados * 3) % 22

            if DRY:
                print(f"  [simulacro] {uid:12} {nombre:20} {genero:6} {ciudad}")
                creados += 1
                continue

            with open(ruta, "rb") as fichero:
                url = subir(f"mock/{uid}.jpg", fichero.read())

            ficha = {
                "uid": uid,
                "displayName": nombre,
                "age": edad,
                "gender": genero,
                "interestedIn": ["female"] if genero == "male" else ["male"],
                "currentCity": ciudad,
                "currentCountryName": pais,
                "photoUrl": url,
                "photos": [url],
                "bio": f"Perfil de prueba para la IA visual ({ciudad}).",
                "isBot": True,
                "intentMode": "dating",
                "traveling": False,
                "verified": False,
                "showDistance": True,
                "showActiveStatus": True,
                "geo": {"lat": lat, "lng": lng},
                "updatedAt": ahora,
            }
            pedir(f"{BASE}/users?documentId={uid}", "POST", {"fields": {
                "uid": valor(uid),
                "displayName": valor(nombre),
                "photoUrl": valor(url),
                "onboardingCompleted": valor(True),
                "profileCompleted": valor(True),
                "isBot": valor(True),
                "profile": valor({
                    "currentCity": ciudad,
                    "currentCountryName": pais,
                    "currentCountryIso2": iso2,
                    "gender": genero,
                    "age": edad,
                }),
                "location": valor({"latitude": lat, "longitude": lng}),
            }})
            pedir(f"{BASE}/discovery?documentId={uid}", "POST",
                  {"fields": {k: valor(v) for k, v in ficha.items()}})
            print(f"  {nombre:20} {genero:6} {edad}  {ciudad:10} {clave}")
            creados += 1

    print(f"\n{creados} perfiles sembrados.")


if __name__ == "__main__":
    main()
