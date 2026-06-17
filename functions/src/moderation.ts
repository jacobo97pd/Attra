/// Moderacion basica de comentarios de like/Attra. Capa inicial sin IA; deja la
/// interfaz lista para un ModerationService futuro (p.ej. con un modelo).

export const MAX_COMMENT_LENGTH = 180;

/// Si se activa, rechaza comentarios con URLs/emails/telefonos (compartir
/// contacto antes de tiempo). Politica: por defecto NO se bloquea.
export const BLOCK_CONTACT_INFO = false;

/// Lista minima de terminos prohibidos (placeholder). Ampliar segun politica.
/// En minusculas; se compara sobre el texto normalizado.
const BANNED_TERMS: string[] = [
  // insultos graves / amenazas / contenido sexual explicito no consentido
  // (placeholders neutros; el equipo de T&S define la lista real)
  "[[banned-term-1]]",
  "[[banned-term-2]]",
];

const URL_RE = /(https?:\/\/|www\.)/i;
const EMAIL_RE = /[\w.+-]+@[\w-]+\.[\w.-]+/;
const PHONE_RE = /(\+?\d[\d\s().-]{7,}\d)/;

export type CommentModerationStatus = "none" | "approved" | "rejected";

export interface ModerationResult {
  status: CommentModerationStatus;
  reason?: "too_long" | "banned" | "contact_info";
  cleanText: string;
}

/// Modera un comentario. `none` = sin comentario (vacio tras trim).
export function moderateComment(raw: unknown): ModerationResult {
  if (typeof raw !== "string") {
    return { status: "none", cleanText: "" };
  }
  const text = raw.trim();
  if (text.length === 0) {
    return { status: "none", cleanText: "" };
  }
  if (text.length > MAX_COMMENT_LENGTH) {
    return { status: "rejected", reason: "too_long", cleanText: text };
  }
  const lower = text.toLowerCase();
  for (const term of BANNED_TERMS) {
    if (lower.includes(term)) {
      return { status: "rejected", reason: "banned", cleanText: text };
    }
  }
  if (BLOCK_CONTACT_INFO && (URL_RE.test(text) || EMAIL_RE.test(text) || PHONE_RE.test(text))) {
    return { status: "rejected", reason: "contact_info", cleanText: text };
  }
  return { status: "approved", cleanText: text };
}
