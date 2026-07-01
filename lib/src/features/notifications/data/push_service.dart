import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notification_router.dart';

/// Gestiona el push (FCM): permiso, token y registro del token en el backend
/// (`users/{uid}.fcmTokens` via callable `registerPushToken`). El contenido de
/// la notificación lo genera el backend (triggers en notifications.ts).
///
/// Best-effort y defensivo: si FCM no está configurado en la plataforma o falla,
/// no rompe nada (la bandeja in-app sigue funcionando por Firestore).
class PushService {
  PushService({required FirebaseFunctions functions}) : _functions = functions;

  final FirebaseFunctions _functions;
  String? _lastToken;
  bool _started = false;

  /// Pide permiso, obtiene el token y lo registra. Idempotente por sesión.
  Future<void> init(String uid) async {
    if (uid.isEmpty || _started) return;
    // FCM web requiere VAPID + service worker (configuración aparte). En desktop
    // no aplica. Lo activamos en móvil; en el resto, no-op silencioso.
    if (kIsWeb ||
        !(defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      return;
    }
    _started = true;
    try {
      final FirebaseMessaging messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // iOS: el token FCM (getToken) requiere que el token APNs esté disponible.
      // Justo tras arrancar puede tardar un instante; si pedimos getToken antes,
      // devuelve null y el token nunca se registra. Esperamos el APNs token
      // (con reintentos cortos) antes de pedir el FCM. No-op en Android.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        String? apns = await messaging.getAPNSToken();
        int tries = 0;
        while (apns == null && tries < 6) {
          await Future<void>.delayed(const Duration(seconds: 1));
          apns = await messaging.getAPNSToken();
          tries++;
        }
        if (apns == null && kDebugMode) {
          debugPrint('[push] sin token APNs (¿entitlement/APNs key?).');
        }
      }

      final String? token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        _lastToken = token;
        await _register(token);
      }
      // Re-registra si el token rota.
      messaging.onTokenRefresh.listen((String t) {
        _lastToken = t;
        _register(t);
      });
      // Mensajes en primer plano: la bandeja in-app ya se actualiza por
      // Firestore (el backend escribió el doc), así que no duplicamos UI aquí.
      FirebaseMessaging.onMessage.listen((RemoteMessage m) {
        if (kDebugMode) {
          debugPrint('[push] foreground: ${m.notification?.title}');
        }
      });

      // Tap con la app CERRADA: la notificación que la abrió.
      final RemoteMessage? initial = await messaging.getInitialMessage();
      if (initial != null) {
        NotificationRouter.instance.open(_routeOf(initial));
      }
      // Tap con la app en BACKGROUND: navega a la pantalla correcta.
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage m) {
        NotificationRouter.instance.open(_routeOf(m));
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[push] init falló -> $e');
    }
  }

  /// Extrae la ruta lógica del payload de datos (la pone el backend en `data`).
  String? _routeOf(RemoteMessage m) {
    final Object? r = m.data['route'];
    return r is String && r.isNotEmpty ? r : 'feed';
  }

  Future<void> _register(String token) async {
    try {
      await _functions
          .httpsCallable('registerPushToken')
          .call<dynamic>(<String, dynamic>{'token': token});
    } catch (e) {
      if (kDebugMode) debugPrint('[push] registerPushToken falló -> $e');
    }
  }

  /// Quita el token actual al cerrar sesión (deja de recibir push).
  Future<void> unregister() async {
    final String? token = _lastToken;
    _started = false;
    if (token == null) return;
    try {
      await _functions
          .httpsCallable('unregisterPushToken')
          .call<dynamic>(<String, dynamic>{'token': token});
    } catch (_) {/* best-effort */}
  }
}
