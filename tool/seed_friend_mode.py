"""Siembra datos MOCK de Modo Amigos para poder VER cómo se ve todo:

  - Perfiles en modo amigos en `seed_profiles` (intentMode friends|both|groups
    + socialInterests). Sin geo, así aparecen en el feed de cualquier usuario de
    España al cambiar a "Amistad"/"Ambas" (el filtro de género no aplica en
    amistad). isBot=true para que `fetchSeedProfiles` los recoja.
  - Grupos en `friendGroups` (varias ciudades/intereses, status open) para que la
    pantalla de Grupos muestre recomendados.

NO toca perfiles reales, users ni discovery de nadie. Idempotente (PATCH por id).

Requiere env GTOKEN (gcloud auth print-access-token). Uso:
  GTOKEN=$(gcloud auth print-access-token) python tool/seed_friend_mode.py
"""
import os
import json
import unicodedata
import urllib.request
from datetime import datetime, timezone


def slug(name):
    norm = unicodedata.normalize("NFKD", name)
    return "".join(c for c in norm if not unicodedata.combining(c)).lower()


TOKEN = os.environ["GTOKEN"]
PROJ = "attra-database"
HDR = {
    "Authorization": f"Bearer {TOKEN}",
    "x-goog-user-project": PROJ,
    "Content-Type": "application/json",
}
NOW = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class Ts:
    def __init__(self, iso):
        self.iso = iso


def to_value(v):
    if isinstance(v, Ts):
        return {"timestampValue": v.iso}
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


def man_photo(i):
    return f"https://randomuser.me/api/portraits/men/{i}.jpg"


def woman_photo(i):
    return f"https://randomuser.me/api/portraits/women/{i}.jpg"


def patch(collection, doc_id, data):
    fields = {k: to_value(v) for k, v in data.items()}
    mask = "&".join(f"updateMask.fieldPaths={k}" for k in data)
    url = (f"https://firestore.googleapis.com/v1/projects/{PROJ}/databases/"
           f"{PROJ}/documents/{collection}/{doc_id}?{mask}")
    req = urllib.request.Request(
        url, data=json.dumps({"fields": fields}).encode(),
        method="PATCH", headers=HDR)
    urllib.request.urlopen(req).read()


# (nombre, edad, género, ciudad, puesto, empresa, bio, socialInterests, intentMode, foto)
FRIEND_PROFILES = [
    ("Leo", 28, "male", "Madrid", "Diseñador", "Freelance",
     "Busco gente para planes de finde y quedadas.",
     ["senderismo", "fotografia", "cerveza"], "friends", man_photo(41)),
    ("Nora", 26, "female", "Madrid", "Bioquímica", "CSIC",
     "Nueva en la ciudad, con ganas de hacer amigos.",
     ["cafe", "arte", "cine"], "friends", woman_photo(41)),
    ("Bruno", 31, "male", "Barcelona", "Cocinero", "El Nou",
     "Cocinillas buscando compis de cenas.",
     ["gastronomia", "musica", "viajes"], "friends", man_photo(42)),
    ("Vega", 24, "female", "Valencia", "Estudiante", "UV",
     "Deporte y planes de playa a tope.",
     ["running", "playa", "yoga"], "friends", woman_photo(42)),
    ("Iker", 30, "male", "Madrid", "Ingeniero", "Indra",
     "Abierto a lo que surja, citas o amistad.",
     ["escalada", "cine", "cocina"], "both", man_photo(43)),
    ("Sofía", 29, "female", "Barcelona", "Abogada", "Cuatrecasas",
     "Planes con buena conversación.",
     ["lectura", "vino", "arte"], "both", woman_photo(43)),
    ("Mateo", 27, "male", "Sevilla", "Fotógrafo", "Freelance",
     "Rutas en moto y conciertos.",
     ["moto", "musica", "fotografia"], "both", man_photo(44)),
    ("Candela", 25, "female", "Madrid", "Community manager", "Agencia",
     "Me flipan los planes en grupo.",
     ["juegos", "cerveza", "planes"], "groups", woman_photo(44)),
    ("Unai", 33, "male", "Bilbao", "Profesor", "UPV",
     "Senderismo en grupo cada finde.",
     ["senderismo", "montaña", "naturaleza"], "groups", man_photo(45)),
    ("Lucía", 28, "female", "Madrid", "Enfermera", "Hospital La Paz",
     "Quedadas para hacer deporte.",
     ["deporte", "running", "gym"], "groups", woman_photo(45)),
]


# (nombre, ciudad, descripción, intereses, [miembros mock], max, status)
GROUPS = [
    ("Senderismo por la sierra", "Madrid",
     "Rutas fáciles cada sábado por la mañana. Todos los niveles.",
     ["senderismo", "naturaleza", "fotografia"],
     ["unai", "leo"], 8, "open"),
    ("Cine de autor", "Madrid",
     "Vemos una peli a la semana y la comentamos con unas cañas.",
     ["cine", "cultura", "debate"],
     ["nora", "iker"], 6, "open"),
    ("Runners de mañana", "Barcelona",
     "Salimos a correr antes del trabajo. Ritmo tranquilo.",
     ["running", "deporte", "cafe"],
     ["sofia", "bruno"], 10, "open"),
    ("Cenas y tapas", "Valencia",
     "Probamos sitios nuevos cada quince días.",
     ["gastronomia", "comida", "planes"],
     ["vega"], 8, "open"),
    ("Escalada indoor", "Madrid",
     "Rocódromo entre semana, para engancharse.",
     ["escalada", "deporte", "fitness"],
     ["iker", "lucia"], 6, "open"),
    ("Fotografía urbana", "Sevilla",
     "Paseos con cámara por el casco antiguo.",
     ["fotografia", "arte", "paseo"],
     ["mateo"], 5, "open"),
    ("Board games night", "Barcelona",
     "Noches de juegos de mesa y cerveza artesana.",
     ["juegos", "planes", "cerveza"],
     ["candela", "sofia"], 8, "open"),
    ("Música en directo", "Madrid",
     "Vamos juntos a conciertos pequeños de la ciudad.",
     ["musica", "conciertos", "copas"],
     ["candela", "leo", "lucia"], 12, "open"),
]


def build_profile(name, age, gender, city, job, company, bio, social, mode, photo):
    return {
        "uid": f"mock_fm_{slug(name)}",
        "isBot": True,
        "botProfileVersion": 1,
        "botScenario": "friend_mode",
        "seedQualityScore": 80,
        "displayName": name,
        "age": age,
        "gender": gender,
        # interestedIn vacío = no restringe por género (en amistad da igual).
        "interestedIn": [],
        "orientation": [],
        "bio": bio,
        "currentCity": city,
        "currentCountryName": "España",
        "jobTitle": job,
        "company": company,
        "interests": social,
        "socialInterests": social,
        "intentMode": mode,
        "photoUrl": photo,
        "photos": [{"url": photo, "storagePath": "", "source": "mock", "order": 0}],
    }


def main():
    for p in FRIEND_PROFILES:
        d = build_profile(*p)
        patch("seed_profiles", d["uid"], d)
        print(f"OK perfil {d['uid']}: {d['intentMode']} · {d['currentCity']}")

    for i, (name, city, desc, interests, members, mx, status) in enumerate(GROUPS, 1):
        gid = f"mock_group_{i:02d}"
        member_ids = [f"mock_fm_{m}" for m in members]
        creator = member_ids[0]
        doc = {
            "name": name,
            "description": desc,
            "city": city,
            "interests": interests,
            "memberIds": member_ids,
            "pendingIds": [],
            "maxMembers": mx,
            "createdBy": creator,
            "status": status,
            "createdAt": Ts(NOW),
            "updatedAt": Ts(NOW),
        }
        patch("friendGroups", gid, doc)
        print(f"OK grupo {gid}: {name} ({city}, {len(member_ids)}/{mx})")

    print(f"\n{len(FRIEND_PROFILES)} perfiles + {len(GROUPS)} grupos mock sembrados.")


if __name__ == "__main__":
    main()
