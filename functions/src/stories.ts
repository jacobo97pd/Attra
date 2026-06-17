import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { FieldValue } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { REGION, STORAGE_BUCKET, db } from "./firebase";
import { directedId, pairId } from "./ids";
import { writeMatchAndChat } from "./match";
import {
  col,
  existsBlockBetween,
  requireAuthUid,
  requireStringArg,
  resolvePublicDisplayName,
} from "./common";

const STORY_TTL_MS = 24 * 60 * 60 * 1000;
const MAX_VIDEO_BYTES = 15 * 1024 * 1024;
const MAX_DURATION_SECONDS = 15;
const FREE_MAX_ACTIVE_STORIES = 1;

function bucket() {
  return getStorage().bucket(STORAGE_BUCKET);
}

/// createStory: el cliente ya subio video+thumb a Storage (ruta segura por uid);
/// aqui se valida y se crea el doc autoritativo. Verifica metadata real del
/// objeto (size/contentType), limite de 1 story activa free y caduca en 24h.
export const createStory = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const storyId = requireStringArg(request.data?.storyId, "storyId");
  const videoPath = requireStringArg(request.data?.videoPath, "videoPath");
  const thumbnailPath = requireStringArg(request.data?.thumbnailPath, "thumbnailPath");
  // downloadUrls tokenizadas que el cliente obtuvo de Storage (getDownloadURL).
  const videoUrl = requireStringArg(request.data?.videoUrl, "videoUrl");
  const thumbnailUrl =
    typeof request.data?.thumbnailUrl === "string" ? request.data.thumbnailUrl : "";
  const visibility =
    request.data?.visibility === "matches" ? "matches" : "discovery";
  const caption =
    typeof request.data?.caption === "string"
      ? (request.data.caption as string).slice(0, 200)
      : "";
  const durationSeconds = Number.isFinite(request.data?.durationSeconds)
    ? Math.round(Number(request.data.durationSeconds))
    : 0;

  // Los paths DEBEN pertenecer a este usuario + esta story.
  const prefix = `stories/${uid}/${storyId}/`;
  if (!videoPath.startsWith(prefix) || !thumbnailPath.startsWith(prefix)) {
    throw new HttpsError("permission-denied", "Ruta de archivo no válida.");
  }
  if (durationSeconds > MAX_DURATION_SECONDS) {
    throw new HttpsError("invalid-argument", "El vídeo supera la duración máxima.");
  }

  // Metadata REAL del vídeo (no confiamos en el cliente).
  const videoFile = bucket().file(videoPath);
  const [vExists] = await videoFile.exists();
  if (!vExists) {
    throw new HttpsError("failed-precondition", "El vídeo no existe en Storage.");
  }
  const [vMeta] = await videoFile.getMetadata();
  const vMime = (vMeta.contentType ?? "").toString();
  const vSize = Number(vMeta.size ?? 0);
  if (!vMime.startsWith("video/")) {
    throw new HttpsError("invalid-argument", "El archivo no es un vídeo.");
  }
  if (vSize <= 0 || vSize > MAX_VIDEO_BYTES) {
    throw new HttpsError("invalid-argument", "El vídeo supera el tamaño permitido.");
  }

  // Limite free: 1 story activa.
  const now = Date.now();
  const activeSnap = await col.stories
    .where("ownerUid", "==", uid)
    .where("status", "==", "active")
    .get();
  const activeLive = activeSnap.docs.filter(
    (d) => (d.data().expiresAt?.toMillis?.() ?? 0) > now
  );
  if (activeLive.length >= FREE_MAX_ACTIVE_STORIES) {
    throw new HttpsError("failed-precondition", "Ya tienes una story activa.");
  }

  const userSnap = await col.users.doc(uid).get();
  const displayName = resolvePublicDisplayName(userSnap.data());

  const expiresAt = new Date(now + STORY_TTL_MS);
  await col.stories.doc(storyId).set({
    storyId,
    ownerUid: uid,
    displayName,
    videoPath,
    thumbnailPath,
    videoUrl,
    thumbnailUrl,
    caption,
    status: "active",
    visibility,
    durationSeconds,
    viewsCount: 0,
    repliesCount: 0,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt,
  });

  return { storyId, expiresAt: expiresAt.toISOString() };
});

/// viewStory: registra una vista (idempotente, una por viewer) e incrementa el
/// contador una sola vez.
export const viewStory = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const storyId = requireStringArg(request.data?.storyId, "storyId");
  const storyRef = col.stories.doc(storyId);
  const viewRef = storyRef.collection("views").doc(uid);

  await db.runTransaction(async (tx) => {
    const [storySnap, viewSnap] = await Promise.all([tx.get(storyRef), tx.get(viewRef)]);
    if (!storySnap.exists) throw new HttpsError("not-found", "La story no existe.");
    if (viewSnap.exists) return; // ya vista
    if (storySnap.data()?.ownerUid === uid) return; // el dueño no cuenta
    tx.set(viewRef, { viewerUid: uid, viewedAt: FieldValue.serverTimestamp() });
    tx.update(storyRef, { viewsCount: FieldValue.increment(1) });
  });
  return { ok: true };
});

/// replyToStory: si hay match activo, manda mensaje al chat; si no, crea un like
/// contextual (con origen story) que puede generar match si es reciproco.
export const replyToStory = onCall({ region: REGION }, async (request) => {
  const fromUid = requireAuthUid(request.auth);
  const storyId = requireStringArg(request.data?.storyId, "storyId");
  const text = (typeof request.data?.text === "string" ? request.data.text : "")
    .trim()
    .slice(0, 2000);
  const asAttra = request.data?.asAttra === true;

  const storySnap = await col.stories.doc(storyId).get();
  if (!storySnap.exists) throw new HttpsError("not-found", "La story no existe.");
  const toUid = (storySnap.data()?.ownerUid ?? "") as string;
  if (!toUid || toUid === fromUid) {
    throw new HttpsError("invalid-argument", "No puedes responder a tu propia story.");
  }
  if (await existsBlockBetween(fromUid, toUid)) {
    throw new HttpsError("permission-denied", "No puedes interactuar con este perfil.");
  }

  const chatId = pairId(fromUid, toUid);
  const result = await db.runTransaction(async (tx) => {
    const chatSnap = await tx.get(col.chats.doc(chatId));
    const chatActive =
      chatSnap.exists && (chatSnap.data()?.status ?? "active") === "active";

    if (chatActive) {
      // Hay match: el reply va al chat como mensaje.
      const now = FieldValue.serverTimestamp();
      const msgRef = col.chats.doc(chatId).collection("messages").doc();
      tx.set(msgRef, {
        senderId: fromUid,
        receiverId: toUid,
        type: "text",
        text: text.length > 0 ? text : "Respondió a tu story",
        status: "sent",
        relatedStoryId: storyId,
        createdAt: now,
      });
      tx.update(col.chats.doc(chatId), {
        lastMessage: text.length > 0 ? text : "Respondió a tu story",
        lastMessageType: "text",
        lastMessageSenderId: fromUid,
        lastMessageAt: now,
        updatedAt: now,
        [`unreadCountByUser.${toUid}`]: FieldValue.increment(1),
      });
      tx.update(col.stories.doc(storyId), { repliesCount: FieldValue.increment(1) });
      return { outcome: "message", chatId };
    }

    // Sin match: like contextual con origen story.
    const likeRef = col.likes.doc(directedId(fromUid, toUid));
    const invSnap = await tx.get(col.likes.doc(directedId(toUid, fromUid)));
    tx.set(
      likeRef,
      {
        fromUid,
        toUid,
        type: asAttra ? "attra" : "like",
        status: "active",
        targetType: "story",
        relatedStoryId: storyId,
        commentText: text.length > 0 ? text : null,
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    tx.update(col.stories.doc(storyId), { repliesCount: FieldValue.increment(1) });

    const invActive =
      invSnap.exists && (invSnap.data()?.status ?? "active") !== "rejected";
    if (invActive) {
      const refs = writeMatchAndChat(tx, {
        uidA: fromUid,
        uidB: toUid,
        createdBy: fromUid,
        action: asAttra ? "attra" : "like",
        hasAttra: asAttra,
        attraSenderUid: asAttra ? fromUid : null,
        origin: {
          originLikeId: directedId(fromUid, toUid),
          originTargetType: "profile",
          originCommentText: text.length > 0 ? text : null,
        },
      });
      return { outcome: "matched", chatId: refs.chatId };
    }
    return { outcome: "liked" };
  });

  return result;
});

/// deleteStory: solo el dueño. Borra ficheros de Storage y marca deleted.
export const deleteStory = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const storyId = requireStringArg(request.data?.storyId, "storyId");
  const storyRef = col.stories.doc(storyId);
  const snap = await storyRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "La story no existe.");
  if (snap.data()?.ownerUid !== uid) {
    throw new HttpsError("permission-denied", "No es tu story.");
  }
  await deleteStoryFiles(snap.data()?.videoPath, snap.data()?.thumbnailPath);
  await storyRef.update({ status: "deleted", updatedAt: FieldValue.serverTimestamp() });
  return { ok: true };
});

async function deleteStoryFiles(videoPath?: unknown, thumbnailPath?: unknown): Promise<void> {
  const paths = [videoPath, thumbnailPath].filter(
    (p): p is string => typeof p === "string" && p.length > 0
  );
  await Promise.all(
    paths.map((p) => bucket().file(p).delete().catch(() => undefined))
  );
}

/// cleanupExpiredStories: cada hora marca expired las caducadas y borra sus
/// ficheros de Storage. Requiere Blaze (Cloud Scheduler).
export const cleanupExpiredStories = onSchedule(
  { schedule: "every 60 minutes", region: REGION },
  async () => {
    const now = new Date();
    const snap = await col.stories
      .where("status", "==", "active")
      .where("expiresAt", "<", now)
      .limit(300)
      .get();
    for (const doc of snap.docs) {
      await deleteStoryFiles(doc.data().videoPath, doc.data().thumbnailPath);
      await doc.ref.update({ status: "expired", updatedAt: FieldValue.serverTimestamp() });
    }
  }
);
