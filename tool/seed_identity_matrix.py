"""Siembra en `seed_profiles` la MATRIZ COMPLETA de identidades de Attra.

POR QUE HACE FALTA
------------------
El onboarding deja elegir OCHO identidades de genero (female, male, non_binary,
trans_woman, trans_man, genderfluid, agender, other), DIEZ orientaciones y
CUATRO modos de intencion (dating, friends, both, groups). Los perfiles mock que
habia en la base solo usaban DOS generos: female y male. Resultado: cualquiera
que no fuera un hombre hetero o una mujer hetero podia terminar el onboarding y
encontrarse el feed vacio, sin que nada estuviera "roto".

El filtro de genero del feed es BIDIRECCIONAL (FeedFilter.apply): yo tengo que
buscarte a ti Y tu tienes que buscarme a mi. Asi que para que NADIE se quede sin
ver perfiles hacen falta, como minimo, las 3x3 combinaciones de
(casilla de genero del candidato) x (casilla de genero que el candidato busca).
Este script siembra las 8 identidades x las 3 casillas de "a quien buscas" = 24
perfiles, mas extras para las orientaciones y los modos que faltaban.

Ver tambien lib/src/features/profile/domain/gender_matching.dart: la traduccion
de identidad a casilla vive alli y este script la respeta.

SOBRE LAS FOTOS
---------------
Salen de ~/attra_ia/caras, las mismas de tool/seed_visual_test_profiles.py:
retratos de Wikimedia Commons con licencia libre, a 700 px, curados a mano. Se
usan estas y no las miniaturas de randomuser.me porque la IA visual ordena por
parecido de CARA y con miniaturas de 128 px la prueba da numeros bonitos y
falsos (se agrupan por compresion y encuadre, no por parecido).

Los nombres son internacionales variados y NO tienen ninguna correspondencia con
la persona de la foto. Las fotos tampoco definen la identidad del perfil: para
las identidades fuera del binario se reparten de todo el conjunto, porque no
existe una cara "de persona no binaria" y elegirla por genero seria inventarse
un estereotipo. Todos los perfiles van con isBot=true y prefijo `mock_ix_`.

USO
---
    GTOKEN=$(gcloud auth print-access-token) python tool/seed_identity_matrix.py
    # --dry-run   ensena que haria, sin escribir ni subir nada
    # --clean     borra SOLO los perfiles que sembro este script
    # --sin-fotos usa randomuser.me en vez de subir las caras locales
    #             (sirve para poblar el feed; NO sirve para juzgar la IA visual)

Idempotente: PATCH por id determinista, re-ejecutable sin duplicar.
"""

import json
import os
import sys
import unicodedata
import urllib.parse
import urllib.request
import uuid

PROJ = "attra-database"
BUCKET = "attra-database.firebasestorage.app"
BASE = (f"https://firestore.googleapis.com/v1/projects/{PROJ}/databases/"
        f"{PROJ}/documents")
CARAS = os.path.expanduser("~/attra_ia/caras")
PREFIJO = "mock_ix_"

DRY = "--dry-run" in sys.argv
CLEAN = "--clean" in sys.argv
SIN_FOTOS = "--sin-fotos" in sys.argv

# Se lee sin exigirlo: asi el modulo se puede importar desde los tests
# sin credenciales. Quien intente escribir de verdad sin token se estrella
# en la primera peticion, que es donde tiene que enterarse.
TOKEN = os.environ.get("GTOKEN", "")
HDR = {
    "Authorization": f"Bearer {TOKEN}",
    "x-goog-user-project": PROJ,
    "Content-Type": "application/json",
}

# --- Identidades ---------------------------------------------------------
# (valor, etiqueta en la app, conjunto de fotos)
#   "m" = conjunto m01..m20, "h" = conjunto h01..h20, "x" = todo el conjunto.
# Una mujer trans es una mujer y un hombre trans es un hombre, asi que sus
# fotos salen del mismo sitio que las de cualquier otra mujer u hombre.
IDENTIDADES = [
    ("female", "Mujer", "m"),
    ("male", "Hombre", "h"),
    ("non_binary", "No binario", "x"),
    ("trans_woman", "Mujer trans", "m"),
    ("trans_man", "Hombre trans", "h"),
    ("genderfluid", "Genero fluido", "x"),
    ("agender", "Agenero", "x"),
    ("other", "Otro", "x"),
]

# Las tres unicas casillas que sabe expresar `interestedIn`.
CASILLAS = ["female", "male", "non_binary"]

# Casilla que representa a cada identidad (espejo de GenderMatching.bucketsFor).
CASILLA_DE = {
    "female": "female", "trans_woman": "female",
    "male": "male", "trans_man": "male",
    "non_binary": "non_binary", "genderfluid": "non_binary",
    "agender": "non_binary",
    "other": "any",
}

# Nombres por casilla, no por identidad concreta: una mujer trans lleva nombre
# de mujer y un hombre trans, de hombre. Las identidades fuera del binario
# llevan nombres que se usan indistintamente, que es lo que hace la gente.
# Un mock llamado "Bruno" con ficha de mujer se lee como un error del sistema,
# y quien revisa la app no tiene por que saber que es solo un indice mal
# repartido. Los apellidos son variados y NO guardan relacion con la foto.
NOMBRES = {
    "female": [
        "Alba Ferrer", "Lena Vogel", "Rita Almeida", "Vera Pavlova",
        "Yara Haddad", "Zoe Fischer", "Gala Puig", "Hanna Weiss",
        "Jana Ruiz", "Cira Longhi", "Tessa Bruin", "Uma Chandra",
    ],
    "male": [
        "Bruno Salas", "Eneko Arrieta", "Hugo Bianchi", "Jonas Lindqvist",
        "Mateo Rivas", "Omar Belkacem", "Xavi Colomer", "Ben Castell",
        "Fabio Duarte", "Ivo Marchetti", "Quim Serrano", "Dani Estevez",
    ],
    "neutro": [
        "Cleo Marin", "Dara Oliveira", "Kai Moreau", "Noa Sterling",
        "Sam Okafor", "Wren Ashby", "Elis Karlsson", "Kim Andersen",
        "Alex Duran", "Robin Vidal", "Ariel Sosa", "Charlie Nunes",
        "Andrea Leal", "Remy Fontaine", "Sasha Ivanova", "Nico Ferrand",
    ],
}

OFICIOS = [
    ("Fisioterapeuta", "Clinica Norte"), ("Ilustradora", "Estudio Pez"),
    ("Cocinero", "Casa Lucia"), ("Data analyst", "Adevinta"),
    ("Enfermere", "Hospital La Paz"), ("Luthier", "Taller Serrano"),
    ("Profesora", "IES Cervantes"), ("Arquitecto", "Estudio Ribas"),
    ("Veterinaria", "Centro Animal"), ("Sonidista", "Radio Nacional"),
    ("Jardinere", "Vivero El Retiro"), ("Traductora", "Freelance"),
    ("Panadero", "Horno de Lena"), ("Bibliotecarie", "Biblioteca Regional"),
    ("Fotografa", "Freelance"), ("Socorrista", "Piscinas Municipales"),
]

INTERESES = [
    ["senderismo", "cine", "cocina"], ["musica", "conciertos", "vinilos"],
    ["escalada", "viajes", "fotografia"], ["teatro", "lectura", "museos"],
    ["running", "cafe", "podcasts"], ["ceramica", "plantas", "mercadillos"],
    ["natacion", "ajedrez", "series"], ["bici", "camping", "astronomia"],
    ["baile", "idiomas", "brunch"], ["surf", "yoga", "huerto"],
]

PREGUNTAS = [
    ("un_plan_perfecto", "Un plan perfecto para mi es...",
     "Mercado por la manana, comida larga y siesta sin alarma."),
    ("me_delata", "Lo que mas me delata es...",
     "Que me se el menu entero antes de que llegue el camarero."),
    ("nunca_digo_no", "Nunca digo que no a...",
     "Una playlist compartida en un viaje largo en coche."),
    ("aprendiendo", "Ahora mismo estoy aprendiendo...",
     "A hacer pan. Llevo cuatro intentos y tres ladrillos."),
]

# Espana, porque es donde estan el resto de mocks y donde apunta el modo viajes
# de las cuentas de revision. La matriz entera va a Madrid con dispersion corta
# para que quepa dentro del radio por defecto (100 km) de alguien en Madrid; los
# extras se reparten para que la lista no parezca un pueblo de clones.
MADRID = ("Madrid", 40.4168, -3.7038)
OTRAS = [
    ("Barcelona", 41.3874, 2.1686),
    ("Valencia", 39.4699, -0.3763),
    ("Sevilla", 37.3891, -5.9845),
    ("Bilbao", 43.2630, -2.9350),
]
PAIS = "España"


def slug(texto):
    norm = unicodedata.normalize("NFKD", texto)
    limpio = "".join(c for c in norm if not unicodedata.combining(c))
    return "".join(c if c.isalnum() else "_" for c in limpio.lower())


def valor(v):
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
    raise TypeError(f"tipo no soportado: {type(v)}")


def pedir(url, method="GET", body=None, headers=None, raw=None):
    data = raw if raw is not None else (
        json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, method=method,
                                 headers=headers or HDR)
    texto = urllib.request.urlopen(req, timeout=90).read().decode()
    return json.loads(texto) if texto else {}


def subir(path, data):
    """Sube la foto a Storage con token de descarga (igual que el resto de
    scripts de siembra) y devuelve la URL publica."""
    token = str(uuid.uuid4())
    limite = "===attra_boundary==="
    meta = {
        "name": path,
        "contentType": "image/jpeg",
        "metadata": {"firebaseStorageDownloadTokens": token},
    }
    cuerpo = (
        f"--{limite}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"
        .encode() + json.dumps(meta).encode() + b"\r\n"
        + f"--{limite}\r\nContent-Type: image/jpeg\r\n\r\n".encode()
        + data + b"\r\n" + f"--{limite}--".encode()
    )
    pedir(
        f"https://storage.googleapis.com/upload/storage/v1/b/{BUCKET}/o"
        f"?uploadType=multipart",
        "POST", raw=cuerpo,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "x-goog-user-project": PROJ,
            "Content-Type": f"multipart/related; boundary={limite}",
        },
    )
    enc = urllib.parse.quote(path, safe="")
    return (f"https://firebasestorage.googleapis.com/v0/b/{BUCKET}/o/{enc}"
            f"?alt=media&token={token}")


def caras_disponibles():
    """Las caras curadas, separadas por conjunto de origen."""
    if not os.path.isdir(CARAS):
        return {"h": [], "m": []}
    ficheros = sorted(f for f in os.listdir(CARAS) if f.endswith(".jpg"))
    return {
        "h": [f for f in ficheros if f.startswith("h")],
        "m": [f for f in ficheros if f.startswith("m")],
    }


def orientacion_de(gender, busca):
    """Orientacion coherente con la identidad y con a quien busca.

    No es decorativa: el perfil se ensena y una etiqueta que contradiga al
    resto de la ficha se lee como un mock mal hecho.
    """
    casilla = CASILLA_DE.get(gender, "any")
    if casilla == "non_binary" or busca == "non_binary" or casilla == "any":
        return ["queer"]
    if casilla == "female":
        return ["straight"] if busca == "male" else ["lesbian"]
    return ["straight"] if busca == "female" else ["gay"]


def construir():
    """Devuelve la lista de fichas a sembrar, en orden estable."""
    fichas = []

    # --- 1. La matriz: 8 identidades x 3 casillas de "a quien busco" -----
    # Esto es lo que garantiza que NADIE se quede con el feed vacio.
    for identidad, etiqueta, conjunto in IDENTIDADES:
        for busca in CASILLAS:
            fichas.append({
                "gender": identidad,
                "interestedIn": [busca],
                "orientation": orientacion_de(identidad, busca),
                "intentMode": "dating",
                "conjunto": conjunto,
                "escenario": f"matriz_{identidad}_{busca}",
                "nota": f"{etiqueta}, busca {busca}",
            })

    # --- 2. Orientaciones que la matriz no llega a cubrir ----------------
    # La matriz sale hetero/gay/lesbiana/queer por construccion. Estas seis
    # existen en el onboarding y no aparecian en NINGUN perfil de la base.
    extras = [
        ("female", ["female", "male"], ["bisexual"], "dating", "m"),
        ("non_binary", ["female", "male", "non_binary"], ["pansexual"],
         "dating", "x"),
        ("male", ["female"], ["asexual"], "dating", "h"),
        ("trans_woman", ["male"], ["demisexual"], "dating", "m"),
        ("trans_man", ["female", "male"], ["questioning"], "dating", "h"),
        ("agender", ["non_binary"], ["other"], "dating", "x"),
    ]
    for gender, busca, orient, modo, conjunto in extras:
        fichas.append({
            "gender": gender, "interestedIn": busca, "orientation": orient,
            "intentMode": modo, "conjunto": conjunto,
            "escenario": f"orientacion_{orient[0]}",
            "nota": f"{gender}, {orient[0]}",
        })

    # --- 3. Modos de intencion ------------------------------------------
    # En amistad el genero NO filtra (FeedFilter: solo filtra en solape de
    # dating), asi que con pocos perfiles se cubre. `groups` no sale en el
    # feed de personas: su superficie son los grupos.
    modos = [
        ("female", ["male"], "friends", "m"),
        ("male", ["female"], "friends", "h"),
        ("non_binary", ["non_binary"], "friends", "x"),
        ("trans_man", ["female"], "both", "h"),
        ("female", ["female", "male"], "both", "m"),
        ("male", ["female"], "groups", "h"),
        ("genderfluid", ["non_binary"], "groups", "x"),
    ]
    for gender, busca, modo, conjunto in modos:
        # Buscar a mas de una casilla no es "hetero de la primera que salga":
        # la etiqueta tiene que decir lo mismo que la ficha.
        orient = ["bisexual"] if len(busca) > 1 \
            else orientacion_de(gender, busca[0])
        fichas.append({
            "gender": gender, "interestedIn": busca,
            "orientation": orient,
            "intentMode": modo, "conjunto": conjunto,
            "escenario": f"modo_{modo}",
            "nota": f"{gender}, modo {modo}",
        })

    return fichas


def completar(fichas, caras):
    """Rellena nombre, edad, ciudad, foto y el resto de campos del esquema."""
    # Una cara, un perfil. Si dos perfiles comparten foto, la IA visual les da
    # parecido perfecto entre si y la prueba deja de medir nada.
    #
    # Reparto en DOS PASADAS: primero los perfiles atados a un conjunto
    # concreto ("h"/"m") y solo despues los que pueden tirar de cualquiera
    # ("x"). Al reves, los "x" arrasaban con las caras del principio de la lista
    # y los perfiles que si necesitaban ese conjunto se quedaban sin ninguna.
    gastadas = set()
    caras_por_indice = {}
    for vuelta in ("hm", "x"):
        for indice, ficha in enumerate(fichas):
            es_x = ficha["conjunto"] == "x"
            if (vuelta == "hm") == es_x:
                continue
            disponibles = (caras["h"] + caras["m"]) if es_x \
                else caras[ficha["conjunto"]]
            libres = [c for c in disponibles if c not in gastadas]
            if libres:
                caras_por_indice[indice] = libres[0]
                gastadas.add(libres[0])
            elif disponibles:
                # Mas perfiles que caras: se repite, pero avisando, porque a
                # partir de aqui el parecido facial deja de ser fiable.
                caras_por_indice[indice] = disponibles[indice %
                                                       len(disponibles)]
                print(f"  AVISO: se agotaron las caras, el perfil {indice} "
                      f"repite {caras_por_indice[indice]}")

    contador_nombres = {"female": 0, "male": 0, "neutro": 0}
    completas = []

    for indice, ficha in enumerate(fichas):
        casilla = CASILLA_DE.get(ficha["gender"], "any")
        grupo = casilla if casilla in ("female", "male") else "neutro"
        pool = NOMBRES[grupo]
        nombre = pool[contador_nombres[grupo] % len(pool)]
        contador_nombres[grupo] += 1
        uid = PREFIJO + slug(nombre.split()[0]) + "_" + str(indice).zfill(2)
        cara = caras_por_indice.get(indice)

        # Edades repartidas de 19 a 58: cubre los extremos del filtro de edad
        # por los dos lados, que con todos los mocks entre 25 y 35 no se probaba.
        edad = 19 + (indice * 7) % 40
        oficio, empresa = OFICIOS[indice % len(OFICIOS)]

        # La matriz entera se queda en Madrid, con dispersion corta para caer
        # dentro del radio por defecto. Los extras se reparten por otras
        # ciudades: con el modo viajes puesto en Espana se ven todos igual.
        if ficha["escenario"].startswith("matriz_"):
            ciudad, lat, lng = MADRID
            lat += ((indice % 7) - 3) * 0.03
            lng += ((indice % 5) - 2) * 0.03
        else:
            ciudad, lat, lng = OTRAS[indice % len(OTRAS)]

        pregunta = PREGUNTAS[indice % len(PREGUNTAS)]
        completas.append({
            **ficha,
            "uid": uid,
            "displayName": nombre,
            "edad": edad,
            "ciudad": ciudad,
            "lat": round(lat, 4),
            "lng": round(lng, 4),
            "oficio": oficio,
            "empresa": empresa,
            "intereses": INTERESES[indice % len(INTERESES)],
            "pregunta": pregunta,
            "cara": cara,
            "indice": indice,
        })
    return completas


def documento(f, url_foto):
    """La ficha en el esquema PLANO que lee SeedProfile.fromMap."""
    # Variedad en los filtros avanzados para que se puedan probar de verdad.
    # ethnicity y religion se dejan FUERA a proposito: son datos sensibles que
    # en la app solo viajan con consentimiento explicito, y un mock no consiente.
    fuma = ["no", "sometimes", "no", "yes"][f["indice"] % 4]
    bebe = ["socially", "no", "socially", "yes"][f["indice"] % 4]
    estudios = ["bachelor", "master", "vocational", "phd",
                "high_school"][f["indice"] % 5]
    meta = ["long_term", "casual", "friendship",
            "unsure"][f["indice"] % 4]

    datos = {
        "uid": f["uid"],
        "displayName": f["displayName"],
        "age": f["edad"],
        "gender": f["gender"],
        "interestedIn": f["interestedIn"],
        "orientation": f["orientation"],
        "intentMode": f["intentMode"],
        "bio": f"{f['nota']}. Perfil de prueba de Attra.",
        "jobTitle": f["oficio"],
        "company": f["empresa"],
        "currentCity": f["ciudad"],
        "currentCountryName": PAIS,
        "geo": {"lat": f["lat"], "lng": f["lng"]},
        "location": {"latitude": f["lat"], "longitude": f["lng"]},
        "interests": f["intereses"],
        "socialInterests": f["intereses"][:2],
        "relationshipIntent": meta,
        "educationLevel": estudios,
        "heightCm": 155 + (f["indice"] * 3) % 45,
        "lifestyle": {"smoking": fuma, "drinking": bebe},
        "verified": f["indice"] % 5 == 0,
        "traveling": False,
        "showDistance": True,
        "showActiveStatus": True,
        "photoUrl": url_foto,
        "photos": [{
            "url": url_foto,
            "storagePath": "",
            "source": "mock",
            "order": 0,
        }],
        "profilePrompts": [{
            "id": f["pregunta"][0],
            "question": f["pregunta"][1],
            "answer": f["pregunta"][2],
            "isActive": True,
        }],
        "isBot": True,
        "botProfileVersion": 1,
        "botScenario": f["escenario"],
        "seedQualityScore": 80,
    }
    return datos


def limpiar():
    total = 0
    token = None
    nombres = []
    while True:
        url = f"{BASE}/seed_profiles?pageSize=300"
        if token:
            url += f"&pageToken={token}"
        pagina = pedir(url)
        nombres += [d["name"] for d in pagina.get("documents", [])]
        token = pagina.get("nextPageToken")
        if not token:
            break
    for nombre in nombres:
        if not nombre.rsplit("/", 1)[1].startswith(PREFIJO):
            continue
        if not DRY:
            pedir(f"https://firestore.googleapis.com/v1/{nombre}", "DELETE")
        total += 1
    print(f"  {'se borrarian' if DRY else 'borrados'} {total} perfiles "
          f"{PREFIJO}*")


def resumen(fichas):
    """Comprobacion de cobertura: que la matriz cubre lo que dice cubrir."""
    from collections import Counter
    generos = Counter(f["gender"] for f in fichas)
    orientaciones = Counter(o for f in fichas for o in f["orientation"])
    modos = Counter(f["intentMode"] for f in fichas)

    print("\n--- Cobertura ---")
    print(f"  perfiles: {len(fichas)}")
    print(f"  generos ({len(generos)}/8): {dict(generos)}")
    print(f"  orientaciones ({len(orientaciones)}/10): {dict(orientaciones)}")
    print(f"  modos ({len(modos)}/4): {dict(modos)}")

    # La comprobacion que de verdad importa: para cada par
    # (casilla que busco, casilla que soy) tiene que haber alguien.
    huecos = []
    for busco in CASILLAS:
        for soy in CASILLAS:
            hay = any(
                (CASILLA_DE.get(f["gender"]) in (busco, "any"))
                and (soy in f["interestedIn"])
                and f["intentMode"] in ("dating", "both")
                for f in fichas
            )
            if not hay:
                huecos.append(f"busco {busco} / soy {soy}")
    if huecos:
        print(f"  HUECOS SIN CUBRIR: {huecos}")
        return False
    print("  las 9 combinaciones de genero estan cubiertas")
    return True


def main():
    if CLEAN:
        limpiar()
        return

    caras = caras_disponibles()
    if not SIN_FOTOS and not (caras["h"] or caras["m"]):
        print(f"AVISO: no hay caras en {CARAS}.")
        print("       Usa --sin-fotos para sembrar con randomuser.me (sirve")
        print("       para poblar el feed, NO para juzgar la IA visual).")
        sys.exit(1)

    fichas = completar(construir(), caras)
    if not resumen(fichas):
        sys.exit(1)

    print()
    sembrados = 0
    for f in fichas:
        if SIN_FOTOS or not f["cara"]:
            # randomuser.me solo sirve fotos en dos carpetas. Para las
            # identidades fuera del binario se alterna por indice en vez de
            # mandarlas todas a la misma: no hay carpeta que les corresponda
            # y elegir siempre una seria inventarse un aspecto por defecto.
            casilla = CASILLA_DE.get(f["gender"])
            if casilla == "male":
                conjunto = "men"
            elif casilla == "female":
                conjunto = "women"
            else:
                conjunto = "men" if f["indice"] % 2 else "women"
            url_foto = (f"https://randomuser.me/api/portraits/{conjunto}/"
                        f"{f['indice'] % 90}.jpg")
        elif DRY:
            url_foto = f"[subiria {f['cara']}]"
        else:
            with open(os.path.join(CARAS, f["cara"]), "rb") as fichero:
                url_foto = subir(f"mock/{f['uid']}.jpg", fichero.read())

        datos = documento(f, url_foto)
        if DRY:
            print(f"  [simulacro] {f['uid']:26} {f['gender']:12} "
                  f"busca={','.join(f['interestedIn']):20} "
                  f"{f['orientation'][0]:11} {f['intentMode']:8} "
                  f"{f['edad']:>2}  {f['ciudad']}")
        else:
            campos = {k: valor(v) for k, v in datos.items()}
            mask = "&".join(f"updateMask.fieldPaths={k}" for k in datos)
            pedir(f"{BASE}/seed_profiles/{f['uid']}?{mask}", "PATCH",
                  {"fields": campos})
            print(f"  {f['uid']:26} {f['gender']:12} "
                  f"{f['orientation'][0]:11} {f['intentMode']:8} "
                  f"{f['edad']:>2}  {f['ciudad']}")
        sembrados += 1

    print(f"\n{sembrados} perfiles "
          f"{'se sembrarian' if DRY else 'sembrados'} en seed_profiles.")


if __name__ == "__main__":
    main()
