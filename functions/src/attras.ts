import { onCall, HttpsError } from "firebase-functions/v2/https";
import { createHash } from "node:crypto";
import {
  DocumentReference,
  FieldValue,
  Transaction,
} from "firebase-admin/firestore";
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

/// De donde sale el gasto. Solo para auditoria del ledger: el cobro es el mismo.
export type AttraSpendSource = "attra_send" | "story_reply";

/// Estado del monedero leido DENTRO de la transaccion y listo para gastar.
///
/// Se parte en dos (leer / cobrar) porque Firestore exige TODAS las lecturas de
/// una transaccion antes de la primera escritura, y quien cobra normalmente
/// tiene que leer otras cosas (like inverso, match, entitlement) en el mismo
/// bloque.
export interface AttraSpendState {
  uid: string;
  /// Saldo autoritativo (`attraWallets`), no el espejo de `users`.
  balance: number;
  /// Este MISMO gasto ya se cobro (mismo `spendKey`): reintento del usuario o
  /// reenvio del cliente. Ni se vuelve a cobrar ni se rechaza la accion.
  alreadyCharged: boolean;
  /// Se puede seguir adelante: hay saldo, o ya estaba pagado.
  canSpend: boolean;
  walletRef: DocumentReference;
  ledgerRef: DocumentReference;
}

/// El saldo de Attras vive en TRES sitios que hay que mover a la vez:
///   1. `attraWallets/{uid}.balance` — autoritativo, el que decide si hay saldo.
///   2. `users/{uid}.attrasBalance` — espejo, de donde lo lee la app.
///   3. `attraLedger/{id}` — apunte auditable del gasto.
/// Tocar solo uno los desincroniza: ya paso (las rutas de abono escribian el
/// espejo y las de gasto no, asi que el numero que veia el usuario no bajaba
/// nunca). Por eso el gasto pasa SIEMPRE por `readAttraSpend` +
/// `commitAttraSpend` en vez de copiar el bloque: `replyToStory` se copio a
/// medias y acabo regalando Attras (escribia el like de tipo "attra" sin mirar
/// el monedero ni descontar nada).
///
/// `spendKey` = clave logica de la accion que se cobra (p.ej. "esta story, este
/// usuario"). Si se pasa, el apunte del ledger lleva id determinista y un
/// segundo intento se detecta como `alreadyCharged`. `sendAttra` NO la usa a
/// proposito: alli el doble cobro ya lo corta el propio like (el segundo envio
/// ve un like "attra" activo y sale por `already_liked`), y una clave por par
/// haria gratis el Attra de quien vuelve a intentarlo despues de que le
/// cancelaran el like.
export async function readAttraSpend(
  tx: Transaction,
  uid: string,
  spendKey: string | null = null
): Promise<AttraSpendState> {
  const walletRef = col.wallets.doc(uid);
  const ledgerRef = spendKey
    ? col.ledger.doc(
        `spend_${createHash("sha256").update(spendKey).digest("hex")}`
      )
    : col.ledger.doc();
  const [walletSnap, ledgerSnap] = await Promise.all([
    tx.get(walletRef),
    spendKey ? tx.get(ledgerRef) : Promise.resolve(null),
  ]);
  const balance = Number(walletSnap.data()?.balance ?? 0);
  const alreadyCharged = ledgerSnap?.exists === true;
  return {
    uid,
    balance,
    alreadyCharged,
    canSpend: alreadyCharged || balance >= 1,
    walletRef,
    ledgerRef,
  };
}

/// Descuenta 1 Attra escribiendo los tres sitios. No-op si ya estaba cobrado.
/// El `canSpend` lo comprueba quien llama (para poder devolver
/// "insufficient_attras" sin abortar la transaccion); aqui solo queda la red de
/// seguridad para que un fallo de orden nunca deje saldo negativo.
export function commitAttraSpend(
  tx: Transaction,
  spend: AttraSpendState,
  params: {
    targetUid: string;
    source: AttraSpendSource;
    relatedStoryId?: string | null;
  }
): void {
  if (spend.alreadyCharged) return;
  if (spend.balance < 1) {
    throw new HttpsError("failed-precondition", "No te quedan Attras.");
  }

  const now = FieldValue.serverTimestamp();
  tx.set(
    spend.walletRef,
    { balance: FieldValue.increment(-1), updatedAt: now },
    { merge: true }
  );
  tx.set(
    col.users.doc(spend.uid),
    { attrasBalance: Math.max(0, spend.balance - 1), updatedAt: now },
    { merge: true }
  );
  tx.set(spend.ledgerRef, {
    uid: spend.uid,
    type: "send",
    amount: -1,
    balanceAfter: spend.balance - 1,
    targetUserId: params.targetUid,
    source: params.source,
    relatedStoryId: params.relatedStoryId ?? null,
    createdAt: now,
  });
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
  const attraSendRef = col.attraSends.doc();

  return db.runTransaction(async (tx): Promise<AttraResult> => {
    const [
      toSnap,
      seedSnap,
      blockAB,
      blockBA,
      spend,
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
        readAttraSpend(tx, fromUid),
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

    if (!spend.canSpend) {
      return { outcome: "insufficient_attras" };
    }

    // Consumo transaccional + ledger (monedero, espejo y apunte a la vez).
    commitAttraSpend(tx, spend, { targetUid: toUid, source: "attra_send" });

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
