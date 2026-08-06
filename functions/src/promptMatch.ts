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

/// Altura: palabras COMPLETAS. Antes se casaban por subcadena y "trabajo"
/// contenía "bajo", así que cualquier prompt que mencionara el trabajo activaba
/// el filtro de "bajito" y descartaba a la gente alta.
const TALL_WORDS = ["alto", "alta", "altos", "altas", "tall"];
const SHORT_WORDS = ["bajo", "baja", "bajos", "bajas", "short"];
/// Raíces de altura (casan "bajito"/"bajita" pero solo al inicio de palabra).
const SHORT_STEMS = ["bajit"];

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

/// Caracteres que cuentan como "letra" en el texto YA normalizado. No se usa
/// `\b` porque en JS `\b` se apoya en `\w` (ASCII) y partiría palabras con ñ/ç.
const WORD_CHAR = "a-z0-9ñç";

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

const TERM_PATTERNS = new Map<string, RegExp>();

/// Construye (y cachea) el patrón de un término. `stem=true` exige solo que la
/// coincidencia empiece en frontera de palabra (para raíces como "viaj", que
/// deben casar "viajar"/"viajes" pero no "desviaje").
function termPattern(term: string, stem: boolean): RegExp {
  const key = `${stem ? "s" : "w"}:${term}`;
  const cached = TERM_PATTERNS.get(key);
  if (cached) return cached;
  // En palabra completa se admite el plural español (-s / -es) para no perder
  // lo que sí casaba por subcadena ("chicos grandes" → plus).
  const tail = stem ? "" : `(?:e?s)?(?![${WORD_CHAR}])`;
  const re = new RegExp(`(?<![${WORD_CHAR}])${escapeRegExp(term)}${tail}`);
  TERM_PATTERNS.set(key, re);
  return re;
}

/// ¿Aparece `term` como palabra COMPLETA en `text` (ya normalizado)?
export function hasWord(text: string, term: string): boolean {
  return termPattern(normalize(term), false).test(text);
}

/// ¿Empieza alguna palabra de `text` por la raíz `stem`?
export function hasStem(text: string, stem: string): boolean {
  return termPattern(normalize(stem), true).test(text);
}

export function extractPromptSignals(prompt: string): PromptSignals {
  // Antes se buscaban los sinónimos como subcadena cruda: "trabajo" activaba
  // "bajo" (altura), "grande" salía de "grandes planes", etc. Ahora se exige
  // frontera de palabra (raíces de intereses: frontera solo por delante).
  const t = normalize(prompt);
  const eyeColors: string[] = [];
  for (const [key, syns] of Object.entries(EYE_SYNONYMS)) {
    if (syns.some((s) => hasWord(t, s))) eyeColors.push(key);
  }
  const bodyTypes: string[] = [];
  for (const [key, syns] of Object.entries(BODY_SYNONYMS)) {
    if (syns.some((s) => hasWord(t, s))) bodyTypes.push(key);
  }
  let heightPref: HeightPref = "any";
  if (TALL_WORDS.some((w) => hasWord(t, w))) heightPref = "tall";
  else if (
    SHORT_WORDS.some((w) => hasWord(t, w)) ||
    SHORT_STEMS.some((w) => hasStem(t, w))
  ) {
    heightPref = "short";
  }

  const keywords: string[] = [];
  for (const w of INTEREST_VOCAB) {
    if (hasStem(t, w) && !keywords.includes(w)) keywords.push(w);
  }
  return { eyeColors, bodyTypes, heightPref, keywords };
}

/// Traduce el valor DECLARADO del perfil a la clave del catálogo. Los perfiles
/// guardan indistintamente la clave ("green") o el término en español
/// ("verde"), y sin esto solo casaban los que ya venían en inglés.
function canonicalTrait(
  table: Record<string, string[]>,
  raw: string | undefined
): string | null {
  if (!raw) return null;
  const value = normalize(raw).trim();
  if (value.length === 0) return null;
  if (Object.prototype.hasOwnProperty.call(table, value)) return value;
  for (const [key, syns] of Object.entries(table)) {
    if (syns.includes(value)) return key;
  }
  // Valores libres tipo "ojos azul claro".
  for (const [key, syns] of Object.entries(table)) {
    if (syns.some((s) => hasWord(value, s))) return key;
  }
  return null;
}

export function signalsAreEmpty(s: PromptSignals): boolean {
  return (
    s.eyeColors.length === 0 &&
    s.bodyTypes.length === 0 &&
    s.heightPref === "any" &&
    s.keywords.length === 0
  );
}

/// Datos declarados de un candidato que se pueden casar con el prompt.
export interface PromptProfileData {
  eyeColor?: string;
  bodyType?: string;
  heightCm?: number;
  text: string;
}

/// Resultado del encaje de datos. `score` es null cuando NO hay nada
/// comparable (prompt sin señales, o el perfil no declara ninguno de los
/// campos pedidos): eso NO es un cero, es "no evaluable", y quien llama debe
/// repartir el peso a la parte visual en vez de hundir al candidato.
export interface PromptDataMatch {
  score: number | null;
  /// Nº de criterios que el perfil sí declara (sobre los que pide el prompt).
  comparable: number;
}

/// Puntúa [0..1] el encaje de datos declarados con las señales.
///
/// Antes, un criterio pedido contaba en el denominador aunque el perfil no
/// hubiera rellenado ese campo: no declarar el color de ojos puntuaba igual que
/// declararlo distinto al pedido, y como casi ningún perfil rellena todo, el
/// score de datos salía siempre hundido. Ahora solo entran en el cálculo los
/// campos REALMENTE declarados (permisivo con el dato ausente, igual que
/// FeedFilter en el cliente); lo ausente ni suma ni resta.
export function dataMatch(
  signals: PromptSignals,
  profile: PromptProfileData
): PromptDataMatch {
  if (signalsAreEmpty(signals)) return { score: null, comparable: 0 };
  let got = 0;
  let total = 0;
  const pt = normalize(profile.text);

  if (signals.eyeColors.length > 0) {
    const declared = canonicalTrait(EYE_SYNONYMS, profile.eyeColor);
    if (declared !== null) {
      total += 1;
      if (signals.eyeColors.includes(declared)) got += 1;
    }
  }
  if (signals.bodyTypes.length > 0) {
    const declared = canonicalTrait(BODY_SYNONYMS, profile.bodyType);
    if (declared !== null) {
      total += 1;
      if (signals.bodyTypes.includes(declared)) got += 1;
    }
  }
  if (signals.heightPref !== "any") {
    if (typeof profile.heightCm === "number" && profile.heightCm > 0) {
      total += 1;
      const ok =
        signals.heightPref === "tall"
          ? profile.heightCm >= 180
          : profile.heightCm <= 170;
      if (ok) got += 1;
    }
  }
  if (signals.keywords.length > 0 && pt.trim().length > 0) {
    total += 1;
    const hits = signals.keywords.filter((k) => hasStem(pt, k)).length;
    if (hits > 0) got += Math.min(1, hits / signals.keywords.length);
  }
  if (total === 0) return { score: null, comparable: 0 };
  return { score: Math.min(1, got / total), comparable: total };
}

/// Variante numérica (0 cuando no hay nada comparable). Se mantiene por
/// compatibilidad; para rankear usa `dataMatch` y distingue el null.
export function dataScore(
  signals: PromptSignals,
  profile: PromptProfileData
): number {
  return dataMatch(signals, profile).score ?? 0;
}
