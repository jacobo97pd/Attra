"""Deshace TODOS los matches y deja el grafo de interacción en blanco.

Para qué: poder repetir pruebas de emparejamiento desde cero. No basta con
borrar `matches`, y por eso este script hace más de lo que su nombre sugiere:

  - `chats`     : un chat sin match es estado roto, y su subcolección
                  `messages` NO se borra al borrar el chat (Firestore no
                  cascadea): quedaría invisible pero ocupando y facturando.
  - `likes`     : si sobrevive un like recíproco, el match se rehace SOLO en
                  cuanto la app arranca.
  - `dislikes`  : quien ya se descartó no vuelve a salir en el feed, así que
                  sin limpiarlos no queda a quién probar.

Lo que NO toca, a propósito: `users`, `discovery`, `stories`, monedero,
entitlements ni compras. Esto reinicia las interacciones, no las cuentas.

    GTOKEN=$(gcloud auth print-access-token) python tool/reset_interactions.py
    # Añade --dry-run para ver qué borraría sin borrar nada.

DESTRUCTIVO E IRREVERSIBLE sobre la base de producción. Con `--dry-run` primero.
"""

import json
import os
import sys
import urllib.error
import urllib.request

TOKEN = os.environ["GTOKEN"]
PROJECT = "attra-database"
BASE = (
    f"https://firestore.googleapis.com/v1/projects/{PROJECT}"
    f"/databases/{PROJECT}/documents"
)
HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "x-goog-user-project": PROJECT,
}

DRY_RUN = "--dry-run" in sys.argv

# Colecciones de primer nivel que se vacían, en orden.
COLLECTIONS = ("matches", "chats", "likes", "dislikes")

# Subcolecciones que hay que vaciar ANTES que su padre. Firestore no borra en
# cascada: borrar el documento padre deja los hijos vivos y sin forma de
# alcanzarlos desde la consola.
SUBCOLLECTIONS = {
    "chats": ("messages",),
    "matches": ("sparkSessions", "games"),
}


def request(url, method="GET"):
    req = urllib.request.Request(url, headers=HEADERS, method=method)
    try:
        body = urllib.request.urlopen(req).read().decode()
        return json.loads(body) if body else {}
    except urllib.error.HTTPError as error:
        # 404 en una subcolección que no existe es lo normal, no un fallo.
        if error.code == 404:
            return {}
        raise


def document_names(path):
    """Nombres completos de los documentos de `path`, paginando."""
    names = []
    token = None
    while True:
        url = f"{BASE}/{path}?pageSize=300"
        if token:
            url += f"&pageToken={token}"
        page = request(url)
        names += [doc["name"] for doc in page.get("documents", [])]
        token = page.get("nextPageToken")
        if not token:
            return names


def delete(name):
    if DRY_RUN:
        return
    request(f"https://firestore.googleapis.com/v1/{name}", "DELETE")


def main():
    if DRY_RUN:
        print("SIMULACRO: no se borra nada.\n")

    counts = {}
    for collection, subs in SUBCOLLECTIONS.items():
        for parent in document_names(collection):
            relative = parent.split("/documents/", 1)[1]
            for sub in subs:
                for child in document_names(f"{relative}/{sub}"):
                    delete(child)
                    counts[f"{collection}/{sub}"] = (
                        counts.get(f"{collection}/{sub}", 0) + 1
                    )

    for collection in COLLECTIONS:
        names = document_names(collection)
        for name in names:
            delete(name)
        counts[collection] = len(names)

    verbo = "se borrarían" if DRY_RUN else "borrados"
    for key, value in sorted(counts.items()):
        print(f"  {verbo} {value:4}  {key}")
    if not DRY_RUN:
        print("\nGrafo de interacción en blanco: nadie tiene match, like ni "
              "descarte.\nLos perfiles y sus historias siguen intactos.")


if __name__ == "__main__":
    main()
