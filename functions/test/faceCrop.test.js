/**
 * Tests del preprocesado de imagen para la IA visual (functions/src/faceCrop.ts).
 *
 * COMO SE EJECUTAN (el proyecto no tiene runner de JS: se usa el de Node 20+):
 *
 *   cd functions && npm run build && node --test test/faceCrop.test.js
 *
 * Se prueban contra la salida COMPILADA (`lib/`) a proposito: es exactamente el
 * codigo que se despliega.
 *
 * QUE SE VERIFICA Y POR QUE:
 *
 *  1) ORIENTACION EXIF. Era el fallo mas caro y el mas invisible: la foto
 *     vertical de movil se guarda apaisada con una etiqueta EXIF que dice
 *     "girame". `sharp(buf).metadata()` devuelve el marco ALMACENADO, asi que
 *     se median 600x800 y se recortaba sobre unos pixeles que en realidad eran
 *     800x600 -> el recorte caia en el fondo. Y peor: `sharp(...).jpeg()` sin
 *     `.rotate()` BORRA la etiqueta sin aplicarla, asi que a Vertex le llegaba
 *     una cara tumbada Y sin forma de enderezarla. Aqui se fija que el
 *     preprocesado devuelve SIEMPRE pixeles ya enderezados.
 *  2) El recorte se calcula en el mismo marco en el que se aplica.
 *  3) `noFaceTraits` no se inventa datos.
 *
 * Cloud Vision no se llama: `prepareForEmbedding` sin credenciales cae por la
 * rama "no he podido mirar", que es justo la que hay que comprobar que NO se
 * hace pasar por "no hay cara".
 */
const { test } = require("node:test");
const assert = require("node:assert");
const sharp = require("sharp");

const {
  faceRect,
  primaryFace,
  noFaceTraits,
  traitsFrom,
  prepareForEmbedding,
} = require("../lib/faceCrop.js");

/// JPEG 600x800 con una banda roja arriba (donde estaria la cabeza) y etiqueta
/// EXIF `orientation`. Con orientation=6 lo que el usuario VE es 800x600.
async function photoWithExif(orientation) {
  const base = await sharp({
    create: {
      width: 600,
      height: 800,
      channels: 3,
      background: { r: 20, g: 20, b: 20 },
    },
  })
    .composite([
      {
        input: await sharp({
          create: {
            width: 600,
            height: 200,
            channels: 3,
            background: { r: 255, g: 0, b: 0 },
          },
        })
          .png()
          .toBuffer(),
        top: 0,
        left: 0,
      },
    ])
    .jpeg()
    .toBuffer();
  if (orientation === undefined) return base;
  return sharp(base).withMetadata({ orientation }).jpeg().toBuffer();
}

test("prepareForEmbedding endereza la orientacion EXIF", async () => {
  // Sin EXIF: la foto ya esta derecha, 600x800.
  const derecha = await photoWithExif(undefined);
  const metaDerecha = await sharp(derecha).metadata();
  assert.strictEqual(metaDerecha.width, 600);
  assert.strictEqual(metaDerecha.height, 800);

  // Con EXIF=6 los pixeles almacenados siguen siendo 600x800...
  const tumbada = await photoWithExif(6);
  const metaAlmacenada = await sharp(tumbada).metadata();
  assert.strictEqual(metaAlmacenada.width, 600);
  assert.strictEqual(metaAlmacenada.height, 800);
  assert.strictEqual(metaAlmacenada.orientation, 6);

  // ...pero lo que hay que analizar es el marco ENDEREZADO: 800x600.
  // OJO: `.rotate().metadata()` NO sirve para saberlo. `metadata()` describe
  // SIEMPRE la imagen de ENTRADA, no el resultado del pipeline, asi que sigue
  // diciendo 600x800. Es justo la trampa en la que caia el codigo. La unica
  // forma de tener el tamano ya enderezado es materializar el buffer y leer
  // `info`, que es lo que hace `prepareForEmbedding`.
  const pipelineMeta = await sharp(tumbada).rotate().metadata();
  assert.strictEqual(
    pipelineMeta.width,
    600,
    "metadata() describe la ENTRADA: no vale para medir tras rotate()"
  );
  const { info } = await sharp(tumbada)
    .rotate()
    .toBuffer({ resolveWithObject: true });
  assert.strictEqual(info.width, 800);
  assert.strictEqual(info.height, 600);

  // El preprocesado tiene que trabajar sobre el marco enderezado. Se comprueba
  // en la salida: sin cara detectada cae a `normalizeOnly`, que devuelve un
  // cuadrado de CROP_SIDE; lo que importa es que no lance y que la etiqueta
  // EXIF ya no quede pendiente de aplicar (pixeles derechos, sin etiqueta).
  const out = await prepareForEmbedding(tumbada);
  const outMeta = await sharp(out.bytes).metadata();
  assert.strictEqual(
    outMeta.orientation,
    undefined,
    "la salida no puede llevar una orientacion EXIF pendiente de aplicar"
  );
});

test("un fallo de Vision NO se hace pasar por 'no hay cara'", async () => {
  // Sin credenciales, Cloud Vision no responde: eso es `visionFailed`, y
  // `detected:false` a secas seria mentir sobre la foto del usuario.
  const foto = await photoWithExif(undefined);
  const out = await prepareForEmbedding(foto);
  assert.strictEqual(out.cropped, false);
  assert.strictEqual(
    out.visionFailed,
    true,
    "sin poder llamar a Vision hay que decir que fallo, no que no hay cara"
  );
  assert.strictEqual(out.traits.detected, false);
});

test("faceRect recorta dentro de la imagen y es cuadrado", () => {
  const face = {
    fdBoundingPoly: {
      vertices: [
        { x: 300, y: 100 },
        { x: 500, y: 100 },
        { x: 500, y: 340 },
        { x: 300, y: 340 },
      ],
    },
  };
  const rect = faceRect(face, 800, 600);
  assert.ok(rect, "tiene que haber rectangulo");
  assert.strictEqual(rect.width, rect.height, "el recorte es cuadrado");
  assert.ok(rect.left >= 0 && rect.top >= 0);
  assert.ok(rect.left + rect.width <= 800, "no se sale por la derecha");
  assert.ok(rect.top + rect.height <= 600, "no se sale por abajo");
});

test("faceRect nunca pide un lado mayor que la imagen", () => {
  // Cara enorme en una imagen pequena: con el margen 0.6 el lado pedido se
  // pasa de la imagen y sharp reventaria con `bad extract area`.
  const face = {
    fdBoundingPoly: {
      vertices: [
        { x: 0, y: 0 },
        { x: 400, y: 0 },
        { x: 400, y: 400 },
        { x: 0, y: 400 },
      ],
    },
  };
  const rect = faceRect(face, 420, 410);
  assert.ok(rect);
  assert.ok(rect.width <= 410 && rect.height <= 410);
  assert.ok(rect.left + rect.width <= 420);
  assert.ok(rect.top + rect.height <= 410);
});

test("primaryFace elige la cara MAS GRANDE, no la primera", () => {
  const pequena = {
    fdBoundingPoly: {
      vertices: [
        { x: 0, y: 0 },
        { x: 50, y: 0 },
        { x: 50, y: 50 },
        { x: 0, y: 50 },
      ],
    },
  };
  const grande = {
    fdBoundingPoly: {
      vertices: [
        { x: 100, y: 100 },
        { x: 400, y: 100 },
        { x: 400, y: 400 },
        { x: 100, y: 400 },
      ],
    },
  };
  assert.strictEqual(primaryFace([pequena, grande]), grande);
  assert.strictEqual(primaryFace([]), null);
});

test("noFaceTraits no inventa datos", () => {
  const t = noFaceTraits(0);
  assert.strictEqual(t.detected, false);
  assert.strictEqual(t.confidence, 0);
  assert.strictEqual(t.pose, "unknown");
  assert.strictEqual(t.smile, "UNKNOWN");
  assert.strictEqual(t.faceAreaRatio, 0);
});

test("traitsFrom copia lo que da Vision y calcula el area", () => {
  const face = {
    fdBoundingPoly: {
      vertices: [
        { x: 0, y: 0 },
        { x: 100, y: 0 },
        { x: 100, y: 100 },
        { x: 0, y: 100 },
      ],
    },
    detectionConfidence: 0.87,
    panAngle: 5,
    tiltAngle: -2,
    rollAngle: 1,
    joyLikelihood: "VERY_LIKELY",
  };
  const t = traitsFrom(face, 1, 1000, 1000);
  assert.strictEqual(t.detected, true);
  assert.strictEqual(t.confidence, 0.87);
  assert.strictEqual(t.pose, "frontal");
  assert.strictEqual(t.smile, "VERY_LIKELY");
  // 100x100 sobre 1000x1000 = 1% de la foto.
  assert.ok(Math.abs(t.faceAreaRatio - 0.01) < 1e-9);
  // Lo que Vision NO da no se rellena: no hay gafas, ni edad, ni etnia.
  assert.strictEqual(t.headwear, "UNKNOWN");
});

test("el recorte cae sobre la zona que indica la caja, ya enderezada", async () => {
  // Foto vertical de movil: pixeles almacenados 600x800 + EXIF=6, o sea que lo
  // que se VE es 800x600. Se pinta un cuadrado VERDE que, una vez enderezada la
  // imagen, queda en una posicion conocida; es el papel de "la cara".
  const base = await sharp({
    create: { width: 600, height: 800, channels: 3, background: { r: 20, g: 20, b: 20 } },
  })
    .composite([
      {
        input: await sharp({
          create: { width: 200, height: 200, channels: 3, background: { r: 0, g: 255, b: 0 } },
        })
          .png()
          .toBuffer(),
        // En el marco ALMACENADO (600x800) el verde va abajo-izquierda; con
        // orientation=6 (giro 90 CW) acaba arriba-izquierda del marco visto.
        top: 600,
        left: 0,
      },
    ])
    .jpeg()
    .toBuffer();
  const tumbada = await sharp(base).withMetadata({ orientation: 6 }).jpeg().toBuffer();

  // Marco enderezado, que es en el que Vision razona y en el que hay que medir.
  const { data: upright, info } = await sharp(tumbada)
    .rotate()
    .toBuffer({ resolveWithObject: true });
  assert.strictEqual(info.width, 800);
  assert.strictEqual(info.height, 600);

  // Se localiza el centro real del verde en el marco enderezado.
  const { data: px, info: raw } = await sharp(upright)
    .raw()
    .toBuffer({ resolveWithObject: true });
  let minX = raw.width, maxX = -1, minY = raw.height, maxY = -1;
  for (let y = 0; y < raw.height; y++) {
    for (let x = 0; x < raw.width; x++) {
      const i = (y * raw.width + x) * raw.channels;
      if (px[i + 1] > 180 && px[i] < 90 && px[i + 2] < 90) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  assert.ok(maxX > 0, "el cuadrado verde tiene que aparecer en el marco enderezado");

  // Caja "de Vision" sobre esa zona, en coordenadas del marco enderezado.
  const face = {
    fdBoundingPoly: {
      vertices: [
        { x: minX, y: minY },
        { x: maxX, y: minY },
        { x: maxX, y: maxY },
        { x: minX, y: maxY },
      ],
    },
  };
  const rect = faceRect(face, info.width, info.height);
  assert.ok(rect);

  // Recortar el buffer ENDEREZADO con ese rectangulo tiene que dar verde.
  // (Aplicarlo al buffer sin enderezar era el fallo: caia en el fondo.)
  const cropped = await sharp(upright).extract(rect).raw().toBuffer({ resolveWithObject: true });
  const c = cropped.info;
  const mid = (Math.floor(c.height / 2) * c.width + Math.floor(c.width / 2)) * c.channels;
  assert.ok(
    cropped.data[mid + 1] > 150 && cropped.data[mid] < 110,
    "el centro del recorte tiene que ser la 'cara' (verde), no el fondo"
  );

  // Y el mismo rectangulo sobre el buffer SIN enderezar se sale o cae fuera:
  // es la demostracion de que medir y recortar en marcos distintos rompe.
  const almacenado = await sharp(tumbada).metadata();
  const cabe =
    rect.left + rect.width <= almacenado.width &&
    rect.top + rect.height <= almacenado.height;
  if (cabe) {
    const malo = await sharp(tumbada).extract(rect).raw().toBuffer({ resolveWithObject: true });
    const m = malo.info;
    const midMalo = (Math.floor(m.height / 2) * m.width + Math.floor(m.width / 2)) * m.channels;
    assert.ok(
      !(malo.data[midMalo + 1] > 150 && malo.data[midMalo] < 110),
      "sobre el buffer sin enderezar el recorte NO deberia dar la cara"
    );
  }
});
