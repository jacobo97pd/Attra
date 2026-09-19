import 'package:cloud_functions/cloud_functions.dart';

/// Fallo pidiendo sugerencias, ya traducido a algo que se le puede enseñar a
/// una persona. El código crudo de Firebase ("unavailable", "internal") no le
/// dice nada a nadie.
class ReplySuggestionException implements Exception {
  const ReplySuggestionException(this.message, {this.code});

  final String message;
  final String? code;

  /// El backend distingue "no eres Pro" de "no has dado el consentimiento":
  /// la pantalla necesita saberlo para ofrecer el paywall o el permiso, que
  /// son dos salidas distintas.
  bool get needsConsent => code == 'failed-precondition';
  bool get needsPro => code == 'permission-denied';

  @override
  String toString() => message;
}

/// Pide al backend formas de seguir la conversación.
///
/// El cliente NUNCA envía una sugerencia por su cuenta: la deja en la caja de
/// texto para que la persona la lea, la cambie o la borre. Un chat en el que
/// las respuestas se mandan solas no es una conversación.
class ReplySuggestionService {
  ReplySuggestionService({required FirebaseFunctions functions})
      : _functions = functions;

  final FirebaseFunctions _functions;

  Future<List<String>> suggest({required String chatId}) async {
    try {
      final HttpsCallableResult<dynamic> result = await _functions
          .httpsCallable('suggestReplies')
          .call<dynamic>(<String, dynamic>{'chatId': chatId});
      final dynamic raw = result.data;
      if (raw is! Map) return const <String>[];
      final dynamic list = raw['suggestions'];
      if (list is! List) return const <String>[];
      return list
          .whereType<String>()
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList(growable: false);
    } on FirebaseFunctionsException catch (e) {
      throw ReplySuggestionException(_mensaje(e), code: e.code);
    }
  }

  String _mensaje(FirebaseFunctionsException e) {
    // El backend ya manda textos en castellano pensados para leerse; solo se
    // sustituyen los que vienen vacíos o en jerga de infraestructura.
    final String suyo = (e.message ?? '').trim();
    if (suyo.isNotEmpty && suyo.toUpperCase() != suyo) return suyo;
    switch (e.code) {
      case 'resource-exhausted':
        return 'Has llegado al máximo de sugerencias por hoy.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'No se ha podido contactar con la IA. Inténtalo en un momento.';
      case 'permission-denied':
        return 'Las sugerencias de respuesta son de Attra Pro.';
      default:
        return 'No se han podido generar sugerencias.';
    }
  }
}
