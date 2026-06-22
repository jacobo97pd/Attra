import { HttpsError } from "firebase-functions/v2/https";
import { DocumentData, DocumentSnapshot } from "firebase-admin/firestore";
import { db } from "./firebase";
import { directedId } from "./ids";

export const MAX_MESSAGE_LENGTH = 2000;

/// Limite diario de likes para usuarios Free. TODO(Fase 9): mover a
/// config/featureFlags (`freeDailyLikes`) para control remoto.
export const FREE_DAILY_LIKES = 25;

export type JourneyStatus =
  | "new_match"
  | "icebreaker_suggested"
  | "icebreaker_started"
  | "game_started"
  | "game_completed"
  | "conversation_active"
  | "date_proposed"
  | "date_accepted"
  | "date_completed"
  | "archived";

const JOURNEY_RANK: Record<JourneyStatus, number> = {
  new_match: 0,
  icebreaker_suggested: 1,
  icebreaker_started: 2,
  game_started: 3,
  game_completed: 4,
  conversation_active: 5,
  date_proposed: 6,
  date_accepted: 7,
  date_completed: 8,
  archived: 9,
};

export function normalizeJourneyStatus(value: unknown): JourneyStatus | null {
  const raw = (value ?? "").toString().trim().toLowerCase();
  const statuses = Object.keys(JOURNEY_RANK) as JourneyStatus[];
  for (const status of statuses) {
    if (status === raw) return status;
  }
  return null;
}

export function nextJourneyStatus(
  current: unknown,
  candidate: JourneyStatus
): JourneyStatus {
  const normalized = normalizeJourneyStatus(current);
  if (!normalized) return candidate;
  return JOURNEY_RANK[candidate] >= JOURNEY_RANK[normalized]
    ? candidate
    : normalized;
}

/// Colecciones (centralizadas para no escribir strings sueltos).
export const col = {
  users: db.collection("users"),
  entitlements: db.collection("userEntitlements"),
  wallets: db.collection("attraWallets"),
  ledger: db.collection("attraLedger"),
  attraSends: db.collection("attraSends"),
  boostSessions: db.collection("boostSessions"),
  activeBoosts: db.collection("activeBoosts"),
  boostImpressions: db.collection("boostImpressions"),
  feedEvents: db.collection("feedEvents"),
  likes: db.collection("likes"),
  dislikes: db.collection("dislikes"),
  matches: db.collection("matches"),
  chats: db.collection("chats"),
  blocks: db.collection("blocks"),
  reports: db.collection("reports"),
  stories: db.collection("stories"),
};

/// Nombre publico elegido por el usuario (nunca el legal/Auth). Prioridad:
/// profile.displayName > profile.visibleName > firstName+lastName > displayName.
export function resolvePublicDisplayName(data: DocumentData | undefined): string {
  const d = data ?? {};
  const profile =
    d.profile && typeof d.profile === "object" ? (d.profile as DocumentData) : {};
  const s = (v: unknown): string => (typeof v === "string" ? v.trim() : "");
  const full = [s(profile.firstName), s(profile.lastName)]
    .filter((x) => x.length > 0)
    .join(" ")
    .trim();
  return (
    s(profile.displayName) || s(profile.visibleName) || full || s(d.displayName)
  );
}

export function requireAuthUid(auth: { uid: string } | undefined): string {
  if (!auth || !auth.uid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesion.");
  }
  return auth.uid;
}

export function requireStringArg(value: unknown, name: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `Falta el parametro '${name}'.`);
  }
  return value.trim();
}

/// Un usuario es contactable si existe y no esta baneado ni borrado.
export function isUserContactable(snap: DocumentSnapshot<DocumentData>): boolean {
  if (!snap.exists) return false;
  const data = snap.data() ?? {};
  if (data.isBanned === true) return false;
  if (data.isDeleted === true) return false;
  return true;
}

/// True si existe bloqueo en cualquier direccion entre a y b.
export async function existsBlockBetween(a: string, b: string): Promise<boolean> {
  const [ab, ba] = await Promise.all([
    col.blocks.doc(directedId(a, b)).get(),
    col.blocks.doc(directedId(b, a)).get(),
  ]);
  return ab.exists || ba.exists;
}

/// Clave de uso diario (UTC) para el contador de likes.
export function dailyUsageKey(date = new Date()): string {
  return date.toISOString().slice(0, 10).replace(/-/g, "");
}

export interface ResolvedPhoto {
  found: boolean;
  url: string | null;
  blurHash: string | null;
}

export interface SenderPrioritySnapshot {
  senderTier: string;
  senderIsPlus: boolean;
  senderIsPro: boolean;
  priorityReason: "attra" | "pro" | "plus" | "normal";
}

function millisFromDateLike(value: unknown): number | null {
  if (!value) return null;
  if (value instanceof Date) return value.getTime();
  if (typeof value === "string") {
    const ms = Date.parse(value);
    return Number.isNaN(ms) ? null : ms;
  }
  if (typeof value === "object" && "toMillis" in value) {
    const maybeTimestamp = value as { toMillis?: unknown };
    if (typeof maybeTimestamp.toMillis === "function") {
      const ms = maybeTimestamp.toMillis();
      return typeof ms === "number" ? ms : null;
    }
  }
  return null;
}

export function activeEntitlementTier(
  entData: DocumentData | undefined
): string {
  const tier = (entData?.tier ?? "free").toString();
  if (tier !== "plus" && tier !== "premium" && tier !== "pro") {
    return "free";
  }
  if (entData?.isLifetime === true) return tier;
  const expiresAtMs = millisFromDateLike(entData?.expiresAt);
  if (expiresAtMs !== null && expiresAtMs < Date.now()) return "free";
  return tier;
}

export function senderPrioritySnapshot(
  entData: DocumentData | undefined,
  likeType: "like" | "attra"
): SenderPrioritySnapshot {
  const senderTier = activeEntitlementTier(entData);
  const senderIsPro = senderTier === "pro";
  const senderIsPlus = senderTier === "plus" || senderTier === "premium";
  return {
    senderTier,
    senderIsPlus,
    senderIsPro,
    priorityReason:
      likeType === "attra"
        ? "attra"
        : senderIsPro
          ? "pro"
          : senderIsPlus
            ? "plus"
            : "normal",
  };
}

/// Verifica que `photoId` (storagePath o url) pertenece de verdad al receptor y
/// devuelve un snapshot minimo (url/blurHash). Busca primero en users/{toUid}
/// y, si no existe, en seed_profiles/{toUid} (perfiles mock del feed).
export async function resolveReceiverPhoto(
  toUid: string,
  photoId: string
): Promise<ResolvedPhoto> {
  let snap = await col.users.doc(toUid).get();
  let data = snap.exists ? snap.data() : undefined;
  if (!data) {
    snap = await db.collection("seed_profiles").doc(toUid).get();
    data = snap.exists ? snap.data() : undefined;
  }
  if (!data) return { found: false, url: null, blurHash: null };

  const photos: DocumentData[] = Array.isArray(data.photos) ? data.photos : [];
  for (const p of photos) {
    if (p && (p.storagePath === photoId || p.url === photoId)) {
      return { found: true, url: p.url ?? null, blurHash: p.blurHash ?? null };
    }
  }
  if (data.photoUrl && data.photoUrl === photoId) {
    return { found: true, url: data.photoUrl, blurHash: null };
  }
  return { found: false, url: null, blurHash: null };
}
