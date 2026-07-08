import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { requireAuthUid, requireStringArg } from "./common";

/// Modo Amigos — grupos/planes sociales. Backend-autoritativo: el cliente lee
/// `friendGroups/{id}` (reglas), pero crear/unirse/responder pasa por aquí.
/// No expone ubicación exacta (solo ciudad). No rompe nada de dating.

const groups = db.collection("friendGroups");

const MAX_MEMBERS_CAP = 20;
const MIN_MEMBERS = 2;
const MAX_NAME = 80;
const MAX_DESC = 500;
const MAX_INTERESTS = 12;
const MAX_OPEN_GROUPS_PER_USER = 10; // anti-abuso

function sanitizeInterests(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return (raw as unknown[])
    .filter((x): x is string => typeof x === "string" && x.trim().length > 0)
    .slice(0, MAX_INTERESTS)
    .map((x) => x.trim().slice(0, 40));
}

function deriveStatus(memberCount: number, maxMembers: number, closed: boolean): string {
  if (closed) return "closed";
  return memberCount >= maxMembers ? "full" : "open";
}

/// createFriendGroup: crea un grupo con el usuario como creador y primer miembro.
export const createFriendGroup = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const name = requireStringArg(request.data?.name, "name").slice(0, MAX_NAME);
  const description =
    typeof request.data?.description === "string"
      ? request.data.description.trim().slice(0, MAX_DESC)
      : "";
  const city =
    typeof request.data?.city === "string"
      ? request.data.city.trim().slice(0, 80)
      : "";
  const interests = sanitizeInterests(request.data?.interests);
  const maxMembersRaw = Number(request.data?.maxMembers);
  const maxMembers = Number.isFinite(maxMembersRaw)
    ? Math.min(MAX_MEMBERS_CAP, Math.max(MIN_MEMBERS, Math.round(maxMembersRaw)))
    : 8;

  // Anti-abuso: nº de grupos abiertos que ya creó este usuario.
  const openByUser = await groups
    .where("createdBy", "==", uid)
    .where("status", "in", ["open", "full"])
    .limit(MAX_OPEN_GROUPS_PER_USER + 1)
    .get();
  if (openByUser.size >= MAX_OPEN_GROUPS_PER_USER) {
    throw new HttpsError(
      "resource-exhausted",
      "Tienes demasiados grupos abiertos. Cierra alguno antes de crear otro."
    );
  }

  const ref = groups.doc();
  const now = FieldValue.serverTimestamp();
  await ref.set({
    name,
    description,
    city,
    interests,
    memberIds: [uid],
    pendingIds: [],
    maxMembers,
    createdBy: uid,
    status: "open",
    createdAt: now,
    updatedAt: now,
  });
  return { groupId: ref.id };
});

/// requestJoinGroup: solicita unirse (queda en pendingIds hasta que el admin
/// acepte). No permite si ya eres miembro/pendiente, o si está lleno/cerrado.
export const requestJoinGroup = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const groupId = requireStringArg(request.data?.groupId, "groupId");
  const ref = groups.doc(groupId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "El grupo no existe.");
    const g = snap.data() ?? {};
    const members: string[] = Array.isArray(g.memberIds) ? g.memberIds : [];
    const pending: string[] = Array.isArray(g.pendingIds) ? g.pendingIds : [];
    if ((g.status ?? "open") !== "open") {
      throw new HttpsError("failed-precondition", "Este grupo no admite solicitudes.");
    }
    if (members.includes(uid)) {
      throw new HttpsError("failed-precondition", "Ya eres miembro de este grupo.");
    }
    if (members.length >= (g.maxMembers ?? 8)) {
      throw new HttpsError("failed-precondition", "El grupo está lleno.");
    }
    if (pending.includes(uid)) return; // idempotente
    tx.update(ref, {
      pendingIds: FieldValue.arrayUnion(uid),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { ok: true };
});

/// respondJoinRequest: SOLO el creador acepta/rechaza a un solicitante.
export const respondJoinRequest = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const groupId = requireStringArg(request.data?.groupId, "groupId");
  const targetUid = requireStringArg(request.data?.targetUid, "targetUid");
  const accept = request.data?.accept === true;
  const ref = groups.doc(groupId);

  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "El grupo no existe.");
    const g = snap.data() ?? {};
    if (g.createdBy !== uid) {
      throw new HttpsError("permission-denied", "Solo el creador puede gestionar solicitudes.");
    }
    const members: string[] = Array.isArray(g.memberIds) ? g.memberIds : [];
    const pending: string[] = Array.isArray(g.pendingIds) ? g.pendingIds : [];
    if (!pending.includes(targetUid)) {
      throw new HttpsError("failed-precondition", "Esa solicitud ya no existe.");
    }
    const now = FieldValue.serverTimestamp();
    const maxMembers = (g.maxMembers ?? 8) as number;
    if (!accept) {
      tx.update(ref, {
        pendingIds: FieldValue.arrayRemove(targetUid),
        updatedAt: now,
      });
      return { status: g.status ?? "open" };
    }
    if (members.length >= maxMembers) {
      throw new HttpsError("failed-precondition", "El grupo está lleno.");
    }
    const nextCount = members.length + 1;
    const status = deriveStatus(nextCount, maxMembers, false);
    tx.update(ref, {
      memberIds: FieldValue.arrayUnion(targetUid),
      pendingIds: FieldValue.arrayRemove(targetUid),
      status,
      updatedAt: now,
    });
    return { status };
  });
  return { ok: true, ...result };
});

/// leaveFriendGroup: un miembro (no creador) abandona el grupo.
export const leaveFriendGroup = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const groupId = requireStringArg(request.data?.groupId, "groupId");
  const ref = groups.doc(groupId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "El grupo no existe.");
    const g = snap.data() ?? {};
    if (g.createdBy === uid) {
      throw new HttpsError(
        "failed-precondition",
        "El creador no puede abandonar; cierra el grupo en su lugar."
      );
    }
    const members: string[] = Array.isArray(g.memberIds) ? g.memberIds : [];
    if (!members.includes(uid)) return;
    const nextCount = Math.max(0, members.length - 1);
    tx.update(ref, {
      memberIds: FieldValue.arrayRemove(uid),
      status: deriveStatus(nextCount, (g.maxMembers ?? 8) as number, false),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { ok: true };
});

/// closeFriendGroup: SOLO el creador cierra el grupo (deja de admitir gente).
export const closeFriendGroup = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const groupId = requireStringArg(request.data?.groupId, "groupId");
  const ref = groups.doc(groupId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "El grupo no existe.");
  if (snap.data()?.createdBy !== uid) {
    throw new HttpsError("permission-denied", "Solo el creador puede cerrar el grupo.");
  }
  await ref.update({ status: "closed", updatedAt: FieldValue.serverTimestamp() });
  return { ok: true };
});
