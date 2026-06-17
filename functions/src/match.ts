import { FieldValue, Transaction } from "firebase-admin/firestore";
import { col } from "./common";
import { directedId, pairId } from "./ids";

export interface MatchOrigin {
  originLikeId?: string | null;
  originTargetType?: "profile" | "photo" | "prompt";
  originPhotoId?: string | null;
  originPhotoUrlSnapshot?: string | null;
  originCommentText?: string | null;
}

export interface CreateMatchParams {
  uidA: string;
  uidB: string;
  /// Quien disparo la accion que cerro el match.
  createdBy: string;
  /// 'like' | 'attra'.
  action: "like" | "attra";
  hasAttra: boolean;
  attraSenderUid?: string | null;
  origin?: MatchOrigin;
}

export interface MatchRefs {
  matchId: string;
  chatId: string;
}

/// Escribe (idempotente) el match y su chat 1:1 dentro de una transaccion, y
/// marca ambos likes como `matched`. NO hace lecturas (deben ir antes en la
/// transaccion del llamante). `chatId == matchId`.
///
/// Usa `merge: true` con ids deterministas: si el doc ya existe no se duplica.
export function writeMatchAndChat(
  tx: Transaction,
  params: CreateMatchParams
): MatchRefs {
  const { uidA, uidB, createdBy, action, hasAttra, attraSenderUid } = params;
  const origin = params.origin ?? {};
  const id = pairId(uidA, uidB);
  // Orden estable de participantes.
  const userA = uidA <= uidB ? uidA : uidB;
  const userB = uidA <= uidB ? uidB : uidA;
  const users = [userA, userB];

  const now = FieldValue.serverTimestamp();

  tx.set(
    col.matches.doc(id),
    {
      users,
      userA,
      userB,
      status: "active",
      createdBy,
      createdByAction: action,
      hasAttra,
      attraSenderUid: attraSenderUid ?? null,
      chatId: id,
      originLikeId: origin.originLikeId ?? null,
      originTargetType: origin.originTargetType ?? "profile",
      originPhotoId: origin.originPhotoId ?? null,
      originPhotoUrlSnapshot: origin.originPhotoUrlSnapshot ?? null,
      originCommentText: origin.originCommentText ?? null,
      createdAt: now,
      updatedAt: now,
    },
    { merge: true }
  );

  tx.set(
    col.chats.doc(id),
    {
      matchId: id,
      users,
      status: "active",
      unreadCountByUser: { [userA]: 0, [userB]: 0 },
      typingByUser: { [userA]: false, [userB]: false },
      hasAttra,
      lastMessage: null,
      lastMessageType: null,
      lastMessageSenderId: null,
      lastMessageAt: null,
      createdAt: now,
      updatedAt: now,
    },
    { merge: true }
  );

  // Marca ambos likes como matched.
  for (const [from, to] of [
    [uidA, uidB],
    [uidB, uidA],
  ]) {
    tx.set(
      col.likes.doc(directedId(from, to)),
      { status: "matched", matchedAt: now },
      { merge: true }
    );
  }

  return { matchId: id, chatId: id };
}

export interface ContextMessageParams {
  chatId: string;
  likeId: string;
  fromUid: string;
  toUid: string;
  likeType: "like" | "attra";
  commentText?: string | null;
  targetPhotoId?: string | null;
  targetPhotoUrlSnapshot?: string | null;
  targetPromptQuestion?: string | null;
}

/// Inserta (idempotente) el mensaje de apertura del chat con el comentario,
/// foto o prompt inicial de un like. Solo escribe si el like llevaba contenido.
/// El id del mensaje es determinista (`ctx_<likeId>`) para no duplicarlo.
export function writeContextMessage(tx: Transaction, p: ContextMessageParams): void {
  const hasComment = (p.commentText ?? "").trim().length > 0;
  const hasPhoto = !!p.targetPhotoId;
  const hasPrompt = !!(p.targetPromptQuestion ?? "");
  if (!hasComment && !hasPhoto && !hasPrompt) return;

  const now = FieldValue.serverTimestamp();
  const messageRef = col.chats
    .doc(p.chatId)
    .collection("messages")
    .doc(`ctx_${p.likeId}`);

  tx.set(
    messageRef,
    {
      senderId: p.fromUid,
      receiverId: p.toUid,
      type: p.likeType === "attra" ? "attra_context" : "like_context",
      text: p.commentText ?? "",
      relatedLikeId: p.likeId,
      relatedPhotoId: p.targetPhotoId ?? null,
      relatedPhotoUrlSnapshot: p.targetPhotoUrlSnapshot ?? null,
      relatedPhotoDeleted: false,
      relatedPromptQuestion: p.targetPromptQuestion ?? null,
      status: "sent",
      createdAt: now,
    },
    { merge: true }
  );

  // Hace de mensaje de apertura visible en la lista de chats.
  const fallback = hasPrompt ? "Respondio a tu pregunta" : "Respondio a tu foto";
  tx.set(
    col.chats.doc(p.chatId),
    {
      lastMessage: hasComment ? p.commentText : fallback,
      lastMessageType: p.likeType === "attra" ? "attra_context" : "like_context",
      lastMessageSenderId: p.fromUid,
      lastMessageAt: now,
      updatedAt: now,
    },
    { merge: true }
  );
}

