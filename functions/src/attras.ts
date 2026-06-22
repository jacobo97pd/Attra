import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { directedId, pairId } from "./ids";
import { ContextMessageParams, writeContextMessage, writeMatchAndChat } from "./match";
import { parsePromptTarget } from "./likes";
import { moderateComment } from "./moderation";
import {
  recordBoostLikeReceivedForUser,
  recordBoostMatchGeneratedForUser,
} from "./boosts";
import {
  col,
  isUserContactable,
  requireAuthUid,
  requireStringArg,
  resolveReceiverPhoto,
  senderPrioritySnapshot,
} from "./common";

interface AttraResult {
  outcome:
    | "liked"
    | "matched"
    | "already_liked"
    | "blocked"
    | "insufficient_attras";
  matchId?: string;
  chatId?: string;
}

function hasContent(c: ContextMessageParams): boolean {
  return (
    (c.commentText ?? "").trim().length > 0 ||
    !!c.targetPhotoId ||
    !!(c.targetPromptQuestion ?? "")
  );
}

/// sendAttra: like destacado consumible, opcionalmente sobre una foto y con
/// comentario. Consume 1 Attra (transaccion atomica = sin perdida ni refund
/// manual) y, si hay reciprocidad, crea match con mensaje de apertura.
// minInstances: 1 mantiene la función caliente (sin cold start) en la ruta del
// Attra → el match aparece antes.
export const sendAttra = onCall(
  { region: REGION, minInstances: 1 },
  async (request): Promise<AttraResult> => {
  const fromUid = requireAuthUid(request.auth);
  const toUid = requireStringArg(request.data?.toUid, "toUid");
  if (fromUid === toUid) {
    throw new HttpsError("invalid-argument", "No puedes enviarte un Attra a ti mismo.");
  }

  const isPhoto =
    request.data?.targetType === "photo" &&
    typeof request.data?.targetPhotoId === "string";
  const targetPhotoId = isPhoto ? (request.data.targetPhotoId as string) : null;
  const prompt = parsePromptTarget(request.data);

  const mod = moderateComment(request.data?.commentText);
  if (mod.status === "rejected") {
    throw new HttpsError(
      "invalid-argument",
      mod.reason === "too_long"
        ? "El comentario es demasiado largo."
        : "Este comentario no cumple nuestras normas."
    );
  }

  let photoSnapshotUrl: string | null = null;
  if (isPhoto && targetPhotoId) {
    const resolved = await resolveReceiverPhoto(toUid, targetPhotoId);
    if (!resolved.found) {
      throw new HttpsError("failed-precondition", "Esa foto no esta disponible.");
    }
    photoSnapshotUrl = resolved.url;
  }

  const likeFwdRef = col.likes.doc(directedId(fromUid, toUid));
  const walletRef = col.wallets.doc(fromUid);
  const ledgerRef = col.ledger.doc();
  const attraSendRef = col.attraSends.doc();

  return db.runTransaction(async (tx): Promise<AttraResult> => {
    const [
      toSnap,
      seedSnap,
      blockAB,
      blockBA,
      walletSnap,
      likeFwd,
      likeInv,
      matchSnap,
      entSnap,
      toBoostSnap,
      fromBoostSnap,
    ] =
      await Promise.all([
        tx.get(col.users.doc(toUid)),
        tx.get(db.collection("seed_profiles").doc(toUid)),
        tx.get(col.blocks.doc(directedId(fromUid, toUid))),
        tx.get(col.blocks.doc(directedId(toUid, fromUid))),
        tx.get(walletRef),
        tx.get(likeFwdRef),
        tx.get(col.likes.doc(directedId(toUid, fromUid))),
        tx.get(col.matches.doc(pairId(fromUid, toUid))),
        tx.get(col.entitlements.doc(fromUid)),
        tx.get(col.activeBoosts.doc(toUid)),
        tx.get(col.activeBoosts.doc(fromUid)),
      ]);

    // Comentar es funcion Plus, igual que en sendLike: para Free se descarta el
    // comentario aunque la peticion lo incluya (el Attra en si lo puede enviar
    // cualquiera; lo gateado es el comentario).
    const isFree = (entSnap.data()?.tier ?? "free").toString() === "free";
    const cmtStatus = isFree ? "none" : mod.status;
    const cmtText = cmtStatus === "none" ? null : mod.cleanText;
    const prioritySnapshot = senderPrioritySnapshot(entSnap.data(), "attra");

    if (!isUserContactable(toSnap) && !seedSnap.exists) {
      throw new HttpsError("failed-precondition", "Ese perfil no esta disponible.");
    }
    if (blockAB.exists || blockBA.exists) {
      return { outcome: "blocked" };
    }
    if (matchSnap.exists && (matchSnap.data()?.status ?? "active") === "active") {
      return { outcome: "matched", matchId: matchSnap.id, chatId: matchSnap.id };
    }
    if (
      likeFwd.exists &&
      (likeFwd.data()?.status ?? "active") === "active" &&
      (likeFwd.data()?.type ?? "like") === "attra"
    ) {
      return { outcome: "already_liked" };
    }

    const balance = (walletSnap.data()?.balance ?? 0) as number;
    if (balance < 1) {
      return { outcome: "insufficient_attras" };
    }

    // Consumo transaccional + ledger.
    tx.set(
      walletRef,
      { balance: FieldValue.increment(-1), updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
    tx.set(ledgerRef, {
      uid: fromUid,
      type: "send",
      amount: -1,
      balanceAfter: balance - 1,
      targetUserId: toUid,
      createdAt: FieldValue.serverTimestamp(),
    });

    // Like destacado con foto/comentario.
    tx.set(
      likeFwdRef,
      {
        fromUid,
        toUid,
        type: "attra",
        status: "active",
        ...prioritySnapshot,
        targetType: isPhoto ? "photo" : prompt.isPrompt ? "prompt" : "profile",
        targetPhotoId: isPhoto ? targetPhotoId : null,
        targetPhotoUrlSnapshot: isPhoto ? photoSnapshotUrl : null,
        targetPhotoBlurHash: null,
        targetPhotoDeleted: false,
        targetPromptId: prompt.promptId,
        targetPromptQuestion: prompt.question,
        targetPromptAnswer: prompt.answer,
        commentText: cmtText,
        commentStatus: cmtStatus === "none" ? "none" : "active",
        commentModerationStatus: cmtStatus === "none" ? "approved" : cmtStatus,
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    // Registro de envio de Attra (bandeja del receptor / auditoria).
    tx.set(attraSendRef, {
      fromUid,
      toUid,
      likeId: directedId(fromUid, toUid),
      targetType: isPhoto ? "photo" : prompt.isPrompt ? "prompt" : "profile",
      targetPhotoId: isPhoto ? targetPhotoId : null,
      commentText: cmtText,
      status: "sent",
      createdAt: FieldValue.serverTimestamp(),
    });
    recordBoostLikeReceivedForUser(tx, toUid, toBoostSnap.data());

    const inverseStatus = likeInv.exists ? likeInv.data()?.status ?? "active" : null;
    const inverseActive =
      likeInv.exists && (inverseStatus === "active" || inverseStatus === "matched");

    if (inverseActive) {
      const invData = likeInv.data() ?? {};
      const fwdSpec: ContextMessageParams = {
        chatId: pairId(fromUid, toUid),
        likeId: directedId(fromUid, toUid),
        fromUid,
        toUid,
        likeType: "attra",
        commentText: cmtText,
        targetPhotoId: isPhoto ? targetPhotoId : null,
        targetPhotoUrlSnapshot: isPhoto ? photoSnapshotUrl : null,
        targetPromptQuestion: prompt.question,
      };
      const invSpec: ContextMessageParams = {
        chatId: pairId(fromUid, toUid),
        likeId: directedId(toUid, fromUid),
        fromUid: toUid,
        toUid: fromUid,
        likeType: (invData.type ?? "like") === "attra" ? "attra" : "like",
        commentText: invData.commentText ?? null,
        targetPhotoId: invData.targetPhotoId ?? null,
        targetPhotoUrlSnapshot: invData.targetPhotoUrlSnapshot ?? null,
        targetPromptQuestion: invData.targetPromptQuestion ?? null,
      };

      // El Attra es el opener destacado: su comentario manda como origen.
      const originSpec = hasContent(fwdSpec)
        ? fwdSpec
        : hasContent(invSpec)
        ? invSpec
        : fwdSpec;

      const refs = writeMatchAndChat(tx, {
        uidA: fromUid,
        uidB: toUid,
        createdBy: fromUid,
        action: "attra",
        hasAttra: true,
        attraSenderUid: fromUid,
        origin: {
          originLikeId: originSpec.likeId,
          originTargetType: originSpec.targetPhotoId
            ? "photo"
            : originSpec.targetPromptQuestion
                ? "prompt"
                : "profile",
          originPhotoId: originSpec.targetPhotoId,
          originPhotoUrlSnapshot: originSpec.targetPhotoUrlSnapshot,
          originCommentText: originSpec.commentText,
        },
      });

      writeContextMessage(tx, fwdSpec);
      writeContextMessage(tx, invSpec);
      recordBoostMatchGeneratedForUser(tx, fromUid, fromBoostSnap.data());
      recordBoostMatchGeneratedForUser(tx, toUid, toBoostSnap.data());

      // TODO(Fase 8): push especial "Nuevo match destacado".
      return { outcome: "matched", matchId: refs.matchId, chatId: refs.chatId };
    }

    return { outcome: "liked" };
  });
});
