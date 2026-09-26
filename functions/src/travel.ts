import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { requireAuthUid } from "./common";
import { COUNTRY_NAME_TO_ISO2 } from "./countryNames";
import { geocodeLocality, placesApiKey } from "./places";

/// Modo viaje: utilidades de pais y el callable que situa el destino en el
/// mapa cuando el dataset offline de la app no puede (homonimos lejanos, web).

// --- Normalizacion: MISMA regla que `PlaceNames.normalize` (Dart),
// tool/gen_geo_assets.mjs y los scripts de Python. Si divergen, los nombres
// dejan de casar con el mapa generado.
const DIACRITICS: Readonly<Record<string, string>> = {
  á: "a", à: "a", â: "a", ä: "a", ã: "a", å: "a", ā: "a",
  é: "e", è: "e", ê: "e", ë: "e", ē: "e",
  í: "i", ì: "i", î: "i", ï: "i", ī: "i",
  ó: "o", ò: "o", ô: "o", ö: "o", õ: "o", ø: "o", ō: "o",
  ú: "u", ù: "u", û: "u", ü: "u", ū: "u",
  ñ: "n", ç: "c", ß: "ss", œ: "oe", æ: "ae",
};

export function normalizePlace(input: unknown): string {
  const lower = (typeof input === "string" ? input : "").toLowerCase().trim();
  if (!lower) return "";
  let out = "";
  for (const ch of lower) out += DIACRITICS[ch] ?? ch;
  return out.replace(/\s+/g, " ").trim();
}

/// ISO2 en mayusculas, o "" si no lo es.
export function normalizeIso2(value: unknown): string {
  const s = typeof value === "string" ? value.trim().toUpperCase() : "";
  return /^[A-Z]{2}$/.test(s) ? s : "";
}

/// ISO2 de un nombre de pais en cualquier idioma del dataset ('España',
/// 'Spain', 'Espagne', 'Espanya'...), o "" si no se reconoce. Es el ultimo
/// recurso para cuentas antiguas que solo guardaron el nombre.
export function iso2ForCountryName(name: string): string {
  const key = normalizePlace(name);
  return key ? COUNTRY_NAME_TO_ISO2[key] ?? "" : "";
}

/// Tope diario por usuario del callable: cada llamada sin cache es una
/// peticion de Places (Text Search Pro).
export const MAX_RESOLVES_PER_DAY = 20;
const CACHE_TTL_MS = 90 * 24 * 60 * 60 * 1000;

/// Clave de cache: pais + ciudad normalizada (sin caracteres raros).
export function geoCacheKey(iso2: string, city: string): string {
  const slug = normalizePlace(city)
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 120);
  return `${iso2}_${slug}`;
}

async function consumeDailyQuota(uid: string, nowMs: number): Promise<void> {
  const day = new Date(nowMs).toISOString().slice(0, 10);
  const ref = db.collection("travelGeoUsage").doc(`${uid}_${day}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const used = Number(snap.data()?.count ?? 0);
    if (used >= MAX_RESOLVES_PER_DAY) {
      throw new HttpsError(
        "resource-exhausted",
        "Has buscado demasiados destinos por hoy."
      );
    }
    tx.set(
      ref,
      {
        uid,
        day,
        count: used + 1,
        updatedAt: FieldValue.serverTimestamp(),
        expiresAt: new Date(nowMs + 48 * 60 * 60 * 1000),
      },
      { merge: true }
    );
  });
}

/// Callable: centro de `city` en el pais `iso2` ({lat, lng}) o null.
///
/// Solo lo llama la app si el dataset offline no tiene centro para esa
/// ciudad (y, en movil, tras el geocodificador del sistema). Cache de 90 dias
/// en `geoCache/{ISO2}_{ciudad}` (sin regla en firestore.rules: solo Admin) y
/// tope diario por usuario. Sin GOOGLE_PLACES_API_KEY devuelve null: el viaje
/// se guarda igual, a nivel de pais.
export const resolveTravelDestination = onCall(
  { region: REGION },
  async (request) => {
    const uid = requireAuthUid(request.auth);
    const iso2 = normalizeIso2(request.data?.iso2);
    const city =
      typeof request.data?.city === "string" ? request.data.city.trim() : "";
    if (!iso2 || !city || city.length > 120) {
      throw new HttpsError("invalid-argument", "Destino no valido.");
    }

    const cacheRef = db.collection("geoCache").doc(geoCacheKey(iso2, city));
    const nowMs = Date.now();
    try {
      const cached = await cacheRef.get();
      const data = cached.data();
      const at = (data?.updatedAt as Timestamp | undefined)?.toMillis?.() ?? 0;
      if (cached.exists && at && nowMs - at < CACHE_TTL_MS) {
        return data?.found === true
          ? { lat: data.lat as number, lng: data.lng as number, source: "server" }
          : null;
      }
    } catch {
      // Cache best-effort: si falla, se pregunta a Places.
    }

    // Sin clave no se gasta cuota ni se cachea el "no encontrado": en cuanto
    // se configure la clave, las mismas ciudades tienen que poder situarse.
    if (!placesApiKey()) return null;
    await consumeDailyQuota(uid, nowMs);
    const center = await geocodeLocality(city, iso2);
    // Tambien se cachea el "no encontrado": una ciudad que Places no conoce no
    // merece otra peticion en 90 dias.
    await cacheRef
      .set({
        iso2,
        city,
        found: center !== null,
        lat: center?.lat ?? null,
        lng: center?.lng ?? null,
        updatedAt: FieldValue.serverTimestamp(),
      })
      .catch(() => undefined);
    return center ? { lat: center.lat, lng: center.lng, source: "server" } : null;
  }
);
