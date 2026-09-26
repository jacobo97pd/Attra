const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");

const {
  APPLE_ROOT_CA_G3_BASE64,
  APPLE_ROOT_CA_G3_SHA256,
  AppleJwsError,
  looksLikeJws,
  parseAppleTransaction,
  sha256Hex,
  verifyAppleSignedPayload,
} = require("../lib/storeApple.js");
const { TEST_ROOT_DER, signJws, appleTransaction, PKI, derB64 } = require(
  "./helpers/storekit.js"
);

const TRUST_TEST_ROOT = { trustedRootsDer: [TEST_ROOT_DER] };

function codeOf(fn) {
  try {
    fn();
  } catch (error) {
    assert.ok(error instanceof AppleJwsError, `esperaba AppleJwsError: ${error}`);
    return error.code;
  }
  assert.fail("debia rechazar el JWS");
}

// El ancla de confianza tiene que ser la raiz REAL de Apple. Si alguien la
// cambia (o la pega mal), todo recibo de iOS se rechazaria o, peor, se
// aceptaria cualquier cosa firmada por otra raiz.
test("la raiz fijada es Apple Root CA - G3 (huella publicada por Apple)", () => {
  const der = Buffer.from(APPLE_ROOT_CA_G3_BASE64, "base64");
  assert.equal(sha256Hex(der), APPLE_ROOT_CA_G3_SHA256);
  assert.equal(
    APPLE_ROOT_CA_G3_SHA256,
    "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179"
  );
  const cert = new crypto.X509Certificate(der);
  assert.match(cert.subject, /CN=Apple Root CA - G3/);
  assert.equal(cert.ca, true);
});

test("un JWS con cadena valida devuelve su payload", () => {
  const payload = appleTransaction({ productId: "attra_plus_monthly" });
  const out = verifyAppleSignedPayload(signJws(payload), TRUST_TEST_ROOT);
  assert.equal(out.productId, "attra_plus_monthly");
  assert.equal(out.transactionId, payload.transactionId);
});

test("sin sobrescribir la raiz, solo vale la de Apple (la de test no)", () => {
  assert.equal(
    codeOf(() => verifyAppleSignedPayload(signJws(appleTransaction()))),
    "untrusted_chain"
  );
});

test("una raiz fabricada con la misma forma no vale", () => {
  assert.equal(
    codeOf(() =>
      verifyAppleSignedPayload(signJws(appleTransaction(), { chain: "rogue" }), TRUST_TEST_ROOT)
    ),
    "untrusted_chain"
  );
});

test("colar la raiz buena al final de una cadena ajena no vale", () => {
  const jws = signJws(appleTransaction(), {
    chain: "rogue",
    x5c: [derB64(PKI.rogue.leaf), derB64(PKI.rogue.intermediate), derB64(PKI.good.root)],
  });
  assert.equal(codeOf(() => verifyAppleSignedPayload(jws, TRUST_TEST_ROOT)), "untrusted_chain");
});

test("una hoja sin el OID de StoreKit no vale aunque encadene", () => {
  assert.equal(
    codeOf(() =>
      verifyAppleSignedPayload(signJws(appleTransaction(), { chain: "noOid" }), TRUST_TEST_ROOT)
    ),
    "untrusted_chain"
  );
});

test("tocar el payload rompe la firma", () => {
  const jws = signJws(appleTransaction({ productId: "attra_plus_monthly" }));
  const [h, , s] = jws.split(".");
  const forged = Buffer.from(
    JSON.stringify(appleTransaction({ productId: "attra_pro_yearly" }))
  ).toString("base64url");
  assert.equal(
    codeOf(() => verifyAppleSignedPayload(`${h}.${forged}.${s}`, TRUST_TEST_ROOT)),
    "bad_signature"
  );
});

test("alg distinto de ES256 (p. ej. none) se rechaza", () => {
  assert.equal(
    codeOf(() =>
      verifyAppleSignedPayload(signJws(appleTransaction(), { alg: "none" }), TRUST_TEST_ROOT)
    ),
    "malformed"
  );
});

test("basura y recibos de StoreKit 1 se rechazan como mal formados", () => {
  assert.equal(codeOf(() => verifyAppleSignedPayload("x", TRUST_TEST_ROOT)), "malformed");
  assert.equal(codeOf(() => verifyAppleSignedPayload("a.b.c", TRUST_TEST_ROOT)), "malformed");
  assert.equal(looksLikeJws("MIIT0gYJKoZIhvcNAQcCoIIT"), false);
  assert.equal(looksLikeJws(signJws(appleTransaction())), true);
});

test("certificados fuera de validez en la fecha de firma se rechazan", () => {
  const jws = signJws(appleTransaction({ signedDate: Date.UTC(2020, 0, 1) }));
  assert.equal(
    codeOf(() => verifyAppleSignedPayload(jws, TRUST_TEST_ROOT)),
    "cert_not_valid_at_date"
  );
});

test("parseAppleTransaction saca los campos que usa el backend", () => {
  const t = parseAppleTransaction(
    appleTransaction({
      transactionId: 555,
      originalTransactionId: "444",
      expiresDate: 1234,
      revocationDate: 99,
      quantity: 2,
    })
  );
  assert.equal(t.transactionId, "555");
  assert.equal(t.originalTransactionId, "444");
  assert.equal(t.expiresDateMs, 1234);
  assert.equal(t.revocationDateMs, 99);
  assert.equal(t.quantity, 2);
  assert.throws(() => parseAppleTransaction({ productId: "x" }), AppleJwsError);
});
