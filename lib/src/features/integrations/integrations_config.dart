/// Configuracion de integraciones externas (valores PUBLICOS). Los secretos
/// (client secret) viven SOLO en Cloud Functions, nunca aqui.
///
/// Rellena estos valores tras crear la app en https://developer.spotify.com:
///   1. Crea una app -> obtienes el Client ID.
///   2. En "Redirect URIs" añade EXACTAMENTE las URIs de abajo (web y movil).
///   3. Pega aqui el Client ID. El Client SECRET va en el backend:
///        firebase functions:secrets:set SPOTIFY_CLIENT_ID
///        firebase functions:secrets:set SPOTIFY_CLIENT_SECRET
///
/// Se pueden inyectar en compilacion con --dart-define para no commitearlos:
///   flutter run --dart-define=SPOTIFY_CLIENT_ID=xxxx
class IntegrationsConfig {
  const IntegrationsConfig._();

  /// Client ID publico de Spotify. Placeholder hasta crear la app.
  static const String spotifyClientId = String.fromEnvironment(
    'SPOTIFY_CLIENT_ID',
    defaultValue: 'YOUR_SPOTIFY_CLIENT_ID',
  );

  /// Esquema de callback para movil (flutter_web_auth_2). Debe declararse en
  /// AndroidManifest.xml e Info.plist. La redirect URI movil sera
  /// `${spotifyCallbackScheme}://spotify-callback`.
  static const String spotifyCallbackScheme = 'attra';

  /// Redirect URI EXACTA registrada en el dashboard de Spotify. Debe coincidir
  /// byte a byte con la usada en authorize y en el canje de token (backend).
  /// - Movil: 'attra://spotify-callback'
  /// - Web:   'https://<tu-dominio>/spotify-callback.html' (ver web/).
  static const String spotifyRedirectUri = String.fromEnvironment(
    'SPOTIFY_REDIRECT_URI',
    defaultValue: 'attra://spotify-callback',
  );

  /// Scopes solicitados. user-top-read = artistas/canciones top.
  static const String spotifyScopes = 'user-top-read';

  static bool get isSpotifyConfigured =>
      spotifyClientId != 'YOUR_SPOTIFY_CLIENT_ID' && spotifyClientId.isNotEmpty;
}
