// Utilidades de test: firmar JWS "de la App Store" con una PKI FALSA que tiene
// la misma forma que la de Apple (ver fixtures/storekit-test-pki.json). Asi se
// prueba la verificacion de verdad (cadena, OID, firma) sin depender de un
// recibo real ni de red.
const crypto = require("node:crypto");
const path = require("node:path");
const fs = require("node:fs");

const PKI = JSON.parse(
  fs.readFileSync(path.join(__dirname, "..", "fixtures", "storekit-test-pki.json"), "utf8")
);

function derB64(pem) {
  return new crypto.X509Certificate(pem).raw.toString("base64");
}

const TEST_ROOT_DER = new crypto.X509Certificate(PKI.good.root).raw;

/// Firma [payload] como lo haria StoreKit 2. `chain` elige la cadena:
///  - "good": raiz de test (la que se pasa como confianza en los tests)
///  - "rogue": otra raiz con la misma forma (NO es de confianza)
///  - "noOid": hoja buena pero sin el OID de StoreKit
function signJws(payload, { chain = "good", alg = "ES256", x5c } = {}) {
  let leafPem;
  let keyPem;
  let intermediatePem;
  let rootPem;
  if (chain === "noOid") {
    leafPem = PKI.noOidLeaf.leaf;
    keyPem = PKI.noOidLeaf.leafKey;
    intermediatePem = PKI.good.intermediate;
    rootPem = PKI.good.root;
  } else {
    const c = PKI[chain];
    leafPem = c.leaf;
    keyPem = c.leafKey;
    intermediatePem = c.intermediate;
    rootPem = c.root;
  }
  const header = {
    alg,
    x5c: x5c ?? [derB64(leafPem), derB64(intermediatePem), derB64(rootPem)],
  };
  const h = Buffer.from(JSON.stringify(header)).toString("base64url");
  const p = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const signature = crypto.sign("sha256", Buffer.from(`${h}.${p}`), {
    key: crypto.createPrivateKey(keyPem),
    dsaEncoding: "ieee-p1363",
  });
  return `${h}.${p}.${signature.toString("base64url")}`;
}

/// Transaccion de StoreKit 2 con valores por defecto razonables.
function appleTransaction(extra = {}) {
  const now = Date.now();
  return Object.assign(
    {
      transactionId: "2000000111111111",
      originalTransactionId: "2000000111111111",
      bundleId: "com.jpedrero.attra",
      productId: "attra_pro_monthly",
      purchaseDate: now - 60 * 1000,
      expiresDate: now + 30 * 24 * 60 * 60 * 1000,
      type: "Auto-Renewable Subscription",
      environment: "Sandbox",
      quantity: 1,
      signedDate: now,
    },
    extra
  );
}

module.exports = { PKI, TEST_ROOT_DER, signJws, appleTransaction, derB64 };
