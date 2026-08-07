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

// 72 h: Discover pasa a ser un muro de historias, asi que una ventana de 24 h
// dejaba el muro vacio para quien no entra a diario. Las historias YA creadas
// conservan su expiresAt de 24 h (se guarda por documento, no se recalcula):
// no se alargan retroactivamente, simplemente las nuevas duran mas.
const STORY_TTL_MS = 72 * 60 * 60 * 1000;
const MAX_VIDEO_BYTES = 15 * 1024 * 1024;
const MAX_IMAGE_BYTES = 8 * 1024 * 1024;
const MAX_DURATION_SECONDS = 15;
// Maximo de historias VIVAS por usuario. Era 1, que convierte la funcion en
// "una foto del dia"; con 5 el usuario puede construir un relato, que es lo que
// hace que el muro tenga algo que ver. El tope se aplica en SERVIDOR: el
// cliente puede ocultar el boton, pero quien llame a la callable directamente
// no puede saltarselo.
const MAX_ACTIVE_STORIES = 5;

type StoryMediaType = "video" | "image";
type StoryOverlayType = "text" | "sticker";
type StoryOverlayAlign = "left" | "center" | "right";

type StoryOverlay = {
  type: StoryOverlayType;
  text: string;
  x: number;
  y: number;
  scale: number;
  rotation: number;
  color: number;
  background: boolean;
  align: StoryOverlayAlign;
};

function bucket() {
  return getStorage().bucket(STORAGE_BUCKET);
}

function optionalString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function finiteNumber(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function sanitizeOverlays(value: unknown): StoryOverlay[] {
  if (!Array.isArray(value)) return [];
  return value
    .slice(0, 12)
    .map((raw): StoryOverlay | null => {
      if (!raw || typeof raw !== "object") return null;
      const data = raw as Record<string, unknown>;
      const text = optionalString(data.text).slice(0, 80);
      if (!text) return null;
      const type: StoryOverlayType =
        data.type === "sticker" ? "sticker" : "text";
      const align: StoryOverlayAlign =
        data.align === "left" || data.align === "right" ? data.align : "center";
      const color = Math.round(finiteNumber(data.color, 0xffffffff));
      return {
        type,
        text,
        x: clamp(finiteNumber(data.x, 0.5), 0, 1),
        y: clamp(finiteNumber(data.y, 0.5), 0, 1),
        scale: clamp(finiteNumber(data.scale, 1), 0.4, 3),
        rotation: clamp(finiteNumber(data.rotation, 0), -6.2832, 6.2832),
        color: clamp(color, 0, 0xffffffff),
        background: data.background === true,
        align,
      };
    })
    .filter((overlay): overlay is StoryOverlay => overlay !== null);
}

function assertPathBelongsToStory(path: string, prefix: string): void {
  if (!path.startsWith(prefix)) {
    throw new HttpsError("permission-denied", "Ruta de archivo no valida.");
  }
}

async function validateStorageObject(params: {
  path: string;
  expectedMimePrefix: "video/" | "image/";
  maxBytes: number;
  missingMessage: string;
  invalidMimeMessage: string;
  invalidSizeMessage: string;
}): Promise<void> {
  const file = bucket().file(params.path);
  const [exists] = await file.exists();
  if (!exists) {
    throw new HttpsError("failed-precondition", params.missingMessage);
  }
  const [meta] = await file.getMetadata();
  const mime = (meta.contentType ?? "").toString();
  const size = Number(meta.size ?? 0);
  if (!mime.startsWith(params.expectedMimePrefix)) {
    throw new HttpsError("invalid-argument", params.invalidMimeMessage);
  }
  if (size <= 0 || size > params.maxBytes) {
    throw new HttpsError("invalid-argument", params.invalidSizeMessage);
  }
}

export const createStory = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const storyId = requireStringArg(request.data?.storyId, "storyId");
  const mediaType: StoryMediaType =
    request.data?.mediaType === "image" ? "image" : "video";

  const videoPath = optionalString(request.data?.videoPath);
  const videoUrl = optionalString(request.data?.videoUrl);
  const imagePath = optionalString(request.data?.imagePath);
  const imageUrl = optionalString(request.data?.imageUrl);
  const thumbnailPath = optionalString(request.data?.thumbnailPath);
  const thumbnailUrl = optionalString(request.data?.thumbnailUrl);
  const visibility =
    request.data?.visibility === "matches" ? "matches" : "discovery";
  const caption =
    typeof request.data?.caption === "string"
      ? (request.data.caption as string).slice(0, 200)
      : "";
  const captionX = clamp(finiteNumber(request.data?.captionX, 0.5), 0, 1);
  const captionY = clamp(finiteNumber(request.data?.captionY, 0.85), 0, 1);
  const overlays = sanitizeOverlays(request.data?.overlays);
  const durationSeconds = Number.isFinite(request.data?.durationSeconds)
    ? Math.round(Number(request.data.durationSeconds))
    : mediaType === "image"
      ? 5
      : 0;

  if (durationSeconds > MAX_DURATION_SECONDS) {
    throw new HttpsError(
      "invalid-argument",
      "La story supera la duracion maxima.",
    );
  }

  const prefix = `stories/${uid}/${storyId}/`;
  if (mediaType === "video") {
    if (!videoPath || !videoUrl) {
      throw new HttpsError("invalid-argument", "Falta el video de la story.");
    }
    assertPathBelongsToStory(videoPath, prefix);
    if (thumbnailPath) assertPathBelongsToStory(thumbnailPath, prefix);
    await validateStorageObject({
      path: videoPath,
      expectedMimePrefix: "video/",
      maxBytes: MAX_VIDEO_BYTES,
      missingMessage: "El video no existe en Storage.",
      invalidMimeMessage: "El archivo no es un video.",
      invalidSizeMessage: "El video supera el tamano permitido.",
    });
  } else {
    if (!imagePath || !imageUrl) {
      throw new HttpsError("invalid-argument", "Falta la foto de la story.");
    }
    assertPathBelongsToStory(imagePath, prefix);
    if (thumbnailPath) assertPathBelongsToStory(thumbnailPath, prefix);
    await validateStorageObject({
      path: imagePath,
      expectedMimePrefix: "image/",
      maxBytes: MAX_IMAGE_BYTES,
      missingMessage: "La foto no existe en Storage.",
      invalidMimeMessage: "El archivo no es una imagen.",
      invalidSizeMessage: "La foto supera el tamano permitido.",
    });
  }

  const now = Date.now();
  const activeSnap = await col.stories
    .where("ownerUid", "==", uid)
    .where("status", "==", "active")
    .get();
  const activeLive = activeSnap.docs.filter(
    (d) => (d.data().expiresAt?.toMillis?.() ?? 0) > now,
  );
  if (activeLive.length >= MAX_ACTIVE_STORIES) {
    throw new HttpsError(
      "resource-exhausted",
      `Ya tienes ${MAX_ACTIVE_STORIES} historias activas. Borra alguna o ` +
        "espera a que caduque para subir otra.",
    );
  }

  const userSnap = await col.users.doc(uid).get();
  const displayName = resolvePublicDisplayName(userSnap.data());

  const expiresAt = new Date(now + STORY_TTL_MS);
  await col.stories.doc(storyId).set({
    storyId,
    ownerUid: uid,
    displayName,
    mediaType,
    videoPath,
    videoUrl,
    imagePath,
    imageUrl,
    thumbnailPath,
    thumbnailUrl,
    caption,
    captionX,
    captionY,
    overlays,
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

export const viewStory = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const storyId = requireStringArg(request.data?.storyId, "storyId");
  const storyRef = col.stories.doc(storyId);
  const viewRef = storyRef.collection("views").doc(uid);

  await db.runTransaction(async (tx) => {
    const [storySnap, viewSnap] = await Promise.all([
      tx.get(storyRef),
      tx.get(viewRef),
    ]);
    if (!storySnap.exists)
      throw new HttpsError("not-found", "La story no existe.");
    if (viewSnap.exists) return;
    if (storySnap.data()?.ownerUid === uid) return;
    tx.set(viewRef, { viewerUid: uid, viewedAt: FieldValue.serverTimestamp() });
    tx.update(storyRef, { viewsCount: FieldValue.increment(1) });
  });
  return { ok: true };
});

export const replyToStory = onCall({ region: REGION }, async (request) => {
  const fromUid = requireAuthUid(request.auth);
  const storyId = requireStringArg(request.data?.storyId, "storyId");
  const text = (typeof request.data?.text === "string" ? request.data.text : "")
    .trim()
    .slice(0, 2000);
  const asAttra = request.data?.asAttra === true;

  const storySnap = await col.stories.doc(storyId).get();
  if (!storySnap.exists)
    throw new HttpsError("not-found", "La story no existe.");
  const toUid = (storySnap.data()?.ownerUid ?? "") as string;
  if (!toUid || toUid === fromUid) {
    throw new HttpsError(
      "invalid-argument",
      "No puedes responder a tu propia story.",
    );
  }
  if (await existsBlockBetween(fromUid, toUid)) {
    throw new HttpsError(
      "permission-denied",
      "No puedes interactuar con este perfil.",
    );
  }

  const chatId = pairId(fromUid, toUid);
  const result = await db.runTransaction(async (tx) => {
    const chatSnap = await tx.get(col.chats.doc(chatId));
    const chatActive =
      chatSnap.exists && (chatSnap.data()?.status ?? "active") === "active";

    if (chatActive) {
      const now = FieldValue.serverTimestamp();
      const msgRef = col.chats.doc(chatId).collection("messages").doc();
      tx.set(msgRef, {
        senderId: fromUid,
        receiverId: toUid,
        type: "text",
        text: text.length > 0 ? text : "Respondio a tu story",
        status: "sent",
        relatedStoryId: storyId,
        createdAt: now,
      });
      tx.update(col.chats.doc(chatId), {
        lastMessage: text.length > 0 ? text : "Respondio a tu story",
        lastMessageType: "text",
        lastMessageSenderId: fromUid,
        lastMessageAt: now,
        updatedAt: now,
        [`unreadCountByUser.${toUid}`]: FieldValue.increment(1),
      });
      tx.update(col.stories.doc(storyId), {
        repliesCount: FieldValue.increment(1),
      });
      return { outcome: "message", chatId };
    }

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
      { merge: true },
    );
    tx.update(col.stories.doc(storyId), {
      repliesCount: FieldValue.increment(1),
    });

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

export const deleteStory = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const storyId = requireStringArg(request.data?.storyId, "storyId");
  const storyRef = col.stories.doc(storyId);
  const snap = await storyRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "La story no existe.");
  if (snap.data()?.ownerUid !== uid) {
    throw new HttpsError("permission-denied", "No es tu story.");
  }
  await deleteStoryFiles(
    snap.data()?.videoPath,
    snap.data()?.thumbnailPath,
    snap.data()?.imagePath,
  );
  await storyRef.update({
    status: "deleted",
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

async function deleteStoryFiles(...paths: unknown[]): Promise<void> {
  const unique = Array.from(
    new Set(
      paths.filter(
        (p): p is string => typeof p === "string" && p.trim().length > 0,
      ),
    ),
  );
  await Promise.all(
    unique.map((p) =>
      bucket()
        .file(p)
        .delete()
        .catch(() => undefined),
    ),
  );
}

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
      await deleteStoryFiles(
        doc.data().videoPath,
        doc.data().thumbnailPath,
        doc.data().imagePath,
      );
      await doc.ref.update({
        status: "expired",
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  },
);
