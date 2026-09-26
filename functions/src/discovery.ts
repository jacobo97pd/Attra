import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { FieldValue, DocumentData, Timestamp } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { col, requireAuthUid } from "./common";
import { iso2ForCountryName, normalizeIso2 } from "./travel";

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
  // El color de pelo se recoge en el onboarding (`appearance.hairColor`) pero
  // NO se publicaba aqui, asi que `traitValue(data, "hairColor")` era undefined
  // para el 100% de los usuarios reales y la senal de pelo del buscador por
  // prompt ("chica rubia", "morena") no podia casar con nadie: solo funcionaba
  // contra los bots de seed_profiles, que si traen el campo anidado.
  { key: "hair", group: "appearance", field: "hairColor" },
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
export function isPaidActive(
  entData: DocumentData | undefined,
  nowMs: number = Date.now()
): boolean {
  if (!entData) return false;
  const tier = (entData.tier ?? "free").toString();
  if (tier === "free") return false;
  if (entData.isLifetime === true) return true;
  const expiresAt = entData.expiresAt;
  if (expiresAt?.toMillis) return expiresAt.toMillis() >= nowMs;
  return true; // sin caducidad declarada => activo
}

/// Un usuario es descubrible (aparece en el feed de otros) si completo el
/// onboarding y el perfil, NO es un bot, no esta expulsado y no se ha ocultado:
///   - `isBanned`/`isDeleted`: la moderacion lo saca del feed. Antes el trigger
///     lo volvia a publicar con la misma escritura que lo expulsaba y seguia
///     saliendo en todos los feeds con una ficha a la que nadie podia dar like.
///   - `privacy.hideProfile` (gratis): se sale del feed siempre.
///   - `privacy.showInRecommendations=false`: no aparece recomendado.
///   - `privacy.incognito` (Plus): solo surte efecto con plan de pago activo;
///     asi el modo incognito es una ventaja real de Attra Plus/Pro.
export function isDiscoverable(
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
  if (data.isBanned === true || data.isDeleted === true) return false;
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

/// Fin del viaje: `untilAt` (Timestamp, el nuevo) o el `until` ISO que siguen
/// escribiendo las versiones anteriores de la app. null = sin fecha.
export function travelUntilMs(travel: DocumentData): number | null {
  for (const value of [travel.untilAt, travel.until]) {
    if (!value) continue;
    if (typeof value?.toMillis === "function") return value.toMillis();
    const parsed = Date.parse(String(value));
    if (Number.isFinite(parsed)) return parsed;
  }
  return null;
}

/// El viaje caduca (ver [travelUntilMs]). Sin fecha se considera vigente, para
/// no romper los viajes creados antes de que existiera la caducidad.
export function travelExpired(
  travel: DocumentData,
  nowMs: number = Date.now()
): boolean {
  const until = travelUntilMs(travel);
  return until !== null && until < nowMs;
}

/// `settings.travel` (o el `travel` de primer nivel de docs antiguos).
function travelOf(data: DocumentData | undefined): DocumentData {
  const nested = asMap(asMap(data?.settings).travel);
  return Object.keys(nested).length > 0 ? nested : asMap(data?.travel);
}

/// Centro del destino del viaje, si es creible. Lo escribe el cliente en
/// `settings`, que las reglas no validan: fuera de rango = sin centro.
export function travelCenter(
  travel: DocumentData
): { lat: number; lng: number } | null {
  const lat = asDouble(travel.lat);
  const lng = asDouble(travel.lng);
  if (lat === null || lng === null) return null;
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  return { lat, lng };
}

/// ¿Esta viajando A EFECTOS PUBLICOS? Modo viaje es funcion de PAGO y con
/// caducidad: sin plan activo o pasada la fecha, el viaje se ignora y la ficha
/// vuelve a la ubicacion real (igual que incognito, que ya exigia plan).
export function isTravelingPublic(
  travel: DocumentData,
  isPaid: boolean,
  nowMs: number = Date.now()
): boolean {
  return (
    travel.active === true &&
    asString(travel.country).length > 0 &&
    isPaid &&
    !travelExpired(travel, nowMs)
  );
}

/// ISO2 COMPARABLE del pais publicado: el de destino viajando; si no, el del
/// geocodificador (`currentCountryIso2`), el del onboarding
/// (`currentCountryCode`) o, como ultimo recurso, el deducido del nombre. Es lo
/// que compara el feed: el nombre llega en el idioma de cada telefono
/// ('Espanya', 'Spanien') y comparando nombres un catalan desaparecia del feed
/// de su propia ciudad.
export function resolveCountryIso2(
  profile: DocumentData,
  travel: DocumentData,
  traveling: boolean
): string {
  if (traveling) {
    return (
      normalizeIso2(travel.iso2) || iso2ForCountryName(asString(travel.country))
    );
  }
  return (
    normalizeIso2(profile.currentCountryIso2) ||
    normalizeIso2(profile.currentCountryCode) ||
    iso2ForCountryName(asString(profile.currentCountryName))
  );
}

export function buildDiscoveryDoc(
  uid: string,
  data: DocumentData,
  isPaid: boolean,
  nowMs: number = Date.now()
): DocumentData {
  const profile = asMap(data.profile);
  const prefs = asMap(data.preferences);
  const settings = asMap(data.settings);
  const age =
    asInt(profile.age) ??
    asInt(data.age) ??
    ageFromBirthDate(profile.birthDate ?? data.birthDate);

  const travel = travelOf(data);
  // Modo viaje: el cliente solo pide el cambio; aqui se decide (plan +
  // caducidad). Antes bastaba con escribir settings.travel.active=true.
  const traveling = isTravelingPublic(travel, isPaid, nowMs);
  const realCity = asString(profile.currentCity ?? profile.city);
  const realCountry = asString(profile.currentCountryName);
  const publicCity = traveling ? asString(travel.city) : realCity;
  const showCity = settings["location.showOnProfile"] !== false;
  const countryIso2 = resolveCountryIso2(profile, travel, traveling);

  const out: DocumentData = {
    uid,
    isBot: false,
    displayName: resolvePublicDisplayName(data),
    // Tipos forzados: `users/{uid}` no valida tipos en las reglas y un
    // `bio: 123` copiado tal cual rompia el parser de TODOS los clientes.
    photoUrl: asString(data.photoUrl) || asString(data.profilePhotoUrl),
    photos: Array.isArray(data.photos)
      ? data.photos.filter(
          (p: unknown) => p !== null && typeof p === "object" && !Array.isArray(p)
        )
      : [],
    gender: asString(profile.gender),
    interestedIn: Array.isArray(prefs.interestedIn)
      ? prefs.interestedIn.filter((g: unknown) => typeof g === "string")
      : [],
    age,
    bio: typeof profile.bio === "string" ? profile.bio : "",
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
  if (countryIso2) out.countryIso2 = countryIso2;
  // Rango de edad que busca (onboarding / filtro "Edad" del feed). Sin el, el
  // feed no podia ser reciproco: quien busca 22-30 le salia a quien tiene 58.
  // Mismo recorte que `loadCriteria` del directo: nunca por debajo de 18 ni
  // por encima de 80, y min <= max. Sin dato no se publica (el feed es
  // permisivo cuando falta).
  const ageMinRaw = asInt(prefs.preferredAgeMin);
  const ageMaxRaw = asInt(prefs.preferredAgeMax);
  if (ageMinRaw !== null || ageMaxRaw !== null) {
    const ageMin = Math.max(18, Math.min(ageMinRaw ?? 18, 80));
    out.preferredAgeMin = ageMin;
    out.preferredAgeMax = Math.max(ageMin, Math.min(ageMaxRaw ?? 80, 80));
  }
  // Viajando se publica el FIN del viaje: el feed de los demas deja de
  // ensenarlo "de viaje" en cuanto pasa, sin esperar al barrido horario.
  const untilMs = traveling ? travelUntilMs(travel) : null;
  if (untilMs !== null) out.travelUntil = Timestamp.fromMillis(untilMs);

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
  //
  // MODO VIAJE: las coordenadas REALES nunca se publican viajando (junto al
  // pais de destino dejaban al viajero invisible en todos los feeds). Se
  // publica el CENTRO de la ciudad de destino, redondeado igual: asi el
  // viajero sale alrededor del destino (Cadiz, Jerez, El Puerto) y no en toda
  // Espana, su propia ciudad incluida, como pasaba sin `geo`. Sin centro
  // (viaje a un pais entero, o guardado por una version antigua) no hay `geo`:
  // los clientes nuevos solo ensenan esa ficha a quien esta en la ciudad de
  // destino (FeedFilter, `travelersNeedGeo`); los antiguos, a todo el pais.
  const location = asMap(data.location);
  const center = traveling ? travelCenter(travel) : null;
  const latitude = traveling
    ? center?.lat ?? null
    : asDouble(location.latitude);
  const longitude = traveling
    ? center?.lng ?? null
    : asDouble(location.longitude);
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

/// Hace falta consultar el tier cuando el usuario usa alguna funcion de PAGO
/// que afecta a su ficha publica: modo incognito o modo viaje.
export function needsTier(data: DocumentData | undefined): boolean {
  const settings = asMap(data?.settings);
  if (settings["privacy.incognito"] === true) return true;
  return travelOf(data).active === true;
}

/// Espeja un user en discovery (o lo borra si no es descubrible). Idempotente.
/// Lee el tier (userEntitlements) para resolver las funciones de pago que
/// afectan a la ficha publica: modo incognito y modo viaje.
async function syncOne(uid: string, data: DocumentData | undefined): Promise<void> {
  const ref = discovery.doc(uid);
  let isPaid = false;
  if (needsTier(data)) {
    const entSnap = await col.entitlements.doc(uid).get();
    isPaid = isPaidActive(entSnap.data());
  }
  if (!isDiscoverable(data, isPaid)) {
    await ref.delete().catch(() => undefined);
    return;
  }
  // Reemplazo completo: al ocultar, revocar o borrar un campo no puede quedar
  // una copia antigua en el documento publico.
  await ref.set(buildDiscoveryDoc(uid, data as DocumentData, isPaid));
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

export type TravelSweepAction = "deactivate" | "resync" | "none";

/// Que hacer con un viaje ACTIVO en el barrido (puro, testeable):
///   - "deactivate": paso su fecha. Se apaga en users/{uid} y el trigger lo
///     republica en casa. Antes nada lo apagaba y, si el usuario no volvia a
///     abrir la app, la ficha seguia "de viaje en Cadiz" para siempre.
///   - "resync": la ficha publicada no coincide con el plan (caduco, o volvio
///     a pagar). Una caducidad de plan no escribe nada en ningun documento, asi
///     que ningun trigger se enteraba.
///   - "none": todo en su sitio.
/// [publishedTraveling] = `traveling` de la ficha publicada (undefined = no
/// hay ficha).
export function decideTravelSweep(
  travel: DocumentData,
  isPaid: boolean,
  publishedTraveling: boolean | undefined,
  nowMs: number = Date.now()
): TravelSweepAction {
  if (travel.active !== true) return "none";
  if (travelExpired(travel, nowMs)) return "deactivate";
  const shouldTravel = isTravelingPublic(travel, isPaid, nowMs);
  if (publishedTraveling === undefined) return shouldTravel ? "resync" : "none";
  return publishedTraveling === shouldTravel ? "none" : "resync";
}

/// Lo que escribe el barrido al apagar un viaje caducado. Mismo contrato que
/// al apagarlo desde la app (`UserRepository.buildTravelPatch`): pais, ciudad
/// e ISO2 se CONSERVAN para poder reactivarlo de un toque; el centro y la fecha
/// se borran (se vuelven a calcular al reactivar).
export function travelDeactivationPatch(): DocumentData {
  return {
    "settings.travel.active": false,
    "settings.travel.untilAt": null,
    "settings.travel.lat": null,
    "settings.travel.lng": null,
    "settings.travel.geoSource": "none",
    "settings.travel.updatedAt": FieldValue.serverTimestamp(),
  };
}

/// Ventana hacia atras de caducidades de plan que se revisan en cada pasada.
/// Mas ancha que el intervalo (1 h) para no perder ninguna si una pasada
/// falla o llega tarde.
const PLAN_LAPSE_WINDOW_MS = 3 * 60 * 60 * 1000;
const SWEEP_PAGE = 300;

/// Barrido HORARIO de viajes y planes. Cubre lo que ningun trigger ve porque
/// no hay escritura que lo dispare:
///  1. Viajes caducados -> se apagan (`active=false`, `untilAt=null`).
///  2. Viajes con la ficha desalineada respecto al plan -> se republican.
///  3. Planes que acaban de caducar -> se republica al usuario (incognito
///     deja de valer y el viaje vuelve a casa; su ficha de discovery puede no
///     existir, por eso no basta con recorrer discovery).
export const sweepTravelModes = onSchedule(
  { schedule: "every 60 minutes", region: REGION },
  async () => {
    const nowMs = Date.now();
    let deactivated = 0;
    let resynced = 0;
    let lastId: string | null = null;

    // eslint-disable-next-line no-constant-condition
    while (true) {
      let q = col.users
        .where("settings.travel.active", "==", true)
        .orderBy("__name__")
        .limit(SWEEP_PAGE);
      if (lastId) q = q.startAfter(lastId);
      const snap = await q.get();
      if (snap.empty) break;
      lastId = snap.docs[snap.docs.length - 1].id;

      const ids = snap.docs.map((d) => d.id);
      const [entSnaps, discSnaps] = await Promise.all([
        db.getAll(...ids.map((id) => col.entitlements.doc(id))),
        db.getAll(...ids.map((id) => discovery.doc(id))),
      ]);
      const paidById = new Map<string, boolean>();
      for (const es of entSnaps) paidById.set(es.id, isPaidActive(es.data(), nowMs));
      const publishedById = new Map<string, boolean | undefined>();
      for (const ds of discSnaps) {
        publishedById.set(ds.id, ds.exists ? ds.data()?.traveling === true : undefined);
      }

      const batch = db.batch();
      let writes = 0;
      for (const doc of snap.docs) {
        const data = doc.data();
        const action = decideTravelSweep(
          travelOf(data),
          paidById.get(doc.id) ?? false,
          publishedById.get(doc.id),
          nowMs
        );
        if (action === "deactivate") {
          // La escritura dispara onUserWrittenSyncDiscovery, que lo republica
          // en casa.
          batch.update(doc.ref, travelDeactivationPatch());
          writes++;
          deactivated++;
        } else if (action === "resync") {
          await syncOne(doc.id, data);
          resynced++;
        }
      }
      if (writes > 0) await batch.commit();
      if (snap.size < SWEEP_PAGE) break;
    }

    // Planes que acaban de caducar: su caducidad no escribe nada, asi que ni
    // el trigger de users ni el de entitlements se entera.
    const lapsed = await col.entitlements
      .where("expiresAt", ">=", Timestamp.fromMillis(nowMs - PLAN_LAPSE_WINDOW_MS))
      .where("expiresAt", "<", Timestamp.fromMillis(nowMs))
      .limit(500)
      .get();
    for (const ent of lapsed.docs) {
      const userSnap = await col.users.doc(ent.id).get();
      if (!userSnap.exists || !needsTier(userSnap.data())) continue;
      await syncOne(ent.id, userSnap.data());
      resynced++;
    }

    console.log(
      `[sweepTravelModes] deactivated=${deactivated} resynced=${resynced}`
    );
  }
);

/// Campos del plan que cambian lo que se publica (incognito / modo viaje).
export function entitlementChanged(
  before: DocumentData | undefined,
  after: DocumentData | undefined,
  nowMs: number = Date.now()
): boolean {
  return isPaidActive(before, nowMs) !== isPaidActive(after, nowMs);
}

/// Trigger: al cambiar el plan (compra, renovacion, restauracion, concesion
/// manual) se republica la ficha de quien usa funciones de pago. Antes, quien
/// volvia a pagar con un viaje o incognito puesto no lo veia aplicado hasta su
/// siguiente escritura en users/{uid}.
export const onEntitlementsWrittenSyncDiscovery = onDocumentWritten(
  {
    document: "userEntitlements/{uid}",
    database: DATABASE,
    region: REGION,
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!entitlementChanged(before, after)) return;
    const uid = event.params.uid;
    const userSnap = await col.users.doc(uid).get();
    if (!userSnap.exists) return;
    const data = userSnap.data();
    if (!needsTier(data)) return;
    await syncOne(uid, data);
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

    // Resuelve el tier solo de quienes usan funciones de pago (lote).
    const paidFeatureIds = snap.docs
      .filter((d) => needsTier(d.data()))
      .map((d) => d.id);
    const paidById = new Map<string, boolean>();
    if (paidFeatureIds.length > 0) {
      const entSnaps = await db.getAll(
        ...paidFeatureIds.map((id) => col.entitlements.doc(id))
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
        batch.set(
          discovery.doc(doc.id),
          buildDiscoveryDoc(doc.id, data, paidById.get(doc.id) ?? false)
        );
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
