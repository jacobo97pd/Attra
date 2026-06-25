import { onCall, HttpsError } from "firebase-functions/v2/https";
import { DocumentData, FieldValue, Timestamp } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { col, existsBlockBetween, requireAuthUid, requireStringArg } from "./common";
import { moderateComment } from "./moderation";

/// "Duelo de Química" (5-Minute Spark): reto de conversación de 5 minutos en el
/// chat. Backend-autoritativo. Vive en `chats/{chatId}/gameSessions/{sessionId}`.
///
/// Seguridad por diseño: temas de un CATÁLOGO CURADO (nada político/sexual/
/// sensible), planes de cita SIEMPRE en lugares públicos, sin presión económica,
/// se puede abandonar sin penalización, y se modera el tono.

const GAME_DURATION_MS = 5 * 60 * 1000; // 5 min
const MIN_MESSAGES_TO_JUDGE = 4; // por debajo => "sin ganador, seguid hablando"

type GameMode = "normal" | "coffee_challenge";

interface Theme {
  id: string;
  title: string;
  category: string;
}

/// Catálogo curado de temas/retos. Suaves, divertidos, de planes/gustos/valores.
/// NUNCA política extrema, sexual explícito ni sensible.
const THEMES: Theme[] = [
  { id: "date_20", category: "plans", title: "Tenéis 5 minutos para diseñar vuestra cita perfecta con solo 20€." },
  { id: "convince_plan", category: "plans", title: "Cada uno tiene que convencer al otro de hacer su plan favorito este finde." },
  { id: "quick_choice", category: "choose_one", title: "Responded rápido: café tranquilo, paseo nocturno o cena improvisada. Defended vuestra elección." },
  { id: "elegant_vs_chaos", category: "fun", title: "Uno propone un plan elegante y el otro uno caótico. ¿Cuál tiene más química?" },
  { id: "memorable_3", category: "ideal_dates", title: "Decid tres cosas que harían que una primera cita fuera memorable." },
  { id: "perfect_sunday", category: "tastes", title: "Describid vuestro domingo perfecto. ¿Encajan?" },
  { id: "two_truths_value", category: "values", title: "Cada uno dice algo que valora de verdad en alguien. Sin postureo." },
  { id: "absurd_superpower", category: "absurd_dilemmas", title: "Si pudierais tener un superpoder inútil para una cita, ¿cuál sería?" },
  { id: "playlist", category: "tastes", title: "Montad la playlist de 3 canciones para vuestra primera cita." },
  { id: "city_escape", category: "plans", title: "Os tocan 24h en cualquier ciudad. ¿A dónde y qué hacéis?" },
  { id: "dealbreaker_fun", category: "compatibility", title: "Decid un detalle pequeño que os enamora y otro que os hace gracia." },
  { id: "coffee_or", category: "choose_one", title: "Café de especialidad o chocolate caliente de invierno. Argumentad." },
];

function pickTheme(): Theme {
  return THEMES[Math.floor(Math.random() * THEMES.length)];
}

/// Planes de cita sugeridos (SIEMPRE lugares públicos). Se elige uno acorde al
/// resultado; nunca propone sitios privados ni presiona.
const DATE_PLANS = [
  { title: "Café con calma", description: "Una cafetería tranquila para charlar sin prisa.", placeType: "cafetería" },
  { title: "Paseo y helado", description: "Un paseo por el centro o un parque y un helado.", placeType: "parque" },
  { title: "Mercado y tapeo", description: "Daos una vuelta por un mercado y picad algo rico.", placeType: "mercado" },
  { title: "Plan de museo", description: "Una expo o museo y comentar lo que más os llame.", placeType: "museo" },
  { title: "Atardecer con vistas", description: "Un mirador público al atardecer.", placeType: "mirador" },
];

function pickDatePlan() {
  return DATE_PLANS[Math.floor(Math.random() * DATE_PLANS.length)];
}

interface Msg {
  senderId: string;
  text: string;
}

interface UserStats {
  messages: number;
  words: number;
  questions: number;
  humor: number;
  interest: number;
  uniqueRatio: number;
}

function emptyStats(): UserStats {
  return { messages: 0, words: 0, questions: 0, humor: 0, interest: 0, uniqueRatio: 0 };
}

const HUMOR_RE = /(jaja|jeje|haha|lol|😂|🤣|😅|😆|😜|🙃)/i;
const INTEREST_RE = /(\btú\b|\bte\b|\bti\b|\bcontigo\b|\?|me cuentas|y tú)/i;

function statsFor(uid: string, msgs: Msg[]): UserStats {
  const mine = msgs.filter((m) => m.senderId === uid);
  const s = emptyStats();
  const allWords: string[] = [];
  for (const m of mine) {
    const t = m.text.trim();
    if (!t) continue;
    s.messages += 1;
    const words = t.split(/\s+/).filter(Boolean);
    s.words += words.length;
    allWords.push(...words.map((w) => w.toLowerCase()));
    if (t.includes("?")) s.questions += 1;
    if (HUMOR_RE.test(t)) s.humor += 1;
    if (INTEREST_RE.test(t)) s.interest += 1;
  }
  s.uniqueRatio = allWords.length > 0 ? new Set(allWords).size / allWords.length : 0;
  return s;
}

/// Puntuación compuesta (0..1 aprox) según los criterios pedidos: participación,
/// preguntas, humor, interés genuino, naturalidad/originalidad. NUNCA físico.
function compositeScore(s: UserStats): number {
  const participation = Math.min(s.messages / 5, 1); // ~5 msgs = pleno
  const questions = Math.min(s.questions / 3, 1);
  const humor = Math.min(s.humor / 2, 1);
  const interest = Math.min(s.interest / 3, 1);
  const naturalness = s.words === 0 ? 0 : Math.min(s.words / (s.messages * 8), 1); // frases con cuerpo
  const originality = s.uniqueRatio; // variedad de vocabulario
  return (
    participation * 0.3 +
    questions * 0.25 +
    interest * 0.2 +
    humor * 0.1 +
    naturalness * 0.1 +
    originality * 0.05
  );
}

interface AiResult {
  winnerUserId: string | null;
  isDraw: boolean;
  chemistryScore: number;
  bestMoment: string;
  reason: string;
  suggestedDatePlan: {
    title: string;
    description: string;
    placeType: string;
    payerSuggestion: "winner_chooses" | "loser_invites" | "split" | "none";
  };
  followUpMessage: string;
  noWinner: boolean;
}

/// Análisis HEURÍSTICO (determinista, server-side). Punto de integración para
/// Gemini en Pro (análisis avanzado): bastaría sustituir esta función.
function analyzeConversation(
  msgs: Msg[],
  uidA: string,
  uidB: string,
  nameA: string,
  nameB: string,
  mode: GameMode
): AiResult {
  const total = msgs.filter((m) => m.text.trim().length > 0).length;
  const sa = statsFor(uidA, msgs);
  const sb = statsFor(uidB, msgs);

  // Sin material suficiente: no hay ganador, se propone seguir.
  if (total < MIN_MESSAGES_TO_JUDGE || sa.messages === 0 || sb.messages === 0) {
    return {
      winnerUserId: null,
      isDraw: false,
      chemistryScore: Math.min(40 + total * 5, 60),
      bestMoment: "",
      reason: "Os habéis quedado cortos de tiempo para decidir. ¡Pero la cosa promete!",
      suggestedDatePlan: { ...pickDatePlan(), payerSuggestion: "none" },
      followUpMessage: "¿Y si seguís? Contadme: ¿qué plan haríais este finde?",
      noWinner: true,
    };
  }

  const scoreA = compositeScore(sa);
  const scoreB = compositeScore(sb);
  const diff = Math.abs(scoreA - scoreB);
  const isDraw = diff < 0.08; // muy parejo => empate
  const winner = isDraw ? null : scoreA > scoreB ? uidA : uidB;
  const winnerName = winner === uidA ? nameA : nameB;

  // Química: participación equilibrada + volumen + reciprocidad de preguntas.
  const balance = 1 - Math.min(Math.abs(sa.messages - sb.messages) / Math.max(sa.messages + sb.messages, 1), 1);
  const reciprocity = Math.min((sa.questions + sb.questions) / 4, 1);
  const volume = Math.min((sa.messages + sb.messages) / 10, 1);
  const chemistryScore = Math.round((balance * 0.4 + reciprocity * 0.35 + volume * 0.25) * 100);

  // Mejor momento: el mensaje más "con cuerpo" (largo + pregunta/humor).
  let best = "";
  let bestScore = -1;
  for (const m of msgs) {
    const t = m.text.trim();
    if (!t) continue;
    const sc = t.split(/\s+/).length + (t.includes("?") ? 4 : 0) + (HUMOR_RE.test(t) ? 3 : 0);
    if (sc > bestScore) {
      bestScore = sc;
      best = t;
    }
  }
  best = best.slice(0, 140);

  // Razón amable según la señal dominante del ganador.
  let reason: string;
  if (isDraw) {
    reason = "Empate de química: los dos habéis preguntado, respondido y mantenido viva la conversación.";
  } else {
    const ws = winner === uidA ? sa : sb;
    if (ws.questions >= 2) {
      reason = `Ha ganado ${winnerName} por hacer mejores preguntas y mantener viva la conversación.`;
    } else if (ws.humor >= 1) {
      reason = `Ha ganado ${winnerName} por poner el toque de humor y buen rollo.`;
    } else {
      reason = `Ha ganado ${winnerName} por participar con naturalidad e interés genuino.`;
    }
  }

  // Premio (solo dinámica divertida). Reto Café cambia el texto del premio.
  let payer: AiResult["suggestedDatePlan"]["payerSuggestion"];
  if (isDraw) {
    payer = mode === "coffee_challenge" ? "split" : "none";
  } else {
    payer = mode === "coffee_challenge" ? "loser_invites" : "winner_chooses";
  }

  let followUp: string;
  if (mode === "coffee_challenge" && !isDraw) {
    const loserName = winner === uidA ? nameB : nameA;
    followUp = `Como reto café: ${loserName} invita al primer café. Solo si os apetece, claro. 😊`;
  } else if (!isDraw) {
    followUp = `Como premio, ${winnerName} elige el plan; el otro propone día y hora. ¿Os animáis?`;
  } else {
    followUp = "Plan a medias. ¿Quién propone día y hora?";
  }

  return {
    winnerUserId: winner,
    isDraw,
    chemistryScore,
    bestMoment: best,
    reason,
    suggestedDatePlan: { ...pickDatePlan(), payerSuggestion: payer },
    followUpMessage: followUp,
    noWinner: false,
  };
}

function parseMode(value: unknown): GameMode {
  return value === "coffee_challenge" ? "coffee_challenge" : "normal";
}

async function loadChat(chatId: string, uid: string) {
  const chatRef = col.chats.doc(chatId);
  const snap = await chatRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "El chat no existe.");
  const data = snap.data() ?? {};
  const users: string[] = (data.users ?? []) as string[];
  if (!users.includes(uid)) {
    throw new HttpsError("permission-denied", "No participas en este chat.");
  }
  const other = users.find((u) => u !== uid) ?? "";
  return { chatRef, data, users, other, matchId: (data.matchId ?? chatId).toString() };
}

/// startChatGame: crea la sesión (pending) y la tarjeta de invitación en el chat.
export const startChatGame = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const chatId = requireStringArg(request.data?.chatId, "chatId");
  const mode = parseMode(request.data?.mode);
  const { chatRef, other, matchId } = await loadChat(chatId, uid);
  if (await existsBlockBetween(uid, other)) {
    throw new HttpsError("permission-denied", "No disponible.");
  }

  const sessionRef = chatRef.collection("gameSessions").doc();
  const messageRef = chatRef.collection("messages").doc();
  const now = FieldValue.serverTimestamp();

  await db.runTransaction(async (tx) => {
    tx.set(sessionRef, {
      chatId,
      matchId,
      creatorUserId: uid,
      invitedUserId: other,
      status: "pending",
      mode,
      acceptedBy: [uid], // quien invita ya acepta
      createdAt: now,
    });
    tx.set(messageRef, {
      senderId: uid,
      receiverId: other,
      type: "chat_game",
      text: mode === "coffee_challenge" ? "Reto Café · Duelo de Química" : "Duelo de Química",
      status: "sent",
      gameSessionId: sessionRef.id,
      createdAt: now,
    });
    tx.set(
      chatRef,
      {
        lastMessage: "Te reta a un Duelo de Química ⚡",
        lastMessageType: "chat_game",
        lastMessageSenderId: uid,
        lastMessageAt: now,
        updatedAt: now,
        [`unreadCountByUser.${other}`]: FieldValue.increment(1),
      },
      { merge: true }
    );
  });

  console.log(`[chatGame] start chat=${chatId} session=${sessionRef.id} mode=${mode}`);
  return { sessionId: sessionRef.id };
});

/// respondChatGame: el invitado acepta/rechaza. Si ambos aceptan, arranca el
/// reto (tema del catálogo + cuenta atrás de 5 min) y publica el tema.
export const respondChatGame = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const chatId = requireStringArg(request.data?.chatId, "chatId");
  const sessionId = requireStringArg(request.data?.sessionId, "sessionId");
  const accept = request.data?.accept === true;
  const { chatRef } = await loadChat(chatId, uid);
  const sessionRef = chatRef.collection("gameSessions").doc(sessionId);

  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(sessionRef);
    if (!snap.exists) throw new HttpsError("not-found", "Reto no encontrado.");
    const s = snap.data() ?? {};
    if (s.status !== "pending") {
      return { changed: false, theme: null as Theme | null };
    }
    if (uid !== s.invitedUserId && uid !== s.creatorUserId) {
      throw new HttpsError("permission-denied", "No participas en este reto.");
    }
    const now = FieldValue.serverTimestamp();
    if (!accept) {
      tx.update(sessionRef, { status: "cancelled", completedAt: now });
      return { changed: true, theme: null as Theme | null };
    }
    const acceptedBy: string[] = Array.from(new Set([...(s.acceptedBy ?? []), uid]));
    const both = acceptedBy.includes(s.creatorUserId) && acceptedBy.includes(s.invitedUserId);
    if (!both) {
      tx.update(sessionRef, { acceptedBy, status: "accepted" });
      return { changed: true, theme: null as Theme | null };
    }
    // Ambos aceptan => arranca.
    const theme = pickTheme();
    const endsAt = Timestamp.fromMillis(Date.now() + GAME_DURATION_MS);
    tx.update(sessionRef, {
      acceptedBy,
      status: "active",
      themeId: theme.id,
      themeTitle: theme.title,
      themeCategory: theme.category,
      startedAt: now,
      endsAt,
    });
    return { changed: true, theme };
  });

  // Si arrancó, publica el tema como mensaje de sistema (la IA analizará SOLO
  // los mensajes de estos 5 minutos).
  if (result.theme) {
    const now = FieldValue.serverTimestamp();
    await chatRef.collection("messages").doc(`gamestart_${sessionId}`).set(
      {
        senderId: "system",
        receiverId: "",
        type: "system",
        text: `⚡ Duelo de Química · 5 min\n${result.theme.title}`,
        status: "sent",
        gameSessionId: sessionId,
        createdAt: now,
      },
      { merge: true }
    );
    await chatRef.set(
      {
        lastMessage: "¡Empieza el Duelo de Química! ⚡",
        lastMessageType: "system",
        lastMessageAt: now,
        updatedAt: now,
      },
      { merge: true }
    );
  }
  return { ok: true };
});

/// finishChatGame: al agotarse el tiempo, la IA analiza SOLO los mensajes de la
/// sesión y emite el resultado. Idempotente.
export const finishChatGame = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const chatId = requireStringArg(request.data?.chatId, "chatId");
  const sessionId = requireStringArg(request.data?.sessionId, "sessionId");
  const { chatRef, data: chatData } = await loadChat(chatId, uid);
  const sessionRef = chatRef.collection("gameSessions").doc(sessionId);

  const snap = await sessionRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "Reto no encontrado.");
  const s = snap.data() ?? {};
  if (s.status !== "active") return { ok: true, alreadyDone: true };

  // Solo mensajes de ESTA sesión (privacidad: nada de conversaciones antiguas).
  const msgsSnap = await chatRef
    .collection("messages")
    .where("gameSessionId", "==", sessionId)
    .get();
  const msgs: Msg[] = msgsSnap.docs
    .map((d) => d.data() as DocumentData)
    .filter((m) => m.type === "text" && typeof m.text === "string")
    .map((m) => ({ senderId: (m.senderId ?? "").toString(), text: (m.text ?? "").toString() }));

  // Moderación de tono: si algo grave, se cancela con aviso amable.
  const flagged = msgs.some((m) => moderateComment(m.text).reason === "banned");
  const uidA = (s.creatorUserId ?? "").toString();
  const uidB = (s.invitedUserId ?? "").toString();
  const names = await resolveNames(chatData, uidA, uidB);
  const mode = parseMode(s.mode);

  const now = FieldValue.serverTimestamp();
  if (flagged) {
    await sessionRef.update({ status: "cancelled", completedAt: now });
    await postSystem(chatRef, sessionId, "El reto se ha pausado para mantener el buen rollo. Seguid cuando queráis. 💛");
    return { ok: true, cancelled: true };
  }

  const result = analyzeConversation(msgs, uidA, uidB, names.a, names.b, mode);
  await sessionRef.update({
    status: "completed",
    completedAt: now,
    result,
    analyzedMessages: msgs.length,
  });

  // Mensaje de resultado de la IA en el chat.
  const lines: string[] = [];
  if (result.noWinner) {
    lines.push("Sin ganador esta vez.");
  } else if (result.isDraw) {
    lines.push("¡Empate de química! 💞");
  } else {
    lines.push(result.reason);
  }
  if (result.bestMoment) lines.push(`🌟 Mejor momento: "${result.bestMoment}"`);
  lines.push(`💘 Química: ${result.chemistryScore}/100`);
  if (result.followUpMessage) lines.push(result.followUpMessage);
  await postSystem(chatRef, sessionId, lines.join("\n"));

  console.log(`[chatGame] finish chat=${chatId} session=${sessionId} winner=${result.winnerUserId} chem=${result.chemistryScore}`);
  return { ok: true };
});

/// abandonChatGame: salir del reto sin penalización.
export const abandonChatGame = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const chatId = requireStringArg(request.data?.chatId, "chatId");
  const sessionId = requireStringArg(request.data?.sessionId, "sessionId");
  const { chatRef } = await loadChat(chatId, uid);
  const sessionRef = chatRef.collection("gameSessions").doc(sessionId);
  const snap = await sessionRef.get();
  if (!snap.exists) return { ok: true };
  const s = snap.data() ?? {};
  if (s.status === "completed" || s.status === "cancelled" || s.status === "abandoned") {
    return { ok: true };
  }
  await sessionRef.update({ status: "abandoned", completedAt: FieldValue.serverTimestamp() });
  await postSystem(chatRef, sessionId, "El reto se ha cancelado. Sin problema, ¡seguid a vuestro ritmo! 😊");
  return { ok: true };
});

async function resolveNames(chatData: DocumentData, uidA: string, uidB: string) {
  // Nombres públicos para el texto del resultado. Best-effort (discovery/seed).
  async function nameOf(uid: string): Promise<string> {
    try {
      let d = await db.collection("discovery").doc(uid).get();
      if (!d.exists) d = await db.collection("seed_profiles").doc(uid).get();
      const dn = d.data()?.displayName;
      return typeof dn === "string" && dn.trim() ? dn.trim() : "Alguien";
    } catch {
      return "Alguien";
    }
  }
  const [a, b] = await Promise.all([nameOf(uidA), nameOf(uidB)]);
  return { a, b };
}

async function postSystem(
  chatRef: FirebaseFirestore.DocumentReference,
  sessionId: string,
  text: string
) {
  const now = FieldValue.serverTimestamp();
  await chatRef.collection("messages").doc(`gameresult_${sessionId}`).set(
    {
      senderId: "system",
      receiverId: "",
      type: "system",
      text,
      status: "sent",
      gameSessionId: sessionId,
      createdAt: now,
    },
    { merge: true }
  );
  await chatRef.set(
    {
      lastMessage: "Resultado del Duelo de Química ⚡",
      lastMessageType: "system",
      lastMessageAt: now,
      updatedAt: now,
    },
    { merge: true }
  );
}
