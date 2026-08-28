import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue, DocumentData } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { GoogleAuth } from "google-auth-library";
import { createHash } from "node:crypto";
import { REGION, STORAGE_BUCKET, db } from "./firebase";
import { col, requireAuthUid, requireStringArg } from "./common";
import {
  dataMatch as promptDataMatch,
  extractPromptSignals,
  passesDataFilter,
  PromptProfileData,
} from "./promptMatch";
import {
  EMBED_PIPELINE_VERSION,
  FaceTraits,
  prepareForEmbedding,
} from "./faceCrop";

/// Referencias visuales (embeddings) por usuario. BACKEND-ONLY: el embedding
/// NUNCA se expone al cliente (es dato biométrico/categoría especial RGPD).
const aiRefs = db.collection("aiReferences");

/// Vertex AI multimodal embeddings. Embedding ESTÉTICO de imagen (NO es
/// reconocimiento de identidad, ni siquiera recortando la cara). Requiere
/// habilitar la API: `gcloud services enable aiplatform.googleapis.com`.
///
/// COSTE POR FOTO NO CACHEADA (importa, porque ya no es una sola llamada):
/// desde el recorte de cara son DOS llamadas, Cloud Vision FACE_DETECTION
/// (~$1.50/1000 pasadas las 1000 gratis del mes, o sea ~$0.0015) + el embedding
/// de Vertex (~$0.0001). El grueso de la factura lo pone ahora VISION, no
/// Vertex. Con `VISUAL_MATCH_LIMIT` a 80, una búsqueda con caché fría son hasta
/// 80 de cada. Además `vision.googleapis.com` comparte cuota con la moderación
/// del vídeo en vivo (liveModeration.ts), que sí falla en cerrado: antes de
/// subir el límite o la concurrencia hay que mirar esa cuota.
/// Subir `EMBED_PIPELINE_VERSION` invalida TODA la caché de golpe (la versión va
/// en la clave), así que el día del despliegue se re-embebe el catálogo entero
/// con Vision incluido. No es gratis: es el precio de que los vectores viejos y
/// los nuevos no se mezclen.
const VERTEX_PROJECT = "attra-database";
const VERTEX_LOCATION = "us-central1";
const VERTEX_MODEL = "multimodalembedding@001";
const VISUAL_MATCH_LIMIT = 80;
const VISUAL_EMBED_CONCURRENCY = 4;
/// UMBRAL DE PARECIDO: por debajo de esto, "no se parece".
///
/// VIVE AQUÍ Y VIAJA EN LA RESPUESTA, no en la app. El umbral y el
/// preprocesado son la MISMA decisión: al pasar de la v1 (foto entera) a la v2
/// (cara recortada) los cosenos cambian de escala, así que un corte calibrado
/// para una versión no significa nada en la otra. Teniéndolo en el cliente hacía
/// falta desplegar la app para recalibrarlo — y por eso no se recalibró: se
/// cambió el espacio vectorial y se dejó el corte de la v1 decidiendo quién
/// entra y quién no.
///
/// OJO, ESTE NÚMERO SIGUE SIN CALIBRAR PARA LA v2. El 0.55 viene de mediciones
/// de la v1 (foto entera). Hay que rehacerlas con fotos reales ya recortadas
/// —percentil de separación entre "misma persona" y "distinta persona"— antes
/// de vender precisión. Se deja el valor heredado a propósito en vez de
/// inventarse uno nuevo: mover el corte a ojo sería peor que no moverlo.
const VISUAL_MATCH_THRESHOLD = 0.55;

/// Pesos del ranking por prompt cuando hay AMBAS señales (suman 1).
const VISUAL_PROMPT_WEIGHT = 0.6;
const DATA_PROMPT_WEIGHT = 0.4;
const auth = new GoogleAuth({
  scopes: ["https://www.googleapis.com/auth/cloud-platform"],
});

/// LIMITE DE TASA DE VERTEX: no es teórico, es lo que pasa hoy.
///
/// Midiendo contra el proyecto real, embebiendo las fotos de producción, el 38%
/// de las llamadas (49 de 129) respondieron HTTP 429 — y eso EMBEBIENDO DE UNA
/// EN UNA, no sólo en ráfaga. Vertex tampoco manda cabecera `Retry-After`, así
/// que el reintento tiene que traer su propia espera.
///
/// Antes no había ningún reintento: un 429 devolvía null, el candidato
/// desaparecía del ranking sin más y el usuario Pro veía un "parecido" calculado
/// sobre la mitad de la gente sin enterarse. Con la espera exponencial entran
/// muchas más.
/// 4 intentos con base 400ms → esperas de 0.4s + 0.8s + 1.6s ≈ 2.8s como mucho
/// por foto. Los números están atados al presupuesto de abajo: con más
/// reintentos, un feed de 80 candidatos se comería el timeout de la función y
/// el usuario se quedaría sin NADA en vez de con un resultado parcial.
///
/// NO se promete cobertura del 100%. Con la caché FRÍA —que es exactamente el
/// estado del día que se despliega un cambio de `EMBED_PIPELINE_VERSION`— cada
/// candidato son dos llamadas de red (Vision + Vertex) más la descarga de la
/// foto, así que 80 candidatos a concurrencia 4 NO caben en el presupuesto de
/// 42s. Eso ya no es un problema silencioso: los que no dé tiempo a mirar salen
/// en `skippedUids`, el resultado se marca `complete:false` y el cliente lo
/// dice y ofrece reintentar (la caché va calentándose en cada pasada). Si algún
/// día se quiere cobertura completa en la primera búsqueda, hay que MEDIR el
/// throughput real y ajustar límite/concurrencia con ese dato, no a ojo.
const VERTEX_MAX_ATTEMPTS = 4;
const VERTEX_BACKOFF_BASE_MS = 400;

/// TIMEOUT DE RED POR INTENTO. Sin esto el presupuesto de abajo no acotaba
/// nada: `fetch` (undici) no corta un socket colgado hasta los 300s, así que un
/// candidato que empezaba DENTRO de presupuesto podía llevarse por delante el
/// timeout de 60s de la función entera — y entonces el usuario no se queda con
/// un resultado parcial, se queda sin NADA, que es justo lo que el presupuesto
/// venía a evitar. Cloud Vision ya tenía su timeout; Vertex no.
const VERTEX_REQUEST_TIMEOUT_MS = 10000;

/// PRESUPUESTO DE TIEMPO de la función (la función muere a los 60s).
///
/// Reintentar está bien, pero reintentar sin límite con 80 candidatos a
/// concurrencia 4 se pasa del timeout: Cloud Functions corta, el cliente recibe
/// un error y el usuario se queda sin feed. Con presupuesto, lo que no dé tiempo
/// a puntuar se devuelve como "no evaluado" y el ranking sale INCOMPLETO PERO
/// AVISADO, que es justo lo que el cliente ya sabe pintar.
const VISUAL_TIME_BUDGET_MS = 42000;

/// Códigos que SÍ merecen reintento: cuota (429) y caídas transitorias del lado
/// del servidor. Un 403 (API deshabilitada, falta de rol) no se reintenta: no va
/// a arreglarse solo y sólo serviría para agotar el timeout de la función.
const RETRYABLE_STATUS = new Set([429, 500, 502, 503, 504]);

/// Por qué no hay embedding. Distinguirlo importa: `rate_limited` significa
/// "esto existía y no hemos podido mirarlo" (el resultado está INCOMPLETO), y
/// `unavailable` que el motor no está. Un `null` pelado mezclaba las dos con
/// "este candidato no tiene foto", que no es un fallo de nada.
export type EmbedFailure = "rate_limited" | "unavailable";

export type EmbedResult =
  | { ok: true; embedding: number[] }
  | { ok: false; reason: EmbedFailure };

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/// Espera exponencial con "jitter". El jitter es imprescindible aquí: la función
/// embebe varios candidatos a la vez y, sin ruido, todos reintentarían en el
/// mismo instante y volverían a chocar contra la misma cuota.
function backoffDelay(attempt: number): number {
  const base = VERTEX_BACKOFF_BASE_MS * 2 ** attempt;
  return base + Math.floor(Math.random() * VERTEX_BACKOFF_BASE_MS);
}

const VERTEX_URL =
  `https://${VERTEX_LOCATION}-aiplatform.googleapis.com/v1/projects/` +
  `${VERTEX_PROJECT}/locations/${VERTEX_LOCATION}/publishers/google/models/` +
  `${VERTEX_MODEL}:predict`;

/// Llamada a Vertex con reintentos. `pick` saca el vector de la predicción
/// (imageEmbedding o textEmbedding según la modalidad).
async function vertexPredict(
  instance: unknown,
  pick: (p: Record<string, unknown>) => unknown,
  label: string,
  deadline?: number
): Promise<EmbedResult> {
  let lastRetryable = false;
  for (let attempt = 0; attempt < VERTEX_MAX_ATTEMPTS; attempt++) {
    // Fuera de presupuesto no se empieza otro intento: reintentar cuando ya no
    // hay tiempo solo sirve para matar la función y perder lo ya calculado.
    if (deadline !== undefined && Date.now() > deadline) {
      return { ok: false, reason: "rate_limited" };
    }
    try {
      const token = await auth.getAccessToken();
      const res = await fetch(VERTEX_URL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ instances: [instance] }),
        signal: AbortSignal.timeout(VERTEX_REQUEST_TIMEOUT_MS),
      });
      if (res.ok) {
        const json = (await res.json()) as {
          predictions?: Record<string, unknown>[];
        };
        const emb = pick(json.predictions?.[0] ?? {});
        if (!Array.isArray(emb)) {
          console.error(`[Vertex] ${label}: respuesta sin embedding`);
          return { ok: false, reason: "unavailable" };
        }
        return { ok: true, embedding: emb as number[] };
      }
      const body = await res.text().catch(() => "");
      lastRetryable = RETRYABLE_STATUS.has(res.status);
      // Diagnóstico: la causa más común de un 403 es la API sin habilitar o el
      // service account sin rol aiplatform.user.
      console.error(
        `[Vertex] ${label} HTTP ${res.status} (intento ${attempt + 1}/` +
          `${VERTEX_MAX_ATTEMPTS}): ${body.slice(0, 200)}`
      );
      if (!lastRetryable) return { ok: false, reason: "unavailable" };
    } catch (e) {
      // Red caída / socket cortado: también es transitorio.
      lastRetryable = true;
      console.error(
        `[Vertex] ${label} error (intento ${attempt + 1}): ${(e as Error).message}`
      );
    }
    if (attempt < VERTEX_MAX_ATTEMPTS - 1) {
      // La espera tampoco puede pasarse del presupuesto: dormir 1.6s cuando
      // quedan 300ms es regalarle el timeout a la función.
      let wait = backoffDelay(attempt);
      if (deadline !== undefined) wait = Math.min(wait, deadline - Date.now());
      if (wait <= 0) return { ok: false, reason: "rate_limited" };
      await sleep(wait);
    }
  }
  return { ok: false, reason: lastRetryable ? "rate_limited" : "unavailable" };
}

/// Calcula el embedding de imagen (1408 dims) con Vertex AI.
async function embedImage(bytes: Buffer, deadline?: number): Promise<EmbedResult> {
  return vertexPredict(
    { image: { bytesBase64Encoded: bytes.toString("base64") } },
    (p) => p.imageEmbedding,
    "embedImage",
    deadline
  );
}

/// Embedding de TEXTO en el MISMO espacio multimodal que las imágenes (permite
/// comparar una descripción con las fotos ya embebidas). Coste ínfimo (~1 texto
/// por búsqueda).
async function embedText(text: string): Promise<EmbedResult> {
  return vertexPredict(
    { text: text.slice(0, 1024) },
    (p) => p.textEmbedding,
    "embedText"
  );
}

/// Exige Pro ACTIVO + consentimiento IA explícito + flags de IA habilitados.
/// La IA visual es exclusiva de Attra Pro y opt-in.
async function requireProAiConsent(uid: string): Promise<void> {
  const [entSnap, userSnap, cfgSnap] = await Promise.all([
    col.entitlements.doc(uid).get(),
    col.users.doc(uid).get(),
    db.collection("config").doc("featureFlags").get(),
  ]);
  const tier = (entSnap.data()?.tier ?? "free").toString();
  if (tier !== "pro") {
    throw new HttpsError("permission-denied", "La IA visual es exclusiva de Attra Pro.");
  }
  // Caducidad: si expiró, no es Pro efectivo.
  const expiresAt = entSnap.data()?.expiresAt;
  const isLifetime = entSnap.data()?.isLifetime === true;
  if (!isLifetime && expiresAt?.toMillis && expiresAt.toMillis() < Date.now()) {
    throw new HttpsError("permission-denied", "Tu plan Pro ha caducado.");
  }
  if (userSnap.data()?.aiVisualConsent !== true) {
    throw new HttpsError(
      "failed-precondition",
      "Necesitas dar tu consentimiento explícito para la IA visual."
    );
  }
  const cfg = cfgSnap.data() ?? {};
  if (cfg.aiKillSwitch === true || cfg.aiProcessingEnabled === false) {
    throw new HttpsError("failed-precondition", "La IA está deshabilitada temporalmente.");
  }
}

/// Calcula la huella visual de una foto de referencia: recorta la cara (para
/// que el vector mida a la persona y no el decorado) y la embebe en Vertex.
/// Devuelve también los RASGOS que Cloud Vision da en esa misma llamada.
async function buildReference(
  buffer: Buffer,
  deadline?: number
): Promise<{
  embedding: number[] | null;
  traits: FaceTraits;
  cropped: boolean;
  failure: EmbedFailure | null;
}> {
  const prepared = await prepareForEmbedding(buffer);
  // SI VISION NO CONTESTÓ, NO HAY HUELLA. Antes esto se guardaba como
  // `status: "ready"`: un vector de la foto ENTERA que luego se comparaba
  // contra candidatos con la cara recortada, o sea dos espacios distintos, y
  // para siempre (la versión coincidía, así que nunca se recalculaba). Encima
  // la app le decía al usuario "no se ha detectado ninguna cara, sube un
  // retrato", culpando a su foto de una caída nuestra.
  if (prepared.visionFailed) {
    return {
      embedding: null,
      traits: prepared.traits,
      cropped: prepared.cropped,
      failure: "unavailable",
    };
  }
  const result = await embedImage(prepared.bytes, deadline);
  return {
    embedding: result.ok ? result.embedding : null,
    traits: prepared.traits,
    cropped: prepared.cropped,
    failure: result.ok ? null : result.reason,
  };
}

/// Lo que se le devuelve al cliente sobre su propia foto de referencia.
///
/// PRIVACIDAD: el EMBEDDING no sale nunca de aquí (dato biométrico de categoría
/// especial). Estos rasgos son otra cosa: describen la FOTO (encuadre, pose,
/// expresión, calidad), son los que Vision devuelve tal cual, y se le enseñan
/// sólo a su dueño, que además ya pasó por `requireProAiConsent`. No hay etnia,
/// ni edad, ni sexo: Vision no los da y aquí no se deducen.
function publicTraits(
  traits: FaceTraits,
  cropped: boolean,
  engineFailed = false
): Record<string, unknown> {
  return {
    detected: traits.detected,
    faceCount: traits.faceCount,
    confidence: Number(traits.confidence.toFixed(3)),
    pose: traits.pose,
    panAngle: Number(traits.panAngle.toFixed(1)),
    tiltAngle: Number(traits.tiltAngle.toFixed(1)),
    rollAngle: Number(traits.rollAngle.toFixed(1)),
    smile: traits.smile,
    headwear: traits.headwear,
    blurred: traits.blurred,
    underExposed: traits.underExposed,
    faceAreaRatio: Number(traits.faceAreaRatio.toFixed(4)),
    /// Si es false, el parecido se calculó sobre la foto entera y vale menos.
    /// Se dice, no se disimula.
    faceCropped: cropped,
    /// El MOTOR falló (Cloud Vision no contestó), así que `detected: false` NO
    /// significa "tu foto no tiene cara". Sin esto, una caída de Vision le
    /// decía al usuario que su retrato impecable no valía y le empujaba a
    /// borrarlo y probar otro: culpar al usuario de un fallo nuestro.
    engineFailed,
  };
}

/// analyzeReferencePhoto: el usuario sube una foto de referencia (rostro del
/// "tipo" que le gusta) y el backend guarda una HUELLA VISUAL para mostrar
/// personas parecidas. Cachea por hash del objeto para no recomputar ni gastar.
///
/// La huella es un embedding ESTÉTICO/semántico de Vertex sobre la CARA
/// recortada (ver faceCrop.ts para los números de antes/después). NO es
/// reconocimiento facial y NUNCA se infiere raza/etnia/religión/orientación.
export const analyzeReferencePhoto = onCall(
  {
    region: REGION,
    // Mismo presupuesto que las otras dos funciones de IA: aquí también se
    // decodifica una imagen con sharp y se hace base64 de la foto para Vision y
    // para Vertex. Con el 256MiB global (el que se aplicaba al no decir nada)
    // una foto de móvil de varios MB se queda muy justa.
    memory: "1GiB",
  },
  async (request) => {
  const uid = requireAuthUid(request.auth);
  const referencePath = requireStringArg(request.data?.referencePath, "referencePath");
  await requireProAiConsent(uid);

  if (!referencePath.startsWith(`ai/${uid}/reference/`)) {
    throw new HttpsError("permission-denied", "Ruta de archivo no válida.");
  }
  const file = getStorage().bucket(STORAGE_BUCKET).file(referencePath);
  const [exists] = await file.exists();
  if (!exists) {
    throw new HttpsError("failed-precondition", "La foto no existe en Storage.");
  }
  const [meta] = await file.getMetadata();
  const mime = (meta.contentType ?? "").toString();
  if (!mime.startsWith("image/")) {
    throw new HttpsError("invalid-argument", "El archivo no es una imagen.");
  }
  const photoHash = (meta.md5Hash ?? "").toString();

  const existing = await aiRefs.doc(uid).get();
  // La caché sólo sirve si la huella se calculó con ESTE preprocesado: un
  // embedding de la v1 (foto entera) no es comparable con los de la v2 (cara
  // recortada), así que un cambio de versión obliga a recalcular.
  if (
    existing.exists &&
    existing.data()?.photoHash === photoHash &&
    existing.data()?.status === "ready" &&
    existing.data()?.pipelineVersion === EMBED_PIPELINE_VERSION
  ) {
    await aiRefs.doc(uid).set(
      {
        referencePath,
        photoHash,
        status: "ready",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return {
      status: "ready",
      cached: true,
      traits: existing.data()?.traits ?? null,
    };
  }

  const [buffer] = await file.download();
  const built = await buildReference(buffer);
  const status = built.embedding ? "ready" : "pending_provider";
  // Sin embedding es que falló el motor (Vision o Vertex): los rasgos que se
  // devuelvan tienen que decirlo para que la app no culpe a la foto.
  const traits = publicTraits(built.traits, built.cropped, !built.embedding);
  await aiRefs.doc(uid).set(
    {
      referencePath,
      photoHash,
      // Vector estético (NO identidad). Backend-only, nunca al cliente.
      embedding: built.embedding,
      // Con qué preprocesado se calculó: sin esto no se puede saber si la
      // referencia guardada es comparable con los candidatos de hoy.
      pipelineVersion: EMBED_PIPELINE_VERSION,
      traits,
      status,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return {
    status,
    cached: false,
    traits,
    // Si falló por cuota, el usuario merece saber que no es un "no se puede"
    // permanente sino un "ahora mismo no": el mensaje de la app cambia.
    failure: built.failure,
  };
  }
);

/// Embeddings de fotos cacheados por hash de contenido (md5). BACKEND-ONLY.
///
/// RETENCIÓN (importa, y antes no se cumplía): la clave es el hash de la FOTO,
/// así que el documento no decía de quién era. Sin eso no se puede ejercer el
/// derecho de supresión: no hay forma de localizar qué borrar. Ahora se guarda
/// también el `uid` del candidato y una fecha de caducidad, y `clearAiData`
/// barre los del usuario. Es más necesario que antes: desde el recorte de cara
/// el vector se deriva de la REGIÓN FACIAL, no de la escena entera, así que la
/// defensa de "esto es estético, no biométrico" ya no aplica igual.
const photoEmbeddings = db.collection("photoEmbeddings");

/// Caducidad del embedding cacheado. Un vector derivado de una cara guardado
/// "para siempre" no tiene justificación operativa: la foto de perfil cambia y
/// el hash cambia con ella, así que el documento viejo queda huérfano igualmente.
/// Se apoya en una política TTL de Firestore sobre `expiresAt`.
const PHOTO_EMBEDDING_TTL_DAYS = 90;

/// Clave de caché de un embedding de foto. Antes se hacía base64 del valor y se
/// cortaba a 80 caracteres: el prefijo común de una URL de Firebase Storage
/// (`https://firebasestorage.googleapis.com/v0/b/<bucket>/o/`) ya ocupa más que
/// eso, así que TODAS las fotos servidas por URL caían en la misma clave,
/// compartían embedding y la búsqueda por parecido les daba idéntico score.
/// Un hash del valor COMPLETO no colisiona y no depende de la longitud.
/// La VERSIÓN del preprocesado entra en la clave: los embeddings cacheados de
/// la v1 son de la foto entera y compararlos con los de la v2 (cara recortada)
/// daría un ranking sin sentido. Con la versión en la clave, la caché vieja
/// simplemente deja de encontrarse y se recalcula sola.
function embeddingCacheKey(kind: "md5" | "url", value: string): string {
  const digest = createHash("sha256").update(value).digest("hex");
  return `v${EMBED_PIPELINE_VERSION}_${kind}_${digest}`;
}

/// Por qué un candidato no tiene embedding. `missing` (no tiene foto, no existe
/// la ficha) NO es un fallo nuestro y no debe contarse como resultado
/// incompleto; `rate_limited` y `unavailable` sí lo son.
type PhotoEmbedResult =
  | { ok: true; embedding: number[] }
  | { ok: false; reason: EmbedFailure | "missing" };

/// Embedding (cacheado) de la foto principal de un candidato del feed.
/// Busca primero en `discovery` (usuarios reales) y, si no existe, en
/// `seed_profiles` (perfiles mock/bot). Así la IA visual también puede ordenar
/// los perfiles de prueba (mock_*) por parecido a la referencia.
///
/// La foto se pasa por `prepareForEmbedding` (recorte de cara) ANTES de
/// embeberla, igual que la referencia: si una se recortara y la otra no, los
/// dos vectores no vivirían en el mismo espacio y el coseno no querría decir nada.
async function embeddingForUserPhoto(
  uid: string,
  deadline?: number
): Promise<PhotoEmbedResult> {
  const missing: PhotoEmbedResult = { ok: false, reason: "missing" };
  let snap = await db.collection("discovery").doc(uid).get();
  if (!snap.exists) {
    snap = await db.collection("seed_profiles").doc(uid).get();
  }
  if (!snap.exists) return missing;
  const data = snap.data() ?? {};
  const photos: DocumentData[] = Array.isArray(data.photos) ? data.photos : [];
  const storagePath: string | null =
    photos.length > 0 && typeof photos[0].storagePath === "string" && photos[0].storagePath
      ? (photos[0].storagePath as string)
      : null;
  const photoUrl: string | null =
    typeof data.photoUrl === "string" && data.photoUrl ? data.photoUrl : null;

  let buffer: Buffer | null = null;
  let cacheKey: string | null = null;
  try {
    if (storagePath) {
      const file = getStorage().bucket(STORAGE_BUCKET).file(storagePath);
      const [exists] = await file.exists();
      if (!exists) return missing;
      const [meta] = await file.getMetadata();
      const md5 = (meta.md5Hash ?? "").toString();
      if (!md5) return missing;
      // Se hashea el md5 entero: quitarle los "+/=" del base64 podía fundir dos
      // digests distintos en la misma clave.
      cacheKey = embeddingCacheKey("md5", md5);
      const cached = await photoEmbeddings.doc(cacheKey).get();
      if (cached.exists && Array.isArray(cached.data()?.embedding)) {
        return { ok: true, embedding: cached.data()!.embedding as number[] };
      }
      [buffer] = await file.download();
    } else if (photoUrl) {
      cacheKey = embeddingCacheKey("url", photoUrl);
      // La caché se mira ANTES de descargar: bajarse la foto para luego
      // descubrir que ya estaba cacheada era ancho de banda tirado en cada
      // candidato del feed.
      const cached = await photoEmbeddings.doc(cacheKey).get();
      if (cached.exists && Array.isArray(cached.data()?.embedding)) {
        return { ok: true, embedding: cached.data()!.embedding as number[] };
      }
      const res = await fetch(photoUrl);
      if (!res.ok) return missing;
      buffer = Buffer.from(await res.arrayBuffer());
    } else {
      return missing;
    }
  } catch {
    return missing;
  }

  if (!buffer) return missing;
  const prepared = await prepareForEmbedding(buffer);
  // Vision no contestó: el vector saldría de la foto ENTERA y no es comparable
  // con las referencias recortadas. Antes se calculaba igual y se CACHEABA bajo
  // la clave v2 sin marca ni caducidad, así que un 429 transitorio dejaba a ese
  // candidato mal puntuado para siempre, en las búsquedas de todos los Pro, y
  // encima `complete:true`. Se trata como lo que es: no se ha podido mirar.
  if (prepared.visionFailed) {
    return { ok: false, reason: "unavailable" };
  }
  const result = await embedImage(prepared.bytes, deadline);
  if (!result.ok) return { ok: false, reason: result.reason };
  if (cacheKey) {
    await photoEmbeddings
      .doc(cacheKey)
      .set({
        embedding: result.embedding,
        // DE QUIÉN es el vector. Sin esto el documento era imposible de
        // localizar para borrarlo (la clave es sólo el hash de la foto), así que
        // el derecho de supresión no se podía ejercer sobre él.
        uid,
        // Se guarda si venía de un recorte de cara: sirve para depurar por qué
        // una foto puntúa raro sin tener que volver a llamar a Vision.
        faceCropped: prepared.cropped,
        pipelineVersion: EMBED_PIPELINE_VERSION,
        updatedAt: FieldValue.serverTimestamp(),
        expiresAt: new Date(
          Date.now() + PHOTO_EMBEDDING_TTL_DAYS * 24 * 60 * 60 * 1000
        ),
      })
      .catch(() => undefined);
  }
  return { ok: true, embedding: result.embedding };
}

/// Grupos donde viven los rasgos según de dónde venga la ficha: `discovery` los
/// publica PLANOS (buildDiscoveryDoc hace out[trait.field]) pero los perfiles
/// seed y los `users/{uid}` los guardan ANIDADOS (appearance.eyeColor,
/// lifestyle.*, profile.*). Antes solo se miraba la forma plana (y `profile.*`),
/// así que en casi todo el feed actual —que es seed— la mitad "datos" del
/// matching por prompt era inerte: ni ojos, ni complexión, ni altura.
const TRAIT_GROUPS: readonly string[] = ["appearance", "lifestyle", "profile"];

function asMap(value: unknown): DocumentData {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as DocumentData)
    : {};
}

/// Primer valor no vacío del campo, mirando la raíz y luego cada grupo.
function traitValue(data: DocumentData, field: string): unknown {
  const flat = data[field];
  if (flat !== undefined && flat !== null && flat !== "") return flat;
  for (const group of TRAIT_GROUPS) {
    const nested = asMap(data[group])[field];
    if (nested !== undefined && nested !== null && nested !== "") return nested;
  }
  return undefined;
}

/// Une todas las listas de texto con ese nombre (raíz + grupos), sin duplicar.
function traitStringList(data: DocumentData, field: string): string[] {
  const out: string[] = [];
  const push = (value: unknown): void => {
    if (!Array.isArray(value)) return;
    for (const item of value) {
      if (typeof item === "string" && item.length > 0 && !out.includes(item)) {
        out.push(item);
      }
    }
  };
  push(data[field]);
  for (const group of TRAIT_GROUPS) push(asMap(data[group])[field]);
  return out;
}

/// Datos DECLARADOS de un candidato para el matching por prompt (físico
/// declarado + texto de intereses/bio/prompts). Busca en `discovery` y, si no,
/// en `seed_profiles`. Todo lo ausente simplemente no puntúa.
async function profileDataForPrompt(uid: string): Promise<PromptProfileData> {
  let snap = await db.collection("discovery").doc(uid).get();
  if (!snap.exists) snap = await db.collection("seed_profiles").doc(uid).get();
  const data: DocumentData = snap.exists ? snap.data() ?? {} : {};
  const str = (v: unknown): string => (typeof v === "string" ? v : "");

  const interests: string[] = [
    ...traitStringList(data, "interests"),
    ...traitStringList(data, "socialInterests"),
    ...traitStringList(data, "personalityTags"),
  ];
  // Los prompts van en `profilePrompts` (discovery/seed) o en `profile.prompts`
  // (documento de usuario), y la respuesta puede llamarse answer/text.
  const promptDocs: DocumentData[] = [
    ...(Array.isArray(data.profilePrompts) ? (data.profilePrompts as DocumentData[]) : []),
    ...(Array.isArray(asMap(data.profile).prompts)
      ? (asMap(data.profile).prompts as DocumentData[])
      : []),
  ];
  const prompts: string[] = promptDocs.map(
    (p) => `${str(p?.question)} ${str(p?.answer) || str(p?.text)}`
  );
  const bio = str(traitValue(data, "bio"));
  const eyeColor = str(traitValue(data, "eyeColor")) || undefined;
  // El color de pelo vive donde el resto del físico: anidado en
  // `appearance.hairColor` (seed y documento de usuario) y plano en discovery.
  // OJO: lo de discovery es NUEVO — `hairColor` no estaba en PUBLIC_TRAITS, así
  // que hasta ahora este campo salía undefined para TODOS los usuarios reales y
  // la señal de pelo sólo funcionaba contra los bots de seed. Los documentos de
  // discovery ya existentes no lo tendrán hasta que se regeneren
  // (`buildDiscoveryDoc` se ejecuta al guardar el perfil); mientras tanto, para
  // esos usuarios el pelo cuenta como "no declarado", que es lo honesto.
  const hairColor = str(traitValue(data, "hairColor")) || undefined;
  const bodyType = str(traitValue(data, "bodyType")) || undefined;
  const gender = str(traitValue(data, "gender")) || undefined;
  const heightRaw = traitValue(data, "heightCm");
  const heightCm = typeof heightRaw === "number" ? heightRaw : undefined;
  return {
    gender,
    eyeColor,
    hairColor,
    bodyType,
    heightCm,
    personalityTags: traitStringList(data, "personalityTags"),
    text: [...interests, bio, ...prompts]
      .map((s) => s.trim())
      .filter((s) => s.length > 0)
      .join(" "),
  };
}

function cosine(a: number[], b: number[]): number {
  const n = Math.min(a.length, b.length);
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < n; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na === 0 || nb === 0) return 0;
  return dot / (Math.sqrt(na) * Math.sqrt(nb));
}

async function mapWithConcurrency<T, R>(
  items: T[],
  concurrency: number,
  fn: (item: T) => Promise<R>
): Promise<R[]> {
  const results = new Array<R>(items.length);
  let next = 0;
  const workers = Array.from(
    { length: Math.min(concurrency, items.length) },
    async () => {
      while (true) {
        const index = next;
        next += 1;
        if (index >= items.length) break;
        results[index] = await fn(items[index]);
      }
    }
  );
  await Promise.all(workers);
  return results;
}

/// Por qué no se pudo usar la referencia del usuario. Distinguirlo NO es un
/// detalle: "no tienes foto" le pide al usuario que suba una (y el cliente
/// borra el estado), mientras que "no he podido recalcularla ahora" es un fallo
/// nuestro y transitorio. Devolver lo mismo en los dos casos hacía que un 429 de
/// Vertex durante la migración v1→v2 le dijera "Sube una foto de referencia" a
/// alguien que la tenía subida y perfectamente guardada.
type ReferenceLookup =
  | {
      ok: true;
      embedding: number[];
      /// Rasgos YA guardados de la foto de referencia. Se devuelven con el
      /// ranking para que la app pueda volver a pintar el panel "lo que la IA ha
      /// leído de tu foto" al reabrirla: hasta ahora sólo se veían en la
      /// respuesta de `analyzeReferencePhoto`, o sea una única vez, aunque
      /// estuvieran persistidos en `aiReferences/{uid}.traits`.
      traits: Record<string, unknown> | null;
    }
  | { ok: false; reason: "none" | "unavailable" };

/// Embedding de la referencia del usuario, ya en la versión de preprocesado
/// ACTUAL.
///
/// Las referencias guardadas antes del recorte de cara (v1) son embeddings de la
/// foto ENTERA: compararlas con candidatos recortados daría un parecido sin
/// sentido. En vez de obligar al usuario a volver a subir la foto —que es
/// castigarle por un cambio nuestro— se recalcula aquí desde la foto que ya está
/// en Storage y se guarda migrada. Cuesta un embedding, una sola vez.
async function referenceEmbedding(
  uid: string,
  deadline?: number
): Promise<ReferenceLookup> {
  const refSnap = await aiRefs.doc(uid).get();
  const data = refSnap.data();
  const stored = data?.embedding;
  const version = data?.pipelineVersion;
  if (Array.isArray(stored) && version === EMBED_PIPELINE_VERSION) {
    return {
      ok: true,
      embedding: stored as number[],
      traits: (data?.traits as Record<string, unknown>) ?? null,
    };
  }
  const referencePath = data?.referencePath;
  if (typeof referencePath !== "string" || referencePath.length === 0) {
    // Sin foto guardada no hay nada que migrar. Si había un vector viejo, ya no
    // sirve: devolverlo sería comparar peras con manzanas.
    return { ok: false, reason: "none" };
  }
  try {
    const file = getStorage().bucket(STORAGE_BUCKET).file(referencePath);
    const [exists] = await file.exists();
    // La foto ya no está en el bucket: eso sí es "no hay referencia".
    if (!exists) return { ok: false, reason: "none" };
    const [buffer] = await file.download();
    const built = await buildReference(buffer, deadline);
    if (!built.embedding) {
      // La foto SIGUE AHÍ; lo que ha fallado es el motor (cuota de Vertex,
      // Vision caída). No se toca el documento: la referencia no se degrada por
      // un fallo transitorio, y el siguiente intento vuelve a probar.
      console.error(
        `[Vertex] migración de la referencia de ${uid} fallida: ${built.failure}`
      );
      return { ok: false, reason: "unavailable" };
    }
    await aiRefs
      .doc(uid)
      .set(
        {
          embedding: built.embedding,
          pipelineVersion: EMBED_PIPELINE_VERSION,
          traits: publicTraits(built.traits, built.cropped),
          status: "ready",
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      )
      .catch(() => undefined);
    console.log(`[Vertex] referencia de ${uid} migrada a v${EMBED_PIPELINE_VERSION}`);
    return {
      ok: true,
      embedding: built.embedding,
      traits: publicTraits(built.traits, built.cropped),
    };
  } catch (e) {
    console.error(`[Vertex] no se pudo migrar la referencia: ${(e as Error).message}`);
    return { ok: false, reason: "unavailable" };
  }
}

/// Traduce el fallo de la referencia al error que ve el cliente. El CÓDIGO es
/// lo que el cliente mira: `failed-precondition` = "no tienes referencia";
/// `unavailable` = "vuelve a intentarlo". Antes los dos eran lo mismo.
function referenceError(reason: "none" | "unavailable"): HttpsError {
  return reason === "none"
    ? new HttpsError(
        "failed-precondition",
        "Sube una foto de referencia para buscar parecidos."
      )
    : new HttpsError(
        "unavailable",
        "La IA no está disponible ahora mismo. Vuelve a intentarlo en un momento."
      );
}

/// getVisualMatches: ordena los candidatos del feed por SIMILITUD ESTÉTICA con
/// la foto de referencia del usuario (Attra Pro). El cliente envía los uids ya
/// filtrados; el backend devuelve [{uid, score}] ordenado. Caro acotado: max 80
/// candidatos, embeddings cacheados por hash.
export const getVisualMatches = onCall(
  {
    region: REGION,
    memory: "1GiB",
    timeoutSeconds: 60,
  },
  async (request) => {
    const deadline = Date.now() + VISUAL_TIME_BUDGET_MS;
    const uid = requireAuthUid(request.auth);
    await requireProAiConsent(uid);

    const refLookup = await referenceEmbedding(uid, deadline);
    if (!refLookup.ok) throw referenceError(refLookup.reason);
    const ref = refLookup.embedding;
    const referenceTraits = refLookup.traits;
    const candidateUids: string[] = Array.isArray(request.data?.candidateUids)
      ? Array.from(
          new Set(
            (request.data.candidateUids as unknown[]).filter(
              (x): x is string => typeof x === "string" && x.length > 0
            )
          )
        ).slice(0, VISUAL_MATCH_LIMIT)
      : [];
    const candidates = candidateUids.filter((cuid) => cuid !== uid);

    // Embeddings con concurrencia limitada. Las fotos mock pueden pesar varios MB:
    // procesarlas todas a la vez reventaba la Cloud Function por memoria.
    const scored = await mapWithConcurrency(
      candidates,
      VISUAL_EMBED_CONCURRENCY,
      async (cuid) => {
        // Agotado el presupuesto no se empieza a analizar a nadie más: se
        // marca como no evaluado y el cliente avisa de que falta gente.
        if (Date.now() > deadline) {
          return { uid: cuid, score: 0, state: "failed" as const };
        }
        const res = await embeddingForUserPhoto(cuid, deadline);
        // El estado va explícito: un score 0 legítimo y un "no se pudo" son
        // cosas distintas y no pueden compartir representación.
        if (res.ok) {
          return {
            uid: cuid,
            score: cosine(ref, res.embedding),
            state: "ok" as const,
          };
        }
        return {
          uid: cuid,
          score: 0,
          state: res.reason === "missing" ? ("missing" as const) : ("failed" as const),
        };
      }
    );
    const ranking = scored
      .filter((x) => x.state === "ok")
      .map((x) => ({ uid: x.uid, score: x.score }));
    // Candidatos que SÍ tenían foto pero no se pudieron puntuar (cuota de
    // Vertex, motor caído). No es lo mismo que "no encaja": el resultado está
    // incompleto y hay que decirlo, no devolver un ranking corto como si fuera
    // la respuesta completa.
    // Se devuelven los uids concretos, no sólo cuántos: el cliente cachea por
    // uid los que ya ha preguntado, y sin la lista marcaría como "ya
    // consultados" a los que fallaron y no volvería a pedirlos NUNCA. El fallo
    // por cuota es transitorio; tiene que poder reintentarse en la siguiente
    // recarga.
    const skippedUids = scored.filter((x) => x.state === "failed").map((x) => x.uid);
    const skipped = skippedUids.length;
    ranking.sort((a, b) => b.score - a.score);
    // Diagnóstico: cuántos candidatos llegaron a tener embedding (si es 0 con
    // candidatos > 0, las fotos no se pudieron embeber → revisar Vertex/URLs).
    console.log(
      `[Vertex] getVisualMatches: ${ranking.length}/${candidateUids.length} ` +
        `con embedding, ${skipped} sin puntuar por fallo del motor. ` +
        `top=${ranking[0]?.score?.toFixed(3) ?? "-"}`
    );
    return {
      ranking,
      /// false = faltan candidatos por puntuar; el cliente debe avisar en vez de
      /// presentar esto como el ranking definitivo.
      complete: skipped === 0,
      skipped,
      skippedUids,
      requested: candidates.length,
      /// Corte de "se parece / no se parece". Viaja con el ranking para que
      /// cambiar el preprocesado no obligue a desplegar la app (ver
      /// VISUAL_MATCH_THRESHOLD).
      threshold: VISUAL_MATCH_THRESHOLD,
      /// Rasgos de la foto de referencia (los mismos de analyzeReferencePhoto).
      /// Sin esto el panel de rasgos sólo se veía en la sesión en la que se
      /// subía la foto, pese a estar guardados.
      traits: referenceTraits,
    };
  }
);

/// getPromptMatches: busca candidatos que encajen con una DESCRIPCIÓN en
/// lenguaje natural ("chico alto, ojos azules, moreno, aventurero…"). Combina
/// dos señales de coste mínimo:
///   1) VISUAL: embedding de texto del prompt vs embeddings de foto YA cacheados
///      (mismo espacio multimodal). ~1 embedding de texto por búsqueda.
///   2) DATOS: encaje con lo declarado (ojos/complexión/altura/intereses/bio).
/// Es COMPLEMENTARIA a la búsqueda por foto de referencia (no la sustituye).
/// Devuelve [{uid, score, visualScore, dataScore, hasVisual, hasData}] ordenado
/// de más a menos.
export const getPromptMatches = onCall(
  { region: REGION, memory: "1GiB", timeoutSeconds: 60 },
  async (request) => {
    const deadline = Date.now() + VISUAL_TIME_BUDGET_MS;
    const uid = requireAuthUid(request.auth);
    await requireProAiConsent(uid);

    const prompt = requireStringArg(request.data?.prompt, "prompt").slice(0, 500);
    const signals = extractPromptSignals(prompt);
    const candidateUids: string[] = Array.isArray(request.data?.candidateUids)
      ? Array.from(
          new Set(
            (request.data.candidateUids as unknown[]).filter(
              (x): x is string => typeof x === "string" && x.length > 0
            )
          )
        ).slice(0, VISUAL_MATCH_LIMIT)
      : [];
    const candidates = candidateUids.filter((cuid) => cuid !== uid);
    if (candidates.length === 0) {
      return { ranking: [], complete: true, skipped: 0, requested: 0, signals: null };
    }

    // Embedding del prompt (para la parte VISUAL). Si Vertex no responde, el
    // ranking usa solo la parte de DATOS (no rompe).
    const promptEmbRes = await embedText(prompt);
    const promptEmb = promptEmbRes.ok ? promptEmbRes.embedding : null;

    const scored = await mapWithConcurrency(
      candidates,
      VISUAL_EMBED_CONCURRENCY,
      async (cuid) => {
        // Fuera de presupuesto no se embebe más (ver VISUAL_TIME_BUDGET_MS).
        // Los datos declarados sí se siguen leyendo: son una lectura de
        // Firestore, no cuestan IA, y permiten seguir puntuando algo.
        const outOfTime = Date.now() > deadline;
        const [photoRes, pdata] = await Promise.all([
          promptEmb && !outOfTime
            ? embeddingForUserPhoto(cuid, deadline)
            : Promise.resolve<PhotoEmbedResult>({
                ok: false,
                reason: outOfTime ? "rate_limited" : "missing",
              }),
          profileDataForPrompt(cuid),
        ]);
        // Se distingue "no tiene foto" de "no hemos podido mirarla": lo segundo
        // hace el resultado incompleto y hay que contarlo.
        const photoFailed = !photoRes.ok && photoRes.reason !== "missing";
        // Visual: coseno [-1..1] → [0..1].
        const visualScore =
          promptEmb && photoRes.ok
            ? Math.max(0, Math.min(1, (cosine(promptEmb, photoRes.embedding) + 1) / 2))
            : null;
        // dataScore = null cuando el prompt no pide ningún criterio puntuable
        // (p. ej. sólo el género, que va por veto).
        const dMatch = promptDataMatch(signals, pdata);
        const dScore = dMatch.score;
        // VETO / SUELO DE DATOS: si el perfil declara un género distinto al
        // pedido, o no hay ni una prueba de que encaje con lo que se escribió,
        // no entra. Antes esto se dejaba en manos de un umbral del cliente que
        // no daba: con la fórmula de abajo, `d` neutro sale exactamente 0.5 y
        // `_kPromptThreshold` valía 0.5, así que "no saber nada" pasaba SIEMPRE.
        const rejected = !passesDataFilter(dMatch);

        // Combinación MONÓTONA: subir el encaje de datos nunca puede bajar el
        // score. La fórmula anterior (`dScore > 0 ? 0.6v+0.4d : v`) era
        // discontinua en d=0: con d=0 valía v, pero con un d mínimo caía a
        // 0.6·v, así que un candidato que encajaba EN PARTE con lo pedido
        // quedaba por debajo de otro que no encajaba en nada.
        // Pesos: 60% parecido visual de la foto, 40% datos declarados. Si una de
        // las dos partes no es evaluable, la otra se lleva todo el peso (no se
        // puntúa como un 0, que sería penalizar la falta de dato).
        // Un dato NO evaluable vale NEUTRAL, no "todo el peso para la otra
        // parte". Darle a la parte visual el 100% cuando no hay datos repetia
        // el mismo sesgo que se queria eliminar: un perfil que no declara nada
        // (v=0.80 -> 0.80) seguia por encima de otro que cumple la mitad de lo
        // pedido (v=0.80, d=0.5 -> 0.68). Con el neutro ambos empatan, declarar
        // datos que encajan SUBE y declarar datos que no encajan BAJA, que es
        // el comportamiento que espera el usuario.
        const NEUTRAL = 0.5;
        const v = visualScore ?? NEUTRAL;
        const d = dScore ?? NEUTRAL;
        const score =
          VISUAL_PROMPT_WEIGHT * v + DATA_PROMPT_WEIGHT * d;

        return {
          uid: cuid,
          score,
          // Desglose para que el cliente pueda explicar el resultado. Los flags
          // distinguen "0 real" de "no evaluable".
          visualScore: visualScore ?? 0,
          dataScore: dScore ?? 0,
          hasVisual: visualScore !== null,
          hasData: dScore !== null,
          photoFailed,
          rejected,
        };
      }
    );
    // A quien NO se le pudo mirar la foto, FUERA del ranking (igual que hace
    // getVisualMatches con los mismos fallos). Antes se le sustituía la mitad
    // visual por un neutro 0.5 inventado y se le rankeaba igual: un candidato
    // sin mirar que declaraba todo lo pedido salía con 0.700, por ENCIMA de
    // otro al que sí se le miró la foto y encajaba igual pero puntuaba 0.670.
    // O sea, no saber nada de ti te subía. Además el aviso de "incompleto" dice
    // que FALTA gente, no que el ORDEN de la que sale esté contaminado.
    const ranking = scored
      .filter((x) => x.score > 0 && !x.photoFailed && !x.rejected)
      .map(({ photoFailed: _f, rejected: _r, ...rest }) => rest)
      .sort((a, b) => b.score - a.score);
    // El prompt sí se pudo embeber pero varias fotos no: el ranking está
    // sesgado hacia quien sí se pudo mirar. Se avisa, y se dice QUIÉNES para
    // que el cliente pueda reintentarlos (ver getVisualMatches).
    const skippedUids = scored.filter((x) => x.photoFailed).map((x) => x.uid);
    const skipped = skippedUids.length;
    const promptEmbFailed = !promptEmbRes.ok;
    console.log(
      `[Prompt] getPromptMatches: ${ranking.length}/${candidates.length} ` +
        `puntuados, ${skipped} sin foto evaluable por fallo del motor` +
        `${promptEmbFailed ? " (+ el prompt tampoco se pudo embeber)" : ""}. ` +
        `top=${ranking[0]?.score?.toFixed(3) ?? "-"}`
    );
    return {
      ranking,
      /// false = el motor falló en parte del cálculo; el cliente debe avisar.
      complete: skipped === 0 && !promptEmbFailed,
      skipped,
      skippedUids,
      requested: candidates.length,
      /// Sin embedding de texto el ranking sale SOLO de datos declarados. Es un
      /// resultado peor, no un resultado equivalente.
      visualDisabled: promptEmbFailed,
      /// Corte adicional para el cliente. Va a 0 A PROPÓSITO: el filtrado
      /// semántico ya se ha hecho AQUÍ (veto de género + suelo de datos +
      /// exclusión de quien no se pudo mirar), así que todo lo que sale en
      /// `ranking` YA cumple lo que el usuario pidió. El umbral que tenía el
      /// cliente (0.5 sobre el score combinado) era un segundo filtro sin
      /// calibrar que sólo podía quitar buenos resultados: la parte visual
      /// aporta ~0.33 casi constante, así que decidía por ruido, no por encaje.
      threshold: 0,
      /// Qué entendió el buscador. Sirve para que la app pueda enseñar "he
      /// buscado: chico · alto · fuerte · majo" en vez de dejar al usuario
      /// adivinando por qué salen esos perfiles.
      signals: {
        gender: signals.gender,
        eyeColors: signals.eyeColors,
        hairColors: signals.hairColors,
        bodyTypes: signals.bodyTypes,
        heightPref: signals.heightPref,
        personality: signals.personality,
        keywords: signals.keywords,
      },
    };
  }
);

/// getProfileInsights: sugerencias para mejorar el perfil y subir la
/// probabilidad de match. Las DETERMINISTAS (nº fotos, longitud de bio, prompts)
/// ya funcionan; las visuales (orden/calidad de fotos) requieren el proveedor.
export const getProfileInsights = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  await requireProAiConsent(uid);

  const snap = await col.users.doc(uid).get();
  const data: DocumentData = snap.data() ?? {};
  const profile: DocumentData =
    data.profile && typeof data.profile === "object" ? data.profile : {};
  const photos: unknown[] = Array.isArray(data.photos) ? data.photos : [];
  const prompts: unknown[] = Array.isArray(profile.prompts) ? profile.prompts : [];
  const bio = (profile.bio ?? "").toString();

  const insights: { id: string; severity: string; text: string }[] = [];
  if (photos.length < 4) {
    insights.push({
      id: "more_photos",
      severity: "high",
      text: `Sube más fotos (tienes ${photos.length}). Los perfiles con 4-6 fotos reciben más matches.`,
    });
  }
  if (bio.trim().length < 60) {
    insights.push({
      id: "longer_bio",
      severity: "medium",
      text: "Tu bio es corta. Una bio con personalidad mejora la conversión a match.",
    });
  }
  if (prompts.length < 2) {
    insights.push({
      id: "add_prompts",
      severity: "medium",
      text: "Añade al menos 2 prompts: dan tema de conversación y suben las respuestas.",
    });
  }
  // Punto de integración: orden óptimo de fotos y calidad visual (proveedor IA).
  insights.push({
    id: "photo_order_ai",
    severity: "info",
    text: "La sugerencia de orden y mejor foto principal se activará con el análisis visual.",
  });

  return { insights };
});

/// clearAiData: borra la huella visual del usuario (retirar consentimiento).
///
/// Borra las DOS cosas, no sólo la referencia: la huella de la foto que el
/// usuario subió PARA BUSCAR (`aiReferences` + el fichero de Storage) y los
/// embeddings derivados de SU PROPIA foto de perfil que se calcularon para
/// puntuarle cuando OTROS le tenían como candidato (`photoEmbeddings`). Estos
/// últimos no se tocaban: al retirar el consentimiento desaparecía la
/// referencia, pero el vector derivado de su cara seguía en Firestore sin
/// caducidad y se seguía usando para rankearle en el feed de terceros.
export const clearAiData = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const refSnap = await aiRefs.doc(uid).get();
  const path = refSnap.data()?.referencePath;
  if (typeof path === "string" && path.length > 0) {
    await getStorage().bucket(STORAGE_BUCKET).file(path).delete().catch(() => undefined);
  }
  await aiRefs.doc(uid).delete().catch(() => undefined);

  // Vectores de las fotos de perfil de ESTE usuario. Los cacheados antes de que
  // se guardara el `uid` no llevan el campo y no se pueden localizar: caducarán
  // por TTL. Se acota el borrado para no comerse la función si hubiera muchos.
  try {
    const mine = await photoEmbeddings.where("uid", "==", uid).limit(200).get();
    await Promise.all(mine.docs.map((d) => d.ref.delete().catch(() => undefined)));
    if (!mine.empty) {
      console.log(`[IA] clearAiData: ${mine.size} embeddings de foto borrados de ${uid}`);
    }
  } catch (e) {
    // No romper el borrado de la referencia por esto, pero SÍ dejar rastro: un
    // fallo aquí significa que ha quedado dato biométrico sin borrar.
    console.error(`[IA] clearAiData: no se pudieron borrar los embeddings de ${uid}: ${(e as Error).message}`);
  }
  return { ok: true };
});
