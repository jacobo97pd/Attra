import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { directedId, pairId } from "./ids";
import { writeContextMessage, writeMatchAndChat } from "./match";
import { moderateComment } from "./moderation";
import {
  recordBoostLikeReceivedForUser,
  recordBoostMatchGeneratedForUser,
} from "./boosts";
import {
  FREE_DAILY_LIKES,
  activeEntitlementTier,
  col,
  dailyUsageKey,
  isUserContactable,
  requireAuthUid,
  requireStringArg,
  resolveReceiverPhoto,
  senderPrioritySnapshot,
} from "./common";

/// Tope diario de likes POR TIER.
///
/// QUE FALLABA: el tope solo existia para Free (`FREE_DAILY_LIKES`), asi que
/// Attra Plus tenia likes ILIMITADOS de facto y era indistinguible de Pro en lo
/// unico que de verdad se nota a diario. Ahora Free 25, Plus 100 y Pro/Premium
/// ilimitado, leyendo los topes de `config/featureFlags`.
const DEFAULT_PLUS_DAILY_LIKES = 100;

const FLAGS_CACHE_TTL_MS = 5 * 60 * 1000;
let cachedLikeLimits: {
  value: { free: number; plus: number };
  at: number;
} | null = null;

function flagInt(
  flags: Record<string, unknown>,
  snakeKey: string,
  camelKey: string,
  fallback: number
): number {
  const raw = flags[snakeKey] ?? flags[camelKey];
  if (typeof raw === "number" && Number.isFinite(raw)) return Math.floor(raw);
  if (typeof raw === "string") {
    const parsed = parseInt(raw, 10);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}

/// Lee los topes de `config/featureFlags` con cache en memoria (5 min).
/// `sendLike` es la ruta mas caliente de la app (tiene `minInstances: 1` justo
/// para eso): una lectura extra de Firestore por like solo para releer dos
/// numeros que casi nunca cambian no compensa.
async function dailyLikeLimits(): Promise<{ free: number; plus: number }> {
  const now = Date.now();
  if (cachedLikeLimits && now - cachedLikeLimits.at < FLAGS_CACHE_TTL_MS) {
    return cachedLikeLimits.value;
  }
  let value = { free: FREE_DAILY_LIKES, plus: DEFAULT_PLUS_DAILY_LIKES };
  try {
    const snap = await db.collection("config").doc("featureFlags").get();
    const flags = (snap.data() ?? {}) as Record<string, unknown>;
    const free = flagInt(flags, "free_daily_likes", "freeDailyLikes", FREE_DAILY_LIKES);
    const plus = flagInt(
      flags,
      "plus_daily_likes",
      "plusDailyLikes",
      DEFAULT_PLUS_DAILY_LIKES
    );
    // Un flag a 0/negativo dejaria la app inutilizable (nadie podria dar likes):
    // se ignora y se usa el default.
    value = {
      free: free >= 1 ? free : FREE_DAILY_LIKES,
      plus: plus >= 1 ? plus : DEFAULT_PLUS_DAILY_LIKES,
    };
  } catch {
    // Sin flags se usan los defaults del producto: nunca se bloquea el like.
    value = { free: FREE_DAILY_LIKES, plus: DEFAULT_PLUS_DAILY_LIKES };
  }
  cachedLikeLimits = { value, at: now };
  return value;
}

/// Tope diario del tier. `null` = ilimitado (Pro y el legacy Premium, al que se
/// le dan las ventajas de Pro para que nadie pierda lo que ya tenia).
function dailyLikeLimitForTier(
  tier: string,
  limits: { free: number; plus: number }
): number | null {
  switch (tier) {
    case "pro":
    case "premium":
      return null;
    case "plus":
      return limits.plus;
    default:
      return limits.free;
  }
}

interface FlowResult {
  outcome: "liked" | "matched" | "already_liked" | "blocked" | "limit_reached";
  matchId?: string;
  chatId?: string;
}

/// Spec minimo de un like para construir el mensaje de contexto.
interface LikeSpec {
  likeId: string;
  fromUid: string;
  toUid: string;
  likeType: "like" | "attra";
  commentText: string | null;
  targetPhotoId: string | null;
  targetPhotoUrlSnapshot: string | null;
  targetPromptQuestion?: string | null;
}

function specHasContent(s: LikeSpec): boolean {
  return (
    (s.commentText ?? "").trim().length > 0 ||
    !!s.targetPhotoId ||
    !!(s.targetPromptQuestion ?? "")
  );
}

/// Extrae el objetivo "prompt" de la peticion (pregunta/respuesta snapshot).
export function parsePromptTarget(data: unknown): {
  isPrompt: boolean;
  promptId: string | null;
  question: string | null;
  answer: string | null;
} {
  const d = (data ?? {}) as Record<string, unknown>;
  const isPrompt =
    d.targetType === "prompt" && typeof d.targetPromptQuestion === "string";
  if (!isPrompt) {
    return { isPrompt: false, promptId: null, question: null, answer: null };
  }
  const question = (d.targetPromptQuestion as string).trim().slice(0, 120);
  const answer =
    typeof d.targetPromptAnswer === "string"
      ? (d.targetPromptAnswer as string).trim().slice(0, 200)
      : null;
  const promptId =
    typeof d.targetPromptId === "string" ? (d.targetPromptId as string) : null;
  return { isPrompt: question.length > 0, promptId, question, answer };
}

/// sendLike: intencion unilateral, opcionalmente dirigida a una foto y con
/// comentario. Crea match transaccional si hay reciprocidad y, si el like
/// llevaba comentario/foto, inserta el mensaje de apertura en el chat.
// minInstances mantiene 1 instancia "caliente": evita el cold start (~varios
// segundos) en la ruta crítica del like → la pantalla de match aparece antes.
export const sendLike = onCall(
  { region: REGION, minInstances: 1 },
  async (request): Promise<FlowResult> => {
  const fromUid = requireAuthUid(request.auth);
  const toUid = requireStringArg(request.data?.toUid, "toUid");
  if (fromUid === toUid) {
    throw new HttpsError("invalid-argument", "No puedes darte like a ti mismo.");
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

  // Verifica que la foto pertenece al receptor (fuera de la transaccion).
  let photoSnapshotUrl: string | null = null;
  if (isPhoto && targetPhotoId) {
    const resolved = await resolveReceiverPhoto(toUid, targetPhotoId);
    if (!resolved.found) {
      throw new HttpsError("failed-precondition", "Esa foto no esta disponible.");
    }
    photoSnapshotUrl = resolved.url;
  }

  const likeFwdRef = col.likes.doc(directedId(fromUid, toUid));
  const usageRef = col.users
    .doc(fromUid)
    .collection("usage")
    .doc(`likes_${dailyUsageKey()}`);
  // Fuera de la transaccion: `config/featureFlags` es otro documento y no debe
  // entrar en el bloqueo del like.
  const likeLimits = await dailyLikeLimits();

  return db.runTransaction(async (tx): Promise<FlowResult> => {
    const [
      toSnap,
      seedSnap,
      blockAB,
      blockBA,
      likeFwd,
      likeInv,
      matchSnap,
      entSnap,
      usageSnap,
      toBoostSnap,
      fromBoostSnap,
      fromSnap,
    ] =
      await Promise.all([
        tx.get(col.users.doc(toUid)),
        tx.get(db.collection("seed_profiles").doc(toUid)),
        tx.get(col.blocks.doc(directedId(fromUid, toUid))),
        tx.get(col.blocks.doc(directedId(toUid, fromUid))),
        tx.get(likeFwdRef),
        tx.get(col.likes.doc(directedId(toUid, fromUid))),
        tx.get(col.matches.doc(pairId(fromUid, toUid))),
        tx.get(col.entitlements.doc(fromUid)),
        tx.get(usageRef),
        tx.get(col.activeBoosts.doc(toUid)),
        tx.get(col.activeBoosts.doc(fromUid)),
        tx.get(col.users.doc(fromUid)),
      ]);

    // Destino valido = usuario contactable O perfil semilla (feed de bots).
    if (!isUserContactable(toSnap) && !seedSnap.exists) {
      throw new HttpsError("failed-precondition", "Ese perfil no esta disponible.");
    }
    if (blockAB.exists || blockBA.exists) {
      return { outcome: "blocked" };
    }
    if (matchSnap.exists && (matchSnap.data()?.status ?? "active") === "active") {
      return { outcome: "matched", matchId: matchSnap.id, chatId: matchSnap.id };
    }

    const alreadyLiked =
      likeFwd.exists && (likeFwd.data()?.status ?? "active") === "active";
    const inverseStatus = likeInv.exists ? likeInv.data()?.status ?? "active" : null;
    const inverseActive =
      likeInv.exists && (inverseStatus === "active" || inverseStatus === "matched");

    // Antes se leia `entSnap.data().tier` en crudo: un entitlement de pago
    // CADUCADO seguia contando como Plus/Pro (comentarios en el like y, ahora,
    // tope de likes). `activeEntitlementTier` ya resuelve caducidad y lifetime,
    // y es lo que usa `senderPrioritySnapshot` justo debajo, asi que ademas
    // elimina la incoherencia entre las dos lecturas del mismo dato.
    const tier = activeEntitlementTier(entSnap.data());
    const isFree = tier === "free";
    const prioritySnapshot = senderPrioritySnapshot(entSnap.data(), "like");
    const usageCount = (usageSnap.data()?.count ?? 0) as number;
    // Attra Swipes: si te quedas sin likes diarios (Free o Plus) puedes CONSUMIR
    // un swipe (consumible comprado) para seguir likeando. Si no tienes,
    // limit_reached. Pro/Premium no tienen tope, asi que nunca gastan swipes.
    const dailyLimit = dailyLikeLimitForTier(tier, likeLimits);
    const overDailyLimit =
      !alreadyLiked && dailyLimit !== null && usageCount >= dailyLimit;
    const fromWallet = (fromSnap.data()?.wallet ?? {}) as Record<string, unknown>;
    const swipeBalance = Number(fromWallet.swipes ?? 0);
    let consumeSwipe = false;
    if (overDailyLimit) {
      if (swipeBalance >= 1) {
        consumeSwipe = true;
      } else {
        return { outcome: "limit_reached" };
      }
    }

    // Comentar al dar like es funcion Plus. Para Free se descarta el comentario
    // aunque la peticion lo incluya (defensa de servidor; el cliente ya lo
    // oculta). Asi el gate de monetizacion no depende solo del cliente.
    const cmtStatus = isFree ? "none" : mod.status;
    const cmtText = cmtStatus === "none" ? null : mod.cleanText;

    if (!alreadyLiked) {
      tx.set(
        likeFwdRef,
        {
          fromUid,
          toUid,
          type: "like",
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
      // Si venías de "pasar" (descarte) a esta persona, dar like BORRA ese
      // descarte: no puedes gustarte y pasar a la vez. Habilita la "segunda
      // vuelta" (re-ver los NO) sin dejar estado inconsistente.
      tx.delete(col.dislikes.doc(directedId(fromUid, toUid)));
      tx.set(
        usageRef,
        { count: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() },
        { merge: true }
      );
      // Consume un Attra Swipe si se usó para superar el límite diario del tier.
      if (consumeSwipe) {
        tx.set(
          col.users.doc(fromUid),
          {
            wallet: { swipes: FieldValue.increment(-1) },
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }
      recordBoostLikeReceivedForUser(tx, toUid, toBoostSnap.data());
    }

    if (inverseActive) {
      const fwdData = alreadyLiked
        ? likeFwd.data() ?? {}
        : {
            type: "like",
            commentText: cmtText,
            targetPhotoId: isPhoto ? targetPhotoId : null,
            targetPhotoUrlSnapshot: isPhoto ? photoSnapshotUrl : null,
            targetPromptQuestion: prompt.question,
          };
      const invData = likeInv.data() ?? {};

      const fwdSpec: LikeSpec = {
        likeId: directedId(fromUid, toUid),
        fromUid,
        toUid,
        likeType: (fwdData.type ?? "like") === "attra" ? "attra" : "like",
        commentText: fwdData.commentText ?? null,
        targetPhotoId: fwdData.targetPhotoId ?? null,
        targetPhotoUrlSnapshot: fwdData.targetPhotoUrlSnapshot ?? null,
        targetPromptQuestion: fwdData.targetPromptQuestion ?? null,
      };
      const invSpec: LikeSpec = {
        likeId: directedId(toUid, fromUid),
        fromUid: toUid,
        toUid: fromUid,
        likeType: (invData.type ?? "like") === "attra" ? "attra" : "like",
        commentText: invData.commentText ?? null,
        targetPhotoId: invData.targetPhotoId ?? null,
        targetPhotoUrlSnapshot: invData.targetPhotoUrlSnapshot ?? null,
        targetPromptQuestion: invData.targetPromptQuestion ?? null,
      };

      // Origen del match: preferimos el like original del que respondio (inv).
      const originSpec = specHasContent(invSpec) ? invSpec : fwdSpec;
      const hasAttra = invSpec.likeType === "attra";

      const refs = writeMatchAndChat(tx, {
        uidA: fromUid,
        uidB: toUid,
        createdBy: fromUid,
        action: "like",
        hasAttra,
        attraSenderUid: hasAttra ? toUid : null,
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

      // Mensajes de apertura (idempotentes) para cualquier like con contenido.
      writeContextMessage(tx, { chatId: refs.chatId, ...invSpec });
      writeContextMessage(tx, { chatId: refs.chatId, ...fwdSpec });
      recordBoostMatchGeneratedForUser(tx, fromUid, fromBoostSnap.data());
      recordBoostMatchGeneratedForUser(tx, toUid, toBoostSnap.data());

      // TODO(Fase 8): push "Nuevo match".
      return { outcome: "matched", matchId: refs.matchId, chatId: refs.chatId };
    }

    return { outcome: alreadyLiked ? "already_liked" : "liked" };
  });
});

/// passProfile: descarte unilateral. Idempotente por id determinista.
export const passProfile = onCall({ region: REGION }, async (request) => {
  const fromUid = requireAuthUid(request.auth);
  const toUid = requireStringArg(request.data?.toUid, "toUid");
  if (fromUid === toUid) {
    throw new HttpsError("invalid-argument", "Parametro invalido.");
  }

  const dislikeRef = col.dislikes.doc(directedId(fromUid, toUid));
  const receivedLikeRef = col.likes.doc(directedId(toUid, fromUid));
  await db.runTransaction(async (tx) => {
    const receivedLike = await tx.get(receivedLikeRef);
    tx.set(
      dislikeRef,
      { fromUid, toUid, createdAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
    // Passing from the received-likes inbox is an explicit decline. Marking
    // the inbound intent as cancelled removes it from both users' pending
    // lists while preserving an audit-safe lifecycle record.
    if (
      receivedLike.exists &&
      (receivedLike.data()?.status ?? "active") === "active"
    ) {
      tx.set(
        receivedLikeRef,
        {
          status: "cancelled",
          cancelledAt: FieldValue.serverTimestamp(),
          cancelledBy: fromUid,
          cancelReason: "passed_by_recipient",
        },
        { merge: true }
      );
    }
  });
  return { outcome: "passed" };
});
