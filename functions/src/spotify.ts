import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { REGION, db } from "./firebase";
import { col, requireAuthUid, requireStringArg } from "./common";

/// Credenciales de la app de Spotify (variables de entorno, NO Secret Manager,
/// para no bloquear el deploy del resto de funciones mientras Spotify no este
/// configurado). El CLIENT_ID es publico; el SECRET es confidencial. Se leen de
/// forma perezosa (al invocar), no al cargar el modulo. Configurar en
/// `functions/.env` (o `functions/.env.attra-database`):
///   SPOTIFY_CLIENT_ID=xxxx
///   SPOTIFY_CLIENT_SECRET=yyyy
/// (Si en el futuro quieres Secret Manager, habilita su API y vuelve a
///  defineSecret.)
function spotifyCreds(): { clientId: string; clientSecret: string } {
  const clientId = process.env.SPOTIFY_CLIENT_ID ?? "";
  const clientSecret = process.env.SPOTIFY_CLIENT_SECRET ?? "";
  if (!clientId || !clientSecret) {
    throw new HttpsError(
      "failed-precondition",
      "Spotify no está configurado en el servidor (faltan credenciales)."
    );
  }
  return { clientId, clientSecret };
}

/// Tokens privados por usuario. NUNCA se exponen al cliente (reglas: write/read
/// = false). Solo el backend (Admin SDK) los usa para refrescar y leer datos.
const tokensCol = db.collection("spotifyTokens");

interface SpotifyArtist {
  name: string;
  imageUrl: string | null;
  genres: string[];
}

/// Intercambia el authorization code por tokens (flujo Authorization Code).
async function exchangeCode(
  code: string,
  redirectUri: string,
  clientId: string,
  clientSecret: string
): Promise<{ accessToken: string; refreshToken: string; expiresIn: number; scope: string }> {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: redirectUri,
  });
  const res = await fetch("https://accounts.spotify.com/api/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization:
        "Basic " + Buffer.from(`${clientId}:${clientSecret}`).toString("base64"),
    },
    body,
  });
  if (!res.ok) {
    throw new HttpsError("permission-denied", "Spotify rechazo la autorizacion.");
  }
  const json = (await res.json()) as Record<string, unknown>;
  return {
    accessToken: String(json.access_token ?? ""),
    refreshToken: String(json.refresh_token ?? ""),
    expiresIn: Number(json.expires_in ?? 3600),
    scope: String(json.scope ?? ""),
  };
}

/// Renueva el access token con el refresh token.
async function refreshAccessToken(
  refreshToken: string,
  clientId: string,
  clientSecret: string
): Promise<{ accessToken: string; expiresIn: number }> {
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: refreshToken,
  });
  const res = await fetch("https://accounts.spotify.com/api/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization:
        "Basic " + Buffer.from(`${clientId}:${clientSecret}`).toString("base64"),
    },
    body,
  });
  if (!res.ok) {
    throw new HttpsError("failed-precondition", "No se pudo renovar Spotify.");
  }
  const json = (await res.json()) as Record<string, unknown>;
  return {
    accessToken: String(json.access_token ?? ""),
    expiresIn: Number(json.expires_in ?? 3600),
  };
}

/// Lee los artistas mas escuchados (scope user-top-read).
async function fetchTopArtists(accessToken: string): Promise<SpotifyArtist[]> {
  const res = await fetch(
    "https://api.spotify.com/v1/me/top/artists?limit=10&time_range=medium_term",
    { headers: { Authorization: `Bearer ${accessToken}` } }
  );
  if (!res.ok) return [];
  const json = (await res.json()) as { items?: Record<string, unknown>[] };
  const items = Array.isArray(json.items) ? json.items : [];
  return items.map((a) => {
    const images = Array.isArray(a.images) ? (a.images as Record<string, unknown>[]) : [];
    return {
      name: String(a.name ?? ""),
      imageUrl: images.length > 0 ? String(images[0].url ?? "") : null,
      genres: Array.isArray(a.genres) ? (a.genres as string[]).slice(0, 3) : [],
    };
  });
}

/// Escribe el resumen PUBLICO (artistas) en el perfil y marca la conexion.
async function writePublicSummary(uid: string, artists: SpotifyArtist[]): Promise<void> {
  await col.users.doc(uid).set(
    {
      profile: {
        spotify: {
          connected: true,
          topArtists: artists,
          syncedAt: FieldValue.serverTimestamp(),
        },
      },
    },
    { merge: true }
  );
}

/// spotifyConnect: el cliente envia el `code` obtenido en el redirect OAuth.
/// El backend lo canjea por tokens, guarda el refresh token (privado), lee los
/// artistas top y publica el resumen. Devuelve los artistas para la UI.
export const spotifyConnect = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const code = requireStringArg(request.data?.code, "code");
  const redirectUri = requireStringArg(request.data?.redirectUri, "redirectUri");

  const { clientId, clientSecret } = spotifyCreds();

  const tokens = await exchangeCode(code, redirectUri, clientId, clientSecret);
    if (!tokens.accessToken) {
      throw new HttpsError("permission-denied", "Spotify no devolvio token.");
    }

    const artists = await fetchTopArtists(tokens.accessToken);

    await tokensCol.doc(uid).set(
      {
        refreshToken: tokens.refreshToken,
        accessToken: tokens.accessToken,
        scope: tokens.scope,
        expiresAt: Date.now() + tokens.expiresIn * 1000,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  await writePublicSummary(uid, artists);

  return { connected: true, topArtists: artists };
});

/// spotifyRefresh: re-sincroniza artistas usando el refresh token guardado.
export const spotifyRefresh = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  const snap = await tokensCol.doc(uid).get();
  const refreshToken = snap.data()?.refreshToken as string | undefined;
  if (!refreshToken) {
    throw new HttpsError("failed-precondition", "Spotify no esta conectado.");
  }
  const { clientId, clientSecret } = spotifyCreds();
  const { accessToken, expiresIn } = await refreshAccessToken(
    refreshToken,
    clientId,
    clientSecret
  );
  const artists = await fetchTopArtists(accessToken);
  await tokensCol.doc(uid).set(
    { accessToken, expiresAt: Date.now() + expiresIn * 1000, updatedAt: FieldValue.serverTimestamp() },
    { merge: true }
  );
  await writePublicSummary(uid, artists);
  return { connected: true, topArtists: artists };
});

/// spotifyDisconnect: borra tokens y limpia el resumen publico.
export const spotifyDisconnect = onCall({ region: REGION }, async (request) => {
  const uid = requireAuthUid(request.auth);
  await tokensCol.doc(uid).delete().catch(() => undefined);
  await col.users.doc(uid).set(
    { profile: { spotify: { connected: false, topArtists: [] } } },
    { merge: true }
  );
  return { ok: true };
});
