import { onCall } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { FieldValue, DocumentData } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { REGION, db } from "./firebase";
import { pairId } from "./ids";
import { col, existsBlockBetween, resolvePublicDisplayName } from "./common";

const DATABASE = "attra-database";

export type Accent = "desire" | "match" | "premium" | "calm" | "safety";

export interface NotifContent {
  kind: string;
  emoji: string;
  title: string;
  body: string;
  accent: Accent;
  route: string;
}

/// Plantillas (espejo de las de Dart). Copy con personalidad + emoji + acento.
function tplNewLike(): NotifContent {
  return {
    kind: "new_like",
    emoji: "👀",
    title: "Le gustas a alguien",
    body: "Alguien ha deslizado a la derecha. ¿Quién será? 😏",
    accent: "desire",
    route: "likes",
  };
}
function tplAttra(name: string): NotifContent {
  return {
    kind: "attra_received",
    emoji: "⭐",
    title: "Te han enviado un Attra",
    body: `${name} va en serio contigo. Mira quién es ✨`,
    accent: "premium",
    route: "likes",
  };
}
function tplNewMatch(name: string): NotifContent {
  return {
    kind: "new_match",
    emoji: "✨",
    title: `¡Nuevo match con ${name}!`,
    body: "Habéis conectado. Da el primer paso 💬",
    accent: "match",
    route: "chats",
  };
}
function tplNewMessage(name: string, preview: string): NotifContent {
  return {
    kind: "new_message",
    emoji: "💬",
    title: `${name} te ha escrito`,
    body: preview && preview.trim().length > 0 ? preview.trim().slice(0, 90) : "Tienes un mensaje nuevo",
    accent: "desire",
    route: "chats",
  };
}
function tplSparkChallenge(name: string): NotifContent {
  return {
    kind: "spark_challenge",
    emoji: "⚡",
    title: `${name} te ha retado`,
    body: "Juega Attra Spark (5 min) para romper el hielo ⚡",
    accent: "desire",
    route: "chats",
  };
}
function tplComeBack(days: number): NotifContent {
  return {
    kind: "come_back",
    emoji: "🌙",
    title: "Te echamos de menos",
    body:
      days > 1
        ? `Hace ${days} días que no entras y hay gente esperándote`
        : "Vuelve, que hay movimiento por aquí",
    accent: "calm",
    route: "feed",
  };
}
/// Crea la notificación IN-APP en `notifications/{uid}/items` y envía PUSH (FCM)
/// a los tokens del usuario. Best-effort: si el usuario es bot/no existe, se
/// omite. NUNCA lanza (no debe tumbar el trigger que la invoca).
export async function createNotification(
  uid: string,
  c: NotifContent,
  data: Record<string, unknown> = {}
): Promise<void> {
  try {
    if (!uid) return;
    const userSnap = await col.users.doc(uid).get();
    if (!userSnap.exists) return; // destino no es un usuario real (p.ej. bot)
    const u = userSnap.data() ?? {};
    if (u.isBanned === true || u.isDeleted === true) return;

    // 1) Documento in-app (lo lee la bandeja del cliente).
    await db
      .collection("notifications")
      .doc(uid)
      .collection("items")
      .add({
        kind: c.kind,
        emoji: c.emoji,
        title: c.title,
        body: c.body,
        accent: c.accent,
        route: c.route,
        read: false,
        data,
        createdAt: FieldValue.serverTimestamp(),
      });

    // 2) Push FCM a los tokens del usuario (si tiene y FCM está configurado).
    const tokens: string[] = Array.isArray(u.fcmTokens)
      ? (u.fcmTokens as unknown[]).filter((t): t is string => typeof t === "string")
      : [];
    if (tokens.length === 0) return;
    const res = await getMessaging().sendEachForMulticast({
      tokens,
      notification: { title: `${c.emoji} ${c.title}`, body: c.body },
      data: { route: c.route, kind: c.kind },
      android: { priority: "high", notification: { color: "#FF4F68" } },
      apns: { payload: { aps: { sound: "default" } } },
    });
    // Limpia tokens inválidos.
    const invalid: string[] = [];
    res.responses.forEach((r, i) => {
      if (!r.success) {
        const code = r.error?.code ?? "";
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          invalid.push(tokens[i]);
        }
      }
    });
    if (invalid.length > 0) {
      await col.users
        .doc(uid)
        .update({ fcmTokens: FieldValue.arrayRemove(...invalid) })
        .catch(() => undefined);
    }
  } catch (e) {
    console.error("[notifications] createNotification falló", e);
  }
}

/// Claves con las que cada tipo de aviso de la bandeja de `ownerUid` apunta a
/// `otherUid`. Cada plantilla guarda el vinculo en un sitio distinto, asi que
/// mirar solo `fromUid` se dejaba la mayoria:
///  - like / Attra → `data.fromUid` = la otra persona;
///  - match / reto Spark → `data.matchId` = id del par;
///  - mensaje → `data.chatId` = id del par (chatId == matchId).
export function pairNotificationFilters(
  ownerUid: string,
  otherUid: string
): Array<{ field: string; value: string }> {
  const id = pairId(ownerUid, otherUid);
  return [
    { field: "data.fromUid", value: otherUid },
    { field: "data.matchId", value: id },
    { field: "data.chatId", value: id },
  ];
}

const PAIR_NOTIF_PAGE = 200;

/// Borra de las DOS bandejas los avisos que apuntan a la otra persona del par.
///
/// QUE FALLABA: bloquear no tocaba `notifications/{uid}/items`, y el cliente
/// no filtra la bandeja por bloqueos: la campana de quien bloqueaba seguia
/// enseñando "B te ha escrito" con el texto del mensaje (a veces justo el
/// motivo del bloqueo) y llevando a su chat. Se borran (no se ocultan) porque
/// son copias renderizadas, no evidencia: los mensajes siguen en
/// chats/{id}/messages. Los push ya entregados al movil no se pueden retirar.
/// Devuelve cuantos borro.
export async function deletePairNotifications(
  uidA: string,
  uidB: string
): Promise<number> {
  let deleted = 0;
  for (const [owner, other] of [
    [uidA, uidB],
    [uidB, uidA],
  ]) {
    const items = db.collection("notifications").doc(owner).collection("items");
    for (const f of pairNotificationFilters(owner, other)) {
      // Sin cursor a proposito: lo ya borrado no vuelve a salir en la
      // siguiente pagina, asi que basta con repetir la consulta.
      let more = true;
      while (more) {
        const snap = await items
          .where(f.field, "==", f.value)
          .limit(PAIR_NOTIF_PAGE)
          .get();
        if (snap.empty) break;
        const batch = db.batch();
        for (const doc of snap.docs) batch.delete(doc.ref);
        await batch.commit();
        deleted += snap.size;
        more = snap.size >= PAIR_NOTIF_PAGE;
      }
    }
  }
  return deleted;
}

// --- Triggers (aislados; NO tocan los callables de like/match/chat) ---

/// Nuevo like → avisa al receptor (anónimo, dirige a la bandeja de likes).
export const onLikeCreated = onDocumentCreated(
  { document: "likes/{likeId}", database: DATABASE, region: REGION },
  async (event) => {
    const data = event.data?.data() as DocumentData | undefined;
    if (!data) return;
    // Solo likes PENDIENTES. Cuando el like cierra un match en la misma
    // transaccion (sendLike/sendAttra/vivo), el doc NACE ya 'matched': avisar
    // "Le gustas a alguien" mandaba a una bandeja donde ese like no sale (filtra
    // 'active') y duplicaba el push de "Nuevo match", que ya cubre el caso. Sin
    // `status` (docs antiguos) se trata como pendiente.
    if ((data.status ?? "active").toString() !== "active") return;
    const toUid = (data.toUid ?? "").toString();
    const fromUid = (data.fromUid ?? "").toString();
    const type = (data.type ?? "like").toString();
    if (!toUid || toUid === fromUid) return;
    // Un like escrito justo antes de un bloqueo puede disparar esto DESPUES de
    // que applyBlock limpiara la bandeja: el aviso volveria a aparecer.
    if (await existsBlockBetween(fromUid, toUid)) return;
    if (type === "attra") {
      const fromSnap = await col.users.doc(fromUid).get();
      const name = resolvePublicDisplayName(fromSnap.data()) || "Alguien";
      await createNotification(toUid, tplAttra(name), { fromUid });
    } else {
      await createNotification(toUid, tplNewLike(), { fromUid });
    }
  }
);

/// Nuevo match → avisa a AMBOS participantes con el nombre del otro.
export const onMatchCreated = onDocumentCreated(
  { document: "matches/{matchId}", database: DATABASE, region: REGION },
  async (event) => {
    const data = event.data?.data() as DocumentData | undefined;
    // Blocked pairs also have participants so both feeds can exclude them.
    if (!data || data.status !== "active") return;
    const users: string[] = Array.isArray(data.users)
      ? (data.users as unknown[]).filter((u): u is string => typeof u === "string")
      : [];
    if (users.length !== 2) return;
    const [a, b] = users;
    const [snapA, snapB] = await Promise.all([
      col.users.doc(a).get(),
      col.users.doc(b).get(),
    ]);
    const nameA = resolvePublicDisplayName(snapA.data()) || "tu match";
    const nameB = resolvePublicDisplayName(snapB.data()) || "tu match";
    await Promise.all([
      createNotification(a, tplNewMatch(nameB), { matchId: event.params.matchId }),
      createNotification(b, tplNewMatch(nameA), { matchId: event.params.matchId }),
    ]);
  }
);

/// Nuevo mensaje → avisa al receptor con el nombre del emisor + preview.
export const onMessageCreated = onDocumentCreated(
  { document: "chats/{chatId}/messages/{messageId}", database: DATABASE, region: REGION },
  async (event) => {
    const data = event.data?.data() as DocumentData | undefined;
    if (!data) return;
    const type = (data.type ?? "text").toString();
    // Solo mensajes "humanos" (no contexto/sistema). El mensaje de cierre
    // (`closure`, Attra Clear §3) NO genera push "te ha escrito": se ve in-app.
    if (
      ["system", "like_context", "attra_context", "closure"].includes(type)
    ) {
      return;
    }
    const senderId = (data.senderId ?? "").toString();
    const receiverId = (data.receiverId ?? "").toString();
    if (!receiverId || receiverId === senderId || senderId === "system") return;
    // Misma carrera que en onLikeCreated: un mensaje en vuelo al bloquear no
    // debe volver a dejar su preview en la bandeja de quien bloqueo.
    if (await existsBlockBetween(senderId, receiverId)) return;
    const senderSnap = await col.users.doc(senderId).get();
    const name = resolvePublicDisplayName(senderSnap.data()) || "Alguien";
    const preview =
      type === "text" ? (data.text ?? "").toString() : "Te ha enviado algo";
    await createNotification(receiverId, tplNewMessage(name, preview), {
      chatId: event.params.chatId,
    });
  }
);

/// ¿Puede `inviterUid` retar a `invitedUid` en este match? Match ACTIVO con
/// ambos dentro y sin bloqueo en ningun sentido.
///
/// QUE FALLABA: applyBlock deja matches/{par} con `users` y status 'blocked'
/// aunque nunca hubiera match, y el trigger no miraba ni el estado ni los
/// bloqueos: el bloqueado creaba la sesion con el SDK y el que le bloqueo
/// recibia "X te ha retado" (push incluido). Las reglas ya lo cortan; esto es
/// la defensa del lado servidor (y cubre sesiones creadas antes de las reglas).
export async function sparkChallengeAllowed(
  matchId: string,
  inviterUid: string,
  invitedUid: string
): Promise<boolean> {
  const matchSnap = await col.matches.doc(matchId).get();
  if (!matchSnap.exists) return false;
  const match = matchSnap.data() ?? {};
  if ((match.status ?? "active").toString() !== "active") return false;
  const users: unknown[] = Array.isArray(match.users) ? match.users : [];
  if (!users.includes(inviterUid) || !users.includes(invitedUid)) return false;
  return !(await existsBlockBetween(inviterUid, invitedUid));
}

/// Reto de Attra Spark → avisa al INVITADO (userBId). La sesión la crea el
/// cliente en `matches/{id}/sparkSessions/{sessionId}` con el invitador ya
/// aceptado; notificamos solo cuando nace en estado `waiting`.
export const onSparkSessionCreated = onDocumentCreated(
  {
    document: "matches/{matchId}/sparkSessions/{sessionId}",
    database: DATABASE,
    region: REGION,
  },
  async (event) => {
    const data = event.data?.data() as DocumentData | undefined;
    if (!data) return;
    if ((data.status ?? "").toString() !== "waiting") return;
    const invitedUid = (data.userBId ?? "").toString();
    // El invitador es SIEMPRE userAId, que las reglas atan a quien crea la
    // sesion. `invitedBy` no lo valida nadie: leerlo dejaba poner el nombre de
    // otra persona en el reto. El cliente legitimo escribe ambos iguales.
    const inviterUid = (data.userAId ?? "").toString();
    if (!invitedUid || !inviterUid || invitedUid === inviterUid) return;
    if (!(await sparkChallengeAllowed(event.params.matchId, inviterUid, invitedUid))) {
      return;
    }
    const inviterSnap = await col.users.doc(inviterUid).get();
    const name = resolvePublicDisplayName(inviterSnap.data()) || "Alguien";
    await createNotification(invitedUid, tplSparkChallenge(name), {
      matchId: event.params.matchId,
    });
  }
);

// --- Scheduled (re-engagement) ---

/// "Hace mucho que no entras": usuarios con lastLoginAt antiguo. Marca para no
/// repetir a diario (comeBackNotifiedAt). Ventana: 3-30 días de inactividad.
export const sendComeBackNotifications = onSchedule(
  { schedule: "every 24 hours", region: REGION },
  async () => {
    const now = Date.now();
    const threeDays = now - 3 * 24 * 3600 * 1000;
    const thirtyDays = now - 30 * 24 * 3600 * 1000;
    const snap = await col.users
      .where("lastLoginAt", "<=", new Date(threeDays))
      .where("lastLoginAt", ">=", new Date(thirtyDays))
      .limit(300)
      .get();
    let sent = 0;
    for (const doc of snap.docs) {
      const u = doc.data();
      const lastNotified = (u.comeBackNotifiedAt?.toMillis?.() ?? 0) as number;
      // No repetir si ya se le avisó en los últimos 6 días.
      if (now - lastNotified < 6 * 24 * 3600 * 1000) continue;
      const lastLogin = (u.lastLoginAt?.toMillis?.() ?? now) as number;
      const days = Math.floor((now - lastLogin) / (24 * 3600 * 1000));
      await createNotification(doc.id, tplComeBack(days));
      await doc.ref.update({ comeBackNotifiedAt: FieldValue.serverTimestamp() }).catch(() => undefined);
      sent++;
    }
    console.log(`[sendComeBackNotifications] sent=${sent}`);
  }
);

// --- Registro de token FCM (cliente) ---

/// Guarda el token de push del dispositivo en `users/{uid}.fcmTokens` (array).
export const registerPushToken = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  const token = request.data?.token;
  if (!uid || typeof token !== "string" || token.length < 10) {
    return { ok: false };
  }
  await col.users.doc(uid).set(
    { fcmTokens: FieldValue.arrayUnion(token), updatedAt: FieldValue.serverTimestamp() },
    { merge: true }
  );
  return { ok: true };
});

/// Quita un token (logout / token caducado).
export const unregisterPushToken = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  const token = request.data?.token;
  if (!uid || typeof token !== "string") return { ok: false };
  await col.users
    .doc(uid)
    .set({ fcmTokens: FieldValue.arrayRemove(token) }, { merge: true });
  return { ok: true };
});
