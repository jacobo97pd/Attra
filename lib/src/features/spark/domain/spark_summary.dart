import 'spark_round.dart';
import 'spark_session.dart';

/// Resumen final de una sesión de Spark (tipado para la UI).
class SparkSummary {
  const SparkSummary({
    required this.coincidences,
    required this.funnyDifferences,
    required this.topics,
    required this.suggestedQuestions,
    required this.chatLine,
  });

  /// Temas/etiquetas en común (p. ej. "naturaleza", "humor", "planes tranquilos").
  final List<String> coincidences;

  /// Diferencias en clave divertida (nunca como juicio).
  final List<String> funnyDifferences;

  /// Temas sugeridos para seguir hablando.
  final List<String> topics;

  /// 1-2 preguntas sugeridas para abrir conversación (editables, no se envían
  /// solas).
  final List<String> suggestedQuestions;

  /// Línea para el mensaje de sistema del chat.
  final String chatLine;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'coincidences': coincidences,
        'funnyDifferences': funnyDifferences,
        'topics': topics,
        'suggestedQuestions': suggestedQuestions,
        'chatLine': chatLine,
      };

  static SparkSummary fromMap(Map<String, dynamic> map) {
    List<String> list(Object? v) =>
        v is List ? v.whereType<String>().toList(growable: false) : const <String>[];
    return SparkSummary(
      coincidences: list(map['coincidences']),
      funnyDifferences: list(map['funnyDifferences']),
      topics: list(map['topics']),
      suggestedQuestions: list(map['suggestedQuestions']),
      chatLine: (map['chatLine'] as String?) ??
          'Habéis completado Attra Spark.',
    );
  }
}

/// Construye el resumen con REGLAS SIMPLES (sin IA, sin juicios de
/// compatibilidad ni atributos sensibles). Si más adelante hay IA, puede
/// sustituir/mejorar este texto, pero esta es la base que siempre funciona.
class SparkSummaryBuilder {
  const SparkSummaryBuilder._();

  /// Etiqueta temática amable por opción/categoría (para "coincidencias").
  static const Map<String, String> _themeForKey = <String, String>{
    'calm': 'planes tranquilos',
    'adventure': 'aventura',
    'food': 'buena comida',
    'spontaneous': 'lo improvisado',
    'beach': 'playa',
    'mountain': 'montaña',
    'tapas': 'tapeo',
    'dinner': 'cenas con calma',
    'museum': 'cultura',
    'concert': 'música en directo',
    'sofa': 'planes de sofá',
    'getaway': 'escapadas',
    'city': 'la ciudad',
    'nature': 'naturaleza',
    'humor': 'humor',
    'laugh': 'humor',
  };

  static SparkSummary build({
    required SparkSession session,
    required List<SparkRound> rounds,
    String nameA = 'Tú',
    String nameB = 'tu match',
  }) {
    final List<String> coincidences = <String>[];
    final List<String> funny = <String>[];
    final List<String> topics = <String>[];

    String aKey(SparkRound r) => _choiceKey(session.answerOf(r.id, session.userAId));
    String bKey(SparkRound r) => _choiceKey(session.answerOf(r.id, session.userBId));
    String labelFor(SparkRound r, String key) {
      for (final SparkOption o in r.options) {
        if (o.key == key) return o.label.toLowerCase();
      }
      return key;
    }

    for (final SparkRound r in rounds) {
      final String a = aKey(r);
      final String b = bKey(r);
      if (a.isEmpty || b.isEmpty) continue;

      if (a == b) {
        // Coincidencia: usa etiqueta temática si la hay, si no la propia opción.
        final String theme = _themeForKey[a] ?? labelFor(r, a);
        if (!coincidences.contains(theme)) coincidences.add(theme);
        if (r.kind == SparkRoundKind.react) {
          if (!coincidences.contains('humor')) coincidences.add('humor');
        }
      } else if (r.kind == SparkRoundKind.guess ||
          r.kind == SparkRoundKind.vibe) {
        funny.add(
            '${_cap(nameA)} ${labelFor(r, a)}, $nameB ${labelFor(r, b)}');
        topics.add(r.prompt.toLowerCase());
      }
    }

    // Temas: a partir de coincidencias o, si no hay, de las propias rondas.
    if (coincidences.isNotEmpty) {
      topics.insert(0, coincidences.first);
    }
    final List<String> dedupTopics = <String>[];
    for (final String t in topics) {
      if (!dedupTopics.contains(t)) dedupTopics.add(t);
      if (dedupTopics.length >= 3) break;
    }

    final List<String> questions = _questions(coincidences, session, rounds);

    final String chatLine = coincidences.isEmpty
        ? 'Habéis completado Attra Spark. ¡Tenéis gustos que se complementan!'
        : 'Habéis completado Attra Spark. Coincidencias: '
            '${_joinNatural(coincidences.take(3).toList())}.';

    return SparkSummary(
      coincidences: coincidences,
      funnyDifferences: funny.take(2).toList(growable: false),
      topics: dedupTopics,
      suggestedQuestions: questions,
      chatLine: chatLine,
    );
  }

  static List<String> _questions(
    List<String> coincidences,
    SparkSession session,
    List<SparkRound> rounds,
  ) {
    final List<String> out = <String>[];
    if (coincidences.contains('naturaleza') ||
        coincidences.contains('montaña')) {
      out.add('¿Cuál sería tu escapada a la naturaleza perfecta?');
    }
    if (coincidences.contains('planes tranquilos') ||
        coincidences.contains('planes de sofá')) {
      out.add('¿Tu plan de sofá ideal incluye peli, serie o música?');
    }
    if (coincidences.contains('humor')) {
      out.add('¿Qué fue lo último que te hizo reír de verdad?');
    }
    if (coincidences.contains('buena comida') ||
        coincidences.contains('tapeo')) {
      out.add('Si abrimos plan de comer, ¿dulce o salado para empezar?');
    }
    // Fallback amable y abierto.
    if (out.isEmpty) {
      out.add('De todo lo que ha salido, ¿qué te apetece más repetir?');
      out.add('¿Cuál dirías que es tu plan perfecto un finde cualquiera?');
    }
    return out.take(2).toList(growable: false);
  }

  /// Extrae la clave de elección de una respuesta (String o Map {choice,...}).
  static String _choiceKey(Object? answer) {
    if (answer is String) return answer;
    if (answer is Map) {
      final Object? c = answer['choice'];
      if (c is String) return c;
    }
    return '';
  }

  static String _cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  static String _joinNatural(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} y ${items.last}';
  }
}
