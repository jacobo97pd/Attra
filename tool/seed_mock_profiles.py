"""Siembra 23 perfiles mock de prueba en seed_profiles (attra-database) via
Firestore REST con token de owner (bypassa reglas; seed_profiles es write:false
para clientes).

  5 chicos heteros   (male,   interestedIn=[female], orientation=[straight])
  8 chicas heteros   (female, interestedIn=[male],   orientation=[straight])
  5 chicos gays      (male,   interestedIn=[male],   orientation=[gay])
  5 chicas lesbianas (female, interestedIn=[female], orientation=[lesbian])

Cada uno con 1 sola foto (randomuser.me, real y gendered). isBot=true para que
`fetchSeedProfiles` (where isBot==true) los recoja. NO toca users ni discovery,
asi que los perfiles reales siguen apareciendo igual.

Requiere env GTOKEN (gcloud auth print-access-token).
Idempotente: usa PATCH por id (mock_t_<name>), re-ejecutable.
"""
import os
import json
import unicodedata
import urllib.request


def slug(name):
    """Id ASCII sin tildes (Adrián -> adrian) para la ruta del documento."""
    norm = unicodedata.normalize("NFKD", name)
    return "".join(c for c in norm if not unicodedata.combining(c)).lower()

TOKEN = os.environ["GTOKEN"]
PROJ = "attra-database"
HDR = {
    "Authorization": f"Bearer {TOKEN}",
    "x-goog-user-project": PROJ,
    "Content-Type": "application/json",
}


def to_value(v):
    """Convierte un valor Python al formato tipado de Firestore REST."""
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


# (nombre, edad, ciudad, pais, puesto, empresa, bio, intereses)
HETERO_MEN = [
    ("Carlos", 29, "Madrid", "España", "Ingeniero", "Indra",
     "Running, cañas y planes de finde.", ["deporte", "viajes", "musica"]),
    ("Javier", 33, "Valencia", "España", "Arquitecto", "Estudio JV",
     "Me pierde el mar y la buena comida.", ["surf", "cocina", "arte"]),
    ("Miguel", 27, "Sevilla", "España", "Profesor", "IES Triana",
     "Senderismo y conciertos siempre que puedo.", ["montaña", "musica"]),
    ("Pablo", 31, "Bilbao", "España", "Comercial", "Iberdrola",
     "Pintxos, ciclismo y series.", ["ciclismo", "cine", "gastronomia"]),
    ("Adrián", 25, "Málaga", "España", "Diseñador", "Freelance",
     "Skate, fotografía y café de especialidad.", ["skate", "foto", "cafe"]),
]
GAY_MEN = [
    ("Sergio", 30, "Barcelona", "España", "Enfermero", "Hospital Clínic",
     "Gimnasio, brunch y escapadas.", ["fitness", "viajes", "brunch"]),
    ("Hugo", 28, "Madrid", "España", "Estilista", "Salón Hugo",
     "Moda, baile y buen rollo.", ["moda", "baile", "musica"]),
    ("Iván", 34, "Valencia", "España", "Abogado", "Cuatrecasas",
     "Lector empedernido y runner.", ["lectura", "running", "vino"]),
    ("Rubén", 26, "Sevilla", "España", "Fotógrafo", "Freelance",
     "Cine de autor y rutas en moto.", ["cine", "moto", "foto"]),
    ("Dani", 32, "Zaragoza", "España", "Chef", "La Rebotica",
     "Cocino, viajo y colecciono vinilos.", ["cocina", "musica", "viajes"]),
]
HETERO_WOMEN = [
    ("María", 28, "Madrid", "España", "Médica", "Hospital La Paz",
     "Yoga, viajes y planes con amigas.", ["yoga", "viajes", "lectura"]),
    ("Laura", 31, "Barcelona", "España", "Diseñadora", "Glovo",
     "Arte, café y escapadas de finde.", ["arte", "cafe", "diseño"]),
    ("Carmen", 26, "Sevilla", "España", "Periodista", "Canal Sur",
     "Flamenco, cine y buena conversación.", ["baile", "cine", "musica"]),
    ("Ana", 34, "Valencia", "España", "Ingeniera", "Mercadona",
     "Padel, paella y playa.", ["padel", "playa", "cocina"]),
    ("Elena", 29, "Bilbao", "España", "Profesora", "UPV/EHU",
     "Montaña, libros y planes tranquilos.", ["montaña", "lectura"]),
    ("Valeria", 27, "Madrid", "España", "Product manager", "Cabify",
     "Planes improvisados, rooftops y rutas de brunch.", ["brunch", "viajes", "tech"]),
    ("Inés", 30, "Barcelona", "España", "UX researcher", "Wallapop",
     "Museos pequeños, conciertos indie y conversaciones largas.", ["arte", "musica", "cafe"]),
    ("Clara", 25, "Valencia", "España", "Fisioterapeuta", "Clínica Turia",
     "Playa al atardecer, pilates y cocina mediterránea.", ["pilates", "playa", "cocina"]),
]
LESBIAN_WOMEN = [
    ("Marta", 30, "Madrid", "España", "Psicóloga", "Consulta propia",
     "Senderismo, perros y buena música.", ["montaña", "perros", "musica"]),
    ("Cristina", 27, "Barcelona", "España", "Fotógrafa", "Freelance",
     "Viajo con la cámara siempre encima.", ["foto", "viajes", "arte"]),
    ("Paula", 33, "Valencia", "España", "Veterinaria", "Clínica Animal",
     "Surf, animales y planes al aire libre.", ["surf", "animales"]),
    ("Nuria", 25, "Sevilla", "España", "Ilustradora", "Freelance",
     "Dibujo, conciertos y café.", ["arte", "musica", "cafe"]),
    ("Alba", 32, "Málaga", "España", "Cocinera", "El Pimpi",
     "Cocina, escalada y road trips.", ["cocina", "escalada", "viajes"]),
]


# Coordenadas aproximadas por ciudad para que el feed pueda filtrar por
# distancia (igual que los perfiles reales, que publican geo en discovery).
CITY_COORDS = {
    "Madrid": (40.4168, -3.7038),
    "Barcelona": (41.3874, 2.1686),
    "Valencia": (39.4699, -0.3763),
    "Sevilla": (37.3891, -5.9845),
    "Bilbao": (43.2630, -2.9350),
    "Málaga": (36.7213, -4.4214),
    "Zaragoza": (41.6488, -0.8891),
}


def build(idx, name, age, city, country, job, company, bio, interests,
          gender, interested_in, orientation, photo_url):
    lat, lng = CITY_COORDS.get(city, (None, None))
    doc = {
        "uid": f"mock_t_{slug(name)}",
        "isBot": True,
        "botProfileVersion": 1,
        "botScenario": "test_orientation",
        "seedQualityScore": 80,
        "displayName": name,
        "age": age,
        "gender": gender,
        "interestedIn": interested_in,
        "orientation": orientation,
        "bio": bio,
        "currentCity": city,
        "currentCountryName": country,
        "jobTitle": job,
        "company": company,
        "interests": interests,
        "photoUrl": photo_url,
        "photos": [{
            "url": photo_url,
            "storagePath": "",
            "source": "mock",
            "order": 0,
        }],
    }
    # geo (para distancia en el feed) y location espejo, solo si conocemos la ciudad.
    if lat is not None and lng is not None:
        doc["geo"] = {"lat": lat, "lng": lng}
        doc["location"] = {"latitude": lat, "longitude": lng}
    return doc


def main():
    docs = []
    mi = 1   # indice foto hombres
    wi = 1   # indice foto mujeres
    for grp in HETERO_MEN:
        docs.append(build(mi, *grp, "male", ["female"], ["straight"],
                          man_photo(mi))); mi += 1
    for grp in GAY_MEN:
        docs.append(build(mi, *grp, "male", ["male"], ["gay"],
                          man_photo(mi))); mi += 1
    for grp in HETERO_WOMEN:
        docs.append(build(wi, *grp, "female", ["male"], ["straight"],
                          woman_photo(wi))); wi += 1
    for grp in LESBIAN_WOMEN:
        docs.append(build(wi, *grp, "female", ["female"], ["lesbian"],
                          woman_photo(wi))); wi += 1

    for d in docs:
        doc_id = d["uid"]
        fields = {k: to_value(v) for k, v in d.items()}
        mask = "&".join(f"updateMask.fieldPaths={k}" for k in d)
        url = (f"https://firestore.googleapis.com/v1/projects/{PROJ}/databases/"
               f"{PROJ}/documents/seed_profiles/{doc_id}?{mask}")
        req = urllib.request.Request(
            url, data=json.dumps({"fields": fields}).encode(),
            method="PATCH", headers=HDR)
        urllib.request.urlopen(req).read()
        print(f"OK {doc_id}: {d['gender']}/{d['orientation'][0]}")

    print(f"\n{len(docs)} perfiles mock sembrados en seed_profiles.")


if __name__ == "__main__":
    main()
