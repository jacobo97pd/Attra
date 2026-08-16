/**
 * Tests de la marcha atras del feed (functions/src/rewind.ts).
 *
 * COMO SE EJECUTAN (el proyecto no tiene runner de JS: se usa el de Node 20+):
 *
 *   cd functions && npm run build && node --test test/rewind.test.js
 *
 * Se prueban contra la salida COMPILADA (`lib/`) a proposito: es exactamente el
 * codigo que se despliega, y asi el test no necesita ni transpilador ni
 * dependencias nuevas.
 *
 * QUE SE VERIFICA Y POR QUE: las dos decisiones que hacian MENTIR al boton.
 *
 *  1) Deshacer un pase tiene que devolver a "active" el like que esa persona te
 *     habia mandado y que `passProfile` dejo "cancelled". Si no, `sendLike` no
 *     ve like inverso activo y el match ya NO salta nunca: el caso exacto para
 *     el que existe la funcion (rectificar sobre alguien que te dio like) era el
 *     unico que quedaba roto para siempre.
 *  2) Deshacer un like tiene que devolver lo que ese like CONSUMIO (el like del
 *     dia y, si se pago con un Attra Swipe, el swipe). Sin esto, deshacer un
 *     like que habias pagado destruia un consumible de pago, y volver a darlo
 *     cobraba un segundo.
 *
 * Las dos decisiones viven en funciones puras justo para poder fijarlas aqui sin
 * emulador ni red.
 */
const { test } = require("node:test");
const assert = require("node:assert");

const {
  canRestoreCancelledLike,
  refundForLike,
} = require("../lib/rewind.js");

const YO = "uid_yo";
const ELLA = "uid_ella";

test("el like que cancelo MI pase se revive", () => {
  assert.strictEqual(
    canRestoreCancelledLike(
      {
        status: "cancelled",
        cancelledBy: YO,
        cancelReason: "passed_by_recipient",
      },
      YO
    ),
    true
  );
});

test("un like activo no se toca (no hay nada que revivir)", () => {
  assert.strictEqual(
    canRestoreCancelledLike({ status: "active" }, YO),
    false
  );
});

test("un like que cancelo OTRO no es mio para revivirlo", () => {
  assert.strictEqual(
    canRestoreCancelledLike(
      {
        status: "cancelled",
        cancelledBy: ELLA,
        cancelReason: "passed_by_recipient",
      },
      YO
    ),
    false
  );
});

test("cancelado por otro motivo (bloqueo, arrepentimiento del autor) tampoco", () => {
  assert.strictEqual(
    canRestoreCancelledLike(
      { status: "cancelled", cancelledBy: YO, cancelReason: "blocked" },
      YO
    ),
    false
  );
});

test("sin documento no hay nada que restaurar", () => {
  assert.strictEqual(canRestoreCancelledLike(undefined, YO), false);
});

test("un like pagado con swipe devuelve el swipe y el like del dia", () => {
  const refund = refundForLike({ usageKey: "20260816", consumedSwipe: true });
  assert.strictEqual(refund.usageDay, "20260816");
  assert.strictEqual(refund.swipe, true);
});

test("un like normal devuelve el like del dia, pero no un swipe", () => {
  const refund = refundForLike({ usageKey: "20260816", consumedSwipe: false });
  assert.strictEqual(refund.usageDay, "20260816");
  assert.strictEqual(refund.swipe, false);
});

test("el dia se devuelve al contador del like, NO al de hoy", () => {
  // Se deshace hoy un like de ayer: bajar el contador de hoy regalaria un like.
  const refund = refundForLike({ usageKey: "20260101", consumedSwipe: false });
  assert.strictEqual(refund.usageDay, "20260101");
});

test("un like anterior a la marca no toca ningun contador", () => {
  // Docs creados antes de guardar `usageKey`: no se puede saber que dia
  // consumieron, y adivinarlo bajaria el de hoy. No se inventa nada.
  const refund = refundForLike({ createdAt: "cuando fuera" });
  assert.strictEqual(refund.usageDay, null);
  assert.strictEqual(refund.swipe, false);
});
