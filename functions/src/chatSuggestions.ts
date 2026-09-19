import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import type { DocumentData } from "firebase-admin/firestore";
import { GoogleAuth } from "google-auth-library";

import { REGION, db } from "./firebase";
import { col, requireAuthUid, activeEntitlementTier } from "./common";

/// SUGERENCIAS DE RESPUESTA en el chat.
///
/// Propone hasta tres formas de seguir la conversación. NUNCA envía nada: la
/// sugerencia cae en la caja de texto y la persona la edita o la borra. Lo que
/// se manda al modelo son los últimos mensajes del chat, que son de DOS
/// personas, así que esta función exige:
///
///   1. plan Pro vigente,
///   2. consentimiento explícito de quien pide la sugerencia
///      (`users/{uid}.chatSuggestionsConsent`), igual que la IA visual,
///   3. los flags remotos (`chat_suggestions_enabled`, más los cortes
///      generales `aiKillSwitch` / `aiProcessingEnabled`),
///   4. que quien pide sea participante del chat.
///
/// El modelo corre en `europe-west4`, como el perfil de voz: son mensajes
/// privados de gente en la UE y no tienen por qué salir de la UE. (La IA visual
/// sigue en us-central1; ver la nota en ai.ts.)
///
/// No se guarda ningún mensaje en sitios nuevos: se leen, se mandan al modelo y
/// se devuelven las sugerencias. Lo único que persiste es un contador diario
/// para el tope.

const VERTEX_PROJECT = "attra-database";
const VERTEX_LOCATION = "europe-west4";
const VERTEX_MODEL =
  process.env.CHAT_SUGGESTIONS_MODEL?.trim() || "gemini-2.5-flash";

/// Cuántos mensajes de contexto se mandan. Suficiente para pillar el tono sin
/// volcar la conversación entera a un tercero.
const CONTEXT_MESSAGES = 12;
/// Tope por persona y día. Acota la factura y evita el uso compulsivo.
const MAX_PER_DAY = 20;
const MAX_SUGGESTIONS = 3;
/// Una sugerencia es una frase para mandar por chat, no un párrafo.
const MAX_SUGGESTION_CHARS = 160;
const MODEL_TIMEOUT_MS = 12_000;

const auth = new GoogleAuth({
  scopes: ["https://www.googleapis.com/auth/cloud-platform"],
});

export interface SuggestionMessage {
  senderId: string;
  text: string;
}

/// ¿Tiene sentido ofrecer sugerencias en este chat AHORA MISMO?
///
/// Pura y exportada para poder probarla. El producto pide "no siempre, solo
/// alguna": ofrecerlas en cada mensaje convierte la conversación en un
/// intercambio de frases de máquina, y además se paga una llamada cada vez.
/// Se ofrecen cuando de verdad ayudan:
///   - hay algo a lo que responder (el último mensaje NO es mío), y
///   - la conversación ha arrancado (al menos un mensaje por cada lado), y
///   - no se acaba de usar (hay un enfriamiento entre sugerencias).
export function shouldOfferSuggestions(input: {
  messages: SuggestionMessage[];
  myUid: string;
  lastSuggestedAtMs: number | null;
  nowMs: number;
  cooldownMs?: number;
}): boolean {
  const { messages, myUid, lastSuggestedAtMs, nowMs } = input;
  const cooldownMs = input.cooldownMs ?? 5 * 60 * 1000;

  if (messages.length === 0) return false;

  const last = messages[messages.length - 1];
  // Si el último mensaje es mío, la pelota está en su tejado: sugerir aquí
  // empuja a insistir, que es justo lo contrario de lo que quiere nadie.
  if (last.senderId === myUid) return false;

  const mios = messages.filter((m) => m.senderId === myUid).length;
  const suyos = messages.length - mios;
  if (mios === 0 || suyos === 0) return false;

  if (lastSuggestedAtMs !== null && nowMs - lastSuggestedAtMs < cooldownMs) {
    return false;
  }
  return true;
}

/// Limpia lo que devuelve el modelo y lo deja en sugerencias usables.
///
/// El modelo responde con una lista, pero no siempre limpia: numera, mete
/// guiones, comillas, líneas vacías o se enrolla. Exportada para probarla,
/// porque es donde acaba saliendo texto raro en la caja de un usuario.
export function parseSuggestions(raw: string): string[] {
  const vistas = new Set<string>();
  const salida: string[] = [];
  for (const linea of (raw ?? "").split("\n")) {
    let t = linea.trim();
    if (t.length === 0) continue;
    // "1. ", "1) ", "- ", "* ", "• "
    t = t.replace(/^\s*(?:\d+\s*[.)-]|[-*•])\s*/, "").trim();
    // Comillas de apertura/cierre que el modelo añade por su cuenta.
    t = t.replace(/^["'«“”]+/, "").replace(/["'»“”]+$/, "").trim();
    if (t.length === 0) continue;
    if (t.length > MAX_SUGGESTION_CHARS) t = t.slice(0, MAX_SUGGESTION_CHARS).trim();
    const clave = t.toLowerCase();
    if (vistas.has(clave)) continue;
    vistas.add(clave);
    salida.push(t);
    if (salida.length === MAX_SUGGESTIONS) break;
  }
  return salida;
}

/// Construye el prompt. Los mensajes van etiquetados por lado, sin nombres ni
/// uids: el modelo no necesita saber quién es nadie para proponer una respuesta.
export function buildPrompt(
  messages: SuggestionMessage[],
  myUid: string
): string {
  const transcripcion = messages
    .slice(-CONTEXT_MESSAGES)
    .map((m) => `${m.senderId === myUid ? "YO" : "LA OTRA PERSONA"}: ${m.text}`)
    .join("\n");

  return [
    "Eres quien ayuda a alguien a seguir una conversación en una app de citas.",
    "Te doy los últimos mensajes. Escribe TRES formas distintas de responder.",
    "",
    "Reglas:",
    "- En el MISMO idioma en el que hablan.",
    "- Cada una en una línea, sin numerar y sin comillas.",
    "- Cortas: como mucho una o dos frases.",
    "- Naturales, como escribe una persona. Nada de sonar a plantilla.",
    "- Que continúen la conversación: pregunta algo o aporta algo tuyo.",
    "- Distintas entre sí: no tres versiones de lo mismo.",
    "- Nada sexual, ofensivo, insistente ni que presione para quedar.",
    "- No inventes datos sobre ninguno de los dos.",
    "",
    "Conversación:",
    transcripcion,
  ].join("\n");
}

/// Texto plano de una respuesta de Gemini.
function textFromGemini(payload: unknown): string {
  const candidatos = (payload as DocumentData)?.candidates;
  if (!Array.isArray(candidatos) || candidatos.length === 0) return "";
  const partes = candidatos[0]?.content?.parts;
  if (!Array.isArray(partes)) return "";
  return partes
    .map((p: DocumentData) => (typeof p?.text === "string" ? p.text : ""))
    .join("")
    .trim();
}

async function callModel(prompt: string): Promise<string> {
  const client = await auth.getClient();
  const token = await client.getAccessToken();
  const url =
    `https://${VERTEX_LOCATION}-aiplatform.googleapis.com/v1/projects/` +
    `${VERTEX_PROJECT}/locations/${VERTEX_LOCATION}/publishers/google/models/` +
    `${VERTEX_MODEL}:generateContent`;

  const control = new AbortController();
  const corte = setTimeout(() => control.abort(), MODEL_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token.token ?? token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.9, maxOutputTokens: 256 },
      }),
      signal: control.signal,
    });
    if (!res.ok) {
      console.error(`[Sugerencias] Vertex HTTP ${res.status}`);
      throw new HttpsError("unavailable", "La IA no está disponible ahora.");
    }
    return textFromGemini(await res.json());
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error(`[Sugerencias] ${(error as Error).message}`);
    throw new HttpsError("unavailable", "La IA no está disponible ahora.");
  } finally {
    clearTimeout(corte);
  }
}

/// Mismas puertas que la IA visual, más la del chat. El orden importa: primero
/// lo que depende del usuario (plan, consentimiento) y luego el corte global,
/// para que el mensaje de error diga la verdad de por qué no se puede.
async function requireChatAiAccess(uid: string): Promise<void> {
  const [entSnap, userSnap, cfgSnap] = await Promise.all([
    col.entitlements.doc(uid).get(),
    col.users.doc(uid).get(),
    db.collection("config").doc("featureFlags").get(),
  ]);

  if (activeEntitlementTier(entSnap.data()) !== "pro") {
    throw new HttpsError(
      "permission-denied",
      "Las sugerencias de respuesta son de Attra Pro."
    );
  }
  if (userSnap.data()?.chatSuggestionsConsent !== true) {
    throw new HttpsError(
      "failed-precondition",
      "Necesitas dar tu consentimiento para que la IA lea la conversación."
    );
  }
  const cfg = cfgSnap.data() ?? {};
  // `!== true`, no `=== false`: si la clave no está sembrada, la función queda
  // APAGADA. Con `=== false` una clave ausente dejaba pasar, y esto manda una
  // conversación privada a un modelo. Una función así se enciende a propósito.
  if (
    cfg.chat_suggestions_enabled !== true ||
    cfg.aiKillSwitch === true ||
    cfg.aiProcessingEnabled === false
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Las sugerencias están desactivadas temporalmente."
    );
  }
}

/// Tope diario por persona. El documento se llama por día para que caduque solo
/// con una política TTL y no haya que barrerlo a mano.
async function consumeDailyQuota(uid: string, nowMs: number): Promise<void> {
  const dia = new Date(nowMs).toISOString().slice(0, 10);
  const ref = db.collection("chatSuggestionUsage").doc(`${uid}_${dia}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const usadas = Number(snap.data()?.count ?? 0);
    if (usadas >= MAX_PER_DAY) {
      throw new HttpsError(
        "resource-exhausted",
        "Has llegado al máximo de sugerencias por hoy."
      );
    }
    tx.set(
      ref,
      {
        uid,
        day: dia,
        count: usadas + 1,
        updatedAt: FieldValue.serverTimestamp(),
        expiresAt: new Date(nowMs + 48 * 60 * 60 * 1000),
      },
      { merge: true }
    );
  });
}

export const suggestReplies = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const chatId =
    typeof request.data?.chatId === "string" ? request.data.chatId.trim() : "";
  if (chatId.length === 0) {
    throw new HttpsError("invalid-argument", "Falta el chat.");
  }

  await requireChatAiAccess(uid);

  const chatSnap = await col.chats.doc(chatId).get();
  if (!chatSnap.exists) {
    throw new HttpsError("not-found", "La conversación no existe.");
  }
  // Participante. Sin esto, cualquiera con un chatId podría leerse por la vía
  // de las sugerencias una conversación ajena entera.
  const users = chatSnap.data()?.users;
  if (!Array.isArray(users) || !users.includes(uid)) {
    throw new HttpsError("permission-denied", "No participas en ese chat.");
  }

  const mensajesSnap = await col.chats
    .doc(chatId)
    .collection("messages")
    .orderBy("createdAt", "desc")
    .limit(CONTEXT_MESSAGES)
    .get();

  const messages: SuggestionMessage[] = mensajesSnap.docs
    .map((d) => d.data())
    // Solo texto humano: las tarjetas de sistema, propuestas y minijuegos no
    // aportan tono y sí ruido.
    .filter((m) => m.type === "text" && typeof m.text === "string")
    .map((m) => ({ senderId: String(m.senderId ?? ""), text: String(m.text) }))
    .reverse();

  if (messages.length === 0) {
    return { suggestions: [], reason: "sin_conversacion" };
  }

  await consumeDailyQuota(uid, Date.now());

  const suggestions = parseSuggestions(
    await callModel(buildPrompt(messages, uid))
  );
  return { suggestions, reason: suggestions.length > 0 ? "ok" : "sin_respuesta" };
});
