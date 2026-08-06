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
  PromptProfileData,
} from "./promptMatch";

/// Referencias visuales (embeddings) por usuario. BACKEND-ONLY: el embedding
/// NUNCA se expone al cliente (es dato biométrico/categoría especial RGPD).
const aiRefs = db.collection("aiReferences");

/// Vertex AI multimodal embeddings: barato (~$0.0001/imagen), mismo ecosistema.
/// Embedding ESTÉTICO de imagen (no reconocimiento de identidad). Requiere
/// habilitar la API: `gcloud services enable aiplatform.googleapis.com`.
const VERTEX_PROJECT = "attra-database";
const VERTEX_LOCATION = "us-central1";
const VERTEX_MODEL = "multimodalembedding@001";
const VISUAL_MATCH_LIMIT = 80;
const VISUAL_EMBED_CONCURRENCY = 4;
/// Pesos del ranking por prompt cuando hay AMBAS señales (suman 1).
const VISUAL_PROMPT_WEIGHT = 0.6;
const DATA_PROMPT_WEIGHT = 0.4;
const auth = new GoogleAuth({
  scopes: ["https://www.googleapis.com/auth/cloud-platform"],
});

/// Calcula el embedding de imagen (1408 dims) con Vertex AI. Devuelve null si
/// la API no está disponible/habilitada (el flujo sigue como pending_provider).
async function embedImage(bytes: Buffer): Promise<number[] | null> {
  try {
    const token = await auth.getAccessToken();
    const url =
      `https://${VERTEX_LOCATION}-aiplatform.googleapis.com/v1/projects/` +
      `${VERTEX_PROJECT}/locations/${VERTEX_LOCATION}/publishers/google/models/` +
      `${VERTEX_MODEL}:predict`;
    const res = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        instances: [{ image: { bytesBase64Encoded: bytes.toString("base64") } }],
      }),
    });
    if (!res.ok) {
      // Diagnóstico: la causa más común es la API sin habilitar o el service
      // account sin rol aiplatform.user (403). Se ve en los logs de la función.
      const body = await res.text().catch(() => "");
      console.error(`[Vertex] embedImage HTTP ${res.status}: ${body.slice(0, 300)}`);
      return null;
    }
    const json = (await res.json()) as {
      predictions?: { imageEmbedding?: number[] }[];
    };
    const emb = json.predictions?.[0]?.imageEmbedding;
    if (!Array.isArray(emb)) {
      console.error("[Vertex] respuesta sin imageEmbedding");
      return null;
    }
    return emb;
  } catch (e) {
    console.error(`[Vertex] embedImage error: ${(e as Error).message}`);
    return null;
  }
}

/// Embedding de TEXTO en el MISMO espacio multimodal que las imágenes (permite
/// comparar una descripción con las fotos ya embebidas). Coste ínfimo (~1 texto
/// por búsqueda). Devuelve null si Vertex no está disponible.
async function embedText(text: string): Promise<number[] | null> {
  try {
    const token = await auth.getAccessToken();
    const url =
      `https://${VERTEX_LOCATION}-aiplatform.googleapis.com/v1/projects/` +
      `${VERTEX_PROJECT}/locations/${VERTEX_LOCATION}/publishers/google/models/` +
      `${VERTEX_MODEL}:predict`;
    const res = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        instances: [{ text: text.slice(0, 1024) }],
      }),
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      console.error(`[Vertex] embedText HTTP ${res.status}: ${body.slice(0, 300)}`);
      return null;
    }
    const json = (await res.json()) as {
      predictions?: { textEmbedding?: number[] }[];
    };
    const emb = json.predictions?.[0]?.textEmbedding;
    return Array.isArray(emb) ? emb : null;
  } catch (e) {
    console.error(`[Vertex] embedText error: ${(e as Error).message}`);
    return null;
  }
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

/// analyzeReferencePhoto: el usuario sube una foto de referencia (rostro del
/// "tipo" que le gusta) y el backend guarda una HUELLA VISUAL para mostrar
/// personas parecidas. Cachea por hash del objeto para no recomputar ni gastar.
///
/// NOTA: el cálculo real del embedding facial es un PUNTO DE INTEGRACIÓN con un
/// proveedor (AWS Rekognition face vectors / Vertex AI / modelo propio). Aquí se
/// valida, se cachea por hash y se deja `embedding: null` (pendiente proveedor).
/// NUNCA inferir raza/etnia/religión/orientación: solo similitud estética.
export const analyzeReferencePhoto = onCall({ region: REGION }, async (request) => {
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
  if (
    existing.exists &&
    existing.data()?.photoHash === photoHash &&
    existing.data()?.status === "ready"
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
    return { status: "ready", cached: true };
  }

  // Embedding estético con Vertex AI (si la API está habilitada).
  const [buffer] = await file.download();
  const embedding = await embedImage(buffer);
  const status = embedding ? "ready" : "pending_provider";
  await aiRefs.doc(uid).set(
    {
      referencePath,
      photoHash,
      embedding, // vector estético (NO identidad). Backend-only, nunca al cliente.
      status,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return { status, cached: false };
});

/// Embeddings de fotos cacheados por hash de contenido (md5). BACKEND-ONLY.
const photoEmbeddings = db.collection("photoEmbeddings");

/// Clave de caché de un embedding de foto. Antes se hacía base64 del valor y se
/// cortaba a 80 caracteres: el prefijo común de una URL de Firebase Storage
/// (`https://firebasestorage.googleapis.com/v0/b/<bucket>/o/`) ya ocupa más que
/// eso, así que TODAS las fotos servidas por URL caían en la misma clave,
/// compartían embedding y la búsqueda por parecido les daba idéntico score.
/// Un hash del valor COMPLETO no colisiona y no depende de la longitud.
function embeddingCacheKey(kind: "md5" | "url", value: string): string {
  return `${kind}_${createHash("sha256").update(value).digest("hex")}`;
}

/// Embedding (cacheado) de la foto principal de un candidato del feed.
/// Busca primero en `discovery` (usuarios reales) y, si no existe, en
/// `seed_profiles` (perfiles mock/bot). Así la IA visual también puede ordenar
/// los perfiles de prueba (mock_*) por parecido a la referencia.
async function embeddingForUserPhoto(uid: string): Promise<number[] | null> {
  let snap = await db.collection("discovery").doc(uid).get();
  if (!snap.exists) {
    snap = await db.collection("seed_profiles").doc(uid).get();
  }
  if (!snap.exists) return null;
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
      if (!exists) return null;
      const [meta] = await file.getMetadata();
      const md5 = (meta.md5Hash ?? "").toString();
      if (!md5) return null;
      // Se hashea el md5 entero: quitarle los "+/=" del base64 podía fundir dos
      // digests distintos en la misma clave.
      cacheKey = embeddingCacheKey("md5", md5);
      const cached = await photoEmbeddings.doc(cacheKey).get();
      if (cached.exists && Array.isArray(cached.data()?.embedding)) {
        return cached.data()!.embedding as number[];
      }
      [buffer] = await file.download();
    } else if (photoUrl) {
      const res = await fetch(photoUrl);
      if (!res.ok) return null;
      buffer = Buffer.from(await res.arrayBuffer());
      cacheKey = embeddingCacheKey("url", photoUrl);
      const cached = await photoEmbeddings.doc(cacheKey).get();
      if (cached.exists && Array.isArray(cached.data()?.embedding)) {
        return cached.data()!.embedding as number[];
      }
    } else {
      return null;
    }
  } catch {
    return null;
  }

  const emb = buffer ? await embedImage(buffer) : null;
  if (emb && cacheKey) {
    await photoEmbeddings
      .doc(cacheKey)
      .set({ embedding: emb, updatedAt: FieldValue.serverTimestamp() })
      .catch(() => undefined);
  }
  return emb;
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
  const bodyType = str(traitValue(data, "bodyType")) || undefined;
  const heightRaw = traitValue(data, "heightCm");
  const heightCm = typeof heightRaw === "number" ? heightRaw : undefined;
  return {
    eyeColor,
    bodyType,
    heightCm,
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
    const uid = requireAuthUid(request.auth);
    await requireProAiConsent(uid);

    const refSnap = await aiRefs.doc(uid).get();
    const ref = refSnap.data()?.embedding;
    if (!Array.isArray(ref)) {
      throw new HttpsError(
        "failed-precondition",
        "Sube una foto de referencia para buscar parecidos."
      );
    }
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
        const emb = await embeddingForUserPhoto(cuid);
        return emb ? { uid: cuid, score: cosine(ref as number[], emb) } : null;
      }
    );
    const ranking = scored.filter(
      (x): x is { uid: string; score: number } => x !== null
    );
    ranking.sort((a, b) => b.score - a.score);
    // Diagnóstico: cuántos candidatos llegaron a tener embedding (si es 0 con
    // candidatos > 0, las fotos no se pudieron embeber → revisar Vertex/URLs).
    console.log(
      `[Vertex] getVisualMatches: ${ranking.length}/${candidateUids.length} ` +
        `con embedding. top=${ranking[0]?.score?.toFixed(3) ?? "-"}`
    );
    return { ranking };
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
    if (candidates.length === 0) return { ranking: [] };

    // Embedding del prompt (para la parte VISUAL). Si Vertex no responde, el
    // ranking usa solo la parte de DATOS (no rompe).
    const promptEmb = await embedText(prompt);

    const scored = await mapWithConcurrency(
      candidates,
      VISUAL_EMBED_CONCURRENCY,
      async (cuid) => {
        const [photoEmb, pdata] = await Promise.all([
          promptEmb ? embeddingForUserPhoto(cuid) : Promise.resolve(null),
          profileDataForPrompt(cuid),
        ]);
        // Visual: coseno [-1..1] → [0..1].
        const visualScore =
          promptEmb && photoEmb
            ? Math.max(0, Math.min(1, (cosine(promptEmb, photoEmb) + 1) / 2))
            : null;
        // dataScore = null cuando no hay NADA comparable (prompt sin señales o
        // el perfil no declara ninguno de los campos pedidos).
        const dScore = promptDataMatch(signals, pdata).score;

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
        };
      }
    );
    const ranking = scored
      .filter((x) => x.score > 0)
      .sort((a, b) => b.score - a.score);
    console.log(
      `[Prompt] getPromptMatches: ${ranking.length}/${candidates.length} ` +
        `puntuados. top=${ranking[0]?.score?.toFixed(3) ?? "-"}`
    );
    return { ranking };
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
export const clearAiData = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const refSnap = await aiRefs.doc(uid).get();
  const path = refSnap.data()?.referencePath;
  if (typeof path === "string" && path.length > 0) {
    await getStorage().bucket(STORAGE_BUCKET).file(path).delete().catch(() => undefined);
  }
  await aiRefs.doc(uid).delete().catch(() => undefined);
  return { ok: true };
});
