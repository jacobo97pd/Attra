import { onCall, HttpsError } from "firebase-functions/v2/https";
import { REGION } from "./firebase";
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

/// rewindFeedAction: deshace el ultimo gesto de feed para perfiles no
/// matcheados. Free no puede; Plus/Premium lo limita la UI a un paso; Pro guarda
/// historial ilimitado en la sesion. En servidor bloqueamos Free y matches.
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

  const matchSnap = await col.matches.doc(pairId(uid, targetUid)).get();
  if (matchSnap.exists && (matchSnap.data()?.status ?? "active") === "active") {
    throw new HttpsError(
      "failed-precondition",
      "No se puede deshacer un match ya creado.",
    );
  }

  const ref =
    action === "pass"
      ? col.dislikes.doc(directedId(uid, targetUid))
      : col.likes.doc(directedId(uid, targetUid));
  const snap = await ref.get();
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
  if (action === "like") {
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
  }

  await ref.delete();
  return { ok: true, rewound: true };
});
