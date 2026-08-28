/**
 * Tests del buscador por PROMPT (functions/src/promptMatch.ts).
 *
 * COMO SE EJECUTAN (el proyecto no tiene runner de JS: se usa el de Node 20+):
 *
 *   cd functions && npm run build && node --test test/promptMatch.test.js
 *
 * Se prueban contra la salida COMPILADA (`lib/`) a proposito: es exactamente el
 * codigo que se despliega. Antes habia una replica en Dart
 * (`prompt_match_rules.dart`) con sus tests, pero NINGUN consumidor: se podia
 * cambiar este .ts entero y los tests seguian en verde porque median la copia.
 * La replica se ha borrado; lo que se prueba aqui es lo que corre en produccion.
 *
 * QUE SE VERIFICA Y POR QUE. Los cuatro fallos que hacian que el filtro
 * devolviera lo contrario de lo pedido, todos medidos antes de arreglarlos:
 *
 *  1) DECLARAR DATOS BAJABA LA NOTA. Con "chico alto fuerte majo y amable", un
 *     perfil que solo declaraba el genero puntuaba 0.730 y uno que era
 *     literalmente lo pedido (187cm, musculado) 0.630. La causa: el denominador
 *     eran los campos que cada perfil habia rellenado, no los criterios pedidos.
 *  2) EL GENERO DILUIA EN VEZ DE FILTRAR. Como sumando de una media, pedir
 *     "chica de ojos verdes" dejaba pasar a mujeres de ojos marrones.
 *  3) LA NEGACION SE IGNORABA. "nada de chicos" extraia gender=male y devolvia
 *     justo lo contrario: solo hombres.
 *  4) LA BIO INVENTABA PERSONALIDAD. "me encanta el dulce" contaba como
 *     "majo y amable"; "planes originales" como "creativo".
 */
const { test } = require("node:test");
const assert = require("node:assert");

const {
  extractPromptSignals,
  dataMatch,
  passesDataFilter,
  UNKNOWN_CREDIT,
} = require("../lib/promptMatch.js");

/// Score combinado tal cual lo calcula ai.ts (0.6 visual + 0.4 datos, con
/// neutro 0.5 cuando una parte no es evaluable).
function combined(signals, profile, visual = 0.55) {
  const d = dataMatch(signals, profile).score;
  return 0.6 * visual + 0.4 * (d === null ? 0.5 : d);
}

// -- 1. Extraccion de senales ----------------------------------------------

test("la frase del encargo se entiende entera", () => {
  const s = extractPromptSignals("chico alto fuerte majo y amable");
  assert.strictEqual(s.gender, "male");
  assert.strictEqual(s.heightPref, "tall");
  assert.deepStrictEqual(s.bodyTypes, ["muscular"]);
  // "majo"/"amable" -> empathetic, que es el valor que existe en el catalogo.
  assert.deepStrictEqual(s.personality, ["empathetic"]);
});

test("'chica morena de ojos verdes': pelo Y ojos, cada uno en su sitio", () => {
  const s = extractPromptSignals("chica morena de ojos verdes");
  assert.strictEqual(s.gender, "female");
  assert.deepStrictEqual(s.eyeColors, ["green"]);
  // "morena" = pelo oscuro: castano y negro, que decida el perfil.
  assert.deepStrictEqual(s.hairColors.slice().sort(), ["black", "brown"]);
});

test("un color pegado a 'pelo' no activa el mismo color de ojos", () => {
  const s = extractPromptSignals("chico de pelo negro y ojos claros");
  assert.ok(s.hairColors.includes("black"));
  assert.ok(!s.eyeColors.includes("black"), "la frase NO dice ojos negros");
});

test("NEGACION: 'nada de chicos' no puede pedir chicos", () => {
  const s = extractPromptSignals("nada de chicos");
  assert.strictEqual(
    s.gender,
    "any",
    "se anula la senal; invertirla seria inventarse lo que el usuario quiere"
  );
});

test("NEGACION: 'que no sea un chico bajito' no filtra por genero", () => {
  const s = extractPromptSignals("que no sea un chico bajito");
  assert.strictEqual(s.gender, "any");
});

test("nombrar las dos alturas = sin preferencia", () => {
  // Antes ganaba "alto" por orden de evaluacion y la frase acababa filtrando
  // justo lo que decia no filtrar.
  assert.strictEqual(
    extractPromptSignals("no me importa si es alto o bajo").heightPref,
    "any"
  );
});

test("nombrar los dos generos = sin preferencia", () => {
  const s = extractPromptSignals("me da igual chico o chica, que sea majo");
  assert.strictEqual(s.gender, "any");
  assert.deepStrictEqual(s.personality, ["empathetic"]);
});

test("'trabajo' no activa el filtro de 'bajo'", () => {
  assert.strictEqual(
    extractPromptSignals("que le guste su trabajo").heightPref,
    "any"
  );
});

// -- 2. El genero es un VETO, no un sumando --------------------------------

test("VETO: pedir 'chico' descarta a una mujer aunque cumpla el resto", () => {
  const s = extractPromptSignals("chico alto fuerte majo y amable");
  const m = dataMatch(s, {
    gender: "female",
    heightCm: 190,
    bodyType: "muscular",
    personalityTags: ["empathetic"],
    text: "",
  });
  assert.strictEqual(m.genderMismatch, true);
  assert.strictEqual(passesDataFilter(m), false);
});

test("no declarar genero NO penaliza", () => {
  const s = extractPromptSignals("chico alto");
  const m = dataMatch(s, { heightCm: 190, text: "" });
  assert.strictEqual(m.genderMismatch, false);
  assert.strictEqual(passesDataFilter(m), true);
});

test("el genero no rescata a quien falla lo que SI se pidio", () => {
  // Caso medido: mujer de ojos MARRONES pasaba el filtro de "ojos verdes"
  // porque el genero, como criterio mas de la media, le daba medio punto.
  const s = extractPromptSignals("chica morena de ojos verdes");
  const marrones = dataMatch(s, {
    gender: "female",
    eyeColor: "brown",
    hairColor: "brown",
    text: "",
  });
  assert.strictEqual(passesDataFilter(marrones), false);

  const verdes = dataMatch(s, {
    gender: "female",
    eyeColor: "green",
    hairColor: "brown",
    text: "",
  });
  assert.strictEqual(verdes.score, 1);
  assert.strictEqual(passesDataFilter(verdes), true);
});

// -- 3. Declarar datos NO puede bajar la nota ------------------------------

test("REGRESION: quien cumple lo pedido va por delante de quien no declara nada", () => {
  const s = extractPromptSignals("chico alto fuerte majo y amable");
  const soloGenero = { gender: "male", text: "" };
  const loPedido = {
    gender: "male",
    heightCm: 187,
    bodyType: "muscular",
    personalityTags: ["fun"],
    text: "",
  };
  const a = combined(s, soloGenero);
  const b = combined(s, loPedido);
  assert.ok(
    b > a,
    `el que cumple lo pedido (${b.toFixed(3)}) tiene que ir por delante del ` +
      `que no declara nada (${a.toFixed(3)})`
  );
  // Y el que no declara nada no entra: no hay ni una prueba de que encaje.
  assert.strictEqual(passesDataFilter(dataMatch(s, soloGenero)), false);
  assert.strictEqual(passesDataFilter(dataMatch(s, loPedido)), true);
});

test("un perfil que no declara nada saca exactamente el credito neutro", () => {
  const s = extractPromptSignals("chico alto fuerte majo");
  const m = dataMatch(s, { gender: "male", text: "" });
  assert.strictEqual(m.score, UNKNOWN_CREDIT);
  assert.strictEqual(passesDataFilter(m), false);
});

test("rellenar un campo mas nunca baja el score", () => {
  const s = extractPromptSignals("chico alto fuerte");
  const sinCuerpo = dataMatch(s, { gender: "male", heightCm: 190, text: "" });
  const conCuerpo = dataMatch(s, {
    gender: "male",
    heightCm: 190,
    bodyType: "muscular",
    text: "",
  });
  assert.ok(conCuerpo.score >= sinCuerpo.score);
});

// -- 4. La bio no puede inventar personalidad ------------------------------

test("'me encanta el dulce' NO es 'majo y amable'", () => {
  const s = extractPromptSignals("chico majo y amable");
  const m = dataMatch(s, {
    gender: "male",
    text: "Me encanta el dulce y los planes originales",
  });
  // Sin autodescripcion, la personalidad queda como NO declarada (neutro), no
  // como acierto.
  assert.strictEqual(m.score, UNKNOWN_CREDIT);
  assert.strictEqual(passesDataFilter(m), false);
});

test("'soy muy majo' SI cuenta", () => {
  const s = extractPromptSignals("chico majo y amable");
  const m = dataMatch(s, { gender: "male", text: "Soy muy majo y tranquilo" });
  assert.strictEqual(m.score, 1);
  assert.strictEqual(passesDataFilter(m), true);
});

test("personalityTags declarados mandan sobre la bio", () => {
  const s = extractPromptSignals("chica divertida");
  const m = dataMatch(s, {
    gender: "female",
    personalityTags: ["fun"],
    text: "",
  });
  assert.strictEqual(m.score, 1);
});

// -- 5. Forma REAL del documento de discovery ------------------------------

test("doc de discovery sin hairColor: el pelo cuenta como no declarado", () => {
  // Hasta ahora `hairColor` no se publicaba en discovery, asi que este es el
  // documento que llega para la mayoria de usuarios reales. Lo importante es
  // que "no lo se" NO se convierta en "encaja": una morena no puede salir como
  // resultado perfecto de "chica rubia".
  const s = extractPromptSignals("chica rubia");
  const m = dataMatch(s, { gender: "female", text: "" });
  assert.notStrictEqual(m.score, 1, "no declarar el pelo no puede dar un 10");
  assert.strictEqual(passesDataFilter(m), false);
});

test("con el pelo ya publicado, rubia entra y morena no", () => {
  const s = extractPromptSignals("chica rubia");
  const rubia = dataMatch(s, {
    gender: "female",
    hairColor: "blonde",
    text: "",
  });
  const morena = dataMatch(s, {
    gender: "female",
    hairColor: "brown",
    text: "",
  });
  assert.strictEqual(passesDataFilter(rubia), true);
  assert.strictEqual(passesDataFilter(morena), false);
});

test("los perfiles guardan el valor en espanol o la clave, y ambos casan", () => {
  const s = extractPromptSignals("de ojos verdes");
  const clave = dataMatch(s, { eyeColor: "green", text: "" });
  const espanol = dataMatch(s, { eyeColor: "verdes", text: "" });
  assert.strictEqual(clave.score, espanol.score);
  assert.strictEqual(clave.score, 1);
});

// -- 6. Prompt sin senales -------------------------------------------------

test("un prompt sin senales no filtra a nadie", () => {
  const s = extractPromptSignals("hola que tal");
  const m = dataMatch(s, { gender: "male", text: "" });
  assert.strictEqual(m.score, null);
  assert.strictEqual(passesDataFilter(m), true, "sin criterios no se veta");
});

test("un prompt con SOLO genero no exige nada mas", () => {
  const s = extractPromptSignals("busco un chico");
  const m = dataMatch(s, { gender: "male", text: "" });
  assert.strictEqual(m.score, null);
  assert.strictEqual(passesDataFilter(m), true);
});
