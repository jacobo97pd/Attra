import 'package:flutter/foundation.dart';

/// Puente entre el push (sin contexto de navegación) y la UI (HomeShell, que
/// cambia de pestaña). Cuando se TOCA una notificación (app en background o
/// cerrada), PushService deja aquí la ruta lógica y HomeShell la consume.
///
/// Singleton sencillo: evita acoplar PushService con el árbol de widgets.
class NotificationRouter {
  NotificationRouter._();
  static final NotificationRouter instance = NotificationRouter._();

  /// Ruta pendiente (ej: 'chats', 'likes', 'feed', 'profile', 'chat:{id}').
  /// HomeShell escucha y la consume.
  final ValueNotifier<String?> pendingRoute = ValueNotifier<String?>(null);

  void open(String? route) {
    final String r = (route ?? '').trim();
    if (r.isEmpty) return;
    pendingRoute.value = r;
  }

  /// Devuelve y limpia la ruta pendiente (one-shot).
  String? consume() {
    final String? r = pendingRoute.value;
    pendingRoute.value = null;
    return r;
  }
}
