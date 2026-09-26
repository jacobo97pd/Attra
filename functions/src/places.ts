import { FieldValue } from "firebase-admin/firestore";
import { db } from "./firebase";
import { passesPlaceQuality } from "./datePlanRules";

/// Cliente de Google Places API (New) — SOLO server-side. La IA razona, Places
/// verifica: nunca inventamos sitios. Coste controlado con:
///  - FieldMask (solo campos baratos que usamos).
///  - Caché por consulta (`placesCache/{key}`, TTL 7 días) → repeticiones = 0€.
///  - `date_plans_places_enabled` + presencia de GOOGLE_PLACES_API_KEY (si falta,
///    el generador usa fallback y NO llama a Google).
///
/// La key se lee de forma perezosa de `process.env.GOOGLE_PLACES_API_KEY`
/// (configúrala en `functions/.env.attra-database`). Mismo patrón que Spotify.

const PLACES_ENDPOINT = "https://places.googleapis.com/v1/places:searchText";
const CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const MAX_RESULTS = 5;

/// Campos MÍNIMOS (SKU económico). No pedimos fotos, horarios detallados, etc.
const FIELD_MASK = [
  "places.id",
  "places.displayName",
  "places.formattedAddress",
  "places.rating",
  "places.userRatingCount",
  "places.priceLevel",
  "places.googleMapsUri",
  "places.primaryTypeDisplayName",
].join(",");

export interface PlaceResult {
  placeId: string;
  name: string;
  address: string;
  rating?: number;
  reviewCount?: number;
  priceLevel?: number;
  mapsUrl: string;
  placeType: string;
}

export function placesApiKey(): string {
  return process.env.GOOGLE_PLACES_API_KEY ?? "";
}

/// price_level (enum del API New) → 0-4.
function mapPriceLevel(v: unknown): number | undefined {
  switch (v) {
    case "PRICE_LEVEL_FREE":
      return 0;
    case "PRICE_LEVEL_INEXPENSIVE":
      return 1;
    case "PRICE_LEVEL_MODERATE":
      return 2;
    case "PRICE_LEVEL_EXPENSIVE":
      return 3;
    case "PRICE_LEVEL_VERY_EXPENSIVE":
      return 4;
    default:
      return undefined;
  }
}

/// Clave de caché estable a partir de la consulta normalizada.
function cacheKey(query: string): string {
  return query
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 200);
}

function parsePlaces(json: unknown): PlaceResult[] {
  const places = (json as { places?: unknown[] })?.places;
  if (!Array.isArray(places)) return [];
  const out: PlaceResult[] = [];
  for (const p of places) {
    const o = p as Record<string, unknown>;
    const id = typeof o.id === "string" ? o.id : "";
    if (!id) continue;
    const name =
      ((o.displayName as { text?: string } | undefined)?.text ?? "").toString();
    const type =
      ((o.primaryTypeDisplayName as { text?: string } | undefined)?.text ?? "")
        .toString();
    out.push({
      placeId: id,
      name,
      address: (o.formattedAddress ?? "").toString(),
      rating: typeof o.rating === "number" ? o.rating : undefined,
      reviewCount:
        typeof o.userRatingCount === "number" ? o.userRatingCount : undefined,
      priceLevel: mapPriceLevel(o.priceLevel),
      mapsUrl: (o.googleMapsUri ?? "").toString(),
      placeType: type,
    });
  }
  return out;
}

/// Busca lugares para `query` (p. ej. "quiet coffee shop near Chamberí, Madrid").
/// Devuelve resultados que pasan el filtro de calidad, mejor valorados primero.
/// Cachea la respuesta cruda por consulta. Si no hay key o Places falla,
/// devuelve [] (el generador aplica fallback, nunca inventa sitios).
export async function searchPlaces(query: string): Promise<PlaceResult[]> {
  const key = placesApiKey();
  if (!key) return [];

  const ck = cacheKey(query);
  const cacheRef = db.collection("placesCache").doc(ck);
  try {
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data() ?? {};
      const ts = (data.updatedAt?.toMillis?.() ?? 0) as number;
      if (ts && Date.now() - ts < CACHE_TTL_MS && Array.isArray(data.results)) {
        return rank(data.results as PlaceResult[]);
      }
    }
  } catch {
    // Caché best-effort: si falla, seguimos a la API.
  }

  let results: PlaceResult[] = [];
  try {
    const res = await fetch(PLACES_ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": key,
        "X-Goog-FieldMask": FIELD_MASK,
      },
      body: JSON.stringify({
        textQuery: query,
        maxResultCount: MAX_RESULTS,
        // Sesga a sitios abiertos (no filtra duro; la disponibilidad exacta se
        // confirma al abrir en Maps).
        openNow: false,
      }),
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      console.error(`[Places] HTTP ${res.status}: ${body.slice(0, 300)}`);
      return [];
    }
    results = parsePlaces(await res.json());
  } catch (e) {
    console.error(`[Places] error: ${(e as Error).message}`);
    return [];
  }

  // Cachea el crudo (best-effort).
  await cacheRef
    .set({ query, results, updatedAt: FieldValue.serverTimestamp() })
    .catch(() => undefined);

  return rank(results);
}

/// Centro de una LOCALIDAD (ciudad/pueblo) para el modo viaje: el dataset
/// offline de la app no tiene centro para los homónimos lejanos y en web no hay
/// geocodificador del sistema. Pide solo `places.location` y `places.types`
/// (nada de fotos ni reseñas), sesgado al país con `regionCode` y al tipo
/// `locality`. Devuelve null sin key, si Places falla o si lo que devuelve no
/// es una localidad (mejor sin centro que en un bar con el mismo nombre).
export async function geocodeLocality(
  city: string,
  iso2: string
): Promise<{ lat: number; lng: number } | null> {
  const key = placesApiKey();
  if (!key || !city.trim() || !/^[A-Z]{2}$/.test(iso2)) return null;
  try {
    const res = await fetch(PLACES_ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": key,
        "X-Goog-FieldMask": "places.location,places.types",
      },
      body: JSON.stringify({
        textQuery: city.trim(),
        includedType: "locality",
        strictTypeFiltering: true,
        regionCode: iso2,
        maxResultCount: 1,
      }),
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      console.error(`[Places] locality HTTP ${res.status}: ${body.slice(0, 300)}`);
      return null;
    }
    return parseLocality(await res.json());
  } catch (e) {
    console.error(`[Places] locality error: ${(e as Error).message}`);
    return null;
  }
}

/// Extrae el centro de la primera localidad de una respuesta de searchText.
export function parseLocality(json: unknown): { lat: number; lng: number } | null {
  const places = (json as { places?: unknown[] })?.places;
  if (!Array.isArray(places) || places.length === 0) return null;
  const first = places[0] as Record<string, unknown>;
  const types = Array.isArray(first.types) ? (first.types as unknown[]) : [];
  if (!types.includes("locality")) return null;
  const loc = first.location as { latitude?: unknown; longitude?: unknown } | undefined;
  const lat = typeof loc?.latitude === "number" ? loc.latitude : NaN;
  const lng = typeof loc?.longitude === "number" ? loc.longitude : NaN;
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  return { lat, lng };
}

/// Filtra por calidad y ordena por rating (desc), luego nº de reseñas.
function rank(results: PlaceResult[]): PlaceResult[] {
  return results
    .filter((r) => passesPlaceQuality(r.rating, r.reviewCount))
    .sort((a, b) => {
      const dr = (b.rating ?? 0) - (a.rating ?? 0);
      if (Math.abs(dr) > 0.001) return dr;
      return (b.reviewCount ?? 0) - (a.reviewCount ?? 0);
    });
}
