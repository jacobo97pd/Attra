import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../../settings/domain/setting_definition.dart';
import '../domain/integration_connector.dart';
import '../integrations_config.dart';

/// Conecta Spotify con el flujo Authorization Code:
/// 1. Abre la pantalla de consentimiento de Spotify (flutter_web_auth_2).
/// 2. Captura el `code` del redirect.
/// 3. Lo envia a la Cloud Function `spotifyConnect`, que canjea el token con el
///    client SECRET (que nunca toca el cliente), lee los artistas y los guarda.
class SpotifyAuthService implements IntegrationConnector {
  SpotifyAuthService({required FirebaseFunctions functions})
      : _functions = functions;

  final FirebaseFunctions _functions;

  static const String _settingKey = 'integrations.spotify';

  @override
  bool handles(String settingKey) => settingKey == _settingKey;

  @override
  Future<bool> connect(SettingDefinition def) async {
    if (!IntegrationsConfig.isSpotifyConfigured) {
      throw const IntegrationException(
          'Spotify no está configurado todavía (falta el Client ID).');
    }

    final String state = _randomState();
    final Uri authorizeUrl =
        Uri.parse('https://accounts.spotify.com/authorize').replace(
      queryParameters: <String, String>{
        'response_type': 'code',
        'client_id': IntegrationsConfig.spotifyClientId,
        'scope': IntegrationsConfig.spotifyScopes,
        'redirect_uri': IntegrationsConfig.spotifyRedirectUri,
        'state': state,
      },
    );

    final String resultUrl;
    try {
      resultUrl = await FlutterWebAuth2.authenticate(
        url: authorizeUrl.toString(),
        callbackUrlScheme: IntegrationsConfig.spotifyCallbackScheme,
      );
    } catch (e) {
      // Cancelacion del usuario o fallo de la ventana OAuth.
      if (kDebugMode) debugPrint('[Spotify] auth cancelada/fallida: $e');
      return false;
    }

    final Uri redirect = Uri.parse(resultUrl);
    final String? error = redirect.queryParameters['error'];
    if (error != null) {
      throw IntegrationException('Spotify denegó el acceso ($error).');
    }
    if (redirect.queryParameters['state'] != state) {
      throw const IntegrationException(
          'Respuesta de Spotify no válida (state).');
    }
    final String? code = redirect.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw const IntegrationException('Spotify no devolvió código.');
    }

    try {
      await _functions.httpsCallable('spotifyConnect').call<dynamic>(
        <String, dynamic>{
          'code': code,
          'redirectUri': IntegrationsConfig.spotifyRedirectUri,
        },
      );
      return true;
    } on FirebaseFunctionsException catch (e) {
      throw IntegrationException(e.message ?? 'No se pudo conectar Spotify.');
    }
  }

  @override
  Future<void> disconnect(SettingDefinition def) async {
    try {
      await _functions.httpsCallable('spotifyDisconnect').call<dynamic>();
    } on FirebaseFunctionsException catch (e) {
      throw IntegrationException(
          e.message ?? 'No se pudo desconectar Spotify.');
    }
  }

  String _randomState() {
    final Random rng = Random.secure();
    return List<int>.generate(16, (_) => rng.nextInt(256))
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
