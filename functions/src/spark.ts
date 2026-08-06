import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { FieldValue, DocumentData } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
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

/// Una partida dura 5 min (`countdownSeconds` = 300) y CUALQUIER escritura de la
/// partida (aceptar, responder, reaccionar, avanzar de ronda) refresca
/// `lastActivityAt`. Con este margen, una sesión "active" sin tocar es una
/// sesión muerta con total seguridad.
const SPARK_ACTIVE_STALE_MS = 20 * 60 * 1000;

/// Una invitación "waiting" sí puede aceptarse mucho después (la tarjeta del
/// chat la ofrece), así que se le da un TTL largo antes de cerrarla.
const SPARK_WAITING_TTL_MS = 24 * 60 * 60 * 1000;

/// sweepSparkSessions: cierre por VENCIMIENTO en el servidor. El paso a estado
/// terminal lo hacía SOLO el cliente (el temporizador de la pantalla de juego, y
/// además únicamente en el dispositivo del anfitrión): si cerraba la app, salía
/// de la pantalla o perdía conexión, la sesión se quedaba "waiting"/"active"
/// eternamente. Como Spark es un rompehielos de UNA sola vez por match, eso
/// dejaba a la pareja con una partida colgada y sin poder volver a jugar.
///
/// Se elige un SCHEDULER (y no un cierre perezoso al leer) porque el documento
/// se lee en streaming desde el cliente: no hay un punto de lectura en backend
/// donde engancharse, y el cliente NO puede cerrar sesiones ajenas sin abrir la
/// partida. El barrido escribe solo el estado terminal (no inventa resumen: la
/// partida no llegó a terminar).
export const sweepSparkSessions = onSchedule(
  { schedule: "every 10 minutes", region: REGION },
  async () => {
    const now = Date.now();
    const targets: Array<{ status: string; cutoffMs: number }> = [
      { status: "active", cutoffMs: SPARK_ACTIVE_STALE_MS },
      { status: "waiting", cutoffMs: SPARK_WAITING_TTL_MS },
    ];
    let expired = 0;

    for (const target of targets) {
      try {
        const snap = await db
          .collectionGroup("sparkSessions")
          .where("status", "==", target.status)
          .where("lastActivityAt", "<=", new Date(now - target.cutoffMs))
          .limit(200)
          .get();
        if (snap.empty) continue;
        const batch = db.batch();
        for (const doc of snap.docs) {
          batch.update(doc.ref, {
            status: "expired",
            endedAt: FieldValue.serverTimestamp(),
            lastActivityAt: FieldValue.serverTimestamp(),
            closedBy: "server",
          });
          expired++;
        }
        await batch.commit();
      } catch (e) {
        console.error(
          `[spark] sweep ${target.status}: ${(e as Error).message}`
        );
      }
    }

    console.log(`[spark] sweep expired=${expired}`);
  }
);
