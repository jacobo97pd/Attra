/// Attra Plans — reglas PURAS de generación (espejo TS de
/// `lib/src/features/date_plans/domain/date_plan_rules.dart`). Deciden qué TIPO
/// de plan encaja y qué lugares son aceptables. Sin red ni IA (la IA llega en
/// Fase 3 y afinará `commonCategories`/`recommendedPlanTypes`).

export type PlanCategory =
  | "cafe"
  | "paseo"
  | "helado"
  | "comida"
  | "copas"
  | "cultura"
  | "musica";

export type PlanTier = "safe" | "social" | "differential";

export const MIN_CONVERSATION_FOR_PLAN = 6;
export const MIN_PLACE_RATING = 4.1;
export const MIN_PLACE_REVIEWS = 30;

interface CategoryMeta {
  tier: PlanTier;
  /// Título humano de la opción.
  title: string;
  /// Consulta de texto para Places (en inglés funciona bien globalmente).
  placeQuery: string;
  /// Etiqueta corta.
  tag: string;
  /// Palabras clave para detectar interés (minúsculas, sin tildes). ES + EN.
  keywords: string[];
}

const META: Record<PlanCategory, CategoryMeta> = {
  cafe: {
    tier: "safe",
    title: "Café tranquilo",
    placeQuery: "quiet cozy coffee shop",
    tag: "relajado",
    keywords: ["cafe", "cafeteria", "coffee", "te", "chocolate", "tomar algo", "merendar"],
  },
  paseo: {
    tier: "safe",
    title: "Un paseo",
    placeQuery: "park nice for a walk",
    tag: "al aire libre",
    keywords: ["pasear", "paseo", "andar", "caminar", "parque", "naturaleza", "walk", "senderismo", "aire libre", "playa", "monte"],
  },
  helado: {
    tier: "safe",
    title: "Un helado",
    placeQuery: "ice cream shop",
    tag: "dulce",
    keywords: ["helado", "heladeria", "ice cream"],
  },
  comida: {
    tier: "social",
    title: "Comer algo casual",
    placeQuery: "casual restaurant good for a date",
    tag: "casual",
    keywords: ["comer", "comida", "cena", "cenar", "restaurante", "tapas", "food", "dinner", "lunch", "brunch", "sushi", "pizza", "hamburguesa"],
  },
  copas: {
    tier: "social",
    title: "Una copa con ambiente",
    placeQuery: "cocktail bar with good vibe",
    tag: "ambiente",
    keywords: ["copa", "copas", "bar", "cerveza", "vino", "cocktail", "coctel", "terraza", "fiesta", "drink", "vermut"],
  },
  cultura: {
    tier: "differential",
    title: "Algo de cultura",
    placeQuery: "museum or art gallery",
    tag: "cultura",
    keywords: ["museo", "expo", "exposicion", "arte", "cultura", "teatro", "cine", "libro", "lectura", "museum", "galeria", "historia"],
  },
  musica: {
    tier: "differential",
    title: "Música en directo",
    placeQuery: "live music venue",
    tag: "música",
    keywords: ["musica", "concierto", "directo", "banda", "dj", "festival", "vinilo", "guitarra", "cantar", "karaoke", "music", "gig"],
  },
};

const ALL_CATEGORIES = Object.keys(META) as PlanCategory[];

/// Mapa de acentos (espejo del de Dart) para no depender de ̀-ͯ.
const ACCENTS: Record<string, string> = {
  á: "a", à: "a", ä: "a", â: "a",
  é: "e", è: "e", ë: "e", ê: "e",
  í: "i", ì: "i", ï: "i", î: "i",
  ó: "o", ò: "o", ö: "o", ô: "o",
  ú: "u", ù: "u", ü: "u", û: "u",
  ñ: "n", ç: "c",
};

export function categoryMeta(cat: PlanCategory): CategoryMeta {
  return META[cat];
}

/// minúsculas + sin tildes.
function norm(s: string): string {
  const lower = s.toLowerCase();
  let out = "";
  for (const ch of lower) {
    out += ACCENTS[ch] ?? ch;
  }
  return out;
}

export function hasEnoughConversation(realMessageCount: number): boolean {
  return realMessageCount >= MIN_CONVERSATION_FOR_PLAN;
}

export function isValidZone(zone: string | undefined | null): boolean {
  const z = (zone ?? "").trim();
  if (z.length < 2 || z.length > 80) return false;
  // No aceptamos coordenadas exactas (privacidad).
  if (/^-?\d+\.\d+\s*,\s*-?\d+\.\d+$/.test(z)) return false;
  return true;
}

/// Categorías de interés COMÚN, ordenadas por relevancia (más señales primero).
export function commonCategories(
  aInterests: string[],
  bInterests: string[],
  chatMessages: string[]
): PlanCategory[] {
  const aText = aInterests.map(norm).join(" ");
  const bText = bInterests.map(norm).join(" ");
  const chatText = chatMessages.map(norm).join(" ");

  const score = new Map<PlanCategory, number>();
  for (const cat of ALL_CATEGORIES) {
    const kws = META[cat].keywords;
    const inA = kws.some((k) => aText.includes(k));
    const inB = kws.some((k) => bText.includes(k));
    const inChat = kws.some((k) => chatText.includes(k));
    let s = 0;
    if (inA && inB) s += 3;
    if (inChat) s += 2;
    if ((inA || inB) && inChat) s += 1;
    if (s > 0) score.set(cat, s);
  }
  return [...score.keys()].sort((a, b) => (score.get(b) ?? 0) - (score.get(a) ?? 0));
}

/// Hasta 3 tipos cubriendo carriles distintos (seguro→social→diferencial).
export function recommendedPlanTypes(common: PlanCategory[]): PlanCategory[] {
  const out: PlanCategory[] = [];
  const usedTiers = new Set<PlanTier>();
  for (const cat of common) {
    if (usedTiers.has(META[cat].tier)) continue;
    out.push(cat);
    usedTiers.add(META[cat].tier);
    if (out.length === 3) break;
  }
  const fillers: PlanCategory[] = ["cafe", "comida", "cultura", "paseo"];
  for (const f of fillers) {
    if (out.length === 3) break;
    if (out.includes(f)) continue;
    if (usedTiers.has(META[f].tier)) continue;
    out.push(f);
    usedTiers.add(META[f].tier);
  }
  for (const f of fillers) {
    if (out.length === 3) break;
    if (!out.includes(f)) out.push(f);
  }
  return out;
}

export function passesPlaceQuality(rating?: number, reviewCount?: number): boolean {
  if (typeof rating === "number" && rating < MIN_PLACE_RATING) return false;
  if (typeof reviewCount === "number" && reviewCount < MIN_PLACE_REVIEWS) return false;
  return true;
}
