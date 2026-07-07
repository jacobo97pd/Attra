import { onCall, HttpsError } from "firebase-functions/v2/https";
import { DocumentData, FieldValue } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import {
  col,
  existsBlockBetween,
  nextJourneyStatus,
  requireAuthUid,
  requireStringArg,
  resolvePublicDisplayName,
} from "./common";
import {
  PlanCategory,
  categoryMeta,
  commonCategories,
  isValidZone,
  passesPlaceQuality,
  recommendedPlanTypes,
} from "./datePlanRules";
import { searchPlaces, PlaceResult } from "./places";

/// Attra Plans — funciones server-side. El cliente NUNCA escribe en
/// `matches/{matchId}/datePlans`: pasa por aquí (Admin SDK, autoritativo).
///
/// Fase 1: solo `createDatePlanProposal` (manual, sin IA ni Places). La
/// generación con reglas/Places (Fase 2), IA (Fase 3) y votación (Fase 4)
/// se añaden como funciones nuevas sin tocar ésta.

const MAX_OPTIONS = 3;
const MAX_OPEN_PROPOSALS_PER_MATCH = 2; // anti-abuso
const PROPOSAL_COOLDOWN_MS = 30 * 60 * 1000; // 30 min entre propuestas por usuario
const PROPOSAL_TTL_MS = 7 * 24 * 60 * 60 * 1000; // caduca a los 7 días
const OPEN_STATUSES = [
  "pending",
  "accepted_by_user_a",
  "accepted_by_user_b",
];
const PRIVACY_MODES = ["city", "zone", "midpoint"];

/// Lee los flags de Attra Plans de `config/featureFlags`. Kill switch y
/// habilitación se comprueban SIEMPRE server-side (defensa en profundidad).
async function requireDatePlansEnabled(): Promise<void> {
  const cfgSnap = await db.collection("config").doc("featureFlags").get();
  const cfg = cfgSnap.data() ?? {};
  const enabled = cfg.date_plans_enabled ?? cfg.datePlansEnabled ?? false;
  const kill = cfg.date_plans_kill_switch ?? cfg.datePlansKillSwitch ?? false;
  if (enabled !== true || kill === true) {
    throw new HttpsError(
      "failed-precondition",
      "Attra Plans no está disponible ahora mismo."
    );
  }
}

/// Sanea una opción de plan enviada por el cliente. En Fase 1 (manual) NO hay
/// datos de Places: se limita a texto libre acotado, sin geo exacta.
function sanitizeManualOption(raw: unknown, index: number): DocumentData {
  const o = (raw ?? {}) as DocumentData;
  const str = (v: unknown, max: number): string =>
    typeof v === "string" ? v.trim().slice(0, max) : "";
  const title = str(o.title, 80);
  if (!title) {
    throw new HttpsError(
      "invalid-argument",
      `La opción ${index + 1} necesita un título.`
    );
  }
  let dt: string | null = null;
  if (typeof o.suggestedDateTime === "string") {
    const parsed = new Date(o.suggestedDateTime);
    if (!Number.isNaN(parsed.getTime())) dt = parsed.toISOString();
  }
  return {
    id: `opt_${index + 1}`,
    title,
    description: str(o.description, 300),
    // Fase 1 manual: sin lugar real verificado por Places.
    placeName: str(o.placeName, 120),
    placeId: "",
    placeType: str(o.placeType, 60),
    address: str(o.address, 200),
    area: str(o.area, 80),
    mapsUrl: "",
    suggestedDateTime: dt,
    whyItFits: str(o.whyItFits, 300),
    tags: Array.isArray(o.tags)
      ? (o.tags as unknown[])
          .filter((t): t is string => typeof t === "string")
          .slice(0, 6)
          .map((t) => t.slice(0, 40))
      : [],
    sourceApi: "manual",
  };
}

/// Nombre humano (para el "por qué encaja") de cada categoría.
const CATEGORY_NOUN: Record<PlanCategory, string> = {
  cafe: "el café",
  paseo: "pasear",
  helado: "los helados",
  comida: "comer bien",
  copas: "tomar algo",
  cultura: "el arte y la cultura",
  musica: "la música",
};

/// Franjas de precio aceptables por presupuesto declarado.
const BUDGET_PRICE_LEVELS: Record<string, number[]> = {
  bajo: [0, 1],
  medio: [1, 2, 3],
  alto: [2, 3, 4],
};

/// Extrae señales de interés de un usuario (intereses declarados + bio +
/// respuestas de prompts). Solo texto; nunca datos sensibles.
function userInterestSignals(data: DocumentData | undefined): string[] {
  const d = data ?? {};
  const profile =
    d.profile && typeof d.profile === "object" ? (d.profile as DocumentData) : {};
  const collect = (v: unknown): string[] =>
    Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : [];
  const interests = [...collect(d.interests), ...collect(profile.interests)];
  const bio = typeof profile.bio === "string" ? profile.bio : "";
  const prompts = Array.isArray(profile.prompts)
    ? (profile.prompts as DocumentData[]).map((p) =>
        (p?.answer ?? p?.text ?? "").toString()
      )
    : [];
  return [...interests, bio, ...prompts].filter((s) => s.trim().length > 0);
}

/// Día/hora sugeridos a partir de las preferencias (aprox., editable después).
function computeSuggestedDateTime(
  dateRange: string,
  timeWindow: string
): Date {
  const now = new Date();
  const target = new Date(now);
  if (dateRange === "weekend") {
    // próximo sábado
    const day = target.getDay(); // 0=domingo..6=sábado
    const add = (6 - day + 7) % 7 || 7;
    target.setDate(target.getDate() + add);
  } else {
    target.setDate(target.getDate() + 2);
  }
  const hour =
    timeWindow === "afternoon" ? 17 : timeWindow === "evening" ? 20 : 19;
  target.setHours(hour, 30, 0, 0);
  return target;
}

/// generateDatePlanSuggestions (Fase 2): genera hasta 3 opciones de plan con
/// REGLAS (intereses comunes) + Google Places (lugares reales). Si Places no
/// está disponible, usa fallback (tipo de plan sin inventar sitios). No expone
/// ubicación exacta de ningún usuario.
export const generateDatePlanSuggestions = onCall(
  { region: REGION },
  async (request) => {
    const uid = requireAuthUid(request.auth);
    const chatId = requireStringArg(request.data?.chatId, "chatId");
    await requireDatePlansEnabled();

    const optZone =
      typeof request.data?.zone === "string" ? request.data.zone.trim() : "";
    const dateRange =
      typeof request.data?.dateRange === "string" ? request.data.dateRange : "";
    const timeWindow =
      typeof request.data?.timeWindow === "string"
        ? request.data.timeWindow
        : "flexible";
    const budget =
      typeof request.data?.budget === "string" ? request.data.budget : "";

    const chatRef = col.chats.doc(chatId);
    const chatSnap = await chatRef.get();
    if (!chatSnap.exists) throw new HttpsError("not-found", "El chat no existe.");
    const chat = chatSnap.data() ?? {};
    const users: string[] = (chat.users ?? []) as string[];
    if (!users.includes(uid)) {
      throw new HttpsError("permission-denied", "No participas en este chat.");
    }
    if ((chat.status ?? "active") !== "active") {
      throw new HttpsError("failed-precondition", "Este chat ya no está disponible.");
    }
    const otherUid = users.find((u) => u !== uid) ?? "";
    if (await existsBlockBetween(uid, otherUid)) {
      throw new HttpsError("permission-denied", "No puedes proponer un plan a este usuario.");
    }
    const matchId = (chat.matchId ?? chatId).toString();
    const plansCol = col.matches.doc(matchId).collection("datePlans");

    // Anti-abuso (igual que en creación manual): límite de abiertas + cooldown.
    const openSnap = await plansCol
      .where("status", "in", OPEN_STATUSES)
      .limit(MAX_OPEN_PROPOSALS_PER_MATCH + 1)
      .get();
    if (openSnap.size >= MAX_OPEN_PROPOSALS_PER_MATCH) {
      throw new HttpsError(
        "resource-exhausted",
        "Ya hay propuestas de plan abiertas. Resolvedlas antes de crear otra."
      );
    }
    const nowMs = Date.now();
    for (const doc of openSnap.docs) {
      const d = doc.data();
      if (d.createdBy === uid) {
        const createdMs = (d.createdAt?.toMillis?.() ?? 0) as number;
        if (createdMs && nowMs - createdMs < PROPOSAL_COOLDOWN_MS) {
          throw new HttpsError(
            "resource-exhausted",
            "Espera un poco antes de proponer otro plan."
          );
        }
      }
    }

    // Perfiles de ambos + mensajes recientes (para intereses comunes).
    const [meSnap, otherSnap, msgsSnap] = await Promise.all([
      col.users.doc(uid).get(),
      otherUid ? col.users.doc(otherUid).get() : Promise.resolve(null),
      chatRef
        .collection("messages")
        .where("type", "==", "text")
        .orderBy("createdAt", "desc")
        .limit(30)
        .get()
        .catch(() => null),
    ]);
    const aInterests = userInterestSignals(meSnap.data());
    const bInterests = userInterestSignals(otherSnap?.data());
    const chatMessages: string[] = msgsSnap
      ? msgsSnap.docs.map((d) => (d.data().text ?? "").toString())
      : [];

    const common = commonCategories(aInterests, bInterests, chatMessages);
    // Permite forzar un tipo (optionalPlanType) colocándolo primero.
    const forced =
      typeof request.data?.planType === "string"
        ? (request.data.planType as string)
        : "";
    const seed =
      forced && ALL_CATEGORY_KEYS.includes(forced as PlanCategory)
        ? [forced as PlanCategory, ...common.filter((c) => c !== forced)]
        : common;
    const types = recommendedPlanTypes(seed);

    // Zona/ciudad (nunca ubicación exacta). Solo llamamos a Places si hay zona
    // o ciudad válida.
    const cfgSnap = await db.collection("config").doc("featureFlags").get();
    const cfg = cfgSnap.data() ?? {};
    const placesEnabled =
      (cfg.date_plans_places_enabled ?? cfg.datePlansPlacesEnabled ?? false) === true;
    const city =
      typeof meSnap.data()?.profile?.city === "string"
        ? (meSnap.data()!.profile.city as string).trim()
        : typeof meSnap.data()?.city === "string"
          ? (meSnap.data()!.city as string).trim()
          : "";
    const zone = isValidZone(optZone) ? optZone : "";
    const locationText = [zone, city].filter((s) => s.length > 0).join(", ");
    const canUsePlaces = placesEnabled && locationText.length > 0;

    const budgetLevels = BUDGET_PRICE_LEVELS[budget] ?? null;
    const usedPlaceIds = new Set<string>();
    const suggestedAt = computeSuggestedDateTime(dateRange, timeWindow);

    const options: DocumentData[] = [];
    for (let i = 0; i < types.length; i++) {
      const cat = types[i];
      const meta = categoryMeta(cat);
      let picked: PlaceResult | null = null;
      if (canUsePlaces) {
        const query = `${meta.placeQuery} near ${locationText}`;
        const results = await searchPlaces(query);
        // Aplica presupuesto si se pidió; si nada encaja, ignora el filtro.
        const byBudget = budgetLevels
          ? results.filter(
              (r) => r.priceLevel === undefined || budgetLevels.includes(r.priceLevel)
            )
          : results;
        const pool = byBudget.length > 0 ? byBudget : results;
        picked = pool.find((r) => !usedPlaceIds.has(r.placeId)) ?? null;
        if (picked) usedPlaceIds.add(picked.placeId);
      }

      const why = buildWhyItFits(common, cat);
      if (picked && passesPlaceQuality(picked.rating, picked.reviewCount)) {
        options.push({
          id: `opt_${i + 1}`,
          title: meta.title,
          description: "",
          placeName: picked.name,
          placeId: picked.placeId,
          placeType: picked.placeType,
          address: picked.address,
          area: zone || city,
          rating: picked.rating ?? null,
          reviewCount: picked.reviewCount ?? null,
          priceLevel: picked.priceLevel ?? null,
          mapsUrl: picked.mapsUrl,
          suggestedDateTime: suggestedAt.toISOString(),
          whyItFits: why,
          tags: [meta.tag],
          sourceApi: "google_places",
        });
      } else {
        // Fallback: tipo de plan sin inventar un sitio concreto.
        options.push({
          id: `opt_${i + 1}`,
          title: meta.title,
          description: "",
          placeName: "",
          placeId: "",
          placeType: "",
          address: "",
          area: zone || city,
          mapsUrl: "",
          suggestedDateTime: suggestedAt.toISOString(),
          whyItFits: why,
          tags: [meta.tag],
          sourceApi: "fallback",
        });
      }
    }

    const commonInterests = common
      .slice(0, 3)
      .map((c) => CATEGORY_NOUN[c])
      .filter((s) => s.length > 0);
    const otherName = resolvePublicDisplayName(otherSnap?.data() ?? undefined);
    const generatedReason = buildGeneratedReason(commonInterests, otherName);

    const planRef = plansCol.doc();
    const serverNow = FieldValue.serverTimestamp();
    const orderedUsers = [...users].sort();
    await planRef.set({
      matchId,
      chatId,
      createdBy: uid,
      users: orderedUsers,
      status: "pending",
      source: "ai_suggested",
      options,
      acceptedBy: [],
      rejectedBy: [],
      votesByUser: {},
      selectedOptionId: "",
      commonInterests,
      generatedReason,
      city,
      zone,
      privacyMode: zone ? "zone" : "city",
      createdAt: serverNow,
      updatedAt: serverNow,
      expiresAt: new Date(nowMs + PROPOSAL_TTL_MS),
    });

    await col.matches
      .doc(matchId)
      .set(
        {
          journeyStatus: nextJourneyStatus(chat.journeyStatus, "date_proposed"),
          journeyUpdatedAt: serverNow,
        },
        { merge: true }
      )
      .catch(() => undefined);

    const usedRealPlaces = options.some((o) => o.sourceApi === "google_places");
    return { planId: planRef.id, usedRealPlaces, optionCount: options.length };
  }
);

const ALL_CATEGORY_KEYS: PlanCategory[] = [
  "cafe",
  "paseo",
  "helado",
  "comida",
  "copas",
  "cultura",
  "musica",
];

function buildWhyItFits(common: PlanCategory[], cat: PlanCategory): string {
  if (common.includes(cat)) {
    return `Os pega porque a los dos os gusta ${CATEGORY_NOUN[cat]}.`;
  }
  if (common.length > 0) {
    return `Un plan distinto para variar un poco.`;
  }
  return "Un plan sencillo y tranquilo para veros por primera vez.";
}

function buildGeneratedReason(interests: string[], otherName: string): string {
  const who = otherName ? `A ${otherName} y a ti` : "A los dos";
  if (interests.length >= 2) {
    return `${who} os gusta ${interests[0]} y ${interests[1]}, así que os dejo un par de ideas para veros.`;
  }
  if (interests.length === 1) {
    return `${who} os gusta ${interests[0]}. Igual alguna de estas ideas os viene bien para quedar.`;
  }
  return `Un par de ideas para veros por primera vez, con calma.`;
}

/// createDatePlanProposal (Fase 1): crea una propuesta MANUAL en el match del
/// chat. Valida pertenencia, chat activo, no-bloqueo, límite de propuestas
/// abiertas y cooldown. NO expone ni guarda ubicación exacta de ningún usuario.
export const createDatePlanProposal = onCall(
  { region: REGION },
  async (request) => {
    const uid = requireAuthUid(request.auth);
    const chatId = requireStringArg(request.data?.chatId, "chatId");

    await requireDatePlansEnabled();

    const optionsIn = Array.isArray(request.data?.options)
      ? (request.data.options as unknown[])
      : [];
    if (optionsIn.length === 0) {
      throw new HttpsError("invalid-argument", "Añade al menos una opción de plan.");
    }
    if (optionsIn.length > MAX_OPTIONS) {
      throw new HttpsError(
        "invalid-argument",
        `Máximo ${MAX_OPTIONS} opciones por propuesta.`
      );
    }
    const options = optionsIn.map((o, i) => sanitizeManualOption(o, i));

    const city =
      typeof request.data?.city === "string"
        ? (request.data.city as string).trim().slice(0, 80)
        : "";
    const zone =
      typeof request.data?.zone === "string"
        ? (request.data.zone as string).trim().slice(0, 80)
        : "";
    const privacyModeRaw =
      typeof request.data?.privacyMode === "string"
        ? (request.data.privacyMode as string).trim()
        : "city";
    const privacyMode = PRIVACY_MODES.includes(privacyModeRaw)
      ? privacyModeRaw
      : "city";

    const chatRef = col.chats.doc(chatId);
    const chatSnap = await chatRef.get();
    if (!chatSnap.exists) {
      throw new HttpsError("not-found", "El chat no existe.");
    }
    const chat = chatSnap.data() ?? {};
    const users: string[] = (chat.users ?? []) as string[];
    if (!users.includes(uid)) {
      throw new HttpsError("permission-denied", "No participas en este chat.");
    }
    if ((chat.status ?? "active") !== "active") {
      throw new HttpsError("failed-precondition", "Este chat ya no está disponible.");
    }
    const otherUid = users.find((u) => u !== uid) ?? "";
    if (await existsBlockBetween(uid, otherUid)) {
      throw new HttpsError("permission-denied", "No puedes proponer un plan a este usuario.");
    }
    const matchId = (chat.matchId ?? chatId).toString();
    const plansCol = col.matches.doc(matchId).collection("datePlans");

    // Anti-abuso: nº de propuestas abiertas + cooldown de la última del usuario.
    const openSnap = await plansCol
      .where("status", "in", OPEN_STATUSES)
      .limit(MAX_OPEN_PROPOSALS_PER_MATCH + 1)
      .get();
    if (openSnap.size >= MAX_OPEN_PROPOSALS_PER_MATCH) {
      throw new HttpsError(
        "resource-exhausted",
        "Ya hay propuestas de plan abiertas. Resolvedlas antes de crear otra."
      );
    }
    const now = Date.now();
    for (const doc of openSnap.docs) {
      const d = doc.data();
      if (d.createdBy === uid) {
        const createdMs = (d.createdAt?.toMillis?.() ?? 0) as number;
        if (createdMs && now - createdMs < PROPOSAL_COOLDOWN_MS) {
          throw new HttpsError(
            "resource-exhausted",
            "Espera un poco antes de proponer otro plan."
          );
        }
      }
    }

    const planRef = plansCol.doc();
    const serverNow = FieldValue.serverTimestamp();
    // Orden determinista a/b para el ciclo de votación (Fase 4).
    const orderedUsers = [...users].sort();

    await planRef.set({
      matchId,
      chatId,
      createdBy: uid,
      users: orderedUsers,
      status: "pending",
      source: "manual",
      options,
      acceptedBy: [],
      rejectedBy: [],
      votesByUser: {},
      selectedOptionId: "",
      commonInterests: [],
      generatedReason: "",
      city,
      zone,
      privacyMode,
      createdAt: serverNow,
      updatedAt: serverNow,
      expiresAt: new Date(now + PROPOSAL_TTL_MS),
    });

    // Empuja el journey del match hacia "date_proposed" (monótono; no retrocede).
    await col.matches
      .doc(matchId)
      .set(
        {
          journeyStatus: nextJourneyStatus(chat.journeyStatus, "date_proposed"),
          journeyUpdatedAt: serverNow,
        },
        { merge: true }
      )
      .catch(() => undefined);

    return { planId: planRef.id };
  }
);

/// Deriva el estado de una propuesta a partir de los votos. Con la enum
/// existente: pending (0/1-mismatch), accepted_by_user_a/b (solo uno votó),
/// confirmed (ambos coinciden en opción). Un rechazo la cierra.
function derivePlanStatus(
  users: string[],
  votes: Record<string, string>,
  rejectedBy: string[]
): { status: string; selectedOptionId: string } {
  if (rejectedBy.length > 0) return { status: "rejected", selectedOptionId: "" };
  const a = users[0];
  const b = users[1];
  const va = votes[a];
  const vb = votes[b];
  if (va && vb) {
    if (va === vb) return { status: "confirmed", selectedOptionId: va };
    return { status: "pending", selectedOptionId: "" }; // votaron distinto → seguir abierto
  }
  if (va) return { status: "accepted_by_user_a", selectedOptionId: "" };
  if (vb) return { status: "accepted_by_user_b", selectedOptionId: "" };
  return { status: "pending", selectedOptionId: "" };
}

/// voteDatePlan (Fase 4): cada usuario vota su opción favorita o rechaza la
/// propuesta. Cuando AMBOS eligen la MISMA opción, queda `confirmed`. Autoritativo
/// y transaccional. voteType: 'like' (con optionId) | 'reject'.
export const voteDatePlan = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const chatId = requireStringArg(request.data?.chatId, "chatId");
  const planId = requireStringArg(request.data?.planId, "planId");
  const voteType = requireStringArg(request.data?.voteType, "voteType");
  if (voteType !== "like" && voteType !== "reject") {
    throw new HttpsError("invalid-argument", "voteType no válido.");
  }
  const optionId =
    typeof request.data?.optionId === "string" ? request.data.optionId : "";
  if (voteType === "like" && !optionId) {
    throw new HttpsError("invalid-argument", "Falta la opción elegida.");
  }
  await requireDatePlansEnabled();

  const chatRef = col.chats.doc(chatId);
  const chatSnap = await chatRef.get();
  if (!chatSnap.exists) throw new HttpsError("not-found", "El chat no existe.");
  const chat = chatSnap.data() ?? {};
  const chatUsers: string[] = (chat.users ?? []) as string[];
  if (!chatUsers.includes(uid)) {
    throw new HttpsError("permission-denied", "No participas en este chat.");
  }
  if ((chat.status ?? "active") !== "active") {
    throw new HttpsError("failed-precondition", "Este chat ya no está disponible.");
  }
  const matchId = (chat.matchId ?? chatId).toString();
  const planRef = col.matches.doc(matchId).collection("datePlans").doc(planId);

  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(planRef);
    if (!snap.exists) throw new HttpsError("not-found", "La propuesta no existe.");
    const plan = snap.data() ?? {};
    const users: string[] = Array.isArray(plan.users) ? plan.users : [];
    if (!users.includes(uid)) {
      throw new HttpsError("permission-denied", "No participas en esta propuesta.");
    }
    const expiresAtMs = (plan.expiresAt?.toMillis?.() ?? 0) as number;
    if (expiresAtMs && expiresAtMs < Date.now()) {
      throw new HttpsError("failed-precondition", "Esta propuesta ha caducado.");
    }
    if (plan.status === "confirmed" || plan.status === "rejected") {
      throw new HttpsError("failed-precondition", "Esta propuesta ya está resuelta.");
    }

    const votes: Record<string, string> =
      plan.votesByUser && typeof plan.votesByUser === "object"
        ? { ...plan.votesByUser }
        : {};
    const rejectedBy: string[] = Array.isArray(plan.rejectedBy)
      ? [...plan.rejectedBy]
      : [];
    const acceptedBy: string[] = Array.isArray(plan.acceptedBy)
      ? [...plan.acceptedBy]
      : [];

    const now = FieldValue.serverTimestamp();
    if (voteType === "reject") {
      if (!rejectedBy.includes(uid)) rejectedBy.push(uid);
      tx.update(planRef, {
        rejectedBy,
        status: "rejected",
        updatedAt: now,
      });
      return { status: "rejected", selectedOptionId: "" };
    }

    // like: la opción debe existir.
    const options: DocumentData[] = Array.isArray(plan.options) ? plan.options : [];
    if (!options.some((o) => o?.id === optionId)) {
      throw new HttpsError("invalid-argument", "Esa opción no existe.");
    }
    votes[uid] = optionId;
    if (!acceptedBy.includes(uid)) acceptedBy.push(uid);
    const derived = derivePlanStatus(users, votes, rejectedBy);
    tx.update(planRef, {
      votesByUser: votes,
      acceptedBy,
      status: derived.status,
      selectedOptionId: derived.selectedOptionId,
      updatedAt: now,
    });
    return derived;
  });

  // Si queda confirmada, empuja el journey del match hacia "date_accepted".
  if (result.status === "confirmed") {
    await col.matches
      .doc(matchId)
      .set(
        {
          journeyStatus: nextJourneyStatus(chat.journeyStatus, "date_accepted"),
          journeyUpdatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      )
      .catch(() => undefined);
  }

  return result;
});
