/// IA por PROMPT (Attra Pro) — extracción de señales (espejo TS de
/// `lib/src/features/ai_visual/domain/prompt_match_rules.dart`). Separa lo que
/// se casa con datos declarados del perfil (ojos/complexión/altura/intereses)
/// de lo que evalúa la foto vía embedding. No toca la IA de referencia.

export type HeightPref = "any" | "tall" | "short";

export interface PromptSignals {
  eyeColors: string[];
  bodyTypes: string[];
  heightPref: HeightPref;
  keywords: string[];
}

const EYE_SYNONYMS: Record<string, string[]> = {
  blue: ["azul", "azules", "blue"],
  green: ["verde", "verdes", "green"],
  brown: ["marron", "marrones", "cafe", "brown"],
  hazel: ["avellana", "miel", "hazel"],
  gray: ["gris", "grises", "gray", "grey"],
  black: ["negro", "negros", "oscuros", "black"],
};

const BODY_SYNONYMS: Record<string, string[]> = {
  athletic: ["atletico", "atletica", "deportista", "fit", "athletic"],
  muscular: ["musculoso", "musculado", "fuerte", "cachas", "muscular"],
  slim: ["delgado", "delgada", "flaco", "flaca", "esbelto", "slim", "thin"],
  curvy: ["con curvas", "curvy"],
  average: ["normal", "media", "medio", "average"],
  plus: ["grande", "gordito", "gordita", "plus"],
};

const INTEREST_VOCAB = [
  "viaj", "aventur", "mochiler",
  "gracios", "divert", "humor",
  "carismat", "extrovert", "sociable",
  "deport", "gym", "gimnasio", "running", "correr", "sender",
  "music", "arte", "cultur", "lectur", "libro", "cine",
  "cocin", "gastronom", "foodie", "naturaleza", "perro", "gato",
  "fotograf", "bail", "fiesta", "tranquil", "romant", "intelect",
  "espiritual", "yoga", "moto", "coche", "gamer", "videojueg",
];

const TALL_WORDS = ["alto", "alta", "tall"];
const SHORT_WORDS = ["bajo", "baja", "bajit", "short"];

const ACCENTS: Record<string, string> = {
  á: "a", à: "a", ä: "a", â: "a",
  é: "e", è: "e", ë: "e", ê: "e",
  í: "i", ì: "i", ï: "i", î: "i",
  ó: "o", ò: "o", ö: "o", ô: "o",
  ú: "u", ù: "u", ü: "u", û: "u",
};

export function normalize(s: string): string {
  const lower = s.toLowerCase();
  let out = "";
  for (const ch of lower) out += ACCENTS[ch] ?? ch;
  return out;
}

export function extractPromptSignals(prompt: string): PromptSignals {
  const t = normalize(prompt);
  const eyeColors: string[] = [];
  for (const [key, syns] of Object.entries(EYE_SYNONYMS)) {
    if (syns.some((s) => t.includes(s))) eyeColors.push(key);
  }
  const bodyTypes: string[] = [];
  for (const [key, syns] of Object.entries(BODY_SYNONYMS)) {
    if (syns.some((s) => t.includes(s))) bodyTypes.push(key);
  }
  let heightPref: HeightPref = "any";
  if (TALL_WORDS.some((w) => t.includes(w))) heightPref = "tall";
  else if (SHORT_WORDS.some((w) => t.includes(w))) heightPref = "short";

  const keywords: string[] = [];
  for (const w of INTEREST_VOCAB) {
    if (t.includes(w) && !keywords.includes(w)) keywords.push(w);
  }
  return { eyeColors, bodyTypes, heightPref, keywords };
}

export function signalsAreEmpty(s: PromptSignals): boolean {
  return (
    s.eyeColors.length === 0 &&
    s.bodyTypes.length === 0 &&
    s.heightPref === "any" &&
    s.keywords.length === 0
  );
}

/// Puntúa [0..1] el encaje de datos declarados con las señales. Campos ausentes
/// no penalizan (los cubre la foto).
export function dataScore(
  signals: PromptSignals,
  profile: {
    eyeColor?: string;
    bodyType?: string;
    heightCm?: number;
    text: string;
  }
): number {
  if (signalsAreEmpty(signals)) return 0;
  let got = 0;
  let total = 0;
  const pt = normalize(profile.text);

  if (signals.eyeColors.length > 0) {
    total += 1;
    if (profile.eyeColor && signals.eyeColors.includes(profile.eyeColor)) got += 1;
  }
  if (signals.bodyTypes.length > 0) {
    total += 1;
    if (profile.bodyType && signals.bodyTypes.includes(profile.bodyType)) got += 1;
  }
  if (signals.heightPref !== "any") {
    total += 1;
    if (typeof profile.heightCm === "number") {
      const ok =
        signals.heightPref === "tall"
          ? profile.heightCm >= 180
          : profile.heightCm <= 170;
      if (ok) got += 1;
    }
  }
  if (signals.keywords.length > 0) {
    total += 1;
    const hits = signals.keywords.filter((k) => pt.includes(k)).length;
    if (hits > 0) got += Math.min(1, hits / signals.keywords.length);
  }
  return total === 0 ? 0 : Math.min(1, got / total);
}
