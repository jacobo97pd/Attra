import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { FieldValue, DocumentData, Timestamp } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { col, requireAuthUid } from "./common";

/// Base con NOMBRE (los triggers v2 apuntan a la default si no se indica).
const DATABASE = "attra-database";

const discovery = db.collection("discovery");

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
  const age =
    asInt(profile.age) ??
    asInt(data.age) ??
    ageFromBirthDate(profile.birthDate ?? data.birthDate);
  return {
    uid,
    isBot: false,
    displayName: resolvePublicDisplayName(data),
    photoUrl: data.photoUrl ?? data.profilePhotoUrl ?? "",
    photos: Array.isArray(data.photos) ? data.photos : [],
    gender: profile.gender ?? "",
    interestedIn: Array.isArray(prefs.interestedIn) ? prefs.interestedIn : [],
    age,
    bio: profile.bio ?? "",
    currentCity: profile.currentCity ?? profile.city ?? "",
    currentCountryName: profile.currentCountryName ?? "",
    jobTitle: profile.jobTitle ?? "",
    company: profile.company ?? "",
    interests: Array.isArray(profile.interests) ? profile.interests : [],
    orientation: Array.isArray(profile.orientation) ? profile.orientation : [],
    profilePrompts: publicProfilePrompts(data),
    introAudio: publicIntroMedia(profile.introAudio),
    introVideo: publicIntroMedia(profile.introVideo),
    updatedAt: FieldValue.serverTimestamp(),
  };
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
  await ref.set(buildDiscoveryDoc(uid, data as DocumentData), { merge: true });
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
        batch.set(discovery.doc(doc.id), buildDiscoveryDoc(doc.id, data), {
          merge: true,
        });
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
