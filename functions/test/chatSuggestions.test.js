const test = require("node:test");
const assert = require("node:assert");

const {
  shouldOfferSuggestions,
  parseSuggestions,
  buildPrompt,
} = require("../lib/chatSuggestions.js");

const YO = "uid_yo";
const ELLA = "uid_otra";
const AHORA = Date.UTC(2026, 8, 19, 10, 0, 0);
const MIN = 60 * 1000;

function conversacion() {
  return [
    { senderId: YO, text: "Hola, que tal el finde?" },
    { senderId: ELLA, text: "Muy bien, estuve de escalada" },
  ];
}

function oferta(extra) {
  return Object.assign(
    {
      messages: conversacion(),
      myUid: YO,
      lastSuggestedAtMs: null,
      nowMs: AHORA,
    },
    extra
  );
}

test("se ofrece cuando hay algo a lo que responder", () => {
  assert.strictEqual(shouldOfferSuggestions(oferta()), true);
});

// "No siempre, solo alguna": esto es lo que impide que salga en cada pantalla.
test("no se ofrece si el ultimo mensaje es mio", () => {
  const messages = conversacion().concat([{ senderId: YO, text: "Que guay" }]);
  assert.strictEqual(shouldOfferSuggestions(oferta({ messages })), false);
});

test("no se ofrece en un chat vacio", () => {
  assert.strictEqual(shouldOfferSuggestions(oferta({ messages: [] })), false);
});

test("no se ofrece si solo ha hablado una persona", () => {
  const messages = [
    { senderId: ELLA, text: "Hola!" },
    { senderId: ELLA, text: "Que tal?" },
  ];
  assert.strictEqual(shouldOfferSuggestions(oferta({ messages })), false);
});

test("hay enfriamiento entre sugerencias", () => {
  assert.strictEqual(
    shouldOfferSuggestions(oferta({ lastSuggestedAtMs: AHORA - 1 * MIN })),
    false
  );
  assert.strictEqual(
    shouldOfferSuggestions(oferta({ lastSuggestedAtMs: AHORA - 30 * MIN })),
    true
  );
});

test("parseSuggestions quita numeros, guiones y comillas", () => {
  const crudo = [
    '1. "Que fuerte, donde escalas?"',
    "- Yo nunca lo he probado, se te da bien?",
    "* Cuentame mas de eso",
  ].join("\n");
  assert.deepStrictEqual(parseSuggestions(crudo), [
    "Que fuerte, donde escalas?",
    "Yo nunca lo he probado, se te da bien?",
    "Cuentame mas de eso",
  ]);
});

test("parseSuggestions devuelve como mucho tres", () => {
  const crudo = ["una", "dos", "tres", "cuatro", "cinco"].join("\n");
  assert.strictEqual(parseSuggestions(crudo).length, 3);
});

test("parseSuggestions ignora lineas vacias y repetidas", () => {
  const crudo = "Hola\n\n\nhola\n  \nQue tal";
  assert.deepStrictEqual(parseSuggestions(crudo), ["Hola", "Que tal"]);
});

test("parseSuggestions recorta lo que se enrolla", () => {
  const largo = "a".repeat(400);
  const [uno] = parseSuggestions(largo);
  assert.ok(uno.length <= 160, `quedo en ${uno.length}`);
});

test("parseSuggestions aguanta una respuesta vacia del modelo", () => {
  assert.deepStrictEqual(parseSuggestions(""), []);
  assert.deepStrictEqual(parseSuggestions("   \n  \n"), []);
});

// El prompt no puede llevar uids: son identificadores de personas reales y no
// hacen ninguna falta para proponer una respuesta.
test("el prompt etiqueta por lado y no filtra uids", () => {
  const prompt = buildPrompt(conversacion(), YO);
  assert.ok(prompt.includes("YO: Hola, que tal el finde?"));
  assert.ok(prompt.includes("LA OTRA PERSONA: Muy bien, estuve de escalada"));
  assert.ok(!prompt.includes(YO));
  assert.ok(!prompt.includes(ELLA));
});

test("el prompt acota cuantos mensajes se mandan", () => {
  const muchos = [];
  for (let i = 0; i < 40; i++) {
    muchos.push({ senderId: i % 2 ? YO : ELLA, text: `mensaje ${i}` });
  }
  const prompt = buildPrompt(muchos, YO);
  assert.ok(!prompt.includes("mensaje 0"), "no debe mandar la conversacion entera");
  assert.ok(prompt.includes("mensaje 39"), "si debe mandar lo mas reciente");
});

test("el prompt pide el idioma de la conversacion, no uno fijo", () => {
  const prompt = buildPrompt(conversacion(), YO);
  assert.ok(prompt.includes("MISMO idioma"));
});
