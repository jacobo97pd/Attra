import { onCall, HttpsError } from "firebase-functions/v2/https";
import { DocumentData, FieldValue, Transaction } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import {
  JourneyStatus,
  col,
  existsBlockBetween,
  nextJourneyStatus,
  requireAuthUid,
  requireStringArg,
} from "./common";

const MAX_GAME_TEXT = 240;
const DOUBLE_DAILY_FREE_LIMIT = 1;

function sanitize(value: unknown, max = MAX_GAME_TEXT): string {
  if (typeof value !== "string") return "";
  return value.replace(/\s+/g, " ").trim().slice(0, max);
}

function asUsers(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((x): x is string => typeof x === "string")
    : [];
}

function activeTier(entData: DocumentData | undefined): string {
  const tier = (entData?.tier ?? "free").toString();
  if (tier !== "plus" && tier !== "premium" && tier !== "pro") return "free";
  if (entData?.isLifetime === true) return tier;
  const expiresAt = entData?.expiresAt;
  if (expiresAt && typeof expiresAt === "object" && "toMillis" in expiresAt) {
    const ms = (expiresAt as { toMillis(): number }).toMillis();
    if (ms < Date.now()) return "free";
  }
  return tier;
}

function dailyKey(date = new Date()): string {
  return date.toISOString().slice(0, 10).replace(/-/g, "");
}

function usageRef(uid: string) {
  return col.users.doc(uid).collection("journeyUsage").doc(dailyKey());
}

function canUseGame(tier: string, used: number): boolean {
  if (tier === "pro") return true;
  if (tier === "plus" || tier === "premium") return used < 5;
  return used < DOUBLE_DAILY_FREE_LIMIT;
}

async function requireChat(uid: string, chatId: string): Promise<string[]> {
  const chatSnap = await col.chats.doc(chatId).get();
  if (!chatSnap.exists) throw new HttpsError("not-found", "El chat no existe.");
  const chat = chatSnap.data() ?? {};
  const users = asUsers(chat.users);
  if (!users.includes(uid)) {
    throw new HttpsError("permission-denied", "No participas en este chat.");
  }
  if ((chat.status ?? "active") !== "active") {
    throw new HttpsError("failed-precondition", "Este chat ya no esta disponible.");
  }
  const otherUid = users.find((u) => u !== uid) ?? "";
  if (otherUid && (await existsBlockBetween(uid, otherUid))) {
    throw new HttpsError("permission-denied", "No puedes escribir a este usuario.");
  }
  return users;
}

function journeyPatch(
  tx: Transaction,
  chat: DocumentData,
  matchId: string,
  candidate: JourneyStatus,
  now: FieldValue
): Record<string, unknown> {
  const journeyStatus = nextJourneyStatus(chat.journeyStatus, candidate);
  const patch = { journeyStatus, journeyUpdatedAt: now };
  tx.set(col.matches.doc(matchId), patch, { merge: true });
  return patch;
}

async function assertGameQuota(uid: string): Promise<void> {
  const [entSnap, usageSnap] = await Promise.all([
    col.entitlements.doc(uid).get(),
    usageRef(uid).get(),
  ]);
  const tier = activeTier(entSnap.data());
  const used = Number(usageSnap.data()?.miniGamesStarted ?? 0);
  if (!canUseGame(tier, used)) {
    throw new HttpsError(
      "resource-exhausted",
      "Has alcanzado el limite diario de juegos para tu plan."
    );
  }
}

function privateAnswerRef(chatId: string, messageId: string, uid: string) {
  return col.chats
    .doc(chatId)
    .collection("privateAnswers")
    .doc(`${messageId}_${uid}`);
}

export const startDoubleAnswer = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const chatId = requireStringArg(request.data?.chatId, "chatId");
  const question = sanitize(request.data?.question, 180);
  if (!question) {
    throw new HttpsError("invalid-argument", "Falta la pregunta.");
  }
  await requireChat(uid, chatId);
  await assertGameQuota(uid);

  const chatRef = col.chats.doc(chatId);
  const messageRef = chatRef.collection("messages").doc();
  const usage = usageRef(uid);

  const messageId = await db.runTransaction(async (tx): Promise<string> => {
    const chatSnap = await tx.get(chatRef);
    if (!chatSnap.exists) throw new HttpsError("not-found", "El chat no existe.");
    const chat = chatSnap.data() ?? {};
    const users = asUsers(chat.users);
    if (!users.includes(uid)) {
      throw new HttpsError("permission-denied", "No participas en este chat.");
    }
    if ((chat.status ?? "active") !== "active") {
      throw new HttpsError("failed-precondition", "Este chat ya no esta disponible.");
    }
    const receiverId = users.find((u) => u !== uid) ?? "";
    const now = FieldValue.serverTimestamp();
    const matchId = (chat.matchId ?? chatId).toString();
    const journey = journeyPatch(tx, chat, matchId, "game_started", now);

    tx.set(messageRef, {
      senderId: uid,
      receiverId,
      type: "double_answer",
      text: question,
      status: "sent",
      doubleAnswer: {
        question,
        status: "collecting",
        startedBy: uid,
        participants: users,
        answeredBy: Object.fromEntries(users.map((u) => [u, false])),
        answers: {},
        revealedAt: null,
      },
      createdAt: now,
    });
    tx.update(chatRef, {
      lastMessage: "Doble respuesta",
      lastMessageType: "double_answer",
      lastMessageSenderId: uid,
      lastMessageAt: now,
      updatedAt: now,
      ...journey,
      [`unreadCountByUser.${receiverId}`]: FieldValue.increment(1),
    });
    tx.set(
      usage,
      {
        miniGamesStarted: FieldValue.increment(1),
        updatedAt: now,
      },
      { merge: true }
    );
    return messageRef.id;
  });

  return { messageId };
});

export const submitDoubleAnswer = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const chatId = requireStringArg(request.data?.chatId, "chatId");
  const messageId = requireStringArg(request.data?.messageId, "messageId");
  const answer = sanitize(request.data?.answer);
  if (!answer) throw new HttpsError("invalid-argument", "Falta la respuesta.");
  await requireChat(uid, chatId);

  const chatRef = col.chats.doc(chatId);
  const messageRef = chatRef.collection("messages").doc(messageId);
  const ownAnswerRef = privateAnswerRef(chatId, messageId, uid);

  await db.runTransaction(async (tx): Promise<void> => {
    const [chatSnap, msgSnap, ownSnap] = await Promise.all([
      tx.get(chatRef),
      tx.get(messageRef),
      tx.get(ownAnswerRef),
    ]);
    if (!chatSnap.exists) throw new HttpsError("not-found", "El chat no existe.");
    if (!msgSnap.exists) throw new HttpsError("not-found", "El juego no existe.");
    if (ownSnap.exists) {
      throw new HttpsError("failed-precondition", "Ya has respondido.");
    }
    const chat = chatSnap.data() ?? {};
    const users = asUsers(chat.users);
    if (!users.includes(uid)) {
      throw new HttpsError("permission-denied", "No participas en este chat.");
    }
    const msg = msgSnap.data() ?? {};
    if (msg.type !== "double_answer") {
      throw new HttpsError("invalid-argument", "Ese mensaje no es Doble Respuesta.");
    }
    const otherUid = users.find((u) => u !== uid) ?? "";
    const otherAnswerRef = privateAnswerRef(chatId, messageId, otherUid);
    const otherSnap = otherUid ? await tx.get(otherAnswerRef) : null;
    const now = FieldValue.serverTimestamp();
    const answeredBy = {
      ...((msg.doubleAnswer?.answeredBy ?? {}) as Record<string, boolean>),
      [uid]: true,
    };

    tx.set(ownAnswerRef, {
      kind: "double_answer",
      chatId,
      messageId,
      uid,
      answer,
      createdAt: now,
    });

    if (otherSnap?.exists) {
      const otherAnswer = sanitize(otherSnap.data()?.answer);
      const answers: Record<string, string> = {
        [uid]: answer,
        [otherUid]: otherAnswer,
      };
      const matchId = (chat.matchId ?? chatId).toString();
      const journey = journeyPatch(tx, chat, matchId, "game_completed", now);
      tx.update(messageRef, {
        "doubleAnswer.status": "revealed",
        "doubleAnswer.answeredBy": answeredBy,
        "doubleAnswer.answers": answers,
        "doubleAnswer.revealedAt": now,
      });
      tx.update(chatRef, {
        lastMessage: "Doble respuesta revelada",
        lastMessageType: "double_answer",
        lastMessageSenderId: uid,
        lastMessageAt: now,
        updatedAt: now,
        ...journey,
      });
    } else {
      tx.update(messageRef, {
        "doubleAnswer.answeredBy": answeredBy,
      });
    }
  });

  return { ok: true };
});

export const startTwoTruths = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const chatId = requireStringArg(request.data?.chatId, "chatId");
  const rawStatements = Array.isArray(request.data?.statements)
    ? (request.data.statements as unknown[])
    : [];
  const statements = rawStatements.map((v) => sanitize(v, 140));
  const lieIndex = Number(request.data?.lieIndex);
  if (
    statements.length !== 3 ||
    statements.some((s) => !s) ||
    !Number.isInteger(lieIndex) ||
    lieIndex < 0 ||
    lieIndex > 2
  ) {
    throw new HttpsError("invalid-argument", "Necesitas 3 frases y marcar la mentira.");
  }
  await requireChat(uid, chatId);
  await assertGameQuota(uid);

  const chatRef = col.chats.doc(chatId);
  const messageRef = chatRef.collection("messages").doc();
  const usage = usageRef(uid);

  const messageId = await db.runTransaction(async (tx): Promise<string> => {
    const chatSnap = await tx.get(chatRef);
    if (!chatSnap.exists) throw new HttpsError("not-found", "El chat no existe.");
    const chat = chatSnap.data() ?? {};
    const users = asUsers(chat.users);
    if (!users.includes(uid)) {
      throw new HttpsError("permission-denied", "No participas en este chat.");
    }
    if ((chat.status ?? "active") !== "active") {
      throw new HttpsError("failed-precondition", "Este chat ya no esta disponible.");
    }
    const receiverId = users.find((u) => u !== uid) ?? "";
    const now = FieldValue.serverTimestamp();
    const matchId = (chat.matchId ?? chatId).toString();
    const journey = journeyPatch(tx, chat, matchId, "game_started", now);

    tx.set(messageRef, {
      senderId: uid,
      receiverId,
      type: "two_truths",
      text: "Dos verdades y una mentira",
      status: "sent",
      twoTruths: {
        statements,
        status: "guessing",
        startedBy: uid,
        guessedBy: null,
        guessIndex: null,
        lieIndex: null,
        correct: null,
        revealedAt: null,
      },
      createdAt: now,
    });
    tx.set(privateAnswerRef(chatId, messageRef.id, uid), {
      kind: "two_truths",
      chatId,
      messageId: messageRef.id,
      uid,
      lieIndex,
      createdAt: now,
    });
    tx.update(chatRef, {
      lastMessage: "Dos verdades y una mentira",
      lastMessageType: "two_truths",
      lastMessageSenderId: uid,
      lastMessageAt: now,
      updatedAt: now,
      ...journey,
      [`unreadCountByUser.${receiverId}`]: FieldValue.increment(1),
    });
    tx.set(
      usage,
      {
        miniGamesStarted: FieldValue.increment(1),
        updatedAt: now,
      },
      { merge: true }
    );
    return messageRef.id;
  });

  return { messageId };
});

export const guessTwoTruths = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const chatId = requireStringArg(request.data?.chatId, "chatId");
  const messageId = requireStringArg(request.data?.messageId, "messageId");
  const guessIndex = Number(request.data?.guessIndex);
  if (!Number.isInteger(guessIndex) || guessIndex < 0 || guessIndex > 2) {
    throw new HttpsError("invalid-argument", "Respuesta invalida.");
  }
  await requireChat(uid, chatId);

  const chatRef = col.chats.doc(chatId);
  const messageRef = chatRef.collection("messages").doc(messageId);

  await db.runTransaction(async (tx): Promise<void> => {
    const [chatSnap, msgSnap] = await Promise.all([
      tx.get(chatRef),
      tx.get(messageRef),
    ]);
    if (!chatSnap.exists) throw new HttpsError("not-found", "El chat no existe.");
    if (!msgSnap.exists) throw new HttpsError("not-found", "El juego no existe.");
    const chat = chatSnap.data() ?? {};
    const users = asUsers(chat.users);
    if (!users.includes(uid)) {
      throw new HttpsError("permission-denied", "No participas en este chat.");
    }
    const msg = msgSnap.data() ?? {};
    if (msg.type !== "two_truths") {
      throw new HttpsError("invalid-argument", "Ese mensaje no es Dos Verdades.");
    }
    if (msg.senderId === uid) {
      throw new HttpsError("failed-precondition", "No puedes adivinar tu propio juego.");
    }
    if (msg.twoTruths?.status === "revealed") {
      throw new HttpsError("failed-precondition", "Este juego ya esta revelado.");
    }
    const answerRef = privateAnswerRef(chatId, messageId, msg.senderId as string);
    const answerSnap = await tx.get(answerRef);
    if (!answerSnap.exists) {
      throw new HttpsError("failed-precondition", "No se encontro la respuesta privada.");
    }
    const lieIndex = Number(answerSnap.data()?.lieIndex);
    const now = FieldValue.serverTimestamp();
    const matchId = (chat.matchId ?? chatId).toString();
    const journey = journeyPatch(tx, chat, matchId, "game_completed", now);
    tx.update(messageRef, {
      "twoTruths.status": "revealed",
      "twoTruths.guessedBy": uid,
      "twoTruths.guessIndex": guessIndex,
      "twoTruths.lieIndex": lieIndex,
      "twoTruths.correct": guessIndex === lieIndex,
      "twoTruths.revealedAt": now,
    });
    tx.update(chatRef, {
      lastMessage: guessIndex === lieIndex
        ? "Adivino la mentira"
        : "No adivino la mentira",
      lastMessageType: "two_truths",
      lastMessageSenderId: uid,
      lastMessageAt: now,
      updatedAt: now,
      ...journey,
    });
  });

  return { ok: true };
});
