import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { directedId, pairId } from "./ids";
import { col, requireAuthUid, requireStringArg } from "./common";
import { deletePairNotifications } from "./notifications";

/// unmatch: cierra match y chat sin borrar mensajes (moderacion). Solo un
/// participante puede deshacer el match.
///
/// Tambien cancela los dos likes del par. QUE FALLABA: se quedaban 'matched' y
/// `sendLike`/`sendAttra` cuentan un like inverso 'matched' como intencion
/// viva, asi que el otro podia reabrir match y chat con un like hecho a mano.
/// Ahora esas rutas ya tratan un match no activo como terminal; cancelar los
/// likes deja ademas las bandejas coherentes. Va en transaccion (como
/// applyBlock) porque hay que leer los likes antes de escribirlos.
export const unmatch = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const matchId = requireStringArg(request.data?.matchId, "matchId");

  const matchRef = col.matches.doc(matchId);
  await db.runTransaction(async (tx) => {
    const matchSnap = await tx.get(matchRef);
    if (!matchSnap.exists) {
      throw new HttpsError("not-found", "El match no existe.");
    }
    const users: string[] = (matchSnap.data()?.users ?? []) as string[];
    if (!users.includes(uid)) {
      throw new HttpsError("permission-denied", "No perteneces a este match.");
    }
    // Un bloqueo manda sobre un unmatch: rebajar 'blocked' a 'unmatched'
    // borraria la unica señal de bloqueo que ve el bloqueado (no puede leer
    // blocks/*) y reabriria el chat bloqueado como 'closed'. Y un match
    // retirado por cuenta borrada ('deleted') no se resucita en la lista.
    const status = (matchSnap.data()?.status ?? "active").toString();
    if (status === "blocked" || status === "deleted") return;

    const other = users.find((u) => u !== uid) ?? "";
    const likes = other
      ? await tx.getAll(
          col.likes.doc(directedId(uid, other)),
          col.likes.doc(directedId(other, uid))
        )
      : [];

    const now = FieldValue.serverTimestamp();
    tx.update(matchRef, { status: "unmatched", updatedAt: now });
    tx.set(
      col.chats.doc(matchId),
      { status: "closed", updatedAt: now },
      { merge: true }
    );
    for (const like of likes) {
      if (!like.exists) continue;
      // Uno ya cancelado conserva su motivo original (p.ej. el pase).
      if ((like.data()?.status ?? "active") === "cancelled") continue;
      tx.update(like.ref, {
        status: "cancelled",
        cancelReason: "unmatched",
        cancelledBy: uid,
        cancelledAt: now,
        updatedAt: now,
      });
    }
  });
  return { ok: true };
});

/// Lógica de bloqueo reutilizable (usada por blockUser y por SafeDate). Crea el
/// bloqueo, cierra match/chat existentes, borra los descartes del par y limpia
/// sus avisos de las dos bandejas. Idempotente (merge).
export async function applyBlock(
  blockerUid: string,
  blockedUid: string
): Promise<void> {
  if (blockerUid === blockedUid) {
    throw new HttpsError("invalid-argument", "No puedes bloquearte a ti mismo.");
  }
  const matchId = pairId(blockerUid, blockedUid);
  const now = FieldValue.serverTimestamp();
  await db.runTransaction(async (tx) => {
    const likeRefs = [
      col.likes.doc(directedId(blockerUid, blockedUid)),
      col.likes.doc(directedId(blockedUid, blockerUid)),
    ];
    const likes = await tx.getAll(...likeRefs);
    tx.set(col.blocks.doc(directedId(blockerUid, blockedUid)), {
      blockerUid,
      blockedUid,
      matchId,
      chatId: matchId,
      createdAt: now,
    });
    // The pair remains excluded from BOTH discovery feeds, even when these
    // people had no match yet. Without users, the blocked pair was invisible
    // to the participant query used by fetchExcludedUids.
    tx.set(col.matches.doc(matchId), {
      users: [blockerUid, blockedUid].sort(),
      status: "blocked",
      updatedAt: now,
    }, { merge: true });
    tx.set(col.chats.doc(matchId), { status: "blocked", updatedAt: now }, { merge: true });
    // Hide pending interactions from both inboxes without deleting evidence.
    for (const like of likes) {
      if (!like.exists) continue;
      tx.update(like.ref, {
        status: "cancelled",
        cancelReason: "blocked",
        cancelledBy: blockerUid,
        updatedAt: now,
      });
    }
    // Los descartes previos se BORRAN en ambos sentidos. QUE FALLABA: la
    // «segunda vuelta» del feed resta los descartados del conjunto excluido, y
    // un uid descartado Y bloqueado perdia tambien la exclusion del bloqueo:
    // volvia a salir el bloqueado (o quien te bloqueo). El bloqueo ya excluye
    // al par para siempre; el descarte no aporta nada y solo abria esa puerta.
    // (El cliente separa ademas las exclusiones duras; esto es la otra mitad.)
    tx.delete(col.dislikes.doc(directedId(blockerUid, blockedUid)));
    tx.delete(col.dislikes.doc(directedId(blockedUid, blockerUid)));
  });

  // Fuera de la transaccion y best-effort: la bandeja no es evidencia (los
  // mensajes siguen en chats/{id}/messages) y un fallo aqui no puede deshacer
  // ni tumbar el bloqueo, que ya esta escrito.
  try {
    await deletePairNotifications(blockerUid, blockedUid);
  } catch (e) {
    console.error(`[safety] limpieza de notificaciones tras bloqueo: ${e}`);
  }
}

/// Registro de reporte reutilizable. Nunca revela al reportado quién reporta.
export async function createReport(params: {
  reporterUid: string;
  reportedUid: string;
  reason: string;
  details?: string;
  matchId?: string | null;
  chatId?: string | null;
  messageId?: string | null;
  storyId?: string | null;
}): Promise<string> {
  if (params.reporterUid === params.reportedUid) {
    throw new HttpsError("invalid-argument", "Parametro invalido.");
  }
  const reportRef = col.reports.doc();
  await reportRef.set({
    reporterUid: params.reporterUid,
    reportedUid: params.reportedUid,
    reason: params.reason,
    status: "pending",
    details: (params.details ?? "").slice(0, 1000),
    matchId: params.matchId ?? null,
    chatId: params.chatId ?? null,
    messageId: params.messageId ?? null,
    storyId: params.storyId ?? null,
    createdAt: FieldValue.serverTimestamp(),
  });
  return reportRef.id;
}

/// blockUser: crea bloqueo, cierra match/chat existentes y evita futuros
/// matches/mensajes. El bloqueo se valida en sendLike/sendAttra y en las reglas.
export const blockUser = onCall({ region: REGION }, async (request) => {
  const blockerUid = requireAuthUid(request.auth);
  const blockedUid = requireStringArg(request.data?.blockedUid, "blockedUid");
  await applyBlock(blockerUid, blockedUid);
  return { ok: true };
});

/// reportUser: registra un reporte para moderacion. No borra evidencias.
export const reportUser = onCall({ region: REGION }, async (request) => {
  const reporterUid = requireAuthUid(request.auth);
  const reportedUid = requireStringArg(request.data?.reportedUid, "reportedUid");
  const reportId = await createReport({
    reporterUid,
    reportedUid,
    reason:
      typeof request.data?.reason === "string" ? request.data.reason : "other",
    details:
      typeof request.data?.details === "string" ? request.data.details : "",
    matchId: request.data?.matchId ?? null,
    chatId: request.data?.chatId ?? null,
    messageId: request.data?.messageId ?? null,
    storyId: request.data?.storyId == null
      ? null
      : requireStringArg(request.data.storyId, "storyId"),
  });
  return { reportId };
});
