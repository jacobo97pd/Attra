/// Media de presentación del perfil, PÚBLICA (cualquiera que vea el perfil puede
/// reproducirla): un audio de presentación ("voice prompt") y/o un vídeo corto.
///
/// Se guardan anidados en `users/{uid}.profile.introAudio` / `.introVideo`
/// (anidado bajo `profile` => no requiere tocar las reglas de Firestore) y se
/// publican en `discovery/{uid}` para el feed.
library;

/// Audio de presentación del perfil.
class IntroAudio {
  const IntroAudio({
    required this.url,
    required this.storagePath,
    required this.durationMs,
  });

  final String url;
  final String storagePath;
  final int durationMs;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'url': url,
        'storagePath': storagePath,
        'durationMs': durationMs,
      };

  static IntroAudio? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, dynamic> m = raw.map(
        (dynamic k, dynamic v) => MapEntry(k.toString(), v));
    final String url = (m['url'] ?? '').toString();
    if (url.isEmpty) return null;
    return IntroAudio(
      url: url,
      storagePath: (m['storagePath'] ?? '').toString(),
      durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Vídeo de presentación del perfil.
class IntroVideo {
  const IntroVideo({
    required this.url,
    required this.storagePath,
    required this.durationMs,
    this.thumbUrl = '',
  });

  final String url;
  final String storagePath;
  final int durationMs;
  final String thumbUrl;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'url': url,
        'storagePath': storagePath,
        'durationMs': durationMs,
        'thumbUrl': thumbUrl,
      };

  static IntroVideo? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, dynamic> m = raw.map(
        (dynamic k, dynamic v) => MapEntry(k.toString(), v));
    final String url = (m['url'] ?? '').toString();
    if (url.isEmpty) return null;
    return IntroVideo(
      url: url,
      storagePath: (m['storagePath'] ?? '').toString(),
      durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
      thumbUrl: (m['thumbUrl'] ?? '').toString(),
    );
  }
}
