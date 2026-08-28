/// IA por PROMPT (Attra Pro) — extracción de señales (espejo TS de
/// `lib/src/features/ai_visual/domain/prompt_match_rules.dart`). Separa lo que
/// se casa con datos declarados del perfil (género/ojos/pelo/complexión/altura/
/// personalidad/intereses) de lo que evalúa la foto vía embedding. No toca la IA
/// de referencia.
///
/// QUÉ SE IGNORABA ANTES (medido ejecutando el extractor contra frases reales):
///   "chico alto fuerte majo y amable" → cuerpo:[muscular] altura:tall
///        …y nada más: "chico" (género) y "majo"/"amable" (personalidad) se
///        tiraban a la basura, que son 3 de las 5 palabras que pidió el usuario.
///   "chica morena de ojos verdes"     → ojos:[green]
///        …"morena" (color de pelo) se ignoraba por completo.
/// Este módulo añade las tres señales que faltaban: GÉNERO, COLOR DE PELO y
/// PERSONALIDAD.
///
/// CÓMO PUNTÚAN (ver `dataMatch`, que es donde estaba el fallo de fondo):
///   · el GÉNERO es un VETO, no un sumando de la media — como sumando diluía
///     el criterio que el usuario sí había pedido;
///   · el denominador son los criterios PEDIDOS, no los que el perfil rellenó,
///     porque si no declarar datos BAJABA la nota;
///   · lo no declarado vale `UNKNOWN_CREDIT` (neutro), y `passesDataFilter`
///     exige superar ese neutro para entrar: sin una sola prueba de encaje, no
///     se presenta a nadie como resultado de lo que el usuario escribió.
/// La NEGACIÓN se detecta y ANULA la señal (nunca la invierte): "nada de
/// chicos" activaba gender=male y devolvía exactamente lo contrario.

export type HeightPref = "any" | "tall" | "short";

/// Género pedido en el prompt. "any" = no se pidió (lo normal).
export type GenderPref = "any" | "male" | "female" | "non_binary";

export interface PromptSignals {
  gender: GenderPref;
  eyeColors: string[];
  hairColors: string[];
  bodyTypes: string[];
  heightPref: HeightPref;
  /// Claves del catálogo de `personalityTags` del perfil (ambitious,
  /// empathetic, fun, creative, calm, intense).
  personality: string[];
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

/// Colores de OJOS que solo pueden ser de ojos: no hay pelo azul ni avellana en
/// el catálogo del perfil, así que no hace falta desambiguarlos.
const EYE_ONLY = new Set(["blue", "green", "hazel"]);

/// Color de PELO. Claves = catálogo real del perfil (`_hairColorMap` en
/// onboarding_repository.dart): black, brown, blonde, red, gray.
///
/// "moreno/morena" se trata SOLO como pelo oscuro. En español también puede
/// referirse al tono de piel, y ese camino no se toma: la etnia es categoría
/// especial y aquí no se infiere ni se filtra por ella.
const HAIR_SYNONYMS: Record<string, string[]> = {
  black: ["negro", "negra", "azabache", "black"],
  brown: ["castano", "castana", "castanos", "castanas", "marron", "brown"],
  blonde: ["rubio", "rubia", "rubios", "rubias", "blonde", "blond"],
  red: ["pelirrojo", "pelirroja", "pelirrojos", "pelirrojas", "redhead"],
  gray: ["canoso", "canosa", "cano", "platino", "gris", "gray", "grey"],
};

/// Palabras de pelo que NO son ambiguas: signifiquen lo que signifiquen en el
/// resto de la frase, hablan del pelo. "moreno" entra aquí porque nadie describe
/// unos ojos como "morenos".
const HAIR_UNAMBIGUOUS: Record<string, string[]> = {
  black: ["azabache"],
  brown: ["castano", "castana", "castanos", "castanas", "moreno", "morena", "morenos", "morenas"],
  blonde: ["rubio", "rubia", "rubios", "rubias", "blonde", "blond"],
  red: ["pelirrojo", "pelirroja", "pelirrojos", "pelirrojas", "redhead"],
  gray: ["canoso", "canosa", "platino"],
};

/// "moreno" es pelo OSCURO: en el catálogo eso son castaño y negro. Se marcan
/// los dos y que decida el perfil, en vez de elegir uno a dedo y fallar la mitad
/// de las veces.
const DARK_HAIR_WORDS = ["moreno", "morena", "morenos", "morenas"];

/// Sustantivos que dicen de QUÉ se está hablando. Sin esto, "pelo negro"
/// activaba "ojos negros" (el extractor no miraba a qué acompañaba el color).
const EYE_NOUNS = ["ojos", "ojo", "mirada", "iris"];
const HAIR_NOUNS = ["pelo", "cabello", "melena", "pelazo"];

const BODY_SYNONYMS: Record<string, string[]> = {
  athletic: ["atletico", "atletica", "deportista", "fit", "athletic"],
  muscular: ["musculoso", "musculado", "fuerte", "cachas", "muscular"],
  slim: ["delgado", "delgada", "flaco", "flaca", "esbelto", "slim", "thin"],
  curvy: ["con curvas", "curvy"],
  average: ["normal", "media", "medio", "average"],
  plus: ["grande", "gordito", "gordita", "plus"],
};

/// GÉNERO. Claves = las que usa el perfil (male/female/non_binary).
///
/// ¿Aporta algo, si el feed ya filtra por orientación? SÍ, y se comprobó contra
/// los datos reales antes de implementarlo: el filtro del feed
/// (`FeedFilter`, cláusulas `iWantThem`/`theyWantMe`) NO filtra por género
/// cuando (a) el que busca no tiene `interestedIn` declarado — hoy 18 de 32
/// usuarios reales, (b) le interesa más de un género, o (c) la conexión no es de
/// dating (en Modo Amigos el género no se filtra a propósito). Además 10 de los
/// 59 perfiles candidatos no declaran `interestedIn`. Para todos esos casos
/// "chico" es la ÚNICA forma que tiene el usuario de acotar, y hasta ahora se
/// ignoraba en silencio.
const GENDER_SYNONYMS: Record<string, string[]> = {
  male: ["chico", "chicos", "hombre", "hombres", "chaval", "chavales", "tio", "tios", "man", "men", "boy", "guy"],
  female: ["chica", "chicas", "mujer", "mujeres", "chavala", "chavalas", "tia", "tias", "woman", "women", "girl"],
  non_binary: ["no binario", "no binaria", "nobinario", "non binary", "nonbinary", "enby"],
};

/// PERSONALIDAD. Claves = catálogo real de `personalityTags` del perfil
/// (`_personalityTagMap`): ambitious, empathetic, fun, creative, calm, intense.
///
/// "majo", "amable" y "simpático" caen en `empathetic` porque es el valor del
/// catálogo que más se le parece: no hay uno para "buena gente". Se mapea al
/// catálogo que EXISTE en vez de inventar una etiqueta que ningún perfil ha
/// rellenado nunca.
const PERSONALITY_SYNONYMS: Record<string, string[]> = {
  empathetic: [
    "majo", "maja", "majos", "majas",
    "amable", "amables", "simpatico", "simpatica", "simpaticos", "simpaticas",
    "carinoso", "carinosa", "atento", "atenta", "considerado", "considerada",
    "empatico", "empatica", "dulce", "buena gente", "buen tio", "buena tia",
    "generoso", "generosa", "detallista", "noble", "kind", "nice", "empathetic",
  ],
  fun: [
    "divertido", "divertida", "divertidos", "divertidas",
    "gracioso", "graciosa", "graciosos", "graciosas",
    "risas", "cachondo", "cachonda", "marchoso", "marchosa", "fiestero",
    "fiestera", "funny", "fun",
  ],
  calm: [
    "tranquilo", "tranquila", "tranquilos", "tranquilas",
    "relajado", "relajada", "sereno", "serena", "calmado", "calmada",
    "paciente", "pacientes", "calm", "chill",
  ],
  ambitious: [
    "ambicioso", "ambiciosa", "trabajador", "trabajadora", "luchador",
    "luchadora", "currante", "emprendedor", "emprendedora", "ambitious",
  ],
  creative: [
    "creativo", "creativa", "artista", "artistico", "artistica", "original",
    "imaginativo", "imaginativa", "creative",
  ],
  intense: [
    "intenso", "intensa", "apasionado", "apasionada", "pasional", "intense",
  ],
};

/// INTERESES = lo que a alguien le GUSTA HACER. Sólo actividades.
///
/// Se han sacado de aquí las palabras de CARÁCTER ("gracios", "divert",
/// "humor", "carismat", "extrovert", "sociable", "tranquil"): desde que existe
/// la señal de personalidad, esas palabras se contaban DOS VECES. Con "chica
/// divertida" se generaban dos criterios —personalidad e interés— a partir de
/// la misma palabra, así que un perfil que declaraba `personalityTags: [fun]`
/// pero no tenía bio sacaba 0.75 en vez de 1: el criterio duplicado le metía un
/// neutro que sólo servía para diluir. El carácter lo lleva
/// `PERSONALITY_SYNONYMS`, que además tiene detrás el catálogo real del perfil.
const INTEREST_VOCAB = [
  "viaj", "aventur", "mochiler",
  "deport", "gym", "gimnasio", "running", "correr", "sender",
  "music", "arte", "cultur", "lectur", "libro", "cine",
  "cocin", "gastronom", "foodie", "naturaleza", "perro", "gato",
  "fotograf", "bail", "fiesta", "romant", "intelect",
  "espiritual", "yoga", "moto", "coche", "gamer", "videojueg",
];

/// Altura: palabras COMPLETAS. Antes se casaban por subcadena y "trabajo"
/// contenía "bajo", así que cualquier prompt que mencionara el trabajo activaba
/// el filtro de "bajito" y descartaba a la gente alta.
const TALL_WORDS = ["alto", "alta", "altos", "altas", "tall"];
const SHORT_WORDS = ["bajo", "baja", "bajos", "bajas", "short"];
/// Raíces de altura (casan "bajito"/"bajita" pero solo al inicio de palabra).
const SHORT_STEMS = ["bajit"];

/// NEGADORES. Sin esto "nada de chicos" extraia gender=male y el buscador hacia
/// EXACTAMENTE LO CONTRARIO de lo pedido: sacaba solo hombres y borraba del feed
/// a las mujeres, que antes del cambio si salian. Se mira una ventana corta
/// (3 palabras) por delante del termino: "no me importa si es alto o bajo" no
/// debe contar como negacion de "alto".
const NEGATORS = new Set([
  "no", "nada", "sin", "ni", "nunca", "jamas", "excepto", "salvo", "menos",
  "tampoco", "evitar", "odio",
]);
const NEGATION_WINDOW_WORDS = 3;

/// MARCADORES DE IDENTIDAD para deducir personalidad de la BIO.
///
/// Sin esto, "Me encanta el dulce y los planes originales" contaba como
/// "majo y amable" + "creativo": se le atribuia caracter a alguien por hablar
/// de POSTRES. En un prompt "dulce" describe a una persona; en una bio, casi
/// nunca. Se exige que la palabra vaya detras de algo que hable de UNO MISMO.
const IDENTITY_MARKERS = [
  "soy", "era", "sere", "me considero", "me consideran", "dicen que soy",
  "me describen", "me definen", "persona", "gente", "tipo", "tia", "tio",
  "chico", "chica", "hombre", "mujer",
];

/// Ventana (caracteres) tras el marcador de identidad en la que una palabra de
/// personalidad se acepta como autodescripcion.
const IDENTITY_WINDOW_CHARS = 60;

/// Palabras de personalidad DEMASIADO ambiguas para deducirlas de una bio: en
/// texto libre casi siempre hablan de otra cosa (postres, planes, medicina).
/// En el PROMPT si valen: ahi el usuario esta describiendo a una persona.
const TEXT_AMBIGUOUS = new Set([
  "dulce", "original", "noble", "atento", "atenta", "paciente", "pacientes",
  "fun", "nice", "intenso", "intensa",
]);

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

/// Posición de `term` como palabra completa, o -1.
function wordIndex(text: string, term: string): number {
  const m = termPattern(normalize(term), false).exec(text);
  return m ? m.index : -1;
}

/// ¿El término aparece NEGADO? Mira las `NEGATION_WINDOW_WORDS` palabras justo
/// anteriores a su primera aparición.
///
/// Sólo se usa para ANULAR la señal, nunca para invertirla. Invertir sería
/// inventarse lo que el usuario quiere: "nada de chicos" no dice si busca
/// mujeres, personas no binarias o ambas, y `GenderPref` sólo sabe expresar un
/// valor. Anular deja la búsqueda como estaba antes de la señal (no filtra por
/// eso), que es lo peor que puede pasar sin llegar a hacer lo contrario de lo
/// pedido.
export function isNegated(text: string, term: string): boolean {
  const at = wordIndex(text, term);
  if (at <= 0) return false;
  const before = text
    .slice(0, at)
    .split(/[^a-z0-9ñç]+/)
    .filter((w) => w.length > 0);
  const window = before.slice(-NEGATION_WINDOW_WORDS);
  return window.some((w) => NEGATORS.has(w));
}

/// Igual que `hasWord`, pero descarta la aparición si está negada.
function hasPositiveWord(text: string, term: string): boolean {
  return hasWord(text, term) && !isNegated(text, term);
}

/// ¿Aparece la palabra como AUTODESCRIPCIÓN en un texto libre (bio/prompts)?
///
/// Exige un marcador de identidad ("soy", "me consideran", "persona"…) delante,
/// dentro de una ventana corta, y descarta las palabras demasiado ambiguas para
/// texto libre. Sin esto, una bio que hablaba de postres ("me encanta el dulce")
/// puntuaba como "majo y amable", y "planes originales" como "creativo".
function saysAboutSelf(text: string, term: string): boolean {
  if (TEXT_AMBIGUOUS.has(normalize(term))) return false;
  const at = wordIndex(text, term);
  if (at < 0) return false;
  if (isNegated(text, term)) return false;
  const from = Math.max(0, at - IDENTITY_WINDOW_CHARS);
  const context = text.slice(from, at);
  return IDENTITY_MARKERS.some((m) => context.includes(normalize(m)));
}

/// Distancia en caracteres del término al sustantivo más cercano de la lista.
/// Number.MAX_SAFE_INTEGER si no aparece ninguno.
function distanceToNouns(text: string, term: string, nouns: string[]): number {
  const at = wordIndex(text, term);
  if (at < 0) return Number.MAX_SAFE_INTEGER;
  let best = Number.MAX_SAFE_INTEGER;
  for (const noun of nouns) {
    const idx = wordIndex(text, noun);
    if (idx < 0) continue;
    best = Math.min(best, Math.abs(idx - at));
  }
  return best;
}

/// ¿A qué se refiere un color AMBIGUO (negro/gris/marrón, que valen para ojos y
/// para pelo)? Al sustantivo que tenga MÁS CERCA.
///
/// Sin esto, "chico de pelo negro y ojos claros" marcaba ojos negros además de
/// pelo negro —la frase dice justo lo contrario— porque bastaba con que la
/// palabra "ojos" apareciera en algún sitio.
function refersTo(text: string, term: string): "eyes" | "hair" | "none" {
  const toEyes = distanceToNouns(text, term, EYE_NOUNS);
  const toHair = distanceToNouns(text, term, HAIR_NOUNS);
  if (toEyes === Number.MAX_SAFE_INTEGER && toHair === Number.MAX_SAFE_INTEGER) {
    return "none";
  }
  return toEyes <= toHair ? "eyes" : "hair";
}

/// Claves de una tabla de sinónimos que aparecen como palabra completa Y NO
/// negadas ("nada de chicos" ya no cuenta como "quiero chicos").
function matchTable(text: string, table: Record<string, string[]>): string[] {
  const out: string[] = [];
  for (const [key, syns] of Object.entries(table)) {
    if (syns.some((s) => hasPositiveWord(text, s)) && !out.includes(key)) {
      out.push(key);
    }
  }
  return out;
}

export function extractPromptSignals(prompt: string): PromptSignals {
  // Antes se buscaban los sinónimos como subcadena cruda: "trabajo" activaba
  // "bajo" (altura), "grande" salía de "grandes planes", etc. Ahora se exige
  // frontera de palabra (raíces de intereses: frontera solo por delante).
  const t = normalize(prompt);

  // Sólo hace falta saber si la frase habla de pelo: es lo que decide qué hacer
  // con un color ambiguo suelto, sin sustantivo cerca.
  const mentionsHair =
    HAIR_NOUNS.some((w) => hasWord(t, w)) ||
    Object.values(HAIR_UNAMBIGUOUS).some((syns) => syns.some((s) => hasWord(t, s)));

  // OJOS. Los colores exclusivos de ojos (azul/verde/avellana) cuentan siempre.
  // Los COMPARTIDOS con el pelo (negro/gris/marrón) se asignan al sustantivo que
  // tengan más cerca: "pelo negro" ya no activa "ojos negros", y en "pelo negro
  // y ojos claros" el negro se queda solo en el pelo.
  const eyeColors: string[] = [];
  for (const [key, syns] of Object.entries(EYE_SYNONYMS)) {
    const hit = syns.find((s) => hasPositiveWord(t, s));
    if (hit === undefined) continue;
    if (EYE_ONLY.has(key)) {
      eyeColors.push(key);
      continue;
    }
    const target = refersTo(t, hit);
    // Sin ningún sustantivo que desambigüe se mantiene el comportamiento de
    // siempre (color suelto = ojos), salvo que la frase sí hable de pelo.
    if (target === "eyes" || (target === "none" && !mentionsHair)) {
      eyeColors.push(key);
    }
  }

  // PELO. Las palabras inequívocas de pelo (rubia, pelirroja, castaña, morena)
  // cuentan siempre; las compartidas, solo si el sustantivo más cercano es de
  // pelo.
  const hairColors: string[] = [];
  for (const [key, syns] of Object.entries(HAIR_SYNONYMS)) {
    const unambiguous = HAIR_UNAMBIGUOUS[key] ?? [];
    if (unambiguous.some((s) => hasPositiveWord(t, s))) {
      hairColors.push(key);
      continue;
    }
    const hit = syns.find((s) => hasPositiveWord(t, s));
    if (hit === undefined) continue;
    if (refersTo(t, hit) === "hair") hairColors.push(key);
  }
  // "moreno" = pelo oscuro: cuenta como castaño Y negro.
  if (DARK_HAIR_WORDS.some((w) => hasPositiveWord(t, w))) {
    for (const key of ["brown", "black"]) {
      if (!hairColors.includes(key)) hairColors.push(key);
    }
  }

  const bodyTypes = matchTable(t, BODY_SYNONYMS);
  const personality = matchTable(t, PERSONALITY_SYNONYMS);
  const genders = matchTable(t, GENDER_SYNONYMS);
  // Si se nombran dos géneros, no hay preferencia clara: mejor no filtrar que
  // filtrar mal.
  const gender: GenderPref =
    genders.length === 1 ? (genders[0] as GenderPref) : "any";

  // Altura. Si se nombran LAS DOS ("no me importa si es alto o bajo", "alto o
  // bajito, me da igual") no hay preferencia clara: mismo criterio que con el
  // género, mejor no filtrar que filtrar mal. Antes ganaba "alto" por orden de
  // evaluación y la frase acababa filtrando justo lo que decía no filtrar.
  const wantsTall = TALL_WORDS.some((w) => hasPositiveWord(t, w));
  const wantsShort =
    SHORT_WORDS.some((w) => hasPositiveWord(t, w)) ||
    SHORT_STEMS.some((w) => hasStem(t, w) && !isNegated(t, w));
  let heightPref: HeightPref = "any";
  if (wantsTall && !wantsShort) heightPref = "tall";
  else if (wantsShort && !wantsTall) heightPref = "short";

  const keywords: string[] = [];
  for (const w of INTEREST_VOCAB) {
    if (hasStem(t, w) && !keywords.includes(w)) keywords.push(w);
  }
  return {
    gender,
    eyeColors,
    hairColors,
    bodyTypes,
    heightPref,
    personality,
    keywords,
  };
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
    s.gender === "any" &&
    s.eyeColors.length === 0 &&
    s.hairColors.length === 0 &&
    s.bodyTypes.length === 0 &&
    s.heightPref === "any" &&
    s.personality.length === 0 &&
    s.keywords.length === 0
  );
}

/// Datos declarados de un candidato que se pueden casar con el prompt.
export interface PromptProfileData {
  gender?: string;
  eyeColor?: string;
  hairColor?: string;
  bodyType?: string;
  heightCm?: number;
  /// Etiquetas de personalidad declaradas (claves del catálogo).
  personalityTags?: string[];
  text: string;
}

/// Crédito que se le da a un criterio que el perfil NO declara. Es el punto
/// medio a propósito: no declarar no premia ni castiga, sólo deja de aportar
/// evidencia. Es la pieza que arregla el fallo de fondo del modelo anterior.
export const UNKNOWN_CREDIT = 0.5;

/// Resultado del encaje de datos.
///
/// `score` es null cuando el prompt NO pide ningún criterio puntuable (por
/// ejemplo sólo el género, que va por veto): eso NO es un cero, es "no hay nada
/// que puntuar", y quien llama debe tratarlo como neutral.
export interface PromptDataMatch {
  score: number | null;
  /// Nº de criterios PEDIDOS que se han puntuado (declarados o no).
  comparable: number;
  /// El perfil declara un género y NO es el que se pidió. Es un VETO, no una
  /// nota baja: quien llama tiene que sacarlo del ranking.
  genderMismatch: boolean;
}

/// Puntúa [0..1] el encaje de datos declarados con las señales.
///
/// EL DENOMINADOR SON LOS CRITERIOS PEDIDOS, no los que el perfil rellenó.
/// Antes era al revés y eso invertía el ranking en el caso más normal. Medido
/// con el prompt literal "chico alto fuerte majo y amable", coseno visual 0.55:
///
///   perfil                                          antes        ahora
///   A: sólo declara gender=male, nada más           0.730 (1º)   0.530 (2º)
///   B: male, 187cm, muscular, tags=[fun]            0.630 (2º)   0.597 (1º)
///
/// B es literalmente lo que se pidió y salía POR DETRÁS de A, del que no se
/// sabe nada. La causa era que `got/total` usaba como denominador los campos
/// que cada perfil había rellenado: B era "comparable" en personalidad sólo
/// porque rellenó `personalityTags`, y como su etiqueta no era la pedida perdía
/// un cuarto de la nota, mientras A quedaba exento por no declarar nada. O sea,
/// DECLARAR DATOS BAJABA LA NOTA. Con el denominador fijo en lo que pide el
/// prompt y `UNKNOWN_CREDIT` para lo no declarado, rellenar el perfil sólo
/// puede subir o dejar igual.
///
/// EL GÉNERO NO ENTRA EN LA MEDIA. Es un veto. Como criterio más de un
/// promedio lo diluía todo: con "chica morena de ojos verdes" una mujer de ojos
/// MARRONES pasaba de 0.330 (descartada, correcto) a 0.530 (dentro), porque
/// añadir un criterio que casi todo el mundo cumple —el feed ya filtra por
/// orientación— reparte el peso y rescata a quien falla lo que sí se pidió.
export function dataMatch(
  signals: PromptSignals,
  profile: PromptProfileData
): PromptDataMatch {
  const noMatch: PromptDataMatch = {
    score: null,
    comparable: 0,
    genderMismatch: false,
  };
  if (signalsAreEmpty(signals)) return noMatch;

  // ── GÉNERO: veto duro, fuera del promedio ────────────────────────────────
  // Si el perfil declara género y no es el pedido, se acabó. Si no lo declara,
  // no penaliza (mismo criterio permisivo que FeedFilter con el dato ausente).
  if (signals.gender !== "any") {
    const declared = canonicalTrait(GENDER_SYNONYMS, profile.gender);
    if (declared !== null && declared !== signals.gender) {
      return { score: 0, comparable: 1, genderMismatch: true };
    }
  }

  let got = 0;
  let total = 0;
  const pt = normalize(profile.text);

  /// Suma un criterio PEDIDO. El denominador SIEMPRE crece: lo que decide la
  /// nota es lo que se pidió, no lo que el perfil rellenó.
  /// `declared=false` => el perfil no lo dice => crédito neutro (ni premia ni
  /// castiga). `credit` va en [0..1] para los criterios con varios valores
  /// (personalidad, intereses): pedir dos cosas y cumplir una no es lo mismo
  /// que cumplir las dos, ni que no cumplir ninguna.
  const add = (declared: boolean, credit: number): void => {
    total += 1;
    got += declared ? Math.max(0, Math.min(1, credit)) : UNKNOWN_CREDIT;
  };

  if (signals.eyeColors.length > 0) {
    const declared = canonicalTrait(EYE_SYNONYMS, profile.eyeColor);
    add(declared !== null, declared !== null && signals.eyeColors.includes(declared) ? 1 : 0);
  }
  if (signals.hairColors.length > 0) {
    const declared = canonicalTrait(HAIR_SYNONYMS, profile.hairColor);
    add(declared !== null, declared !== null && signals.hairColors.includes(declared) ? 1 : 0);
  }
  if (signals.bodyTypes.length > 0) {
    const declared = canonicalTrait(BODY_SYNONYMS, profile.bodyType);
    add(declared !== null, declared !== null && signals.bodyTypes.includes(declared) ? 1 : 0);
  }
  if (signals.heightPref !== "any") {
    const has = typeof profile.heightCm === "number" && profile.heightCm > 0;
    const ok =
      has &&
      (signals.heightPref === "tall"
        ? (profile.heightCm as number) >= 180
        : (profile.heightCm as number) <= 170);
    add(has, ok ? 1 : 0);
  }
  // PERSONALIDAD. Primero lo DECLARADO en `personalityTags`; si el perfil no
  // rellenó esa lista, vale que lo diga de sí mismo en la bio/prompts ("soy muy
  // simpático"). El texto libre exige marcador de identidad: antes bastaba con
  // que la palabra apareciera, así que "me encanta el dulce" contaba como
  // "amable" y "planes originales" como "creativo".
  if (signals.personality.length > 0) {
    const declared = (profile.personalityTags ?? [])
      .map((tag) => canonicalTrait(PERSONALITY_SYNONYMS, tag))
      .filter((k): k is string => k !== null);
    const fromText =
      declared.length === 0 && pt.trim().length > 0
        ? Object.entries(PERSONALITY_SYNONYMS)
            .filter(([, syns]) => syns.some((w) => saysAboutSelf(pt, w)))
            .map(([key]) => key)
        : [];
    const all = Array.from(new Set([...declared, ...fromText]));
    const hits = signals.personality.filter((k) => all.includes(k)).length;
    add(all.length > 0, hits / signals.personality.length);
  }
  if (signals.keywords.length > 0) {
    const hasText = pt.trim().length > 0;
    const hits = signals.keywords.filter((k) => hasStem(pt, k)).length;
    add(hasText, hits / signals.keywords.length);
  }

  if (total === 0) return noMatch;
  return {
    score: Math.min(1, got / total),
    comparable: total,
    genderMismatch: false,
  };
}

/// ¿Este candidato merece salir en un filtro por prompt?
///
/// La regla es "tiene que saberse ALGO mejor que nada": se exige superar el
/// crédito neutro. Con el modelo de arriba, un perfil que no declara ninguno de
/// los criterios pedidos saca exactamente `UNKNOWN_CREDIT`, así que quedarse en
/// el neutro significa "no hay ni una prueba de que encaje". Antes esa gente
/// entraba con nota alta y el usuario recibía medio feed como si fuera una
/// respuesta a lo que había escrito.
///
/// Es un filtro de PRECISIÓN, y precisión cuesta recall: con perfiles poco
/// rellenos devolverá pocos resultados. Eso es deliberado —el encargo pedía ser
/// ultra preciso— y el feed ya sabe decir "nadie encaja, quita el filtro" en vez
/// de rellenar con ruido.
export function passesDataFilter(match: PromptDataMatch): boolean {
  if (match.genderMismatch) return false;
  if (match.score === null) return true;
  return match.score > UNKNOWN_CREDIT + 1e-9;
}

/// Variante numérica (0 cuando no hay nada comparable). Se mantiene por
/// compatibilidad; para rankear usa `dataMatch` y distingue el null.
export function dataScore(
  signals: PromptSignals,
  profile: PromptProfileData
): number {
  return dataMatch(signals, profile).score ?? 0;
}
