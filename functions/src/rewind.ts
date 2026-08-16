import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import {
  activeEntitlementTier,
  col,
  requireAuthUid,
  requireStringArg,
} from "./common";
import { directedId, pairId } from "./ids";

type RewindAction = "like" | "pass";

function requireRewindAction(value: unknown): RewindAction {
  const raw = (value ?? "").toString().trim().toLowerCase();
  if (raw === "like" || raw === "pass") {
    return raw;
  }
  throw new HttpsError("invalid-argument", "Accion de rewind invalida.");
}

function canUseRewind(tier: string): boolean {
  return tier === "plus" || tier === "premium" || tier === "pro";
}

/// ¿Hay que devolver a "active" el like ENTRANTE al deshacer un pase?
///
/// QUE FALLABA: `passProfile` marca como "cancelled" el like que esa persona te
/// habia mandado, y deshacer el pase solo borraba el dislike. El like entrante
/// se quedaba muerto para siempre: `sendLike` solo hace match cuando el like
/// inverso esta "active" o "matched" (likes.ts), asi que al volver a dar like NO
/// saltaba el match, sin ningun aviso, y ella tampoco podia rehacerlo porque yo
/// seguia excluido de su feed. Era justo el caso de uso que vende este boton:
/// rectificar sobre alguien que ya te habia dado like.
///
/// Se exige que lo cancelara ESTE usuario y por ESTE motivo: un like que anulo
/// su propio autor (o un bloqueo) no es nuestro para revivirlo.
export function canRestoreCancelledLike(
  data: Record<string, unknown> | undefined,
  uid: string
): boolean {
  if (!data) return false;
  return (
    (data.status ?? "").toString() === "cancelled" &&
    data.cancelledBy === uid &&
    data.cancelReason === "passed_by_recipient"
  );
}

/// Que consumio el like que se esta deshaciendo, para devolverlo.
export interface RewindRefund {
  /// Dia (`YYYYMMDD`) cuyo contador de likes hay que bajar. `null` = el doc no
  /// lo lleva (like anterior a este cambio): no se toca ningun contador, porque
  /// adivinar el dia bajaria el de HOY y regalaria un like.
  usageDay: string | null;

  /// El like se pago con un Attra Swipe (consumible comprado) y hay que
  /// devolverlo a la cartera.
  swipe: boolean;
}

/// QUE FALLABA: deshacer un like borraba el doc y no devolvia NADA de lo que ese
/// like habia consumido (contador diario y, si el usuario estaba sobre su tope,
/// un Attra Swipe de pago). Encima, volver a dar like a la misma persona lo
/// cobraba OTRA VEZ: dos consumibles destruidos para un unico like. El dano caia
/// justo sobre Plus, que es quien paga por la marcha atras.
export function refundForLike(
  data: Record<string, unknown> | undefined
): RewindRefund {
  const day = data?.usageKey;
  return {
    usageDay: typeof day === "string" && day.length > 0 ? day : null,
    swipe: data?.consumedSwipe === true,
  };
}

/// rewindFeedAction: deshace el ultimo gesto de feed para perfiles no
/// matcheados. Free no puede; Plus/Premium lo limita la UI a un paso; Pro guarda
/// historial ilimitado en la sesion. En servidor bloqueamos Free y matches.
///
/// Todo el deshacer va en UNA transaccion: borrar el gesto, devolver lo que
/// consumio y revivir el like entrante son un solo hecho. Si se hicieran por
/// separado, un fallo a mitad dejaria al usuario sin like y sin swipe, o con el
/// pase deshecho y el like de la otra persona muerto.
export const rewindFeedAction = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const targetUid = requireStringArg(request.data?.targetUid, "targetUid");
  const action = requireRewindAction(request.data?.action);
  if (uid === targetUid) {
    throw new HttpsError("invalid-argument", "Parametro invalido.");
  }

  const entSnap = await col.entitlements.doc(uid).get();
  const tier = activeEntitlementTier(entSnap.data());
  if (!canUseRewind(tier)) {
    throw new HttpsError(
      "permission-denied",
      "Volver atras es una funcion Plus y Pro.",
    );
  }

  const ref =
    action === "pass"
      ? col.dislikes.doc(directedId(uid, targetUid))
      : col.likes.doc(directedId(uid, targetUid));
  const matchRef = col.matches.doc(pairId(uid, targetUid));
  const inboundRef = col.likes.doc(directedId(targetUid, uid));

  return db.runTransaction(async (tx) => {
    const [snap, matchSnap] = await Promise.all([
      tx.get(ref),
      tx.get(matchRef),
    ]);
    if (matchSnap.exists && (matchSnap.data()?.status ?? "active") === "active") {
      throw new HttpsError(
        "failed-precondition",
        "No se puede deshacer un match ya creado.",
      );
    }
    // No hay nada registrado: se contesta `rewound: false` para que el cliente
    // NO le cobre al usuario su marcha atras por un no-op.
    if (!snap.exists) {
      return { ok: true, rewound: false };
    }

    const data = snap.data() ?? {};
    if (data.fromUid !== uid || data.toUid !== targetUid) {
      throw new HttpsError(
        "permission-denied",
        "No puedes deshacer esta accion.",
      );
    }

    if (action === "pass") {
      const inbound = await tx.get(inboundRef);
      tx.delete(ref);
      if (canRestoreCancelledLike(inbound.data(), uid)) {
        tx.set(
          inboundRef,
          {
            status: "active",
            // Se limpian las marcas de la cancelacion en vez de dejarlas: un
            // like "active" con `cancelledAt` puesto es un documento que miente
            // sobre su propio ciclo de vida.
            cancelledAt: FieldValue.delete(),
            cancelledBy: FieldValue.delete(),
            cancelReason: FieldValue.delete(),
          },
          { merge: true },
        );
        // NO se crea el match aqui a proposito: para que el par estuviera
        // mutuamente activo, `sendLike` ya lo habria creado en su momento (y
        // entonces este rewind se habria rechazado arriba). Con el like entrante
        // ya "active", el siguiente like del usuario SI hace match, que es lo
        // que el boton promete.
      }
      return { ok: true, rewound: true };
    }

    if ((data.type ?? "like").toString() === "attra") {
      throw new HttpsError(
        "failed-precondition",
        "Los Attras enviados no se pueden deshacer.",
      );
    }
    if ((data.status ?? "active").toString() === "matched") {
      throw new HttpsError(
        "failed-precondition",
        "No se puede deshacer un like que ya hizo match.",
      );
    }

    const refund = refundForLike(data);
    const usageRef = refund.usageDay
      ? col.users
          .doc(uid)
          .collection("usage")
          .doc(`likes_${refund.usageDay}`)
      : null;
    // Ultima lectura antes de escribir (en una transaccion todas las lecturas
    // van antes que las escrituras).
    const usageSnap = usageRef ? await tx.get(usageRef) : null;

    tx.delete(ref);
    if (usageRef && usageSnap) {
      // Se escribe el valor leido menos uno en vez de `increment(-1)`: el
      // incremento atomico no tiene suelo y un contador negativo regalaria likes
      // el resto del dia. La transaccion ya protege de la carrera.
      const count = Number(usageSnap.data()?.count ?? 0);
      if (count > 0) {
        tx.set(
          usageRef,
          { count: count - 1, updatedAt: FieldValue.serverTimestamp() },
          { merge: true },
        );
      }
    }
    if (refund.swipe) {
      tx.set(
        col.users.doc(uid),
        {
          wallet: { swipes: FieldValue.increment(1) },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    return { ok: true, rewound: true };
  });
});
