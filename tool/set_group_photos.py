"""Asigna una imagen preset (bundled) a cada grupo de `friendGroups` que aún no
tenga foto, según su nombre/intereses. Deja la app más chula sin subir nada a
Storage (las fotos preset van en assets, se guardan como `asset:<ruta>`).

NO pisa grupos que ya tengan `photoUrl`. Idempotente.

Requiere env GTOKEN (gcloud auth print-access-token de una cuenta con permiso de
escritura en Firestore, p. ej. soporte.attra.app). Uso:
  GTOKEN=$(gcloud auth print-access-token) python tool/set_group_photos.py
"""
import os
import json
import urllib.request

TOKEN = os.environ["GTOKEN"]
PROJ = "attra-database"
BASE = (f"https://firestore.googleapis.com/v1/projects/{PROJ}/databases/"
        f"{PROJ}/documents")
HDR = {
    "Authorization": f"Bearer {TOKEN}",
    "x-goog-user-project": PROJ,
    "Content-Type": "application/json",
}

# Presets disponibles (deben coincidir con assets/images + kGroupPhotoPresets).
DISCO = "asset:assets/images/disco.png"       # fiesta / música / juegos
PAISAJE = "asset:assets/images/paisaje.png"   # aire libre / naturaleza
CINE = "asset:assets/images/cine.png"         # cine
CENA = "asset:assets/images/Cena.png"         # cena / gastronomía / café
PINTURA = "asset:assets/images/pintura.png"   # arte / foto / cultura
DEPORTES = "asset:assets/images/deportes.png"  # deporte / running / escalada


def pick(name, interests):
    s = (name + " " + " ".join(interests)).lower()

    def has(*keys):
        return any(k in s for k in keys)

    if has("sender", "montaña", "montana", "aire", "natur", "ruta", "aventur",
           "playa", "viaje"):
        return PAISAJE
    if has("cine", "peli", "film"):
        return CINE
    if has("escalad", "boulder", "run", "runner", "deporte", "gym", "fit",
           "yoga", "padel", "futbol", "fútbol"):
        return DEPORTES
    if has("cena", "tapas", "gastro", "comida", "vino", "restaur", "cafe",
           "café", "brunch", "cocina"):
        return CENA
    if has("arte", "museo", "cultura", "foto", "expo", "pintura", "lectura"):
        return PINTURA
    if has("mús", "mus", "concier", "directo", "juego", "board", "game",
           "fiesta", "copas", "cerveza", "planes", "quedada"):
        return DISCO
    return DISCO  # por defecto, algo vistoso


def sval(v):
    f = v.get("fields", {})

    def s(k):
        return f.get(k, {}).get("stringValue", "")

    arr = f.get("interests", {}).get("arrayValue", {}).get("values", [])
    interests = [x.get("stringValue", "") for x in arr]
    return s("name"), interests, s("photoUrl")


def patch(doc_id, photo):
    url = (f"{BASE}/friendGroups/{doc_id}?updateMask.fieldPaths=photoUrl")
    body = json.dumps({"fields": {"photoUrl": {"stringValue": photo}}}).encode()
    req = urllib.request.Request(url, data=body, method="PATCH", headers=HDR)
    urllib.request.urlopen(req).read()


def main():
    url = f"{BASE}/friendGroups?pageSize=300"
    req = urllib.request.Request(url, headers=HDR)
    data = json.loads(urllib.request.urlopen(req).read())
    docs = data.get("documents", [])
    done = 0
    for d in docs:
        doc_id = d["name"].split("/")[-1]
        name, interests, photo = sval(d)
        if photo:  # ya tiene foto → no tocar
            print(f"skip {doc_id} ({name}) ya tiene foto")
            continue
        chosen = pick(name, interests)
        patch(doc_id, chosen)
        print(f"OK {doc_id}: {name} -> {chosen.split('/')[-1]}")
        done += 1
    print(f"\n{done} grupos actualizados (de {len(docs)}).")


if __name__ == "__main__":
    main()
