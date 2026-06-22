import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue, DocumentData } from "firebase-admin/firestore";
import { REGION } from "./firebase";
import { col, nextJourneyStatus, requireAuthUid, requireStringArg } from "./common";

/// completeSparkSession: al terminar una partida de Attra Spark, inserta el
/// mensaje de SISTEMA del resumen en el chat (los mensajes de chat son
/// backend-only, por eso esto va por función). Idempotente por sessionId.
///
/// Seguridad: solo un participante del match puede llamarla, y la sesión debe
/// pertenecer a ese match y estar completada. El texto se sanea (longitud/
/// saltos de línea) antes de escribirlo.
export const completeSparkSession = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const matchId = requireStringArg(request.data?.matchId, "matchId");
  const sessionId = requireStringArg(request.data?.sessionId, "sessionId");

  // 1) El llamante debe ser participante del match.
  const matchSnap = await col.matches.doc(matchId).get();
  if (!matchSnap.exists) {
    throw new HttpsError("not-found", "El match no existe.");
  }
  const users: string[] = Array.isArray(matchSnap.data()?.users)
    ? (matchSnap.data()!.users as unknown[]).filter(
        (x): x is string => typeof x === "string"
      )
    : [];
  if (!users.includes(uid)) {
    throw new HttpsError("permission-denied", "No perteneces a este match.");
  }

  // 2) La sesión debe pertenecer al match y estar completada.
  const sessionRef = col.matches
    .doc(matchId)
    .collection("sparkSessions")
    .doc(sessionId);
  const sessionSnap = await sessionRef.get();
  if (!sessionSnap.exists) {
    throw new HttpsError("not-found", "La sesión de Spark no existe.");
  }
  const session = sessionSnap.data() as DocumentData;
  if (session.status !== "completed") {
    throw new HttpsError("failed-precondition", "La partida no está completada.");
  }

  // 3) Texto del resumen (saneado). Fallback seguro si faltara.
  const summary =
    session.summary && typeof session.summary === "object"
      ? (session.summary as DocumentData)
      : {};
  const rawLine =
    typeof summary.chatLine === "string" && summary.chatLine.trim().length > 0
      ? summary.chatLine
      : "Habéis completado Attra Spark.";
  const text = rawLine.toString().replace(/\s+/g, " ").trim().slice(0, 280);

  // 4) Inserta el mensaje de sistema (idempotente) + actualiza el chat.
  const now = FieldValue.serverTimestamp();
  const messageRef = col.chats
    .doc(matchId)
    .collection("messages")
    .doc(`spark_${sessionId}`);

  await messageRef.set(
    {
      senderId: "system",
      receiverId: "",
      type: "system",
      text,
      status: "sent",
      relatedSparkSessionId: sessionId,
      createdAt: now,
    },
    { merge: true }
  );

  const currentJourney = nextJourneyStatus(
    matchSnap.data()?.journeyStatus,
    "game_completed"
  );

  await col.chats.doc(matchId).set(
    {
      lastMessage: text,
      lastMessageType: "system",
      lastMessageSenderId: "system",
      lastMessageAt: now,
      journeyStatus: currentJourney,
      journeyUpdatedAt: now,
      updatedAt: now,
    },
    { merge: true }
  );

  await col.matches.doc(matchId).set(
    {
      journeyStatus: currentJourney,
      journeyUpdatedAt: now,
      updatedAt: now,
    },
    { merge: true }
  );

  // Marca en la sesión que el resumen ya se publicó (evita duplicar trabajo).
  await sessionRef.set(
    { summaryPostedAt: now },
    { merge: true }
  ).catch(() => undefined);

  return { ok: true };
});
