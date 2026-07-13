import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { col, requireAuthUid, requireStringArg } from "./common";

/// Attra SafeDate — funciones server-side. Backend-autoritativo: el cliente lee
/// sus propios datos (reglas), pero contactos/planes/alertas se escriben aquí.
/// Todo gated por `feature_safedate_enabled` (defensa en profundidad). Nunca
/// expone datos privados del match ni informa al match de nada.

const MAX_CONTACTS = 10;
const MAX_NAME = 80;

/// Lee la config de flags y exige SafeDate activo (master switch). Defensa en
/// profundidad: aunque el cliente lo salte, el backend rechaza si está OFF.
async function requireSafeDateEnabled(): Promise<void> {
  const snap = await db.collection("config").doc("featureFlags").get();
  const cfg = snap.data() ?? {};
  if (cfg.feature_safedate_enabled !== true) {
    throw new HttpsError(
      "failed-precondition",
      "SafeDate no está disponible ahora mismo."
    );
  }
}

function normalizePhone(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const plus = raw.trim().startsWith("+");
  const digits = raw.replace(/[^0-9]/g, "");
  if (digits.length < 6 || digits.length > 15) return null;
  return plus ? `+${digits}` : digits;
}

function normalizeEmail(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const e = raw.trim().toLowerCase();
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e) ? e : null;
}

/// saveTrustedContact: crea o actualiza un contacto de confianza del usuario.
/// PRIVADO: vive en users/{uid}/trustedContacts. Nunca visible para otros.
export const saveTrustedContact = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  await requireSafeDateEnabled();

  const displayName = requireStringArg(request.data?.displayName, "displayName")
    .slice(0, MAX_NAME);
  const phone = normalizePhone(request.data?.phone);
  const email = normalizeEmail(request.data?.email);
  if (!phone && !email) {
    throw new HttpsError("invalid-argument", "Añade un teléfono o email válido.");
  }
  const isPrimary = request.data?.isPrimary === true;
  const contactId =
    typeof request.data?.contactId === "string" && request.data.contactId.trim()
      ? request.data.contactId.trim().slice(0, 80)
      : null;

  const contactsCol = col.users.doc(uid).collection("trustedContacts");

  // Límite anti-abuso.
  if (!contactId) {
    const count = await contactsCol.count().get();
    if (count.data().count >= MAX_CONTACTS) {
      throw new HttpsError(
        "resource-exhausted",
        `Máximo ${MAX_CONTACTS} contactos de confianza.`
      );
    }
  }

  const ref = contactId ? contactsCol.doc(contactId) : contactsCol.doc();
  const now = FieldValue.serverTimestamp();

  await db.runTransaction(async (tx) => {
    // Si se marca primario, quita el flag de los demás (un solo primario).
    if (isPrimary) {
      const others = await tx.get(
        contactsCol.where("isPrimary", "==", true)
      );
      for (const doc of others.docs) {
        if (doc.id !== ref.id) tx.update(doc.ref, { isPrimary: false });
      }
    }
    tx.set(
      ref,
      {
        userId: uid,
        displayName,
        phone: phone ?? null,
        email: email ?? null,
        isPrimary,
        updatedAt: now,
        ...(contactId ? {} : { createdAt: now }),
      },
      { merge: true }
    );
  });

  return { contactId: ref.id };
});

/// deleteTrustedContact: elimina un contacto de confianza del usuario.
export const deleteTrustedContact = onCall(
  { region: REGION },
  async (request) => {
    const uid = requireAuthUid(request.auth);
    const contactId = requireStringArg(request.data?.contactId, "contactId");
    await col.users
      .doc(uid)
      .collection("trustedContacts")
      .doc(contactId)
      .delete();
    return { ok: true };
  }
);

/// createSafeDatePlan: crea un plan de cita segura para un match del usuario.
/// Valida pertenencia al match. El plan es del OWNER (no compartido con el match
/// dentro de la app). Guarda solo datos autorizados.
export const createSafeDatePlan = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  await requireSafeDateEnabled();

  const chatId = requireStringArg(request.data?.chatId, "chatId");
  const placeName = requireStringArg(request.data?.placeName, "placeName")
    .slice(0, 120);
  const scheduledAtRaw = request.data?.scheduledAt;
  const scheduledAt =
    typeof scheduledAtRaw === "string" ? new Date(scheduledAtRaw) : null;
  if (!scheduledAt || Number.isNaN(scheduledAt.getTime())) {
    throw new HttpsError("invalid-argument", "Fecha/hora de la cita no válida.");
  }

  // Valida pertenencia al match (vía chat, patrón del resto de la app).
  const chatSnap = await col.chats.doc(chatId).get();
  if (!chatSnap.exists) throw new HttpsError("not-found", "El chat no existe.");
  const users: string[] = (chatSnap.data()?.users ?? []) as string[];
  if (!users.includes(uid)) {
    throw new HttpsError("permission-denied", "No participas en este chat.");
  }
  const otherUserId = users.find((u) => u !== uid) ?? "";
  const matchId = (chatSnap.data()?.matchId ?? chatId).toString();

  const durationRaw = Number(request.data?.expectedDurationMinutes);
  const expectedDurationMinutes = Number.isFinite(durationRaw)
    ? Math.min(720, Math.max(15, Math.round(durationRaw)))
    : 90;
  const trustedContactIds: string[] = Array.isArray(request.data?.trustedContactIds)
    ? (request.data.trustedContactIds as unknown[])
        .filter((x): x is string => typeof x === "string")
        .slice(0, MAX_CONTACTS)
    : [];
  const placeAddress =
    typeof request.data?.placeAddress === "string"
      ? request.data.placeAddress.slice(0, 200)
      : null;

  const now = FieldValue.serverTimestamp();
  const ref = db.collection("safeDatePlans").doc();
  await ref.set({
    ownerUserId: uid,
    matchId,
    otherUserId,
    chatId,
    placeName,
    placeAddress,
    scheduledAt,
    expectedDurationMinutes,
    expectedReturnAt: new Date(
      scheduledAt.getTime() + expectedDurationMinutes * 60000
    ),
    status: "scheduled",
    trustedContactIds,
    shareProfileSnapshot: request.data?.shareProfileSnapshot === true,
    liveLocationEnabled: false,
    createdAt: now,
    updatedAt: now,
  });
  return { planId: ref.id };
});

/// cancelSafeDatePlan / completeSafeDatePlan: transición de estado por el owner.
export const setSafeDatePlanStatus = onCall(
  { region: REGION },
  async (request) => {
    const uid = requireAuthUid(request.auth);
    const planId = requireStringArg(request.data?.planId, "planId");
    const status = requireStringArg(request.data?.status, "status");
    if (!["cancelled", "completed", "active"].includes(status)) {
      throw new HttpsError("invalid-argument", "Estado no permitido.");
    }
    const ref = db.collection("safeDatePlans").doc(planId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "El plan no existe.");
    if (snap.data()?.ownerUserId !== uid) {
      throw new HttpsError("permission-denied", "No es tu plan.");
    }
    await ref.update({ status, updatedAt: FieldValue.serverTimestamp() });
    // Al cerrar la cita, elimina cualquier ubicación temporal (sin historial).
    if (status === "cancelled" || status === "completed") {
      await db
        .collection("safeDateLiveLocations")
        .doc(planId)
        .delete()
        .catch(() => undefined);
    }
    return { ok: true };
  }
);
