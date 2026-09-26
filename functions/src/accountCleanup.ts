import { onDocumentDeleted } from "firebase-functions/v2/firestore";
import {
  DocumentData,
  FieldValue,
  Query,
  QueryDocumentSnapshot,
} from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { col } from "./common";

const DATABASE = "attra-database";

/// Tamaño de pagina: holgado bajo el limite de 500 escrituras por batch.
const CLEANUP_PAGE = 300;

/// Limpieza del grafo social cuando se BORRA una cuenta (users/{uid}).
///
/// QUE FALLABA: `deleteUserData` (cliente) solo borra Storage y users/{uid}, y
/// el unico trigger sobre users (discovery.ts) solo quitaba discovery/{uid}.
/// Likes, matches y chats de esa persona seguian 'active':
///  - su like seguia en «Recibidos» del otro como una tarjeta "Alguien" sin
///    foto que contaba en el total y, para Free, podia ocupar la UNICA
///    tarjeta revelada; al responder, sendLike fallaba;
///  - su match seguia en la pestaña Matches y su chat aceptaba mensajes hacia
///    una cuenta que ya no existe.
/// El cliente no puede arreglarlo: likes/matches/chats solo los escribe el
/// backend. Se engancha al borrado de users/{uid} (y no a Auth) porque el
/// cliente borra ese doc ANTES que el usuario de Auth, y ese segundo paso puede
/// fallar por `requires-recent-login`: asi la limpieza corre igualmente.
///
/// Nada se borra: solo cambia de estado (los mensajes quedan para moderacion).

/// Like que hay que cancelar: el que sigue pendiente o marcado de un match.
/// Los ya cancelados conservan su motivo original.
export function likeNeedsCancelOnAccountDeletion(
  data: DocumentData | undefined
): boolean {
  const status = (data?.status ?? "active").toString();
  return status === "active" || status === "matched";
}

/// Match a retirar: solo el ACTIVO pasa a 'deleted' (estado que el cliente ya
/// conoce). 'blocked' se respeta a proposito: es la unica señal de bloqueo que
/// ve el bloqueado y la usa su feed para excluir al par. 'unmatched'/'closed'
/// ya son terminales.
export function matchNeedsDeleteOnAccountDeletion(
  data: DocumentData | undefined
): boolean {
  return (data?.status ?? "active").toString() === "active";
}

/// Chat a retirar de la lista del otro. Se elige 'deleted' (la lista de chats
/// oculta justo ese estado) y no 'closed': el otro perfil ya no existe, y un
/// chat de solo lectura con alguien sin nombre ni foto seria otro fantasma como
/// la tarjeta de «Recibidos». Tambien los 'closed' (unmatch/cierre previos)
/// por la misma razon. 'blocked' se deja como esta: es estado del bloqueo.
export function chatNeedsDeleteOnAccountDeletion(
  data: DocumentData | undefined
): boolean {
  const status = (data?.status ?? "active").toString();
  return status === "active" || status === "closed";
}

export interface AccountCleanupResult {
  likes: number;
  matches: number;
  chats: number;
}

/// Recorre `query` por paginas y aplica en un batch las actualizaciones que
/// devuelva `patchFor` (null = no tocar ese doc). Cursor por documento: las
/// actualizaciones no cambian los campos del filtro, asi que el orden es
/// estable. Devuelve cuantos docs actualizo.
async function updateInPages(
  query: Query,
  patchFor: (doc: QueryDocumentSnapshot) => Record<string, unknown> | null
): Promise<number> {
  let updated = 0;
  let last: QueryDocumentSnapshot | null = null;
  let more = true;
  while (more) {
    let page = query.limit(CLEANUP_PAGE);
    if (last) page = page.startAfter(last);
    const snap = await page.get();
    if (snap.empty) break;
    const batch = db.batch();
    let writes = 0;
    for (const doc of snap.docs) {
      const patch = patchFor(doc);
      if (!patch) continue;
      batch.update(doc.ref, patch);
      writes++;
    }
    if (writes > 0) await batch.commit();
    updated += writes;
    last = snap.docs[snap.docs.length - 1];
    more = snap.size >= CLEANUP_PAGE;
  }
  return updated;
}

/// Retira likes, matches y chats de `uid`. Idempotente: se puede relanzar (p.ej.
/// en un backfill de cuentas ya borradas) sin tocar lo que ya esta retirado.
/// Cada bloque va por separado: un fallo en uno no deja los otros sin hacer.
export async function cleanupDeletedAccount(
  uid: string
): Promise<AccountCleanupResult> {
  const result: AccountCleanupResult = { likes: 0, matches: 0, chats: 0 };
  if (!uid) return result;
  const now = FieldValue.serverTimestamp();

  const cancelLike = (doc: QueryDocumentSnapshot) =>
    likeNeedsCancelOnAccountDeletion(doc.data())
      ? {
          status: "cancelled",
          cancelReason: "account_deleted",
          cancelledBy: uid,
          cancelledAt: now,
          updatedAt: now,
        }
      : null;
  const retire = (needs: (d: DocumentData | undefined) => boolean) =>
    (doc: QueryDocumentSnapshot) =>
      needs(doc.data())
        ? {
            status: "deleted",
            deletedReason: "account_deleted",
            deletedAt: now,
            updatedAt: now,
          }
        : null;

  const steps: Array<[keyof AccountCleanupResult, () => Promise<number>]> = [
    [
      "likes",
      async () =>
        (await updateInPages(col.likes.where("fromUid", "==", uid), cancelLike)) +
        (await updateInPages(col.likes.where("toUid", "==", uid), cancelLike)),
    ],
    [
      "matches",
      () =>
        updateInPages(
          col.matches.where("users", "array-contains", uid),
          retire(matchNeedsDeleteOnAccountDeletion)
        ),
    ],
    [
      "chats",
      () =>
        updateInPages(
          col.chats.where("users", "array-contains", uid),
          retire(chatNeedsDeleteOnAccountDeletion)
        ),
    ],
  ];
  for (const [key, run] of steps) {
    try {
      result[key] = await run();
    } catch (e) {
      console.error(`[accountCleanup] ${key} de ${uid}: ${(e as Error).message}`);
    }
  }
  console.log(
    `[accountCleanup] ${uid}: likes=${result.likes} matches=${result.matches} chats=${result.chats}`
  );
  return result;
}

/// Trigger: borrado de users/{uid} → retira su grafo social (ver arriba).
export const onUserDeletedCleanup = onDocumentDeleted(
  { document: "users/{uid}", database: DATABASE, region: REGION },
  async (event) => {
    await cleanupDeletedAccount(event.params.uid);
  }
);
