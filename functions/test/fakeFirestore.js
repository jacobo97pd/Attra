/**
 * Firestore EN MEMORIA para los tests de functions (sin emulador ni red).
 *
 * No se llama `*.test.js` a proposito: `node --test test/*.test.js` no lo
 * ejecuta como test, solo lo cargan los que lo necesitan.
 *
 * Sustituye (con `mock.method`, que `mock.restoreAll()` deshace) las piezas del
 * Admin SDK que usan los callables y triggers: lecturas/escrituras de
 * documentos, transacciones, batches, `add` y las consultas `where` (==,
 * array-contains, rangos, limit, orderBy por nombre, startAfter). Los
 * centinelas (serverTimestamp,
 * increment...) se guardan tal cual: los tests miran estados, no contadores
 * materializados; para contar escrituras esta el registro `writes`.
 */
const {
  CollectionReference,
  DocumentReference,
  Query,
} = require("firebase-admin/firestore");
const { db } = require("../lib/firebase.js");

function installFakeFirestore(mock, initial = {}) {
  const docs = new Map(
    Object.entries(initial).map(([path, value]) => [path, { ...value }])
  );
  const writes = [];

  const snapOf = (ref) => {
    const value = docs.get(ref.path);
    return {
      ref,
      id: ref.id,
      exists: value !== undefined,
      data: () => (value === undefined ? undefined : { ...value }),
    };
  };

  const apply = (op, ref, value, options) => {
    const path = ref.path;
    writes.push({ op, path, value });
    if (op === "delete") {
      docs.delete(path);
    } else if (op === "create") {
      if (docs.has(path)) {
        const err = new Error(`ALREADY_EXISTS: ${path}`);
        err.code = 6;
        throw err;
      }
      docs.set(path, { ...value });
    } else if (op === "update") {
      if (!docs.has(path)) {
        const err = new Error(`NOT_FOUND: ${path}`);
        err.code = 5;
        throw err;
      }
      docs.set(path, { ...docs.get(path), ...value });
    } else {
      docs.set(
        path,
        options?.merge ? { ...(docs.get(path) ?? {}), ...value } : { ...value }
      );
    }
  };

  mock.method(DocumentReference.prototype, "get", async function () {
    return snapOf(this);
  });
  for (const op of ["set", "update", "delete", "create"]) {
    mock.method(DocumentReference.prototype, op, async function (value, options) {
      apply(op, this, value, options);
    });
  }
  mock.method(CollectionReference.prototype, "add", async function (value) {
    const ref = this.doc();
    apply("create", ref, value);
    return ref;
  });

  // Transaccion: escrituras en cola hasta que termina el callback (como en
  // Firestore, nada se ve a medias si el callback lanza).
  mock.method(db, "runTransaction", async (fn) => {
    const queued = [];
    const tx = {
      get: async (ref) => snapOf(ref),
      getAll: async (...refs) => refs.map(snapOf),
      set: (ref, value, options) => (queued.push(["set", ref, value, options]), tx),
      update: (ref, value) => (queued.push(["update", ref, value]), tx),
      delete: (ref) => (queued.push(["delete", ref]), tx),
      create: (ref, value) => (queued.push(["create", ref, value]), tx),
    };
    const result = await fn(tx);
    for (const [op, ref, value, options] of queued) apply(op, ref, value, options);
    return result;
  });

  mock.method(db, "batch", () => {
    const queued = [];
    const batch = {
      set: (ref, value, options) => (queued.push(["set", ref, value, options]), batch),
      update: (ref, value) => (queued.push(["update", ref, value]), batch),
      delete: (ref) => (queued.push(["delete", ref]), batch),
      commit: async () => {
        for (const [op, ref, value, options] of queued) apply(op, ref, value, options);
      },
    };
    return batch;
  });

  const fieldOf = (data, field) =>
    field.split(".").reduce((v, k) => (v == null ? undefined : v[k]), data);

  // Rangos (>=, <...) sobre Timestamps o numeros: como Firestore, un campo
  // ausente o de otro tipo no casa.
  const comparable = (v) =>
    v && typeof v.toMillis === "function" ? v.toMillis() : typeof v === "number" ? v : null;

  const fakeQuery = (collPath, filters, lim = null, after = null) => ({
    where: (field, op, value) =>
      fakeQuery(collPath, [...filters, [field, op, value]], lim, after),
    limit: (n) => fakeQuery(collPath, filters, n, after),
    // Los resultados ya salen ordenados por ruta (= por __name__).
    orderBy: () => fakeQuery(collPath, filters, lim, after),
    // Acepta un snapshot o, como `orderBy("__name__")`, el id del documento.
    startAfter: (snap) =>
      fakeQuery(
        collPath,
        filters,
        lim,
        typeof snap === "string" ? `${collPath}/${snap}` : snap.ref.path
      ),
    get: async () => {
      const depth = collPath.split("/").length + 1;
      let paths = [...docs.keys()]
        .filter((p) => p.startsWith(`${collPath}/`) && p.split("/").length === depth)
        .filter((p) =>
          filters.every(([field, op, value]) => {
            const v = fieldOf(docs.get(p), field);
            if (op === "==") return v === value;
            if (op === "array-contains") return Array.isArray(v) && v.includes(value);
            if ([">=", ">", "<=", "<"].includes(op)) {
              const a = comparable(v);
              const b = comparable(value);
              if (a === null || b === null) return false;
              if (op === ">=") return a >= b;
              if (op === ">") return a > b;
              if (op === "<=") return a <= b;
              return a < b;
            }
            throw new Error(`operador no soportado en el fake: ${op}`);
          })
        )
        .sort();
      if (after) paths = paths.filter((p) => p > after);
      if (lim !== null) paths = paths.slice(0, lim);
      const found = paths.map((p) => snapOf(db.doc(p)));
      return { empty: found.length === 0, size: found.length, docs: found };
    },
  });
  mock.method(Query.prototype, "where", function (field, op, value) {
    return fakeQuery(this.path, [[field, op, value]]);
  });

  return { docs, writes };
}

module.exports = { installFakeFirestore };
