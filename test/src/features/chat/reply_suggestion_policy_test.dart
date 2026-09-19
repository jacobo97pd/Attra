import 'package:attra/src/features/chat/domain/chat_message.dart';
import 'package:attra/src/features/chat/domain/reply_suggestion_policy.dart';
import 'package:flutter_test/flutter_test.dart';

const String yo = 'uid_yo';
const String otra = 'uid_otra';
final DateTime ahora = DateTime.utc(2026, 9, 19, 12, 0);

ChatMessage _m(
  String sender,
  String text, {
  Duration hace = Duration.zero,
  MessageType type = MessageType.text,
}) {
  return ChatMessage(
    id: '$sender-$text',
    senderId: sender,
    receiverId: sender == yo ? otra : yo,
    text: text,
    type: type,
    status: MessageStatus.sent,
    createdAt: ahora.subtract(hace),
  );
}

/// Conversación normal en la que el otro acaba de escribir hace un rato.
List<ChatMessage> _conversacionAtascada() => <ChatMessage>[
      _m(yo, 'Hola, qué tal el finde?', hace: const Duration(minutes: 20)),
      _m(otra, 'Muy bien, estuve de escalada',
          hace: const Duration(minutes: 10)),
    ];

void main() {
  group('ReplySuggestionPolicy.shouldOffer', () {
    test('se ofrece cuando llevas rato sin contestar', () {
      expect(
        ReplySuggestionPolicy.shouldOffer(
          messages: _conversacionAtascada(),
          myUid: yo,
          now: ahora,
        ),
        isTrue,
      );
    });

    // El requisito era "no siempre, solo alguna". Esto es lo que lo cumple.
    test('NO se ofrece si el otro acaba de escribir', () {
      final List<ChatMessage> convo = <ChatMessage>[
        _m(yo, 'Hola', hace: const Duration(minutes: 5)),
        _m(otra, 'Buenas', hace: const Duration(seconds: 20)),
      ];
      expect(
        ReplySuggestionPolicy.shouldOffer(
          messages: convo,
          myUid: yo,
          now: ahora,
        ),
        isFalse,
        reason: 'si acabas de recibirlo, estás escribiendo tú',
      );
    });

    test('NO se ofrece si el último mensaje es mío', () {
      final List<ChatMessage> convo = _conversacionAtascada()
        ..add(_m(yo, 'Qué guay', hace: const Duration(minutes: 1)));
      expect(
        ReplySuggestionPolicy.shouldOffer(
          messages: convo,
          myUid: yo,
          now: ahora,
        ),
        isFalse,
        reason: 'la pelota está en su tejado; sugerir aquí es insistir',
      );
    });

    test('se ofrece si te han escrito varias seguidas, aunque sea reciente',
        () {
      final List<ChatMessage> convo = <ChatMessage>[
        _m(yo, 'Hola', hace: const Duration(minutes: 30)),
        _m(otra, 'Buenas!', hace: const Duration(seconds: 40)),
        _m(otra, 'Te cuento una cosa', hace: const Duration(seconds: 10)),
      ];
      expect(
        ReplySuggestionPolicy.shouldOffer(
          messages: convo,
          myUid: yo,
          now: ahora,
        ),
        isTrue,
      );
    });

    test('NO se ofrece en un chat vacío', () {
      expect(
        ReplySuggestionPolicy.shouldOffer(
          messages: const <ChatMessage>[],
          myUid: yo,
          now: ahora,
        ),
        isFalse,
      );
    });

    test('NO se ofrece si sólo ha hablado una persona', () {
      final List<ChatMessage> convo = <ChatMessage>[
        _m(otra, 'Hola?', hace: const Duration(minutes: 40)),
        _m(otra, 'Estás?', hace: const Duration(minutes: 30)),
      ];
      expect(
        ReplySuggestionPolicy.shouldOffer(
          messages: convo,
          myUid: yo,
          now: ahora,
        ),
        isFalse,
        reason: 'sin conversación no hay tono que seguir',
      );
    });

    test('hay enfriamiento tras pedirlas', () {
      expect(
        ReplySuggestionPolicy.shouldOffer(
          messages: _conversacionAtascada(),
          myUid: yo,
          now: ahora,
          lastSuggestedAt: ahora.subtract(const Duration(minutes: 1)),
        ),
        isFalse,
      );
      expect(
        ReplySuggestionPolicy.shouldOffer(
          messages: _conversacionAtascada(),
          myUid: yo,
          now: ahora,
          lastSuggestedAt: ahora.subtract(const Duration(minutes: 30)),
        ),
        isTrue,
      );
    });

    test('los mensajes que no son texto no cuentan como conversación', () {
      final List<ChatMessage> convo = <ChatMessage>[
        _m(yo, '', hace: const Duration(minutes: 30), type: MessageType.image),
        _m(otra, '',
            hace: const Duration(minutes: 20), type: MessageType.image),
      ];
      expect(
        ReplySuggestionPolicy.shouldOffer(
          messages: convo,
          myUid: yo,
          now: ahora,
        ),
        isFalse,
        reason: 'dos fotos no dan tono para sugerir una frase',
      );
    });
  });
}
