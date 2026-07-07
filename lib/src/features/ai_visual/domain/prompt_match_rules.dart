// IA por PROMPT (Attra Pro) — extracción PURA de señales de una descripción en
// lenguaje natural ("un chico alto, de ojos azules, moreno, carismático y
// gracioso, aventurero y que le guste viajar"). Separa lo que se puede casar con
// DATOS DECLARADOS del perfil (ojos, complexión, altura, intereses/personalidad)
// del resto, que se evalúa visualmente con el embedding de la foto.
//
// Es el ESPEJO Dart de `functions/src/promptMatch.ts` (misma lógica, testeable
// y reutilizable). No rompe ni toca la IA de referencia por imagen.

/// Señales estructuradas extraídas de un prompt.
class PromptSignals {
  const PromptSignals({
    this.eyeColors = const <String>[],
    this.bodyTypes = const <String>[],
    this.heightPref = HeightPref.any,
    this.keywords = const <String>[],
  });

  /// Colores de ojos pedidos (claves del catálogo: blue/green/brown/hazel/gray/
  /// black). Vacío = sin preferencia.
  final List<String> eyeColors;

  /// Complexiones pedidas (slim/athletic/average/curvy/muscular/plus).
  final List<String> bodyTypes;

  /// Preferencia de altura.
  final HeightPref heightPref;

  /// Palabras clave de intereses/personalidad para casar con intereses/bio/
  /// prompts (ya normalizadas: minúsculas, sin tildes).
  final List<String> keywords;

  bool get hasStructured =>
      eyeColors.isNotEmpty ||
      bodyTypes.isNotEmpty ||
      heightPref != HeightPref.any;

  bool get isEmpty => !hasStructured && keywords.isEmpty;
}

enum HeightPref { any, tall, short }

/// Extractor de señales (todo estático/puro).
class PromptMatchRules {
  const PromptMatchRules._();

  static const Map<String, List<String>> _eyeSynonyms = <String, List<String>>{
    'blue': <String>['azul', 'azules', 'blue'],
    'green': <String>['verde', 'verdes', 'green'],
    'brown': <String>['marron', 'marrones', 'cafe', 'brown'],
    'hazel': <String>['avellana', 'miel', 'hazel'],
    'gray': <String>['gris', 'grises', 'gray', 'grey'],
    'black': <String>['negro', 'negros', 'oscuros', 'black'],
  };

  static const Map<String, List<String>> _bodySynonyms = <String, List<String>>{
    'athletic': <String>['atletico', 'atletica', 'deportista', 'fit', 'athletic'],
    'muscular': <String>['musculoso', 'musculado', 'fuerte', 'cachas', 'muscular'],
    'slim': <String>['delgado', 'delgada', 'flaco', 'flaca', 'esbelto', 'slim', 'thin'],
    'curvy': <String>['con curvas', 'curvy'],
    'average': <String>['normal', 'media', 'medio', 'average'],
    'plus': <String>['grande', 'gordito', 'gordita', 'plus'],
  };

  /// Personalidad/intereses frecuentes como RAÍCES (stems): casan variantes
  /// morfológicas ("viaj" → viajar/viajes/viajero; "aventur" → aventura/
  /// aventurero). Se comparan por subcadena contra intereses/bio del perfil.
  static const List<String> _interestVocab = <String>[
    'viaj', 'aventur', 'mochiler',
    'gracios', 'divert', 'humor',
    'carismat', 'extrovert', 'sociable',
    'deport', 'gym', 'gimnasio', 'running', 'correr', 'sender',
    'music', 'arte', 'cultur', 'lectur', 'libro', 'cine',
    'cocin', 'gastronom', 'foodie', 'naturaleza', 'perro', 'gato',
    'fotograf', 'bail', 'fiesta', 'tranquil', 'romant', 'intelect',
    'espiritual', 'yoga', 'moto', 'coche', 'gamer', 'videojueg',
  ];

  static const List<String> _tallWords = <String>['alto', 'alta', 'tall'];
  static const List<String> _shortWords = <String>[
    'bajo', 'baja', 'bajit', 'short'
  ];

  /// Normaliza: minúsculas + sin tildes.
  static String normalize(String s) {
    final String lower = s.toLowerCase();
    const Map<String, String> map = <String, String>{
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
    };
    final StringBuffer b = StringBuffer();
    for (final int r in lower.runes) {
      final String ch = String.fromCharCode(r);
      b.write(map[ch] ?? ch);
    }
    return b.toString();
  }

  static bool _containsWord(String text, String word) {
    // Coincidencia por subcadena con límites laxos (suficiente para ES/EN).
    return text.contains(word);
  }

  static PromptSignals extract(String prompt) {
    final String t = normalize(prompt);

    final List<String> eyes = <String>[];
    _eyeSynonyms.forEach((String key, List<String> syns) {
      if (syns.any((String s) => _containsWord(t, s))) eyes.add(key);
    });

    final List<String> bodies = <String>[];
    _bodySynonyms.forEach((String key, List<String> syns) {
      if (syns.any((String s) => _containsWord(t, s))) bodies.add(key);
    });

    HeightPref height = HeightPref.any;
    if (_tallWords.any((String w) => _containsWord(t, w))) {
      height = HeightPref.tall;
    } else if (_shortWords.any((String w) => _containsWord(t, w))) {
      height = HeightPref.short;
    }

    final List<String> kws = <String>[];
    for (final String w in _interestVocab) {
      if (_containsWord(t, w) && !kws.contains(w)) kws.add(w);
    }

    return PromptSignals(
      eyeColors: eyes,
      bodyTypes: bodies,
      heightPref: height,
      keywords: kws,
    );
  }

  /// Puntúa [0..1] el encaje de DATOS del perfil con las señales. Solo cuenta lo
  /// que el perfil declara: si un campo no existe, no penaliza (lo cubre la foto).
  /// [profileText] = intereses + bio + respuestas de prompt (ya unidos).
  static double dataScore({
    required PromptSignals signals,
    String? eyeColor,
    String? bodyType,
    int? heightCm,
    required String profileText,
  }) {
    if (signals.isEmpty) return 0.0;
    double got = 0;
    double total = 0;
    final String pt = normalize(profileText);

    if (signals.eyeColors.isNotEmpty) {
      total += 1;
      if (eyeColor != null && signals.eyeColors.contains(eyeColor)) got += 1;
    }
    if (signals.bodyTypes.isNotEmpty) {
      total += 1;
      if (bodyType != null && signals.bodyTypes.contains(bodyType)) got += 1;
    }
    if (signals.heightPref != HeightPref.any) {
      total += 1;
      if (heightCm != null) {
        final bool ok = signals.heightPref == HeightPref.tall
            ? heightCm >= 180
            : heightCm <= 170;
        if (ok) got += 1;
      }
    }
    if (signals.keywords.isNotEmpty) {
      total += 1;
      final int hits =
          signals.keywords.where((String k) => pt.contains(k)).length;
      if (hits > 0) {
        // Encaje parcial proporcional al nº de intereses cubiertos.
        got += (hits / signals.keywords.length).clamp(0.0, 1.0);
      }
    }
    if (total == 0) return 0.0;
    return (got / total).clamp(0.0, 1.0);
  }
}
