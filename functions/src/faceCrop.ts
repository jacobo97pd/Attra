/// RECORTE DE CARA para la IA visual (Attra Pro).
///
/// POR QUE EXISTE ESTE MODULO
/// `multimodalembedding@001` (el modelo que usa ai.ts) es un embedding
/// SEMANTICO/estetico de la imagen ENTERA, no un reconocedor de identidad. Con
/// la foto completa, buena parte del vector la fijan el encuadre, el fondo, la
/// luz y la compresion, no la persona. Medido sobre las fotos REALES de
/// produccion (20 fotos de 6 personas de `discovery`, usando "otra foto de la
/// misma persona" como verdad de referencia):
///
///   metrica                                   foto entera   recorte de cara
///   P@1 "otra foto de la MISMA persona"        17/19 (89%)     18/19 (95%)
///   separacion coseno (misma - distinta)          0.164           0.170
///   el vecino mas parecido comparte genero      8/15 (53%)     10/15 (67%)
///
/// Es una mejora REAL pero MODESTA: recortar la cara NO convierte a este modelo
/// en un reconocedor facial. Lo que si hace es quitarle al vector el fondo y el
/// encuadre, que era lo que producia los casos absurdos (un hombre cuyo "mas
/// parecido" era una mujer con el mismo tipo de foto). Por eso en ningun sitio
/// se vende esto como reconocimiento facial.
///
/// El margen 0.6 se eligio MIDIENDO: 0.25 empeora (16/19), 0.6 y 1.2 empatan en
/// P@1 (18/19), y 0.6 es el que deja mas cara y menos decorado dentro.
///
/// ORIENTACION EXIF: se endereza SIEMPRE antes de nada (ver
/// `prepareForEmbedding`). Es obligatorio, no cosmetico. Medido con sharp
/// 0.33.5, que es el que se instala: para un JPEG con Orientation=6 (la foto
/// vertical tipica de movil), `sharp(buf).metadata()` devuelve 600x800 (el
/// marco ALMACENADO, no el que se ve) y `sharp(buf).jpeg()` SIN `.rotate()`
/// escribe 600x800 con la etiqueta EXIF BORRADA. O sea, sin enderezar pasaban
/// dos cosas a la vez: (a) medir el ancho/alto en un marco y recortar en otro,
/// y (b) mandarle a Vertex una cara TUMBADA y ademas sin la etiqueta que le
/// habria dejado corregirla. Enderezando una sola vez al principio, el
/// tamano, Cloud Vision y el recorte ven exactamente los mismos pixeles y el
/// problema desaparece de raiz en vez de depender de en que marco devuelve
/// Vision las coordenadas.
///
/// PRIVACIDAD: aqui NO se deduce etnia, edad, sexo ni ninguna categoria
/// especial. Cloud Vision no las devuelve (verificado sobre la respuesta real:
/// FaceAnnotation solo trae poligonos, 34 landmarks, tres angulos, dos
/// confianzas y siete "likelihood" de expresion/calidad) y no se infieren por
/// nuestra cuenta. Los landmarks NO se guardan en ningun sitio.
import { GoogleAuth } from "google-auth-library";

/// `sharp` SE CARGA PEREZOSAMENTE, no en el ámbito del módulo.
///
/// `index.ts` re-exporta `ai.ts`, que importa este fichero, así que un `import
/// sharp` arriba se ejecuta en el arranque en frío de TODAS las funciones del
/// despliegue —chat, notificaciones, safety…— que no usan sharp para nada. Y el
/// despliegue corre con `memory: "256MiB"` global. Medido en la máquina de
/// desarrollo: `require("sharp")` cuesta 115 ms y +13,8 MB de RSS, o sea ~5% del
/// presupuesto de memoria y 115 ms de latencia fría regalados a funciones que
/// nunca tocan una imagen.
let sharpModule: typeof import("sharp") | null = null;
async function loadSharp(): Promise<typeof import("sharp")> {
  if (sharpModule === null) sharpModule = (await import("sharp")).default;
  return sharpModule;
}

/// Credenciales POR DEFECTO de la funcion (el service account de Cloud Run).
/// Mismo patron que liveModeration.ts: nunca una API key en el cliente.
const visionAuth = new GoogleAuth({
  scopes: ["https://www.googleapis.com/auth/cloud-platform"],
});

const VISION_ENDPOINT = "https://vision.googleapis.com/v1/images:annotate";

/// Si Vision tarda mas que esto seguimos con la foto entera: es preferible un
/// parecido peor que dejar colgada una funcion que el usuario esta esperando.
const VISION_TIMEOUT_MS = 8000;

/// Lado del recorte que se manda a Vertex. Normalizar el tamano ademas quita
/// del vector la resolucion original, que era otra fuente de parecido falso
/// (las miniaturas de 128px se agrupaban entre ellas por ser miniaturas).
const CROP_SIDE = 512;

/// Cuanto se amplia la caja de la cara. `fdBoundingPoly` es solo la piel: sin
/// margen se pierden pelo, mandibula y orejas, que si son parecido real.
const CROP_MARGIN = 0.6;

/// Lado maximo con el que se trabaja.
///
/// La foto se reduce a esto ANTES de mirarla, por dos motivos: (a) la peticion
/// a Cloud Vision lleva la imagen en base64, que infla ~33%, y el limite de la
/// API son 20 MB — una foto de movil de varios MB (las mock pesan eso, ver el
/// comentario de ai.ts) se acercaba peligrosamente; y (b) Vision no necesita
/// 4000px para encontrar una cara, asi que era ancho de banda y latencia
/// tirados en cada candidato del feed.
///
/// IMPORTANTE: se reduce UNA VEZ y ese mismo buffer es el que se manda a Vision
/// Y el que se recorta. Si se mandara reducida y se recortara la grande, las
/// coordenadas volverian a estar en un marco distinto del recorte, que es
/// exactamente el fallo que arregla el enderezado de la cabecera. Un lado de
/// 1600 deja la cara tipica en 300-600px, de sobra para un recorte de 512.
const MAX_WORK_EDGE = 1600;

/// Version del preprocesado. VA EN LA CLAVE DE CACHE Y EN LA REFERENCIA: los
/// embeddings de la v1 son de la foto ENTERA y NO son comparables con los de la
/// v2 (cara recortada). Mezclarlos daria un ranking sin sentido, asi que al
/// subir este numero la cache antigua deja de usarse sola.
export const EMBED_PIPELINE_VERSION = 2;

/// Vertice de un poligono de Vision (pixeles).
interface VisionVertex {
  x?: number;
  y?: number;
}

/// Subconjunto de FaceAnnotation que usamos. Solo campos que Cloud Vision
/// devuelve DE VERDAD (verificado contra la respuesta real de la API).
export interface VisionFace {
  boundingPoly?: { vertices?: VisionVertex[] };
  fdBoundingPoly?: { vertices?: VisionVertex[] };
  rollAngle?: number;
  panAngle?: number;
  tiltAngle?: number;
  detectionConfidence?: number;
  joyLikelihood?: string;
  sorrowLikelihood?: string;
  angerLikelihood?: string;
  surpriseLikelihood?: string;
  underExposedLikelihood?: string;
  blurredLikelihood?: string;
  headwearLikelihood?: string;
}

/// Rasgos que SI se pueden afirmar de una foto, tal cual los da Vision.
///
/// NO hay "gafas": Cloud Vision NO devuelve ese dato (comprobado sobre la
/// respuesta real) y no se inventa. Tampoco edad ni etnia: son categoria
/// especial y la linea aqui es dura.
export interface FaceTraits {
  /// Se detecto al menos una cara.
  detected: boolean;
  /// N de caras en la foto (sirve para avisar de fotos de grupo).
  faceCount: number;
  /// Confianza de deteccion [0..1] de la cara principal.
  confidence: number;
  /// Orientacion derivada del angulo de guinada: de frente / tres cuartos /
  /// de perfil. Es geometria de la TOMA, no un rasgo de la persona.
  pose: "frontal" | "three_quarter" | "profile" | "unknown";
  /// Angulos crudos en grados (guinada, cabeceo, alabeo).
  panAngle: number;
  tiltAngle: number;
  rollAngle: number;
  /// Likelihood tal cual de Vision (VERY_UNLIKELY..VERY_LIKELY, o UNKNOWN).
  smile: string;
  headwear: string;
  blurred: string;
  underExposed: string;
  /// Fraccion de la foto que ocupa la cara [0..1]. Por debajo de ~0.05 la cara
  /// casi no influye en el embedding de la foto entera: es el aviso honesto de
  /// "esta es una foto de plano general, no un retrato".
  faceAreaRatio: number;
}

/// Rectangulo de recorte ya saneado contra los limites de la imagen.
interface CropRect {
  left: number;
  top: number;
  width: number;
  height: number;
}

function vertices(poly: { vertices?: VisionVertex[] } | undefined): VisionVertex[] {
  return Array.isArray(poly?.vertices) ? (poly!.vertices as VisionVertex[]) : [];
}

/// Caja envolvente de un poligono, o null si viene vacio/degenerado.
function boxOf(
  poly: { vertices?: VisionVertex[] } | undefined
): { x0: number; y0: number; x1: number; y1: number } | null {
  const v = vertices(poly);
  if (v.length === 0) return null;
  const xs = v.map((p) => p.x ?? 0);
  const ys = v.map((p) => p.y ?? 0);
  const x0 = Math.min(...xs);
  const x1 = Math.max(...xs);
  const y0 = Math.min(...ys);
  const y1 = Math.max(...ys);
  if (x1 <= x0 || y1 <= y0) return null;
  return { x0, y0, x1, y1 };
}

/// Resultado de mirar la foto con Cloud Vision.
///
/// `failed` distingue las DOS cosas que antes se devolvian igual (una lista
/// vacia): "he mirado y aqui no hay ninguna cara" (legitimo, estable, se puede
/// cachear) y "no he podido mirar" (403, cuota, timeout, red). Mezclarlas hacia
/// que una caida de Vision se le contara al usuario como un defecto de SU foto,
/// y que un embedding degradado se guardara en cache como si fuera bueno.
export interface FaceDetection {
  faces: VisionFace[];
  /// El motor no respondio. NO significa "no hay cara".
  failed: boolean;
}

/// Estados HTTP que merecen reintento (mismos que Vertex en ai.ts): cuota y
/// caidas transitorias. Un 403 (API sin habilitar, falta de rol) no se
/// reintenta: no se va a arreglar solo y solo gastaria el presupuesto.
const VISION_RETRYABLE = new Set([429, 500, 502, 503, 504]);

/// Vision tiene los MISMOS problemas de cuota que Vertex, asi que tiene el
/// mismo trato. Menos intentos porque cada uno se lleva hasta 8s de timeout y
/// hay un presupuesto de funcion que respetar.
const VISION_MAX_ATTEMPTS = 3;
const VISION_BACKOFF_BASE_MS = 300;

function visionSleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/// Llama a Cloud Vision FACE_DETECTION, con reintento para cuota/5xx.
///
/// A diferencia de la moderacion del vivo, aqui NO se falla en cerrado: no
/// poder recortar la cara no es un riesgo de seguridad. Pero SI se dice que ha
/// fallado, para que quien llama no cachee basura ni culpe a la foto.
export async function detectFaces(bytes: Buffer): Promise<FaceDetection> {
  let lastRetryable = false;
  for (let attempt = 0; attempt < VISION_MAX_ATTEMPTS; attempt++) {
    try {
      const token = await visionAuth.getAccessToken();
      if (!token) {
        console.error("[Vision] sin access token (ADC no disponible)");
        return { faces: [], failed: true };
      }
      const res = await fetch(VISION_ENDPOINT, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          requests: [
            {
              image: { content: bytes.toString("base64") },
              features: [{ type: "FACE_DETECTION", maxResults: 5 }],
            },
          ],
        }),
        signal: AbortSignal.timeout(VISION_TIMEOUT_MS),
      });
      if (res.ok) {
        const json = (await res.json()) as {
          responses?: { faceAnnotations?: VisionFace[]; error?: unknown }[];
        };
        const ann = json.responses?.[0];
        if (ann?.error) {
          console.error(
            `[Vision] error por peticion: ${JSON.stringify(ann.error).slice(0, 200)}`
          );
          return { faces: [], failed: true };
        }
        // Respuesta buena SIN caras: esto si es "no hay cara", no un fallo.
        return {
          faces: Array.isArray(ann?.faceAnnotations)
            ? (ann!.faceAnnotations as VisionFace[])
            : [],
          failed: false,
        };
      }
      // La causa mas comun de un 403 es `vision.googleapis.com` sin habilitar
      // en el proyecto (SERVICE_DISABLED). Se ve en los logs de la funcion.
      const body = await res.text().catch(() => "");
      lastRetryable = VISION_RETRYABLE.has(res.status);
      console.error(
        `[Vision] faceDetection HTTP ${res.status} (intento ${attempt + 1}/` +
          `${VISION_MAX_ATTEMPTS}): ${body.slice(0, 300)}`
      );
      if (!lastRetryable) return { faces: [], failed: true };
    } catch (e) {
      // Timeout del AbortSignal o red caida: transitorio.
      lastRetryable = true;
      console.error(
        `[Vision] faceDetection error (intento ${attempt + 1}): ${(e as Error).message}`
      );
    }
    if (attempt < VISION_MAX_ATTEMPTS - 1) {
      // Jitter por lo mismo que en Vertex: varios candidatos a la vez
      // reintentarian a la vez y volverian a chocar con la misma cuota.
      const base = VISION_BACKOFF_BASE_MS * 2 ** attempt;
      await visionSleep(base + Math.floor(Math.random() * VISION_BACKOFF_BASE_MS));
    }
  }
  return { faces: [], failed: true };
}

/// La cara PRINCIPAL de la foto: la MAS GRANDE, no la primera que devuelva
/// Vision. En una foto con gente detras, la primera puede ser la de un
/// acompanante y estariamos midiendo el parecido de otra persona.
export function primaryFace(faces: VisionFace[]): VisionFace | null {
  let best: VisionFace | null = null;
  let bestArea = 0;
  for (const f of faces) {
    const box = boxOf(f.fdBoundingPoly) ?? boxOf(f.boundingPoly);
    if (!box) continue;
    const area = (box.x1 - box.x0) * (box.y1 - box.y0);
    if (area > bestArea) {
      bestArea = area;
      best = f;
    }
  }
  return best;
}

/// Rectangulo CUADRADO centrado en la cara y ampliado por CROP_MARGIN, recortado
/// contra los bordes de la imagen. Cuadrado a proposito: el destino es 512x512,
/// y partir de un rectangulo alargado deformaria la cara.
export function faceRect(
  face: VisionFace,
  imgW: number,
  imgH: number
): CropRect | null {
  const box = boxOf(face.fdBoundingPoly) ?? boxOf(face.boundingPoly);
  if (!box || imgW <= 0 || imgH <= 0) return null;
  const cx = (box.x0 + box.x1) / 2;
  const cy = (box.y0 + box.y1) / 2;
  const side = Math.max(box.x1 - box.x0, box.y1 - box.y0) * (1 + CROP_MARGIN);
  // El lado se recorta a lo que quepa: pedirle a sharp un cuadrado mayor que la
  // imagen revienta con `extract_area: bad extract area`.
  const maxSide = Math.min(imgW, imgH);
  const finalSide = Math.max(1, Math.min(Math.round(side), maxSide));
  const left = Math.round(
    Math.max(0, Math.min(cx - finalSide / 2, imgW - finalSide))
  );
  const top = Math.round(
    Math.max(0, Math.min(cy - finalSide / 2, imgH - finalSide))
  );
  return { left, top, width: finalSide, height: finalSide };
}

/// Traduce el angulo de guinada a una etiqueta legible. Los cortes (20/50
/// grados) son los que en las fotos reales de produccion separan un retrato de
/// frente de uno claramente girado.
function poseFromPan(pan: number | undefined): FaceTraits["pose"] {
  if (typeof pan !== "number" || !Number.isFinite(pan)) return "unknown";
  const a = Math.abs(pan);
  if (a <= 20) return "frontal";
  if (a <= 50) return "three_quarter";
  return "profile";
}

const UNKNOWN_LIKELIHOOD = "UNKNOWN";

function likelihood(value: string | undefined): string {
  return typeof value === "string" && value.length > 0
    ? value
    : UNKNOWN_LIKELIHOOD;
}

/// Rasgos cuando NO hay cara: se dice que no hay, no se rellena con ceros que
/// puedan pasar por datos.
export function noFaceTraits(faceCount = 0): FaceTraits {
  return {
    detected: false,
    faceCount,
    confidence: 0,
    pose: "unknown",
    panAngle: 0,
    tiltAngle: 0,
    rollAngle: 0,
    smile: UNKNOWN_LIKELIHOOD,
    headwear: UNKNOWN_LIKELIHOOD,
    blurred: UNKNOWN_LIKELIHOOD,
    underExposed: UNKNOWN_LIKELIHOOD,
    faceAreaRatio: 0,
  };
}

/// Construye los rasgos a partir de la cara y del tamano de la imagen. Solo
/// copia lo que Vision da; no deduce nada.
export function traitsFrom(
  face: VisionFace,
  faceCount: number,
  imgW: number,
  imgH: number
): FaceTraits {
  const box = boxOf(face.fdBoundingPoly) ?? boxOf(face.boundingPoly);
  const area = box ? (box.x1 - box.x0) * (box.y1 - box.y0) : 0;
  const total = imgW * imgH;
  return {
    detected: true,
    faceCount,
    confidence:
      typeof face.detectionConfidence === "number" ? face.detectionConfidence : 0,
    pose: poseFromPan(face.panAngle),
    panAngle: face.panAngle ?? 0,
    tiltAngle: face.tiltAngle ?? 0,
    rollAngle: face.rollAngle ?? 0,
    smile: likelihood(face.joyLikelihood),
    headwear: likelihood(face.headwearLikelihood),
    blurred: likelihood(face.blurredLikelihood),
    underExposed: likelihood(face.underExposedLikelihood),
    faceAreaRatio: total > 0 ? Math.min(1, area / total) : 0,
  };
}

/// Resultado del preprocesado de una foto antes de embeberla.
export interface PreparedImage {
  /// Bytes que hay que mandar a Vertex (cara recortada, o foto entera
  /// enderezada y normalizada si no hubo cara).
  bytes: Buffer;
  /// Se llego a recortar una cara. Si es false el parecido de esa foto vale
  /// menos, y hay que poder decirlo en vez de disimularlo.
  cropped: boolean;
  /// Rasgos de la cara principal (o `detected: false`).
  traits: FaceTraits;
  /// Cloud Vision NO respondio (403/cuota/timeout/red). Es distinto de "no hay
  /// cara": el vector resultante es de foto entera, vive en otro espacio que el
  /// de las referencias recortadas, y quien llama NO debe cachearlo ni
  /// presentarlo como bueno.
  visionFailed: boolean;
}

/// Normaliza SIN recortar: mismo lado de salida que el recorte, para que la
/// resolucion no sea por si sola una senal de parecido.
///
/// `fit: "contain"` y no "cover": "cover" recorta al cuadrado CENTRADO, que en
/// un retrato 3:4 se come el 12,5% de arriba, justo donde esta la cabeza en un
/// plano general. Esta rama es la de respaldo (no hay cara, o Vision no
/// contesta) y tiene que ser de verdad LA FOTO ENTERA, que es ademas lo que la
/// app le dice al usuario que ha pasado.
async function normalizeOnly(bytes: Buffer): Promise<Buffer> {
  const sharp = await loadSharp();
  return sharp(bytes)
    .resize(CROP_SIDE, CROP_SIDE, {
      fit: "contain",
      background: { r: 0, g: 0, b: 0 },
    })
    .jpeg({ quality: 90 })
    .toBuffer();
}

/// Prepara una foto para embeber: endereza, detecta cara, recorta y normaliza.
///
/// Nunca lanza. Si Vision no responde, si no hay cara (3 de las 15 fotos reales
/// de produccion no la tienen: dos planos generales y un producto) o si sharp no
/// sabe leer el formato, cae con elegancia a la foto entera normalizada: peor
/// parecido, pero hay resultado. La diferencia entre esos casos viaja en
/// `visionFailed`, porque no son lo mismo para quien llama.
export async function prepareForEmbedding(bytes: Buffer): Promise<PreparedImage> {
  // ENDEREZAR PRIMERO, una sola vez. `.rotate()` sin argumentos aplica la
  // orientacion EXIF a los pixeles. A partir de aqui el tamano medido, los
  // bytes que ve Cloud Vision y los que recorta sharp son EL MISMO marco, asi
  // que no hay forma de que las coordenadas de la cara se apliquen sobre una
  // imagen distinta de la que se midio (ver la nota de la cabecera).
  let upright = bytes;
  let width = 0;
  let height = 0;
  let sharp: typeof import("sharp");
  try {
    sharp = await loadSharp();
    const { data, info } = await sharp(bytes)
      .rotate()
      // `withoutEnlargement` para no inventar pixeles en fotos pequenas.
      .resize(MAX_WORK_EDGE, MAX_WORK_EDGE, {
        fit: "inside",
        withoutEnlargement: true,
      })
      .toBuffer({ resolveWithObject: true });
    upright = data;
    width = info.width;
    height = info.height;
  } catch (e) {
    // Formato que sharp no sabe leer: se manda tal cual y que decida Vertex.
    // Aqui no se ha podido enderezar, pero tampoco recortar, asi que la foto
    // conserva su EXIF original y Vertex puede honrarlo.
    console.error(`[FaceCrop] imagen ilegible para sharp: ${(e as Error).message}`);
    return { bytes, cropped: false, traits: noFaceTraits(), visionFailed: false };
  }

  const detection = await detectFaces(upright);
  const face = primaryFace(detection.faces);
  if (!face || width === 0 || height === 0) {
    const fallback = await normalizeOnly(upright).catch(() => upright);
    return {
      bytes: fallback,
      cropped: false,
      traits: noFaceTraits(detection.faces.length),
      visionFailed: detection.failed,
    };
  }

  const traits = traitsFrom(face, detection.faces.length, width, height);
  const rect = faceRect(face, width, height);
  if (!rect) {
    const fallback = await normalizeOnly(upright).catch(() => upright);
    return { bytes: fallback, cropped: false, traits, visionFailed: detection.failed };
  }
  try {
    const cropped = await sharp(upright)
      .extract(rect)
      .resize(CROP_SIDE, CROP_SIDE, { fit: "cover" })
      .jpeg({ quality: 90 })
      .toBuffer();
    return { bytes: cropped, cropped: true, traits, visionFailed: false };
  } catch (e) {
    console.error(`[FaceCrop] recorte fallido: ${(e as Error).message}`);
    const fallback = await normalizeOnly(upright).catch(() => upright);
    return { bytes: fallback, cropped: false, traits, visionFailed: detection.failed };
  }
}
