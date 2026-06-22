import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipo de notificación. Cada uno tiene copy con personalidad + emoji + acento
/// de color corporativo (la UI mapea el acento a AppColors).
enum AppNotificationKind {
  newLike('new_like'),
  newMatch('new_match'),
  newMessage('new_message'),
  attraReceived('attra_received'),
  likesWaiting('likes_waiting'),
  comeBack('come_back'),
  sparkInvite('spark_invite'),
  dateProposed('date_proposed'),
  profileOnFire('profile_on_fire'),
  dailyLikesReset('daily_likes_reset'),
  matchCooling('match_cooling'),
  generic('generic');

  const AppNotificationKind(this.wireName);
  final String wireName;

  static AppNotificationKind fromValue(Object? v) {
    final String raw = (v ?? '').toString().trim().toLowerCase();
    for (final AppNotificationKind k in AppNotificationKind.values) {
      if (k.wireName == raw || k.name.toLowerCase() == raw) return k;
    }
    return AppNotificationKind.generic;
  }
}

/// Acento de color corporativo (mapeado a AppColors en la UI; el dominio queda
/// puro/testeable sin depender de Flutter).
enum NotifAccent {
  desire('desire'), // rojo coral / vino — likes y deseo
  match('match'), // gradiente de match — conexión
  premium('premium'), // champagne — Attras / Pro
  calm('calm'), // verde suave — buenas noticias / reactivación amable
  safety('safety'); // azul noche — info / sistema

  const NotifAccent(this.wireName);
  final String wireName;

  static NotifAccent fromValue(Object? v) {
    final String raw = (v ?? '').toString().trim().toLowerCase();
    for (final NotifAccent a in NotifAccent.values) {
      if (a.wireName == raw || a.name.toLowerCase() == raw) return a;
    }
    return NotifAccent.desire;
  }
}

/// Contenido renderizado de una notificación (emoji + copy + acento + ruta).
class NotifContent {
  const NotifContent({
    required this.emoji,
    required this.title,
    required this.body,
    required this.accent,
    required this.route,
  });

  final String emoji;
  final String title;
  final String body;
  final NotifAccent accent;

  /// Ruta lógica al tocar (la app decide a dónde navegar): 'feed' | 'likes' |
  /// 'chats' | 'chat:{matchId}' | 'profile'.
  final String route;
}

/// Plantillas de notificación con personalidad. Tono elegante y humano, nunca
/// infantil. Las mismas plantillas las usa el cliente (in-app) y, en el futuro,
/// el backend para el push (FCM) — misma forma.
class AppNotificationTemplates {
  const AppNotificationTemplates._();

  static NotifContent build(
    AppNotificationKind kind, {
    String name = 'alguien',
    int count = 0,
    int days = 0,
    String preview = '',
    String route = '',
  }) {
    switch (kind) {
      case AppNotificationKind.newLike:
        return NotifContent(
          emoji: '👀',
          title: 'Le gustas a alguien',
          body: 'Alguien ha deslizado a la derecha. ¿Quién será? 😏',
          accent: NotifAccent.desire,
          route: route.isEmpty ? 'likes' : route,
        );
      case AppNotificationKind.newMatch:
        return NotifContent(
          emoji: '✨',
          title: '¡Nuevo match con $name!',
          body: 'Habéis conectado. Da el primer paso 💬',
          accent: NotifAccent.match,
          route: route.isEmpty ? 'chats' : route,
        );
      case AppNotificationKind.newMessage:
        return NotifContent(
          emoji: '💬',
          title: '$name te ha escrito',
          body: preview.isNotEmpty ? preview : 'Tienes un mensaje nuevo',
          accent: NotifAccent.desire,
          route: route.isEmpty ? 'chats' : route,
        );
      case AppNotificationKind.attraReceived:
        return NotifContent(
          emoji: '⭐',
          title: 'Te han enviado un Attra',
          body: '$name va en serio contigo. Mira quién es ✨',
          accent: NotifAccent.premium,
          route: route.isEmpty ? 'likes' : route,
        );
      case AppNotificationKind.likesWaiting:
        return NotifContent(
          emoji: '🔥',
          title: count > 1
              ? 'Tienes $count likes esperando'
              : 'Tienes un like esperando',
          body: 'Hay gente con ganas de conocerte. Échales un ojo',
          accent: NotifAccent.desire,
          route: route.isEmpty ? 'likes' : route,
        );
      case AppNotificationKind.comeBack:
        return NotifContent(
          emoji: '🌙',
          title: 'Te echamos de menos',
          body: days > 1
              ? 'Hace $days días que no entras y hay gente esperándote'
              : 'Vuelve, que hay movimiento por aquí',
          accent: NotifAccent.calm,
          route: route.isEmpty ? 'feed' : route,
        );
      case AppNotificationKind.sparkInvite:
        return NotifContent(
          emoji: '⚡',
          title: '$name quiere jugar',
          body: 'Os retan a Attra Spark: 5 minutos para romper el hielo',
          accent: NotifAccent.desire,
          route: route.isEmpty ? 'chats' : route,
        );
      case AppNotificationKind.dateProposed:
        return NotifContent(
          emoji: '📅',
          title: '$name te propone un plan',
          body: 'Mira la propuesta y decide si os veis',
          accent: NotifAccent.premium,
          route: route.isEmpty ? 'chats' : route,
        );
      case AppNotificationKind.profileOnFire:
        return NotifContent(
          emoji: '📈',
          title: 'Tu perfil está on fire',
          body: count > 0
              ? '$count personas han visto tu perfil últimamente'
              : 'Estás recibiendo más visitas de lo normal',
          accent: NotifAccent.match,
          route: route.isEmpty ? 'profile' : route,
        );
      case AppNotificationKind.dailyLikesReset:
        return NotifContent(
          emoji: '🌅',
          title: 'Likes nuevos disponibles',
          body: 'Empieza el día deslizando. Hay caras nuevas',
          accent: NotifAccent.calm,
          route: route.isEmpty ? 'feed' : route,
        );
      case AppNotificationKind.matchCooling:
        return NotifContent(
          emoji: '🫧',
          title: 'Tu match con $name se enfría',
          body: 'Una pregunta rápida puede reavivarlo',
          accent: NotifAccent.safety,
          route: route.isEmpty ? 'chats' : route,
        );
      case AppNotificationKind.generic:
        return NotifContent(
          emoji: '🔔',
          title: 'Novedad en Attra',
          body: preview.isNotEmpty ? preview : 'Tienes algo nuevo',
          accent: NotifAccent.safety,
          route: route.isEmpty ? 'feed' : route,
        );
    }
  }
}

/// Notificación persistida en `notifications/{uid}/items/{id}`. Guarda el
/// contenido ya renderizado (title/body/emoji/accent/route) para que el backend
/// pueda escribir la misma forma y la UI solo pinte.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.emoji,
    required this.title,
    required this.body,
    required this.accent,
    required this.route,
    required this.read,
    this.createdAt,
    this.data = const <String, dynamic>{},
  });

  final String id;
  final AppNotificationKind kind;
  final String emoji;
  final String title;
  final String body;
  final NotifAccent accent;
  final String route;
  final bool read;
  final DateTime? createdAt;
  final Map<String, dynamic> data;

  /// Crea una notificación a partir de una plantilla (cliente o backend).
  factory AppNotification.fromTemplate(
    AppNotificationKind kind, {
    String name = 'alguien',
    int count = 0,
    int days = 0,
    String preview = '',
    String route = '',
    Map<String, dynamic> data = const <String, dynamic>{},
  }) {
    final NotifContent c = AppNotificationTemplates.build(
      kind,
      name: name,
      count: count,
      days: days,
      preview: preview,
      route: route,
    );
    return AppNotification(
      id: '',
      kind: kind,
      emoji: c.emoji,
      title: c.title,
      body: c.body,
      accent: c.accent,
      route: c.route,
      read: false,
      data: data,
    );
  }

  Map<String, dynamic> toCreateMap() => <String, dynamic>{
        'kind': kind.wireName,
        'emoji': emoji,
        'title': title,
        'body': body,
        'accent': accent.wireName,
        'route': route,
        'read': false,
        'data': data,
        'createdAt': FieldValue.serverTimestamp(),
      };

  factory AppNotification.fromMap(String id, Map<String, dynamic> map) {
    return AppNotification(
      id: id,
      kind: AppNotificationKind.fromValue(map['kind']),
      emoji: (map['emoji'] ?? '🔔').toString(),
      title: (map['title'] ?? '').toString(),
      body: (map['body'] ?? '').toString(),
      accent: NotifAccent.fromValue(map['accent']),
      route: (map['route'] ?? 'feed').toString(),
      read: (map['read'] as bool?) ?? false,
      createdAt: _asDate(map['createdAt']),
      data: map['data'] is Map
          ? (map['data'] as Map)
              .map((dynamic k, dynamic v) => MapEntry(k.toString(), v))
          : const <String, dynamic>{},
    );
  }

  static DateTime? _asDate(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }
}
