/// Catálogo de rondas de Attra Spark (LOCAL y extensible).
///
/// Contenido SEGURO por diseño: humor, romanticismo ligero, planes, valores
/// ligeros, aventura, vida cotidiana y green flags. SIN política, religión, sexo
/// explícito, salud, dinero, traumas ni inferencias sensibles.
///
/// Las rondas se construyen de forma DETERMINISTA a partir del `sessionId`, para
/// que ambos clientes (mismo id) vean exactamente las mismas preguntas/opciones.
library;

/// Tipo de mecánica de una ronda (cómo se renderiza y se revela).
enum SparkRoundKind {
  /// Elige una vibra; se revela si coincidís.
  vibe,

  /// This-or-that: cada uno elige lo suyo Y adivina lo del otro.
  guess,

  /// Reacciona a una situación ligera con una reacción rápida.
  react,

  /// Completa una frase eligiendo un final.
  phrase,

  /// Elegid el siguiente paso.
  nextStep,
}

class SparkOption {
  const SparkOption(this.key, this.label, {this.emoji = ''});
  final String key;
  final String label;
  final String emoji;
}

class SparkRound {
  const SparkRound({
    required this.id,
    required this.kind,
    required this.title,
    required this.prompt,
    required this.options,
    this.category = 'planes',
  });

  final String id;
  final SparkRoundKind kind;
  final String title;
  final String prompt;
  final List<SparkOption> options;
  final String category;
}

class SparkRoundCatalog {
  const SparkRoundCatalog._();

  static const int totalRounds = 5;

  /// Categorías del contenido (extensible).
  static const List<String> categories = <String>[
    'humor',
    'romanticismo',
    'planes',
    'valores',
    'aventura',
    'cotidiana',
    'greenflags',
  ];

  // --- Pools de contenido (seguros, ligeros) --------------------------------

  /// Vibras (ronda 1).
  static const List<SparkOption> _vibes = <SparkOption>[
    SparkOption('calm', 'Plan tranquilo', emoji: '🛋️'),
    SparkOption('adventure', 'Aventura', emoji: '🧭'),
    SparkOption('food', 'Comida o bebida', emoji: '🍷'),
    SparkOption('spontaneous', 'Improvisado', emoji: '✨'),
  ];

  /// This-or-that para "Adivina al otro" (ronda 2). Cada item = par de polos.
  static const List<(String, String, SparkOption, SparkOption)> _thisOrThat =
      <(String, String, SparkOption, SparkOption)>[
    (
      'beach_mountain',
      'planes',
      SparkOption('beach', 'Playa', emoji: '🏖️'),
      SparkOption('mountain', 'Montaña', emoji: '⛰️')
    ),
    (
      'tapas_dinner',
      'planes',
      SparkOption('tapas', 'Tapas', emoji: '🍤'),
      SparkOption('dinner', 'Cena elegante', emoji: '🍽️')
    ),
    (
      'museum_concert',
      'aventura',
      SparkOption('museum', 'Museo', emoji: '🖼️'),
      SparkOption('concert', 'Concierto', emoji: '🎶')
    ),
    (
      'sofa_getaway',
      'cotidiana',
      SparkOption('sofa', 'Domingo de sofá', emoji: '🛋️'),
      SparkOption('getaway', 'Escapada', emoji: '🚗')
    ),
    (
      'city_nature',
      'aventura',
      SparkOption('city', 'Paseo por ciudad', emoji: '🏙️'),
      SparkOption('nature', 'Naturaleza', emoji: '🌿')
    ),
  ];

  /// Situaciones para "Reacciona" (ronda 3).
  static const List<String> _situations = <String>[
    'Primera cita: llega 10 minutos tarde pero trae café para ti.',
    'Te propone cambiar el restaurante por un picnic improvisado en el parque.',
    'En la primera cita saca una lista de planes que le gustaría hacer contigo.',
    'Te manda un meme a las 2 de la tarde sin contexto.',
    'Aparece con un paraguas de más “por si acaso” cuando no llovía.',
  ];

  /// Reacciones rápidas (ronda 3).
  static const List<SparkOption> _reactions = <SparkOption>[
    SparkOption('win', 'Me gana', emoji: '😍'),
    SparkOption('depends', 'Depende', emoji: '🤔'),
    SparkOption('softred', 'Red flag suave', emoji: '🚩'),
    SparkOption('laugh', 'Me río', emoji: '😂'),
    SparkOption('secondchance', 'Le doy otra oportunidad', emoji: '🙂'),
  ];

  /// Frases para "Completa la frase" (ronda 4) con finales sugeridos.
  static const List<(String, String, List<SparkOption>)> _phrases =
      <(String, String, List<SparkOption>)>[
    (
      'date_start',
      'Una cita perfecta para mí empieza con…',
      <SparkOption>[
        SparkOption('coffee', 'un café sin prisa', emoji: '☕'),
        SparkOption('walk', 'un paseo y buena charla', emoji: '🚶'),
        SparkOption('food', 'comer algo rico', emoji: '🍕'),
        SparkOption('plan', 'un plan inesperado', emoji: '🎲'),
      ],
    ),
    (
      'conquers',
      'Me conquista alguien que…',
      <SparkOption>[
        SparkOption('laugh', 'me hace reír', emoji: '😄'),
        SparkOption('listen', 'escucha de verdad', emoji: '👂'),
        SparkOption('curious', 'es curioso/a', emoji: '🔍'),
        SparkOption('kind', 'es detallista', emoji: '💛'),
      ],
    ),
    (
      'greenflag',
      'Una green flag para mí es…',
      <SparkOption>[
        SparkOption('communicate', 'que sepa comunicar', emoji: '💬'),
        SparkOption('plans', 'que cuide los planes', emoji: '📅'),
        SparkOption('calm', 'la calma', emoji: '🧘'),
        SparkOption('humor', 'el buen humor', emoji: '😎'),
      ],
    ),
  ];

  /// Opciones del "siguiente paso" (ronda 5).
  static const List<SparkOption> _nextSteps = <SparkOption>[
    SparkOption('chat', 'Seguir hablando en el chat', emoji: '💬'),
    SparkOption('plan', 'Proponer un primer plan', emoji: '📍'),
    SparkOption('slow', 'Conocernos con calma', emoji: '🌱'),
    SparkOption('special', 'Guardar este match como especial', emoji: '⭐'),
  ];

  /// Construye las 5 rondas de forma DETERMINISTA a partir del [sessionId].
  static List<SparkRound> buildRounds(String sessionId) {
    final int seed = _seed(sessionId);

    final (String, String, SparkOption, SparkOption) tot =
        _thisOrThat[seed % _thisOrThat.length];
    final String situation = _situations[seed % _situations.length];
    final (String, String, List<SparkOption>) phrase =
        _phrases[seed % _phrases.length];

    return <SparkRound>[
      const SparkRound(
        id: 'r1_vibe',
        kind: SparkRoundKind.vibe,
        title: 'Elige tu vibra',
        prompt: '¿Qué vibra te pide hoy el cuerpo?',
        options: _vibes,
        category: 'planes',
      ),
      SparkRound(
        id: 'r2_guess_${tot.$1}',
        kind: SparkRoundKind.guess,
        title: 'Adivina al otro',
        prompt: '${tot.$3.label} o ${tot.$4.label}',
        options: <SparkOption>[tot.$3, tot.$4],
        category: tot.$2,
      ),
      SparkRound(
        id: 'r3_react',
        kind: SparkRoundKind.react,
        title: 'Reacciona a la situación',
        prompt: situation,
        options: _reactions,
        category: 'humor',
      ),
      SparkRound(
        id: 'r4_phrase_${phrase.$1}',
        kind: SparkRoundKind.phrase,
        title: 'Completa la frase',
        prompt: phrase.$2,
        options: phrase.$3,
        category: 'romanticismo',
      ),
      const SparkRound(
        id: 'r5_next',
        kind: SparkRoundKind.nextStep,
        title: 'Elegid el siguiente paso',
        prompt: '¿Hacia dónde os apetece ir?',
        options: _nextSteps,
        category: 'valores',
      ),
    ];
  }

  static int _seed(String sessionId) {
    int h = 0;
    for (final int code in sessionId.codeUnits) {
      h = (h * 31 + code) & 0x7fffffff;
    }
    return h;
  }
}
