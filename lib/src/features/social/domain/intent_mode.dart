// Modo Amigos — intención del usuario en Attra. PURO/testeable (sin Flutter).
//
// Permite que la app funcione como citas, amistad, ambas o planes en grupo,
// SIN romper la lógica de dating existente: los usuarios antiguos (sin campo)
// caen a `dating` por defecto, así que se comportan exactamente igual que antes.

/// Intención del usuario. Determina qué se le muestra en discovery y qué copy
/// se usa (romántico vs social).
enum IntentMode {
  dating('dating'),
  friends('friends'),
  both('both'),
  groups('groups');

  const IntentMode(this.wireName);
  final String wireName;

  bool get isDating => this == IntentMode.dating;
  bool get isFriends => this == IntentMode.friends;
  bool get isBoth => this == IntentMode.both;
  bool get isGroups => this == IntentMode.groups;

  /// ¿Usa copy/experiencia social (amistad/grupos) en vez de romántica?
  bool get isSocial => this == IntentMode.friends || this == IntentMode.groups;

  /// Canales de descubrimiento 1:1 que ofrece este modo. `groups` no participa
  /// en el feed de personas (su superficie son los grupos), por eso va vacío.
  Set<SocialChannel> get channels {
    switch (this) {
      case IntentMode.dating:
        return const <SocialChannel>{SocialChannel.dating};
      case IntentMode.friends:
        return const <SocialChannel>{SocialChannel.friends};
      case IntentMode.both:
        return const <SocialChannel>{
          SocialChannel.dating,
          SocialChannel.friends
        };
      case IntentMode.groups:
        return const <SocialChannel>{};
    }
  }

  /// Compat: acepta wire ('dating'…) o el nombre del enum. Desconocido/ausente
  /// → `dating` (usuarios antiguos se comportan como siempre).
  static IntentMode fromValue(Object? v) {
    final String raw = (v ?? '').toString().trim().toLowerCase();
    for (final IntentMode m in IntentMode.values) {
      if (m.wireName == raw || m.name.toLowerCase() == raw) return m;
    }
    return IntentMode.dating;
  }
}

/// Canal de descubrimiento 1:1.
enum SocialChannel { dating, friends }

/// Reglas de compatibilidad de intención para el feed de PERSONAS.
class IntentCompatibility {
  const IntentCompatibility._();

  /// ¿Debe [candidate] aparecer en el feed de personas de alguien que navega en
  /// [viewer]? Hay overlap si comparten algún canal (dating/friends).
  ///
  /// - dating ve dating/both · friends ve friends/both · both ve dating/friends/both
  /// - un perfil solo-`groups` no aparece en el feed de personas (usa grupos).
  static bool showsInFeed(IntentMode viewer, IntentMode candidate) {
    final Set<SocialChannel> a = viewer.channels;
    final Set<SocialChannel> b = candidate.channels;
    return a.any(b.contains);
  }
}
