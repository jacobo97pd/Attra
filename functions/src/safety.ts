import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { directedId, pairId } from "./ids";
import { col, requireAuthUid, requireStringArg } from "./common";

/// unmatch: cierra match y chat sin borrar mensajes (moderacion). Solo un
/// participante puede deshacer el match.
export const unmatch = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const matchId = requireStringArg(request.data?.matchId, "matchId");

  const matchRef = col.matches.doc(matchId);
  const matchSnap = await matchRef.get();
  if (!matchSnap.exists) {
    throw new HttpsError("not-found", "El match no existe.");
  }
  const users: string[] = (matchSnap.data()?.users ?? []) as string[];
  if (!users.includes(uid)) {
    throw new HttpsError("permission-denied", "No perteneces a este match.");
  }

  const now = FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.update(matchRef, { status: "unmatched", updatedAt: now });
  batch.set(
    col.chats.doc(matchId),
    { status: "closed", updatedAt: now },
    { merge: true }
  );
  await batch.commit();
  return { ok: true };
});

/// blockUser: crea bloqueo, cierra match/chat existentes y evita futuros
/// matches/mensajes. El bloqueo se valida en sendLike/sendAttra y en las reglas.
export const blockUser = onCall({ region: REGION }, async (request) => {
  const blockerUid = requireAuthUid(request.auth);
  const blockedUid = requireStringArg(request.data?.blockedUid, "blockedUid");
  if (blockerUid === blockedUid) {
    throw new HttpsError("invalid-argument", "No puedes bloquearte a ti mismo.");
  }

  const matchId = pairId(blockerUid, blockedUid);
  const now = FieldValue.serverTimestamp();
  const batch = db.batch();

  batch.set(col.blocks.doc(directedId(blockerUid, blockedUid)), {
    blockerUid,
    blockedUid,
    matchId,
    chatId: matchId,
    createdAt: now,
  });
  // Cierra relacion si existe (merge: no falla si no existe).
  batch.set(col.matches.doc(matchId), { status: "blocked", updatedAt: now }, { merge: true });
  batch.set(col.chats.doc(matchId), { status: "blocked", updatedAt: now }, { merge: true });

  await batch.commit();
  return { ok: true };
});

/// reportUser: registra un reporte para moderacion. No borra evidencias.
export const reportUser = onCall({ region: REGION }, async (request) => {
  const reporterUid = requireAuthUid(request.auth);
  const reportedUid = requireStringArg(request.data?.reportedUid, "reportedUid");
  if (reporterUid === reportedUid) {
    throw new HttpsError("invalid-argument", "Parametro invalido.");
  }
  const reason =
    typeof request.data?.reason === "string" ? request.data.reason : "other";
  const details =
    typeof request.data?.details === "string"
      ? (request.data.details as string).slice(0, 1000)
      : "";

  const reportRef = col.reports.doc();
  await reportRef.set({
    reporterUid,
    reportedUid,
    reason,
    status: "pending",
    details,
    matchId: request.data?.matchId ?? null,
    chatId: request.data?.chatId ?? null,
    messageId: request.data?.messageId ?? null,
    createdAt: FieldValue.serverTimestamp(),
  });
  return { reportId: reportRef.id };
});
