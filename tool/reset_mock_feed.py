"""Resetea los mocks del feed para que vuelvan a aparecer.

Borra interacciones entre un usuario real y todos los documentos de
`seed_profiles` con `isBot=true`: likes, dislikes, matches, chats y
subcolecciones relacionadas. No borra los perfiles mock.

Uso:
  python tool/reset_mock_feed.py
  python tool/reset_mock_feed.py --uid <uid>
  python tool/reset_mock_feed.py --dry-run

Si no hay GTOKEN en el entorno, intenta obtenerlo con:
  gcloud auth print-access-token
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


PROJECT = "attra-database"
DATABASE = "attra-database"
BUCKET = "attra-database.firebasestorage.app"
DEFAULT_UID = "m8bd5lZomofr8dhqjZd6hd00BXa2"  # Jacobo Pedrero


def access_token() -> str:
    token = os.environ.get("GTOKEN", "").strip()
    if token:
        return token
    commands: list[list[str]] = []
    for executable in ("gcloud", "gcloud.cmd"):
        found = shutil.which(executable)
        if found:
            commands.append([found, "auth", "print-access-token"])
    commands.append(
        ["powershell", "-NoProfile", "-Command", "gcloud auth print-access-token"]
    )
    for command in commands:
        try:
            return subprocess.check_output(
                command,
                text=True,
                stderr=subprocess.PIPE,
            ).strip()
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue
    raise SystemExit(
        "No hay GTOKEN y no pude ejecutar gcloud auth print-access-token."
    )


class FirebaseRest:
    def __init__(self, token: str, dry_run: bool = False) -> None:
        self.dry_run = dry_run
        self.headers = {
            "Authorization": f"Bearer {token}",
            "x-goog-user-project": PROJECT,
            "Content-Type": "application/json",
        }
        self.doc_base = (
            f"projects/{PROJECT}/databases/{DATABASE}/documents"
        )
        self.rest_base = f"https://firestore.googleapis.com/v1/{self.doc_base}"

    def request_json(
        self,
        url: str,
        *,
        method: str = "GET",
        body: dict | None = None,
        missing_ok: bool = False,
    ) -> dict:
        data = None if body is None else json.dumps(body).encode("utf-8")
        request = urllib.request.Request(
            url,
            data=data,
            method=method,
            headers=self.headers,
        )
        try:
            return json.load(urllib.request.urlopen(request, timeout=60))
        except urllib.error.HTTPError as error:
            if missing_ok and error.code == 404:
                return {}
            details = error.read().decode(errors="replace")
            raise SystemExit(f"HTTP {error.code}: {details}") from error

    def firestore_value(self, value: dict) -> object:
        if "stringValue" in value:
            return value["stringValue"]
        if "integerValue" in value:
            return int(value["integerValue"])
        if "doubleValue" in value:
            return float(value["doubleValue"])
        if "booleanValue" in value:
            return bool(value["booleanValue"])
        if "timestampValue" in value:
            return value["timestampValue"]
        if "arrayValue" in value:
            return [
                self.firestore_value(item)
                for item in value.get("arrayValue", {}).get("values", [])
            ]
        if "mapValue" in value:
            return {
                key: self.firestore_value(item)
                for key, item in value.get("mapValue", {})
                .get("fields", {})
                .items()
            }
        return None

    def doc_id(self, doc_name: str) -> str:
        return doc_name.rsplit("/", 1)[-1]

    def batch_existing(self, paths: list[str]) -> set[str]:
        existing: set[str] = set()
        full_names = [f"{self.doc_base}/{path}" for path in paths]
        for offset in range(0, len(full_names), 300):
            chunk = full_names[offset : offset + 300]
            url = (
                f"https://firestore.googleapis.com/v1/projects/{PROJECT}/"
                f"databases/{DATABASE}/documents:batchGet"
            )
            data = self.request_json(
                url,
                method="POST",
                body={"documents": chunk},
            )
            if not isinstance(data, list):
                continue
            for row in data:
                found = row.get("found")
                if found and found.get("name"):
                    existing.add(found["name"].split("/documents/", 1)[1])
        return existing

    def list_docs(self, collection_path: str, page_size: int = 300) -> list[dict]:
        docs: list[dict] = []
        page_token = ""
        while True:
            query = f"?pageSize={page_size}"
            if page_token:
                query += f"&pageToken={urllib.parse.quote(page_token)}"
            url = f"{self.rest_base}/{collection_path}{query}"
            data = self.request_json(url, missing_ok=True)
            docs.extend(data.get("documents", []))
            page_token = data.get("nextPageToken", "")
            if not page_token:
                return docs

    def query_seed_profiles(self) -> list[str]:
        docs = self.list_docs("seed_profiles")
        out: list[str] = []
        for doc in docs:
            fields = doc.get("fields", {})
            is_bot = self.firestore_value(fields.get("isBot", {}))
            if is_bot is True:
                out.append(self.doc_id(doc["name"]))
        return sorted(set(out))

    def list_collection_ids(self, doc_path: str) -> list[str]:
        url = f"{self.rest_base}/{doc_path}:listCollectionIds"
        data = self.request_json(
            url,
            method="POST",
            body={"pageSize": 100},
            missing_ok=True,
        )
        return sorted(data.get("collectionIds", []))

    def collect_recursive_deletes(self, doc_path: str) -> list[str]:
        """Devuelve subdocs primero y luego el doc padre."""
        full_name = f"{self.doc_base}/{doc_path}"
        paths: list[str] = []
        for collection_id in self.list_collection_ids(doc_path):
            collection_path = f"{doc_path}/{collection_id}"
            for child in self.list_docs(collection_path):
                child_doc_path = child["name"].split("/documents/", 1)[1]
                paths.extend(self.collect_recursive_deletes(child_doc_path))
        paths.append(full_name)
        return paths

    def commit_deletes(self, full_doc_names: list[str]) -> int:
        unique = sorted(set(full_doc_names))
        if self.dry_run:
            return 0
        deleted = 0
        for offset in range(0, len(unique), 450):
            chunk = unique[offset : offset + 450]
            url = (
                f"https://firestore.googleapis.com/v1/projects/{PROJECT}/"
                f"databases/{DATABASE}/documents:commit"
            )
            data = self.request_json(
                url,
                method="POST",
                body={"writes": [{"delete": name} for name in chunk]},
            )
            deleted += len(data.get("writeResults", []))
        return deleted

    def list_storage_objects(self, prefix: str) -> list[str]:
        objects: list[str] = []
        page_token = ""
        while True:
            query = f"?prefix={urllib.parse.quote(prefix)}"
            if page_token:
                query += f"&pageToken={urllib.parse.quote(page_token)}"
            url = f"https://storage.googleapis.com/storage/v1/b/{BUCKET}/o{query}"
            data = self.request_json(url, missing_ok=True)
            objects.extend(item["name"] for item in data.get("items", []))
            page_token = data.get("nextPageToken", "")
            if not page_token:
                return objects

    def delete_storage_objects(self, object_names: list[str]) -> int:
        if self.dry_run:
            return 0
        deleted = 0
        for name in sorted(set(object_names)):
            encoded = urllib.parse.quote(name, safe="")
            url = f"https://storage.googleapis.com/storage/v1/b/{BUCKET}/o/{encoded}"
            request = urllib.request.Request(
                url,
                method="DELETE",
                headers=self.headers,
            )
            try:
                urllib.request.urlopen(request, timeout=60).read()
                deleted += 1
            except urllib.error.HTTPError as error:
                if error.code != 404:
                    details = error.read().decode(errors="replace")
                    raise SystemExit(f"Storage DELETE {error.code}: {details}")
        return deleted


def pair_id(a: str, b: str) -> str:
    return f"{a}_{b}" if a <= b else f"{b}_{a}"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Vuelve a mostrar todos los perfiles mock en el feed.",
    )
    parser.add_argument(
        "--uid",
        default=DEFAULT_UID,
        help=f"UID del usuario a resetear. Por defecto: {DEFAULT_UID}",
    )
    parser.add_argument(
        "--only",
        nargs="*",
        default=None,
        help="Opcional: IDs concretos de seed_profiles a resetear.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Muestra lo que borraria, sin borrar nada.",
    )
    parser.add_argument(
        "--delete-chat-storage",
        action="store_true",
        help="Tambien borra archivos bajo Storage chats/{matchId}/.",
    )
    args = parser.parse_args()

    client = FirebaseRest(access_token(), dry_run=args.dry_run)
    seed_ids = sorted(set(args.only or client.query_seed_profiles()))
    if not seed_ids:
        raise SystemExit("No he encontrado seed_profiles con isBot=true.")

    firestore_deletes: list[str] = []
    storage_deletes: list[str] = []

    candidate_doc_paths: list[str] = []
    match_roots: list[str] = []
    chat_roots: list[str] = []
    match_ids: list[str] = []

    for seed_uid in seed_ids:
        match_id = pair_id(args.uid, seed_uid)
        match_ids.append(match_id)
        candidate_doc_paths.extend([
            f"likes/{args.uid}_{seed_uid}",
            f"likes/{seed_uid}_{args.uid}",
            f"dislikes/{args.uid}_{seed_uid}",
            f"dislikes/{seed_uid}_{args.uid}",
            f"attraSends/{args.uid}_{seed_uid}",
            f"attraSends/{seed_uid}_{args.uid}",
            f"blocks/{args.uid}_{seed_uid}",
            f"blocks/{seed_uid}_{args.uid}",
        ])
        chat_roots.append(f"chats/{match_id}")
        match_roots.append(f"matches/{match_id}")

    existing = client.batch_existing(
        candidate_doc_paths + chat_roots + match_roots
    )
    firestore_deletes.extend(
        f"{client.doc_base}/{path}"
        for path in candidate_doc_paths
        if path in existing
    )

    for root in chat_roots + match_roots:
        if root in existing:
            firestore_deletes.extend(client.collect_recursive_deletes(root))

    if args.delete_chat_storage:
        for match_id in match_ids:
            storage_deletes.extend(client.list_storage_objects(f"chats/{match_id}/"))

    unique_firestore = sorted(set(firestore_deletes))
    unique_storage = sorted(set(storage_deletes))

    print(f"Usuario: {args.uid}")
    print(f"Mocks revisados: {len(seed_ids)}")
    print(f"Docs Firestore a borrar: {len(unique_firestore)}")
    print(f"Objetos Storage a borrar: {len(unique_storage)}")
    if args.dry_run:
        for path in unique_firestore[:80]:
            print("-", path.replace(f"{client.doc_base}/", ""))
        if len(unique_firestore) > 80:
            print(f"... y {len(unique_firestore) - 80} docs mas")
        for name in unique_storage[:40]:
            print("- storage:", name)
        if len(unique_storage) > 40:
            print(f"... y {len(unique_storage) - 40} objetos Storage mas")
        return

    deleted_docs = client.commit_deletes(unique_firestore)
    deleted_storage = client.delete_storage_objects(unique_storage)
    print(f"OK Firestore borrados: {deleted_docs}")
    print(f"OK Storage borrados: {deleted_storage}")
    print("Listo. Al recargar la app, los mocks vuelven al feed si pasan filtros.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit("\nCancelado.")
