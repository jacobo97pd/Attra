import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { FieldValue, DocumentData, Timestamp } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { col, requireAuthUid } from "./common";

/// Base con NOMBRE (los triggers v2 apuntan a la default si no se indica).
const DATABASE = "attra-database";

const discovery = db.collection("discovery");

interface PublicTraitDefinition {
  key: string;
  group: string;
  field: string;
  sensitive?: boolean;
}

interface EffectiveVisibility {
  visibleInProfile: boolean;
  useForFilters: boolean;
}

/// Mantener en paridad con `ProfileTraitsCatalog` del cliente. La clave se usa
/// para resolver el consentimiento y group/field para leer y publicar el dato.
const PUBLIC_TRAITS: readonly PublicTraitDefinition[] = [
  { key: "pronouns", group: "profile", field: "pronouns" },
  {
    key: "sexualOrientation",
    group: "profile",
    field: "orientation",
    sensitive: true,
  },
  { key: "languages", group: "profile", field: "languages" },
  { key: "hometown", group: "profile", field: "birthCity" },
  { key: "height", group: "appearance", field: "heightCm" },
  { key: "zodiac", group: "profile", field: "zodiac" },
  { key: "eyes", group: "appearance", field: "eyeColor" },
  { key: "bodyType", group: "appearance", field: "bodyType" },
  { key: "tattoos", group: "appearance", field: "tattoos" },
  { key: "glasses", group: "appearance", field: "glasses" },
  {
    key: "relationshipGoal",
    group: "profile",
    field: "relationshipIntent",
  },
  { key: "children", group: "lifestyle", field: "hasChildren" },
  { key: "familyPlans", group: "lifestyle", field: "wantsChildren" },
  { key: "smoking", group: "lifestyle", field: "smoking" },
  { key: "drinking", group: "lifestyle", field: "drinking" },
  {
    key: "cannabis",
    group: "lifestyle",
    field: "cannabis",
    sensitive: true,
  },
  {
    key: "drugs",
    group: "lifestyle",
    field: "drugs",
    sensitive: true,
  },
  { key: "diet", group: "lifestyle", field: "diet" },
  { key: "pets", group: "lifestyle", field: "pets" },
  { key: "jobTitle", group: "profile", field: "jobTitle" },
  { key: "company", group: "profile", field: "company" },
  { key: "educationLevel", group: "profile", field: "educationLevel" },
  { key: "university", group: "profile", field: "university" },
  { key: "interestTags", group: "profile", field: "interests" },
  {
    key: "personalityTags",
    group: "style",
    field: "personalityTags",
  },
  {
    key: "ethnicity",
    group: "origin",
    field: "ethnicity",
    sensitive: true,
  },
  {
    key: "religion",
    group: "profile",
    field: "religion",
    sensitive: true,
  },
  {
    key: "politics",
    group: "profile",
    field: "politics",
    sensitive: true,
  },
];

/// True si el tier del doc de entitlements es de pago y sigue activo (no
/// caducado). Espeja la logica de `UserEntitlements.isActiveAt` del cliente.
function isPaidActive(entData: DocumentData | undefined): boolean {
  if (!entData) return false;
  const tier = (entData.tier ?? "free").toString();
  if (tier === "free") return false;
  if (entData.isLifetime === true) return true;
  const expiresAt = entData.expiresAt;
  if (expiresAt?.toMillis) return expiresAt.toMillis() >= Date.now();
  return true; // sin caducidad declarada => activo
}

/// Un usuario es descubrible (aparece en el feed de otros) si completo el
/// onboarding y el perfil, NO es un bot y no se ha ocultado:
///   - `privacy.hideProfile` (gratis): se sale del feed siempre.
///   - `privacy.showInRecommendations=false`: no aparece recomendado.
///   - `privacy.incognito` (Plus): solo surte efecto con plan de pago activo;
///     asi el modo incognito es una ventaja real de Attra Plus/Pro.
function isDiscoverable(
  data: DocumentData | undefined,
  isPaid: boolean
): boolean {
  if (!data) return false;
  if (
    data.onboardingCompleted !== true ||
    data.profileCompleted !== true ||
    data.isBot === true
  ) {
    return false;
  }
  const settings = asMap(data.settings);
  if (settings["privacy.hideProfile"] === true) return false;
  if (settings["privacy.showInRecommendations"] === false) return false;
  if (settings["privacy.incognito"] === true && isPaid) return false;
  return true;
}

function asMap(value: unknown): DocumentData {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as DocumentData)
    : {};
}

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asDouble(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number.parseFloat(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function roundTo(value: number, digits: number): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function isUsableTraitValue(value: unknown): boolean {
  if (typeof value === "string") {
    const clean = value.trim();
    return clean.length > 0 && clean !== "prefer_not_to_say";
  }
  if (typeof value === "number") return Number.isFinite(value);
  if (Array.isArray(value)) {
    return value.some(
      (item) =>
        typeof item === "string" &&
        item.trim().length > 0 &&
        item.trim() !== "prefer_not_to_say"
    );
  }
  return false;
}

function cleanTraitValue(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value
      .filter((item): item is string => typeof item === "string")
      .map((item) => item.trim())
      .filter(
        (item) => item.length > 0 && item !== "prefer_not_to_say"
      );
  }
  return typeof value === "string" ? value.trim() : value;
}

function effectiveVisibility(
  data: DocumentData,
  trait: PublicTraitDefinition
): EffectiveVisibility {
  const fields = asMap(asMap(data.profileVisibility).fields);
  const saved = asMap(fields[trait.key]);
  // Igual que ProfileVisibility.effectiveFor: no sensibles opt-out y sensibles
  // opt-in. Un mapa parcial conserva el default de cada propiedad.
  const fallback = trait.sensitive !== true;
  return {
    visibleInProfile:
      typeof saved.visibleInProfile === "boolean"
        ? saved.visibleInProfile
        : fallback,
    useForFilters:
      typeof saved.useForFilters === "boolean"
        ? saved.useForFilters
        : fallback,
  };
}

/// Construye el documento PLANO de discovery con SOLO campos publicos, con las
/// claves que `SeedProfile.fromMap` (cliente) espera. Datos privados (email,
/// ajustes, ubicacion exacta) NO se copian.
/// Nombre PUBLICO elegido por el usuario (nunca el legal/Auth de Google).
/// Prioridad: profile.displayName > profile.visibleName > firstName+lastName >
/// displayName de primer nivel (ultimo recurso, puede venir de Auth).
function resolvePublicDisplayName(data: DocumentData): string {
  const profile = asMap(data.profile);
  const s = (v: unknown): string => (typeof v === "string" ? v.trim() : "");
  const full = [s(profile.firstName), s(profile.lastName)]
    .filter((x) => x.length > 0)
    .join(" ")
    .trim();
  return (
    s(profile.displayName) || s(profile.visibleName) || full || s(data.displayName)
  );
}

function asInt(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return Math.trunc(value);
  if (typeof value === "string") {
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function asDate(value: unknown): Date | null {
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === "string") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  if (value && typeof value === "object" && "toDate" in value) {
    const maybeTimestamp = value as { toDate?: unknown };
    if (typeof maybeTimestamp.toDate === "function") {
      const date = maybeTimestamp.toDate();
      return date instanceof Date && !Number.isNaN(date.getTime()) ? date : null;
    }
  }
  return null;
}

function ageFromBirthDate(value: unknown): number | null {
  const birthDate = asDate(value);
  if (!birthDate) return null;
  const now = new Date();
  let age = now.getUTCFullYear() - birthDate.getUTCFullYear();
  const hasBirthdayPassed =
    now.getUTCMonth() > birthDate.getUTCMonth() ||
    (now.getUTCMonth() === birthDate.getUTCMonth() &&
      now.getUTCDate() >= birthDate.getUTCDate());
  if (!hasBirthdayPassed) age -= 1;
  if (age < 0 || age > 120) return null;
  return age;
}

function publicProfilePrompts(data: DocumentData): DocumentData[] {
  const rawPrompts = Array.isArray(data.profilePrompts) ? data.profilePrompts : [];
  return rawPrompts
    .map((value: unknown) => asMap(value))
    .filter((prompt) => prompt.isActive !== false)
    .map((prompt) => ({
      id: asString(prompt.id),
      question: asString(prompt.question),
      answer: asString(prompt.answer),
    }))
    .filter((prompt) => prompt.question.length > 0 && prompt.answer.length > 0);
}

function publicIntroMedia(value: unknown): DocumentData | null {
  const media = asMap(value);
  return asString(media.url).length > 0 ? media : null;
}

function buildDiscoveryDoc(uid: string, data: DocumentData): DocumentData {
  const profile = asMap(data.profile);
  const prefs = asMap(data.preferences);
  const settings = asMap(data.settings);
  const age =
    asInt(profile.age) ??
    asInt(data.age) ??
    ageFromBirthDate(profile.birthDate ?? data.birthDate);

  const nestedTravel = asMap(settings.travel);
  const travel =
    Object.keys(nestedTravel).length > 0 ? nestedTravel : asMap(data.travel);
  const traveling =
    travel.active === true && asString(travel.country).length > 0;
  const realCity = asString(profile.currentCity ?? profile.city);
  const realCountry = asString(profile.currentCountryName);
  const publicCity = traveling ? asString(travel.city) : realCity;
  const showCity = settings["location.showOnProfile"] !== false;

  const out: DocumentData = {
    uid,
    isBot: false,
    displayName: resolvePublicDisplayName(data),
    photoUrl: data.photoUrl ?? data.profilePhotoUrl ?? "",
    photos: Array.isArray(data.photos) ? data.photos : [],
    gender: profile.gender ?? "",
    interestedIn: Array.isArray(prefs.interestedIn) ? prefs.interestedIn : [],
    age,
    bio: profile.bio ?? "",
    currentCity: showCity ? publicCity : "",
    currentCountryName: traveling ? asString(travel.country) : realCountry,
    traveling,
    showDistance: settings["privacy.showDistance"] !== false,
    showActiveStatus: settings["privacy.showActiveStatus"] !== false,
    // Modo Amigos: intención + intereses sociales (default dating si falta).
    intentMode:
      typeof profile.intentMode === "string" && profile.intentMode
        ? profile.intentMode
        : "dating",
    socialInterests: Array.isArray(profile.socialInterests)
      ? profile.socialInterests
      : [],
  };

  const filterTraits: DocumentData = {};
  for (const trait of PUBLIC_TRAITS) {
    const value = asMap(data[trait.group])[trait.field];
    if (!isUsableTraitValue(value)) continue;
    const visibility = effectiveVisibility(data, trait);
    if (visibility.visibleInProfile) {
      out[trait.field] = cleanTraitValue(value);
    }
    if (
      trait.sensitive === true &&
      visibility.useForFilters &&
      typeof value === "string"
    ) {
      filterTraits[trait.field] = value.trim();
    }
  }
  if (Object.keys(filterTraits).length > 0) {
    out.filterTraits = filterTraits;
  }

  const prompts = publicProfilePrompts(data);
  if (prompts.length > 0) out.profilePrompts = prompts;

  const introAudio = publicIntroMedia(profile.introAudio);
  if (introAudio) out.introAudio = introAudio;
  const introVideo = publicIntroMedia(profile.introVideo);
  if (introVideo) out.introVideo = introVideo;

  if (settings["integrations.instagram"] === true) {
    const instagram = asString(settings["integrations.instagramHandle"]);
    if (instagram.length > 0) out.instagram = instagram;
  }

  const verification = asMap(data.verification);
  if (asString(verification.liveSelfiePublicPhotoUrl).length > 0) {
    out.verified = true;
  }

  // Coordenadas aproximadas: nunca copiamos latitud/longitud exactas.
  const location = asMap(data.location);
  const latitude = asDouble(location.latitude);
  const longitude = asDouble(location.longitude);
  if (latitude !== null && longitude !== null) {
    const approximate =
      asString(settings["location.precision"]).toLowerCase() === "approximate";
    const digits = approximate ? 1 : 2;
    out.geo = {
      lat: roundTo(latitude, digits),
      lng: roundTo(longitude, digits),
    };
  }

  out.updatedAt = FieldValue.serverTimestamp();
  return out;
}

/// Espeja un user en discovery (o lo borra si no es descubrible). Idempotente.
/// Lee el tier (userEntitlements) para resolver el modo incognito (Plus).
async function syncOne(uid: string, data: DocumentData | undefined): Promise<void> {
  const ref = discovery.doc(uid);
  let isPaid = false;
  // Solo necesitamos el tier si el usuario activo el modo incognito.
  if (asMap(data?.settings)["privacy.incognito"] === true) {
    const entSnap = await col.entitlements.doc(uid).get();
    isPaid = isPaidActive(entSnap.data());
  }
  if (!isDiscoverable(data, isPaid)) {
    await ref.delete().catch(() => undefined);
    return;
  }
  // Reemplazo completo: al ocultar, revocar o borrar un campo no puede quedar
  // una copia antigua en el documento publico.
  await ref.set(buildDiscoveryDoc(uid, data as DocumentData));
}

/// Trigger: cada vez que cambia users/{uid}, sincroniza su espejo publico en
/// discovery. Admin SDK => no depende de reglas ni de que el cliente escriba.
/// Cubre login (lastLoginAt), fin de onboarding y edicion de perfil.
export const onUserWrittenSyncDiscovery = onDocumentWritten(
  { document: "users/{uid}", database: DATABASE, region: REGION },
  async (event) => {
    const uid = event.params.uid;
    const after = event.data?.after?.data();
    // Borrado del user => quitar de discovery.
    if (!event.data?.after?.exists) {
      await discovery.doc(uid).delete().catch(() => undefined);
      return;
    }
    await syncOne(uid, after);
  }
);

/// Backfill puntual: recorre todos los users y publica en discovery los que
/// sean descubribles (y limpia los que no). Pensado para rellenar perfiles
/// existentes sin necesidad de que cada cuenta vuelva a iniciar sesion.
/// Idempotente: se puede ejecutar las veces que haga falta.
export const backfillDiscovery = onCall({ region: REGION }, async (request) => {
  // Cualquier sesion valida puede dispararlo; solo copia datos publicos y es
  // idempotente. (TODO: restringir a un uid admin si se quiere endurecer.)
  requireAuthUid(request.auth);

  let processed = 0;
  let published = 0;
  let removed = 0;
  let lastId: string | null = null;
  const pageSize = 300;

  // Paginacion por __name__ para no cargar toda la coleccion en memoria.
  // eslint-disable-next-line no-constant-condition
  while (true) {
    let q = col.users.orderBy("__name__").limit(pageSize);
    if (lastId) q = q.startAfter(lastId);
    const snap = await q.get();
    if (snap.empty) break;

    // Resuelve el tier solo de quienes tienen incognito activo (lote).
    const incognitoIds = snap.docs
      .filter((d) => asMap(d.data().settings)["privacy.incognito"] === true)
      .map((d) => d.id);
    const paidById = new Map<string, boolean>();
    if (incognitoIds.length > 0) {
      const entSnaps = await db.getAll(
        ...incognitoIds.map((id) => col.entitlements.doc(id))
      );
      for (const es of entSnaps) {
        paidById.set(es.id, isPaidActive(es.data()));
      }
    }

    const batch = db.batch();
    for (const doc of snap.docs) {
      processed += 1;
      lastId = doc.id;
      const data = doc.data();
      if (isDiscoverable(data, paidById.get(doc.id) ?? false)) {
        batch.set(discovery.doc(doc.id), buildDiscoveryDoc(doc.id, data));
        published += 1;
      } else {
        batch.delete(discovery.doc(doc.id));
        removed += 1;
      }
    }
    await batch.commit();
    if (snap.size < pageSize) break;
  }

  if (processed === 0) {
    throw new HttpsError("not-found", "No hay usuarios que procesar.");
  }
  return { processed, published, removed };
});
