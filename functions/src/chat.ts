import { onCall, HttpsError } from "firebase-functions/v2/https";
import { DocumentData, FieldValue, Transaction } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { REGION, STORAGE_BUCKET, db } from "./firebase";
import {
  JourneyStatus,
  MAX_MESSAGE_LENGTH,
  col,
  existsBlockBetween,
  nextJourneyStatus,
  requireAuthUid,
  requireStringArg,
} from "./common";

const CONVERSATION_THRESHOLD = 6;

function numberField(data: DocumentData, key: string): number {
  const value = data[key];
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

/// Combina "yyyy-MM-dd" + "HH:mm" en un Date. Devuelve null si no es válido.
function parseDateTime(date: unknown, time: unknown): Date | null {
  const d = typeof date === "string" ? date.trim() : "";
  const t = typeof time === "string" ? time.trim() : "";
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) return null;
  const hhmm = /^\d{2}:\d{2}$/.test(t) ? t : "00:00";
  const parsed = new Date(`${d}T${hhmm}:00`);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function journeyPatch(
  tx: Transaction,
  matchId: string,
  current: unknown,
  candidate: JourneyStatus,
  now: FieldValue
): Record<string, unknown> {
  const journeyStatus = nextJourneyStatus(current, candidate);
  const patch = { journeyStatus, journeyUpdatedAt: now };
  tx.set(col.matches.doc(matchId), patch, { merge: true });
  return patch;
}

function messageCandidate(nextCount: number): JourneyStatus {
  return nextCount >= CONVERSATION_THRESHOLD
    ? "conversation_active"
    : "icebreaker_started";
}

/// sendMessage: valida pertenencia + chat activo + no-bloqueo, crea el mensaje
/// y actualiza el chat (lastMessage + unreadCount del receptor) atomicamente.
export const sendMessage = onCall({ region: REGION }, async (request) => {
  const senderId = requireAuthUid(request.auth);
  const chatId = requireStringArg(request.data?.chatId, "chatId");
  const rawText = requireStringArg(request.data?.text, "text");
  const text = rawText.slice(0, MAX_MESSAGE_LENGTH);
  // Reto de 5 min: si el mensaje se envía durante una sesión, se marca para que
  // la IA solo analice esos mensajes. No cambia el tipo (sigue siendo "text").
  const gameSessionId =
    typeof request.data?.gameSessionId === "string" && request.data.gameSessionId.trim()
      ? request.data.gameSessionId.trim().slice(0, 80)
      : null;

  const chatRef = col.chats.doc(chatId);
  const messageRef = chatRef.collection("messages").doc();

  // Pre-validacion fuera de la transaccion: pertenencia + bloqueo (otra
  // coleccion). El bloqueo tambien cierra el chat, pero comprobamos por si
  // quedara algun caso sin propagar.
  const preSnap = await chatRef.get();
  if (!preSnap.exists) {
    throw new HttpsError("not-found", "El chat no existe.");
  }
  const preUsers: string[] = (preSnap.data()?.users ?? []) as string[];
  if (!preUsers.includes(senderId)) {
    throw new HttpsError("permission-denied", "No participas en este chat.");
  }
  const otherUid = preUsers.find((u) => u !== senderId) ?? "";
  if (await existsBlockBetween(senderId, otherUid)) {
    throw new HttpsError("permission-denied", "No puedes escribir a este usuario.");
  }

  const messageId = await db.runTransaction(async (tx): Promise<string> => {
    const chatSnap = await tx.get(chatRef);
    if (!chatSnap.exists) {
      throw new HttpsError("not-found", "El chat no existe.");
    }
    const chat = chatSnap.data() ?? {};
    const users: string[] = (chat.users ?? []) as string[];
    if (!users.includes(senderId)) {
      throw new HttpsError("permission-denied", "No participas en este chat.");
    }
    if ((chat.status ?? "active") !== "active") {
      throw new HttpsError("failed-precondition", "Este chat ya no esta disponible.");
    }
    const receiverId = users.find((u) => u !== senderId) ?? "";
    const matchId = (chat.matchId ?? chatId).toString();
    const nextCount = numberField(chat, "realMessageCount") + 1;

    const now = FieldValue.serverTimestamp();
    const journey = journeyPatch(
      tx,
      matchId,
      chat.journeyStatus,
      messageCandidate(nextCount),
      now
    );
    tx.set(messageRef, {
      senderId,
      receiverId,
      type: "text",
      text,
      status: "sent",
      createdAt: now,
      ...(gameSessionId ? { gameSessionId } : {}),
    });
    tx.update(chatRef, {
      lastMessage: text,
      lastMessageType: "text",
      lastMessageSenderId: senderId,
      lastMessageAt: now,
      updatedAt: now,
      realMessageCount: FieldValue.increment(1),
      ...journey,
      [`unreadCountByUser.${receiverId}`]: FieldValue.increment(1),
    });
    return messageRef.id;
  });

  // TODO(Fase 8): push al receptor si no tiene el chat silenciado.
  return { messageId };
});

const MEDIA_LIMITS = {
  image: {
    maxBytes: 5 * 1024 * 1024,
    mimes: ["image/jpeg", "image/png", "image/webp"],
    folder: "images",
    last: "📷 Foto",
  },
  bomb_image: {
    maxBytes: 5 * 1024 * 1024,
    mimes: ["image/jpeg", "image/png", "image/webp"],
    folder: "bombs",
    last: "Foto bomba",
  },
  voice_note: {
    maxBytes: 10 * 1024 * 1024,
    mimes: ["audio/mp4", "audio/m4a", "audio/aac", "audio/mpeg", "audio/webm", "audio/ogg", "audio/wav", "audio/x-wav"],
    folder: "voice",
    last: "🎙️ Nota de voz",
  },
} as const;

/// sendMediaMessage: crea un mensaje `image` o `voice_note`. El cliente ya subio
/// el archivo a Storage (ruta segura por uid); aqui se VALIDA de forma
/// autoritativa: pertenencia al chat, chat activo, no-bloqueo, que el path es el
/// esperado del usuario/chat y que el OBJETO real (size/contentType leidos del
/// bucket, no del cliente) cumple los limites.
export const sendMediaMessage = onCall({ region: REGION }, async (request) => {
  const senderId = requireAuthUid(request.auth);
  const chatId = requireStringArg(request.data?.chatId, "chatId");
  const messageId = requireStringArg(request.data?.messageId, "messageId");
  const type = requireStringArg(request.data?.type, "type");
  const storagePath = requireStringArg(request.data?.storagePath, "storagePath");

  if (type !== "image" && type !== "bomb_image" && type !== "voice_note") {
    throw new HttpsError("invalid-argument", "Tipo de media no soportado.");
  }
  const downloadUrl =
    type === "bomb_image"
      ? ""
      : requireStringArg(request.data?.downloadUrl, "downloadUrl");

  const limits = MEDIA_LIMITS[type];

  // El path DEBE ser el esperado para este chat + este usuario.
  const expectedPrefix = `chats/${chatId}/${limits.folder}/${senderId}/`;
  if (!storagePath.startsWith(expectedPrefix)) {
    throw new HttpsError("permission-denied", "Ruta de archivo no válida.");
  }

  // Metadata REAL del objeto (no confiamos en lo que diga el cliente).
  const file = getStorage().bucket(STORAGE_BUCKET).file(storagePath);
  const [exists] = await file.exists();
  if (!exists) {
    throw new HttpsError("failed-precondition", "El archivo no existe en Storage.");
  }
  const [meta] = await file.getMetadata();
  const realMime = (meta.contentType ?? "").toString();
  const realSize = Number(meta.size ?? 0);
  if (!(limits.mimes as readonly string[]).includes(realMime)) {
    throw new HttpsError("invalid-argument", `Tipo de archivo no permitido (${realMime}).`);
  }
  if (realSize <= 0 || realSize > limits.maxBytes) {
    throw new HttpsError("invalid-argument", "El archivo supera el tamaño permitido.");
  }

  const width = Number.isFinite(request.data?.width) ? Number(request.data.width) : null;
  const height = Number.isFinite(request.data?.height) ? Number(request.data.height) : null;
  const durationMs = Number.isFinite(request.data?.durationMs)
    ? Number(request.data.durationMs)
    : null;
  const fileName =
    typeof request.data?.fileName === "string"
      ? (request.data.fileName as string).slice(0, 120)
      : null;

  const chatRef = col.chats.doc(chatId);

  // Bloqueo (otra coleccion): fuera de la transaccion.
  const preSnap = await chatRef.get();
  if (!preSnap.exists) throw new HttpsError("not-found", "El chat no existe.");
  const preUsers: string[] = (preSnap.data()?.users ?? []) as string[];
  if (!preUsers.includes(senderId)) {
    throw new HttpsError("permission-denied", "No participas en este chat.");
  }
  const otherUid = preUsers.find((u) => u !== senderId) ?? "";
  if (await existsBlockBetween(senderId, otherUid)) {
    throw new HttpsError("permission-denied", "No puedes escribir a este usuario.");
  }

  await db.runTransaction(async (tx): Promise<void> => {
    const chatSnap = await tx.get(chatRef);
    if (!chatSnap.exists) throw new HttpsError("not-found", "El chat no existe.");
    const chat = chatSnap.data() ?? {};
    const users: string[] = (chat.users ?? []) as string[];
    if (!users.includes(senderId)) {
      throw new HttpsError("permission-denied", "No participas en este chat.");
    }
    if ((chat.status ?? "active") !== "active") {
      throw new HttpsError("failed-precondition", "Este chat ya no esta disponible.");
    }
    const receiverId = users.find((u) => u !== senderId) ?? "";
    const matchId = (chat.matchId ?? chatId).toString();
    const nextCount = numberField(chat, "realMessageCount") + 1;
    const now = FieldValue.serverTimestamp();
    const journey = journeyPatch(
      tx,
      matchId,
      chat.journeyStatus,
      messageCandidate(nextCount),
      now
    );

    tx.set(chatRef.collection("messages").doc(messageId), {
      senderId,
      receiverId,
      type,
      text: "",
      status: "sent",
      media: {
        storagePath,
        downloadUrl: type === "bomb_image" ? null : downloadUrl,
        mimeType: realMime,
        sizeBytes: realSize,
        width,
        height,
        durationMs,
        fileName,
      },
      ...(type === "bomb_image"
        ? {
            bomb: {
              state: "unopened",
              viewedBy: null,
              viewedAt: null,
            },
          }
        : {}),
      createdAt: now,
    });
    tx.update(chatRef, {
      lastMessage: limits.last,
      lastMessageType: type,
      lastMessageSenderId: senderId,
      lastMessageAt: now,
      updatedAt: now,
      realMessageCount: FieldValue.increment(1),
      ...journey,
      [`unreadCountByUser.${receiverId}`]: FieldValue.increment(1),
    });
  });

  return { messageId };
});

/// openBombImage: consume una foto bomba. Solo el receptor puede abrirla una
/// vez. Devuelve una signed URL corta y deja el mensaje marcado como visto.
export const openBombImage = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const chatId = requireStringArg(request.data?.chatId, "chatId");
  const messageId = requireStringArg(request.data?.messageId, "messageId");

  const chatRef = col.chats.doc(chatId);
  const messageRef = chatRef.collection("messages").doc(messageId);

  const [chatSnap, msgSnap] = await Promise.all([
    chatRef.get(),
    messageRef.get(),
  ]);
  if (!chatSnap.exists) throw new HttpsError("not-found", "El chat no existe.");
  if (!msgSnap.exists) throw new HttpsError("not-found", "La foto ya no existe.");
  const users: string[] = (chatSnap.data()?.users ?? []) as string[];
  if (!users.includes(uid)) {
    throw new HttpsError("permission-denied", "No participas en este chat.");
  }
  const msg = msgSnap.data() ?? {};
  if (msg.type !== "bomb_image") {
    throw new HttpsError("invalid-argument", "Ese mensaje no es una foto bomba.");
  }
  if (msg.receiverId !== uid) {
    throw new HttpsError(
      "permission-denied",
      "Solo quien recibe la foto bomba puede abrirla."
    );
  }
  if (msg.bomb?.viewedAt || msg.bomb?.state === "viewed") {
    throw new HttpsError("failed-precondition", "Esta foto bomba ya fue vista.");
  }
  const storagePath = (msg.media?.storagePath ?? "").toString();
  if (!storagePath.startsWith(`chats/${chatId}/bombs/`)) {
    throw new HttpsError("failed-precondition", "La foto bomba no esta disponible.");
  }

  const file = getStorage().bucket(STORAGE_BUCKET).file(storagePath);
  const [exists] = await file.exists();
  if (!exists) {
    throw new HttpsError("not-found", "La foto bomba ya no existe.");
  }
  // Devolvemos los BYTES (base64) en vez de una signed URL: getSignedUrl exige
  // permiso de firma (signBlob) que la service account por defecto no tiene.
  // Así funciona sin tocar IAM y la imagen nunca queda accesible por URL.
  const [buffer] = await file.download();

  await db.runTransaction(async (tx): Promise<void> => {
    const [txChatSnap, txMsgSnap] = await Promise.all([
      tx.get(chatRef),
      tx.get(messageRef),
    ]);
    if (!txChatSnap.exists) throw new HttpsError("not-found", "El chat no existe.");
    if (!txMsgSnap.exists) throw new HttpsError("not-found", "La foto ya no existe.");
    const txUsers: string[] = (txChatSnap.data()?.users ?? []) as string[];
    if (!txUsers.includes(uid)) {
      throw new HttpsError("permission-denied", "No participas en este chat.");
    }
    const txMsg = txMsgSnap.data() ?? {};
    if (txMsg.type !== "bomb_image" || txMsg.receiverId !== uid) {
      throw new HttpsError("permission-denied", "No puedes abrir esta foto bomba.");
    }
    if (txMsg.bomb?.viewedAt || txMsg.bomb?.state === "viewed") {
      throw new HttpsError("failed-precondition", "Esta foto bomba ya fue vista.");
    }
    const now = FieldValue.serverTimestamp();
    tx.update(messageRef, {
      "bomb.state": "viewed",
      "bomb.viewedBy": uid,
      "bomb.viewedAt": now,
      readAt: now,
    });
  });

  // Vista consumida: borra el fichero (view-once real, no queda rastro).
  await file.delete().catch(() => undefined);

  return { imageBase64: buffer.toString("base64"), mimeType: "image/jpeg" };
});

/// markMessagesAsRead: resetea el contador del usuario y marca como leidos los
/// mensajes que le llegaron. El reset del contador es lo critico; el marcado de
/// mensajes es best-effort por lotes.
export const markMessagesAsRead = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const chatId = requireStringArg(request.data?.chatId, "chatId");

  const chatRef = col.chats.doc(chatId);
  const chatSnap = await chatRef.get();
  if (!chatSnap.exists) {
    throw new HttpsError("not-found", "El chat no existe.");
  }
  const users: string[] = (chatSnap.data()?.users ?? []) as string[];
  if (!users.includes(uid)) {
    throw new HttpsError("permission-denied", "No participas en este chat.");
  }

  await chatRef.update({
    [`unreadCountByUser.${uid}`]: 0,
    [`manuallyUnreadByUser.${uid}`]: false,
    [`lastReadAtByUser.${uid}`]: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  const pending = await chatRef
    .collection("messages")
    .where("receiverId", "==", uid)
    .where("status", "in", ["sent", "delivered"])
    .limit(450)
    .get();

  if (!pending.empty) {
    const batch = db.batch();
    const now = FieldValue.serverTimestamp();
    for (const doc of pending.docs) {
      batch.update(doc.ref, { status: "read", readAt: now });
    }
    await batch.commit();
  }

  return { ok: true, marked: pending.size };
});

/// markChatAsUnread: marca el chat como NO leido SOLO para el usuario actual,
/// sin tocar unreadCount ni los mensajes (no es destructivo). La UI lo muestra
/// como no leido si unreadCount>0 O manuallyUnread==true.
export const markChatAsUnread = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const chatId = requireStringArg(request.data?.chatId, "chatId");

  const chatRef = col.chats.doc(chatId);
  const chatSnap = await chatRef.get();
  if (!chatSnap.exists) {
    throw new HttpsError("not-found", "El chat no existe.");
  }
  const users: string[] = (chatSnap.data()?.users ?? []) as string[];
  if (!users.includes(uid)) {
    throw new HttpsError("permission-denied", "No participas en este chat.");
  }

  await chatRef.update({
    [`manuallyUnreadByUser.${uid}`]: true,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

/// setTyping: indicador de "escribiendo". Update ligero validando pertenencia.
export const setTyping = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const chatId = requireStringArg(request.data?.chatId, "chatId");
  const isTyping = request.data?.isTyping === true;

  const chatRef = col.chats.doc(chatId);
  const chatSnap = await chatRef.get();
  if (!chatSnap.exists) {
    throw new HttpsError("not-found", "El chat no existe.");
  }
  const users: string[] = (chatSnap.data()?.users ?? []) as string[];
  if (!users.includes(uid)) {
    throw new HttpsError("permission-denied", "No participas en este chat.");
  }

  await chatRef.update({ [`typingByUser.${uid}`]: isTyping });
  return { ok: true };
});

const MAX_PROPOSAL_NOTE = 300;

/// sendDateProposal: crea un mensaje especial `date_proposal` dentro del chat.
/// Valida match activo (chat.status==active), pertenencia, lugar no vacio y
/// fecha/hora presentes. No integra reservas reales: solo la propuesta.
export const sendDateProposal = onCall({ region: REGION }, async (request) => {
  const senderId = requireAuthUid(request.auth);
  const chatId = requireStringArg(request.data?.chatId, "chatId");
  const proposedDate = requireStringArg(request.data?.proposedDate, "proposedDate");
  const proposedTime = requireStringArg(request.data?.proposedTime, "proposedTime");
  const placeName = requireStringArg(request.data?.placeName, "placeName");
  const placeAddress =
    typeof request.data?.placeAddress === "string"
      ? (request.data.placeAddress as string).slice(0, 200)
      : "";
  const note =
    typeof request.data?.note === "string"
      ? (request.data.note as string).slice(0, MAX_PROPOSAL_NOTE)
      : "";

  const chatRef = col.chats.doc(chatId);
  const messageRef = chatRef.collection("messages").doc();

  const messageId = await db.runTransaction(async (tx): Promise<string> => {
    const chatSnap = await tx.get(chatRef);
    if (!chatSnap.exists) {
      throw new HttpsError("not-found", "El chat no existe.");
    }
    const chat = chatSnap.data() ?? {};
    const users: string[] = (chat.users ?? []) as string[];
    if (!users.includes(senderId)) {
      throw new HttpsError("permission-denied", "No participas en este chat.");
    }
    if ((chat.status ?? "active") !== "active") {
      throw new HttpsError("failed-precondition", "Este chat ya no esta disponible.");
    }
    const receiverId = users.find((u) => u !== senderId) ?? "";
    const matchId = (chat.matchId ?? chatId).toString();

    const now = FieldValue.serverTimestamp();
    const journey = journeyPatch(
      tx,
      matchId,
      chat.journeyStatus,
      "date_proposed",
      now
    );
    tx.set(messageRef, {
      senderId,
      receiverId,
      type: "date_proposal",
      text: placeName,
      status: "sent",
      dateProposal: {
        proposedDate,
        proposedTime,
        placeName,
        placeAddress,
        note,
        status: "pending",
        proposedBy: senderId,
      },
      createdAt: now,
    });
    tx.update(chatRef, {
      lastMessage: "Propuesta de cita",
      lastMessageType: "date_proposal",
      lastMessageSenderId: senderId,
      lastMessageAt: now,
      updatedAt: now,
      realMessageCount: FieldValue.increment(1),
      ...journey,
      [`unreadCountByUser.${receiverId}`]: FieldValue.increment(1),
    });
    return messageRef.id;
  });

  return { messageId };
});

const CLOSURE_REASONS = [
  "no_connection",
  "different_goals",
  "not_now",
  "save_time",
  "custom",
];
const MAX_CLOSURE_LENGTH = 500;

/// closeConversationGracefully (Attra Clear §3): cierra un chat ACTIVO con un
/// mensaje de despedida respetuoso. Es autoritativo: escribe el mensaje `closure`
/// y marca el chat `closed` con metadatos (closedBy/Reason/Message) en una única
/// transacción. Tras cerrar, el chat no admite más mensajes (status != active).
/// Cuenta positivamente en métricas de fiabilidad (best-effort, §7).
export const closeConversationGracefully = onCall(
  { region: REGION },
  async (request) => {
    const senderId = requireAuthUid(request.auth);
    const chatId = requireStringArg(request.data?.chatId, "chatId");
    const reason = requireStringArg(request.data?.reason, "reason");
    if (!CLOSURE_REASONS.includes(reason)) {
      throw new HttpsError("invalid-argument", "Motivo de cierre no válido.");
    }
    const message = requireStringArg(request.data?.message, "message").slice(
      0,
      MAX_CLOSURE_LENGTH
    );

    const chatRef = col.chats.doc(chatId);
    const messageRef = chatRef.collection("messages").doc();

    const messageId = await db.runTransaction(async (tx): Promise<string> => {
      const chatSnap = await tx.get(chatRef);
      if (!chatSnap.exists) {
        throw new HttpsError("not-found", "El chat no existe.");
      }
      const chat = chatSnap.data() ?? {};
      const users: string[] = (chat.users ?? []) as string[];
      if (!users.includes(senderId)) {
        throw new HttpsError("permission-denied", "No participas en este chat.");
      }
      if ((chat.status ?? "active") !== "active") {
        throw new HttpsError(
          "failed-precondition",
          "Este chat ya no esta disponible."
        );
      }
      const receiverId = users.find((u) => u !== senderId) ?? "";
      const matchId = (chat.matchId ?? chatId).toString();
      const now = FieldValue.serverTimestamp();
      const journey = journeyPatch(
        tx,
        matchId,
        chat.journeyStatus,
        "archived",
        now
      );

      tx.set(messageRef, {
        senderId,
        receiverId,
        type: "closure",
        text: message,
        status: "sent",
        createdAt: now,
      });
      tx.update(chatRef, {
        status: "closed",
        closedAt: now,
        closedByUserId: senderId,
        closedReason: reason,
        closedMessage: message,
        lastMessage: message,
        lastMessageType: "closure",
        lastMessageSenderId: senderId,
        lastMessageAt: now,
        updatedAt: now,
        realMessageCount: FieldValue.increment(1),
        ...journey,
        [`unreadCountByUser.${receiverId}`]: FieldValue.increment(1),
      });
      return messageRef.id;
    });

    // Métrica de fiabilidad (§7): cerrar con respeto suma. Best-effort: nunca
    // tumba el cierre si falla.
    await col.users
      .doc(senderId)
      .set(
        {
          connectionReliabilityStats: {
            closedChatsRespectfullyCount: FieldValue.increment(1),
          },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      )
      .catch(() => undefined);

    return { messageId };
  }
);

/// respondDateProposal: el RECEPTOR responde a una propuesta (accepted |
/// declined | countered). Solo el receptor (no el proponente) puede responder.
export const respondDateProposal = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const chatId = requireStringArg(request.data?.chatId, "chatId");
  const messageId = requireStringArg(request.data?.messageId, "messageId");
  const response = requireStringArg(request.data?.response, "response");
  if (!["accepted", "declined", "countered"].includes(response)) {
    throw new HttpsError("invalid-argument", "Respuesta invalida.");
  }

  const chatRef = col.chats.doc(chatId);
  const messageRef = chatRef.collection("messages").doc(messageId);

  await db.runTransaction(async (tx): Promise<void> => {
    const [chatSnap, msgSnap] = await Promise.all([
      tx.get(chatRef),
      tx.get(messageRef),
    ]);
    if (!chatSnap.exists) throw new HttpsError("not-found", "El chat no existe.");
    if (!msgSnap.exists) throw new HttpsError("not-found", "La propuesta no existe.");
    const chat = chatSnap.data() ?? {};
    const users: string[] = (chat.users ?? []) as string[];
    if (!users.includes(uid)) {
      throw new HttpsError("permission-denied", "No participas en este chat.");
    }
    if ((chat.status ?? "active") !== "active") {
      throw new HttpsError("failed-precondition", "Este chat ya no esta disponible.");
    }
    const msg = msgSnap.data() ?? {};
    if (msg.type !== "date_proposal") {
      throw new HttpsError("invalid-argument", "Ese mensaje no es una propuesta.");
    }
    if (msg.senderId === uid) {
      throw new HttpsError("failed-precondition", "No puedes responder tu propia propuesta.");
    }
    const now = FieldValue.serverTimestamp();
    tx.update(messageRef, {
      "dateProposal.status": response,
      "dateProposal.respondedAt": now,
    });
    if (response === "accepted") {
      const matchId = (chat.matchId ?? chatId).toString();
      const journey = journeyPatch(
        tx,
        matchId,
        chat.journeyStatus,
        "date_accepted",
        now
      );
      // Attra Clear §6: arma el follow-up post-cita. dateScheduledAt = fecha+hora
      // propuestas (UTC aprox); el cliente muestra "¿Cómo fue la cita?" pasadas
      // 24h. Si la fecha es inválida, queda null y no hay follow-up automático.
      const dp = (msg.dateProposal ?? {}) as DocumentData;
      const scheduledAt = parseDateTime(dp.proposedDate, dp.proposedTime);
      tx.update(chatRef, {
        updatedAt: now,
        ...journey,
        hasDateProposal: true,
        dateProposalStatus: "accepted",
        dateScheduledAt: scheduledAt,
        dateFollowUpStatus: "pending",
      });
    }
  });

  return { ok: true };
});
