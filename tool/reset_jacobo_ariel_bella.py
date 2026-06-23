"""Quita likes/matches entre Jacobo Pedrero y Ariel/Bella Hadid.

Borra, solo para esos pares:
  - likes en ambas direcciones
  - dislikes en ambas direcciones
  - attraSends en ambas direcciones
  - chats/{matchId} con sus subcolecciones
  - matches/{matchId} con sus subcolecciones

No borra perfiles, fotos ni usuarios.

Uso:
  python tool/reset_jacobo_ariel_bella.py --dry-run
  python tool/reset_jacobo_ariel_bella.py
"""

from __future__ import annotations

import argparse
import sys

from reset_mock_feed import FirebaseRest, access_token, pair_id


JACOBO_UID = "m8bd5lZomofr8dhqjZd6hd00BXa2"
TARGETS = {
    "Ariel": "mock_ariel",
    "Bella Hadid": "KaV1qzHPfTa1ZmzPi3cfizNmW8S2",
}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Resetea Ariel y Bella Hadid respecto a Jacobo Pedrero.",
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
    candidate_doc_paths: list[str] = []
    relation_roots: list[str] = []
    match_ids: list[str] = []

    for target_uid in TARGETS.values():
        match_id = pair_id(JACOBO_UID, target_uid)
        match_ids.append(match_id)
        candidate_doc_paths.extend(
            [
                f"likes/{JACOBO_UID}_{target_uid}",
                f"likes/{target_uid}_{JACOBO_UID}",
                f"dislikes/{JACOBO_UID}_{target_uid}",
                f"dislikes/{target_uid}_{JACOBO_UID}",
                f"attraSends/{JACOBO_UID}_{target_uid}",
                f"attraSends/{target_uid}_{JACOBO_UID}",
            ]
        )
        relation_roots.extend([f"chats/{match_id}", f"matches/{match_id}"])

    existing = client.batch_existing(candidate_doc_paths + relation_roots)
    firestore_deletes = [
        f"{client.doc_base}/{path}"
        for path in candidate_doc_paths
        if path in existing
    ]
    for root in relation_roots:
        if root in existing:
            firestore_deletes.extend(client.collect_recursive_deletes(root))

    storage_deletes: list[str] = []
    if args.delete_chat_storage:
        for match_id in match_ids:
            storage_deletes.extend(client.list_storage_objects(f"chats/{match_id}/"))

    unique_firestore = sorted(set(firestore_deletes))
    unique_storage = sorted(set(storage_deletes))

    print(f"Jacobo: {JACOBO_UID}")
    for name, uid in TARGETS.items():
        print(f"Objetivo: {name} ({uid})")
    print(f"Docs Firestore a borrar: {len(unique_firestore)}")
    print(f"Objetos Storage a borrar: {len(unique_storage)}")

    if args.dry_run:
        for path in unique_firestore:
            print("-", path.replace(f"{client.doc_base}/", ""))
        for name in unique_storage:
            print("- storage:", name)
        return

    deleted_docs = client.commit_deletes(unique_firestore)
    deleted_storage = client.delete_storage_objects(unique_storage)
    print(f"OK Firestore borrados: {deleted_docs}")
    print(f"OK Storage borrados: {deleted_storage}")
    print("Listo. Ariel y Bella quedan sin like/match con Jacobo.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit("\nCancelado.")
