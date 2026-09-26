// Firestore EN MEMORIA para probar las callables de compra de punta a punta
// (validacion -> ledger -> entitlement/saldo) sin emulador ni red.
//
// Solo cubre lo que usan esas rutas: `runTransaction` con get/set y la lectura
// de `config/featureFlags`. Las referencias son las REALES del Admin SDK (sus
// `path` son los de produccion), asi que los tests ven los mismos documentos
// que escribiria el codigo de verdad.
const { mock } = require("node:test");
const { db } = require("../../lib/firebase.js");

function installMemoryDb({ docs: initial = {}, flags = {} } = {}) {
  const docs = new Map(Object.entries(initial));
  const realCollection = db.collection.bind(db);
  mock.method(db, "collection", (name) => {
    if (name === "config") {
      return {
        doc: () => ({
          get: async () => ({ exists: true, data: () => flags }),
        }),
      };
    }
    return realCollection(name);
  });
  const snapshot = (ref) => {
    const data = docs.get(ref.path);
    return {
      ref,
      id: ref.id,
      exists: data !== undefined,
      data: () => data,
      get: (field) => (data === undefined ? undefined : data[field]),
    };
  };
  let transactions = 0;
  mock.method(db, "runTransaction", async (fn) => {
    transactions += 1;
    const tx = {
      get: async (ref) => snapshot(ref),
      set: (ref, value, options) => {
        const previous = docs.get(ref.path);
        docs.set(
          ref.path,
          options && options.merge ? { ...(previous ?? {}), ...value } : value
        );
        return tx;
      },
    };
    return fn(tx);
  });
  return {
    docs,
    get: (path) => docs.get(path),
    transactions: () => transactions,
  };
}

module.exports = { installMemoryDb };
