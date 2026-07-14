import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { FieldValue, DocumentData } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { col, requireAuthUid, requireStringArg } from "./common";
import { createNotification } from "./notifications";

/// Attra SafeDate — funciones server-side. Backend-autoritativo: el cliente lee
/// sus propios datos (reglas), pero contactos/planes/alertas se escriben aquí.
/// Todo gated por `feature_safedate_enabled` (defensa en profundidad). Nunca
/// expone datos privados del match ni informa al match de nada.

const MAX_CONTACTS = 10;
const MAX_NAME = 80;

/// Lee la config de flags y exige SafeDate activo (master switch). Defensa en
/// profundidad: aunque el cliente lo salte, el backend rechaza si está OFF.
/// Devuelve el doc de config para reutilizar (tiempos de check-in, etc.).
async function requireSafeDateEnabled(): Promise<DocumentData> {
  const snap = await db.collection("config").doc("featureFlags").get();
  const cfg = snap.data() ?? {};
  if (cfg.feature_safedate_enabled !== true) {
    throw new HttpsError(
      "failed-precondition",
      "SafeDate no está disponible ahora mismo."
    );
  }
  return cfg;
}

function cfgInt(cfg: DocumentData, key: string, fallback: number): number {
  const v = cfg[key];
  if (typeof v === "number") return v;
  if (typeof v === "string") {
    const n = parseInt(v, 10);
    if (!Number.isNaN(n)) return n;
  }
  return fallback;
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
  const cfg = await requireSafeDateEnabled();

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
  const expectedReturnAt = new Date(
    scheduledAt.getTime() + expectedDurationMinutes * 60000
  );
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
    expectedReturnAt,
    status: "scheduled",
    trustedContactIds,
    shareProfileSnapshot: request.data?.shareProfileSnapshot === true,
    liveLocationEnabled: false,
    createdAt: now,
    updatedAt: now,
  });

  // Programa los check-ins del plan (llegada, mitad, regreso previsto) si la
  // fase de check-ins está activa. Backend-autoritativo: el barrido programado
  // (safeDateCheckinSweep) los recordará y marcará perdidos según config.
  if (cfg.feature_safedate_checkins_enabled === true) {
    const midAt = new Date(
      scheduledAt.getTime() + (expectedDurationMinutes / 2) * 60000
    );
    const checkins: Array<{ type: string; dueAt: Date }> = [
      { type: "arrival", dueAt: scheduledAt },
      { type: "during_date", dueAt: midAt },
      { type: "expected_return", dueAt: expectedReturnAt },
    ];
    const batch = db.batch();
    for (const c of checkins) {
      const cRef = ref.collection("checkIns").doc();
      batch.set(cRef, {
        planId: ref.id,
        ownerUserId: uid,
        type: c.type,
        status: "pending",
        dueAt: c.dueAt,
        reminderCount: 0,
        alertedContacts: false,
        createdAt: now,
        updatedAt: now,
      });
    }
    await batch.commit();
  }
  return { planId: ref.id };
});

/// respondCheckIn: el usuario responde a un check-in (estoy bien / recuérdame /
/// necesito llamar / necesito ayuda). Solo el owner del plan. Marca el estado y,
/// si pide ayuda, deja constancia para que el cliente ofrezca acciones (112,
/// avisar contacto). NUNCA llama a emergencias automáticamente.
export const respondCheckIn = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  await requireSafeDateEnabled();
  const planId = requireStringArg(request.data?.planId, "planId");
  const checkInId = requireStringArg(request.data?.checkInId, "checkInId");
  const response = requireStringArg(request.data?.response, "response");
  const allowed = ["ok", "remind_later", "need_call", "need_help", "cancelled"];
  if (!allowed.includes(response)) {
    throw new HttpsError("invalid-argument", "Respuesta no válida.");
  }

  const planRef = db.collection("safeDatePlans").doc(planId);
  const planSnap = await planRef.get();
  if (!planSnap.exists) throw new HttpsError("not-found", "El plan no existe.");
  if (planSnap.data()?.ownerUserId !== uid) {
    throw new HttpsError("permission-denied", "No es tu plan.");
  }
  const ciRef = planRef.collection("checkIns").doc(checkInId);
  const ciSnap = await ciRef.get();
  if (!ciSnap.exists) {
    throw new HttpsError("not-found", "El check-in no existe.");
  }
  await ciRef.update({
    status: response,
    respondedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  // "remind_later" reabre el check-in en la próxima ronda del barrido.
  if (response === "remind_later") {
    await ciRef.update({ status: "pending" });
  }
  return { ok: true };
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
    // Al cerrar la cita, elimina cualquier ubicación temporal (sin historial) y
    // cancela los check-ins pendientes (no seguir molestando tras la cita).
    if (status === "cancelled" || status === "completed") {
      await db
        .collection("safeDateLiveLocations")
        .doc(planId)
        .delete()
        .catch(() => undefined);
      const pending = await ref
        .collection("checkIns")
        .where("status", "==", "pending")
        .get();
      const batch = db.batch();
      for (const d of pending.docs) {
        batch.update(d.ref, {
          status: "cancelled",
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      if (!pending.empty) await batch.commit();
    }
    return { ok: true };
  }
);

// --- Fase 3: check-ins programados + notificaciones + perdido ---

const CHECKIN_LABEL: Record<string, string> = {
  arrival: "¿Has llegado bien?",
  during_date: "¿Va todo bien?",
  expected_return: "¿Ya de vuelta?",
  manual: "¿Todo bien?",
};

/// Barrido cada 5 min: recuerda check-ins vencidos y marca "perdidos" según los
/// tiempos de Remote Config. NUNCA llama a emergencias: si un check-in se pierde
/// y el usuario autorizó contactos, deja constancia de una alerta prudente. La
/// entrega saliente a contactos externos (SMS/email) es dependencia posterior;
/// aquí no se afirma que se haya enviado nada que no se pueda confirmar.
export const safeDateCheckinSweep = onSchedule(
  { schedule: "every 5 minutes", region: REGION },
  async () => {
    const cfgSnap = await db.collection("config").doc("featureFlags").get();
    const cfg = cfgSnap.data() ?? {};
    // Doble gate: master switch + fase de check-ins. Si algo falla → inerte.
    if (
      cfg.feature_safedate_enabled !== true ||
      cfg.feature_safedate_checkins_enabled !== true
    ) {
      return;
    }
    const firstMin = cfgInt(cfg, "safedate_checkin_first_reminder_minutes", 10);
    const secondMin = cfgInt(cfg, "safedate_checkin_second_reminder_minutes", 10);
    const missedMin = cfgInt(cfg, "safedate_checkin_missed_threshold_minutes", 30);
    const now = Date.now();

    // Check-ins vencidos y aún pendientes (collectionGroup sobre subcolecciones).
    const due = await db
      .collectionGroup("checkIns")
      .where("status", "==", "pending")
      .where("dueAt", "<=", new Date(now))
      .limit(200)
      .get();

    let reminders = 0;
    let missed = 0;
    for (const doc of due.docs) {
      const ci = doc.data();
      const uid = (ci.ownerUserId ?? "").toString();
      if (!uid) continue;
      const dueAt = (ci.dueAt?.toMillis?.() ?? now) as number;
      const elapsedMin = Math.floor((now - dueAt) / 60000);
      const reminderCount = (ci.reminderCount ?? 0) as number;
      const type = (ci.type ?? "manual").toString();
      const label = CHECKIN_LABEL[type] ?? CHECKIN_LABEL.manual;
      const planId = (ci.planId ?? doc.ref.parent.parent?.id ?? "").toString();

      // ¿Perdido? Supera el umbral sin respuesta → marca + alerta prudente.
      if (elapsedMin >= missedMin) {
        await doc.ref.update({
          status: "missed",
          updatedAt: FieldValue.serverTimestamp(),
        });
        missed++;
        // Aviso al propio usuario (puede estar sin cobertura / distraído). No es
        // una emergencia por sí mismo; nunca se llama a nadie automáticamente.
        await createNotification(
          uid,
          {
            kind: "safedate_checkin_missed",
            emoji: "🛟",
            title: "No hemos sabido de ti",
            body:
              "No respondiste al check-in de tu cita. Si estás bien, ábrelo y confírmalo.",
            accent: "safety",
            route: "safedate",
          },
          { planId, checkInId: doc.id }
        );
        // Si el usuario autorizó contactos, registra una alerta prudente para
        // que la surface el plan (entrega externa SMS/email = fase posterior).
        await maybeRegisterMissedAlert(planId, uid, doc.id);
        continue;
      }

      // Segundo recordatorio.
      if (reminderCount >= 1 && elapsedMin >= firstMin + secondMin) {
        if (reminderCount < 2) {
          await doc.ref.update({
            reminderCount: 2,
            updatedAt: FieldValue.serverTimestamp(),
          });
          await createNotification(
            uid,
            {
              kind: "safedate_checkin_reminder",
              emoji: "⏰",
              title: label,
              body: "Segundo aviso de tu check-in. Toca para responder.",
              accent: "safety",
              route: "safedate",
            },
            { planId, checkInId: doc.id }
          );
          reminders++;
        }
        continue;
      }

      // Primer aviso (check-in vencido).
      if (reminderCount < 1 && elapsedMin >= 0) {
        await doc.ref.update({
          reminderCount: 1,
          updatedAt: FieldValue.serverTimestamp(),
        });
        await createNotification(
          uid,
          {
            kind: "safedate_checkin_due",
            emoji: "🛡️",
            title: label,
            body: "Tu check-in de SafeDate está listo. Responde en un toque.",
            accent: "safety",
            route: "safedate",
          },
          { planId, checkInId: doc.id }
        );
        reminders++;
      }
    }
    console.log(
      `[safeDateCheckinSweep] due=${due.size} reminders=${reminders} missed=${missed}`
    );
  }
);

/// Registra una alerta prudente por check-in perdido, SOLO si el plan tiene
/// contactos de confianza autorizados. No afirma que se haya avisado a nadie por
/// un canal externo; deja constancia para que el propio usuario y (en fases
/// posteriores) el contacto vean el estado. Idempotente por check-in.
async function maybeRegisterMissedAlert(
  planId: string,
  uid: string,
  checkInId: string
): Promise<void> {
  if (!planId) return;
  const planRef = db.collection("safeDatePlans").doc(planId);
  const planSnap = await planRef.get();
  if (!planSnap.exists) return;
  const plan = planSnap.data() ?? {};
  const contactIds: string[] = Array.isArray(plan.trustedContactIds)
    ? (plan.trustedContactIds as unknown[]).filter(
        (x): x is string => typeof x === "string"
      )
    : [];
  if (contactIds.length === 0) return; // sin contactos autorizados → no alerta
  const alertRef = planRef.collection("alerts").doc(`missed_${checkInId}`);
  const exists = await alertRef.get();
  if (exists.exists) return; // idempotente
  await alertRef.set({
    planId,
    safeDatePlanId: planId,
    ownerUserId: uid,
    userId: uid,
    alertType: "missed_checkin",
    severity: "urgent",
    checkInId,
    // Constancia de a qué contactos concierne, sin exponer sus datos aquí.
    trustedContactIds: contactIds,
    // La entrega externa (SMS/email) es dependencia de infraestructura futura;
    // por honestidad NO marcamos "enviado" hasta poder confirmarlo.
    outboundDelivered: false,
    createdAt: FieldValue.serverTimestamp(),
  });
}

// --- Fase 4: cita activa — ubicación temporal + alertas ---

const ALERT_TYPES = [
  "contact_me",
  "call_me",
  "need_exit",
  "silent_alert",
  "emergency",
] as const;

function alertSeverity(type: string): string {
  if (type === "emergency" || type === "silent_alert") return "urgent";
  if (type === "need_exit") return "warning";
  return "info";
}

/// Carga un plan y verifica que es del usuario. Devuelve la ref y los datos.
async function requireOwnedPlan(
  planId: string,
  uid: string
): Promise<{ ref: FirebaseFirestore.DocumentReference; data: DocumentData }> {
  const ref = db.collection("safeDatePlans").doc(planId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "El plan no existe.");
  const data = snap.data() ?? {};
  if (data.ownerUserId !== uid) {
    throw new HttpsError("permission-denied", "No es tu plan.");
  }
  return { ref, data };
}

/// startLiveLocation: activa ubicación en directo para un plan, SOLO con
/// consentimiento explícito y con caducidad. Privacidad: sin historial, se borra
/// al parar/terminar o al caducar. Nunca se activa sin este consentimiento.
export const startLiveLocation = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const cfg = await requireSafeDateEnabled();
  if (cfg.feature_safedate_live_location_enabled !== true) {
    throw new HttpsError("failed-precondition", "No disponible.");
  }
  if (request.data?.consent !== true) {
    throw new HttpsError(
      "failed-precondition",
      "Se requiere tu consentimiento explícito para compartir ubicación."
    );
  }
  const planId = requireStringArg(request.data?.planId, "planId");
  const { ref, data } = await requireOwnedPlan(planId, uid);

  const maxMin = cfgInt(cfg, "safedate_live_location_max_minutes", 240);
  const now = Date.now();
  // Caduca lo antes: regreso previsto + 60 min, o el máximo de config.
  const returnAt =
    (data.expectedReturnAt?.toMillis?.() as number | undefined) ??
    now + maxMin * 60000;
  const expiresAt = new Date(
    Math.min(returnAt + 60 * 60000, now + maxMin * 60000)
  );

  await db
    .collection("safeDateLiveLocations")
    .doc(planId)
    .set({
      planId,
      ownerUserId: uid,
      consentAt: FieldValue.serverTimestamp(),
      expiresAt,
      latitude: null,
      longitude: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
  await ref.update({
    liveLocationEnabled: true,
    status: "active",
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { ok: true, expiresAt: expiresAt.toISOString() };
});

/// updateLiveLocation: actualiza las coordenadas mientras la sesión está activa.
/// Rechaza si no hay sesión o ya caducó (no se reactiva sin consentimiento).
export const updateLiveLocation = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  await requireSafeDateEnabled();
  const planId = requireStringArg(request.data?.planId, "planId");
  const lat = Number(request.data?.latitude);
  const lng = Number(request.data?.longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    throw new HttpsError("invalid-argument", "Coordenadas no válidas.");
  }
  const locRef = db.collection("safeDateLiveLocations").doc(planId);
  const snap = await locRef.get();
  if (!snap.exists || snap.data()?.ownerUserId !== uid) {
    throw new HttpsError("failed-precondition", "No hay sesión de ubicación.");
  }
  const expiresAt = snap.data()?.expiresAt?.toMillis?.() as number | undefined;
  if (expiresAt && Date.now() > expiresAt) {
    await locRef.delete().catch(() => undefined);
    throw new HttpsError("failed-precondition", "La sesión ha caducado.");
  }
  await locRef.update({
    latitude: lat,
    longitude: lng,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

/// stopLiveLocation: detiene y BORRA la ubicación temporal (sin historial).
export const stopLiveLocation = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  await requireSafeDateEnabled();
  const planId = requireStringArg(request.data?.planId, "planId");
  const { ref } = await requireOwnedPlan(planId, uid);
  await db
    .collection("safeDateLiveLocations")
    .doc(planId)
    .delete()
    .catch(() => undefined);
  await ref.update({
    liveLocationEnabled: false,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

/// sendSafeDateAlert: registra una acción discreta de la persona (pedir que la
/// llamen, necesito salir, alerta silenciosa…). NUNCA informa al match. NUNCA
/// llama a nadie automáticamente: deja constancia para que el propio usuario y
/// (fase posterior) sus contactos la vean. La entrega externa no se afirma.
export const sendSafeDateAlert = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const cfg = await requireSafeDateEnabled();
  if (cfg.feature_safedate_discreet_alert_enabled !== true) {
    throw new HttpsError("failed-precondition", "No disponible.");
  }
  const planId = requireStringArg(request.data?.planId, "planId");
  const type = requireStringArg(request.data?.type, "type");
  if (!ALERT_TYPES.includes(type as (typeof ALERT_TYPES)[number])) {
    throw new HttpsError("invalid-argument", "Tipo de alerta no válido.");
  }
  const { ref, data } = await requireOwnedPlan(planId, uid);
  const contactIds: string[] = Array.isArray(data.trustedContactIds)
    ? (data.trustedContactIds as unknown[]).filter(
        (x): x is string => typeof x === "string"
      )
    : [];

  const alertRef = ref.collection("alerts").doc();
  await alertRef.set({
    planId,
    safeDatePlanId: planId,
    ownerUserId: uid,
    userId: uid,
    alertType: type,
    severity: alertSeverity(type),
    trustedContactIds: contactIds,
    outboundDelivered: false,
    createdAt: FieldValue.serverTimestamp(),
  });
  // Una alerta silenciosa marca el plan como "alerted" (sin nada llamativo).
  if (type === "silent_alert" || type === "emergency") {
    await ref.update({
      status: "alerted",
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  return { ok: true, alertId: alertRef.id };
});

/// Limpieza de ubicaciones temporales caducadas (privacidad: sin historial).
/// Gated por master switch; si algo falla, no toca nada.
export const safeDateLiveLocationSweep = onSchedule(
  { schedule: "every 15 minutes", region: REGION },
  async () => {
    const cfgSnap = await db.collection("config").doc("featureFlags").get();
    if (cfgSnap.data()?.feature_safedate_enabled !== true) return;
    const expired = await db
      .collection("safeDateLiveLocations")
      .where("expiresAt", "<=", new Date())
      .limit(300)
      .get();
    if (expired.empty) return;
    const batch = db.batch();
    for (const d of expired.docs) {
      batch.delete(d.ref);
    }
    await batch.commit();
    console.log(`[safeDateLiveLocationSweep] deleted=${expired.size}`);
  }
);
