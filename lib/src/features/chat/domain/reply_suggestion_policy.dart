import 'chat_message.dart';

/// CUÁNDO ofrecer sugerencias de respuesta.
///
/// El requisito es "no siempre, solo alguna": un botón de IA permanente en
/// cada conversación convierte el chat en un intercambio de frases de máquina,
/// y además cada pulsación es una llamada que se paga. Así que el botón solo
/// aparece cuando de verdad ayuda:
///
///   - hay algo a lo que responder (el último mensaje NO es mío),
///   - la conversación ya arrancó (al menos un mensaje por cada lado),
///   - no se acaban de pedir (enfriamiento),
///   - y, además, hace falta: o llevas un rato sin contestar, o el otro ha
///     escrito varias seguidas sin respuesta. Si acabas de recibir un mensaje y
///     estás escribiendo, no hay nada que sugerir.
///
/// Espejo de `shouldOfferSuggestions` en functions/src/chatSuggestions.ts. Aquí
/// decide si se PINTA el botón; el backend vuelve a comprobar plan,
/// consentimiento y tope, porque el cliente no manda en nada de eso.
class ReplySuggestionPolicy {
  const ReplySuggestionPolicy._();

  /// Tiempo entre una tanda de sugerencias y la siguiente.
  static const Duration cooldown = Duration(minutes: 5);

  /// Cuánto hay que tardar en contestar para que se ofrezca ayuda.
  static const Duration stalled = Duration(minutes: 3);

  /// Mensajes seguidos del otro sin respuesta que también la disparan.
  static const int unansweredBurst = 2;

  static bool shouldOffer({
    required List<ChatMessage> messages,
    required String myUid,
    required DateTime now,
    DateTime? lastSuggestedAt,
  }) {
    final List<ChatMessage> convo = messages
        .where((ChatMessage m) => m.type == MessageType.text)
        .toList(growable: false);
    if (convo.isEmpty) return false;

    final ChatMessage last = convo.last;
    // Si el último mensaje es mío, la pelota está en su tejado. Sugerir aquí
    // solo empuja a insistir.
    if (last.senderId == myUid) return false;

    final int mios = convo.where((ChatMessage m) => m.senderId == myUid).length;
    if (mios == 0 || mios == convo.length) return false;

    if (lastSuggestedAt != null && now.difference(lastSuggestedAt) < cooldown) {
      return false;
    }

    // ¿Hace falta ayuda? Dos señales: llevas rato sin contestar, o te han
    // escrito varias seguidas.
    final DateTime? cuando = last.createdAt;
    final bool atascado = cuando != null && now.difference(cuando) >= stalled;

    int seguidos = 0;
    for (final ChatMessage m in convo.reversed) {
      if (m.senderId == myUid) break;
      seguidos++;
    }
    final bool insiste = seguidos >= unansweredBurst;

    return atascado || insiste;
  }
}
