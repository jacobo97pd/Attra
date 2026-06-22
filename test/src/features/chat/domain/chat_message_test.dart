import 'package:attra/src/features/chat/domain/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatMessage date_proposal', () {
    test('parsea tipo date_proposal y su payload', () {
      final ChatMessage m = ChatMessage.fromMap('m1', <String, dynamic>{
        'senderId': 'a',
        'receiverId': 'b',
        'type': 'date_proposal',
        'text': 'La Tagliatella',
        'status': 'sent',
        'dateProposal': <String, dynamic>{
          'proposedDate': '2026-06-20',
          'proposedTime': '21:00',
          'placeName': 'La Tagliatella',
          'placeAddress': 'Calle Mayor 1',
          'note': '¿Te viene bien?',
          'status': 'pending',
          'proposedBy': 'a',
        },
      });
      expect(m.type, MessageType.dateProposal);
      expect(m.type.isDateProposal, isTrue);
      expect(m.dateProposal, isNotNull);
      expect(m.dateProposal!.placeName, 'La Tagliatella');
      expect(m.dateProposal!.proposedTime, '21:00');
      expect(m.dateProposal!.status, DateProposalStatus.pending);
      expect(m.dateProposal!.isPending, isTrue);
    });

    test('un mensaje de texto normal no trae dateProposal', () {
      final ChatMessage m = ChatMessage.fromMap('m2', <String, dynamic>{
        'senderId': 'a',
        'receiverId': 'b',
        'type': 'text',
        'text': 'hola',
        'status': 'sent',
      });
      expect(m.type, MessageType.text);
      expect(m.type.isDateProposal, isFalse);
      expect(m.dateProposal, isNull);
    });

    test('estado accepted se parsea', () {
      final ChatMessage m = ChatMessage.fromMap('m3', <String, dynamic>{
        'type': 'date_proposal',
        'dateProposal': <String, dynamic>{
          'placeName': 'X',
          'status': 'accepted',
        },
      });
      expect(m.dateProposal!.status, DateProposalStatus.accepted);
      expect(m.dateProposal!.isPending, isFalse);
    });
  });

  group('ChatMessage media (image/voice_note)', () {
    test('parsea mensaje image con MediaInfo', () {
      final ChatMessage m = ChatMessage.fromMap('img1', <String, dynamic>{
        'senderId': 'a',
        'receiverId': 'b',
        'type': 'image',
        'status': 'sent',
        'media': <String, dynamic>{
          'storagePath': 'chats/a_b/images/a/img1.jpg',
          'downloadUrl': 'https://x/img1.jpg',
          'mimeType': 'image/jpeg',
          'sizeBytes': 12345,
          'width': 1600,
          'height': 1200,
        },
      });
      expect(m.type, MessageType.image);
      expect(m.type.isImage, isTrue);
      expect(m.type.isMedia, isTrue);
      expect(m.media!.downloadUrl, 'https://x/img1.jpg');
      expect(m.media!.width, 1600);
      expect(m.media!.sizeBytes, 12345);
    });

    test('parsea mensaje voice_note con durationMs', () {
      final ChatMessage m = ChatMessage.fromMap('v1', <String, dynamic>{
        'type': 'voice_note',
        'status': 'sent',
        'media': <String, dynamic>{
          'storagePath': 'chats/a_b/voice/a/v1.m4a',
          'downloadUrl': 'https://x/v1.m4a',
          'mimeType': 'audio/mp4',
          'durationMs': 4200,
        },
      });
      expect(m.type.isVoiceNote, isTrue);
      expect(m.media!.durationMs, 4200);
      expect(m.media!.mimeType, 'audio/mp4');
    });

    test('parsea foto bomba sin downloadUrl persistida', () {
      final ChatMessage m = ChatMessage.fromMap('b1', <String, dynamic>{
        'senderId': 'a',
        'receiverId': 'b',
        'type': 'bomb_image',
        'status': 'sent',
        'media': <String, dynamic>{
          'storagePath': 'chats/a_b/bombs/a/b1.jpg',
          'mimeType': 'image/jpeg',
          'sizeBytes': 12345,
          'width': 1200,
          'height': 1600,
        },
        'bomb': <String, dynamic>{
          'state': 'unopened',
          'viewedBy': null,
          'viewedAt': null,
        },
      });
      expect(m.type, MessageType.bombImage);
      expect(m.type.isBombImage, isTrue);
      expect(m.type.isMedia, isTrue);
      expect(m.media!.storagePath, 'chats/a_b/bombs/a/b1.jpg');
      expect(m.media!.downloadUrl, isEmpty);
      expect(m.bomb, isNotNull);
      expect(m.bomb!.isViewed, isFalse);
    });

    test('mensaje de texto antiguo (sin media) sigue funcionando', () {
      final ChatMessage m = ChatMessage.fromMap('t1', <String, dynamic>{
        'type': 'text',
        'text': 'hola',
        'status': 'sent',
      });
      expect(m.type, MessageType.text);
      expect(m.type.isMedia, isFalse);
      expect(m.media, isNull);
    });
  });

  group('ChatMessage journey games', () {
    test('parsea double_answer oculto y revelado', () {
      final ChatMessage hidden = ChatMessage.fromMap('d1', <String, dynamic>{
        'type': 'double_answer',
        'doubleAnswer': <String, dynamic>{
          'question': 'Plan ideal?',
          'status': 'collecting',
          'startedBy': 'a',
          'participants': <String>['a', 'b'],
          'answeredBy': <String, bool>{'a': true, 'b': false},
          'answers': <String, String>{},
        },
      });
      expect(hidden.type.isDoubleAnswer, isTrue);
      expect(hidden.doubleAnswer!.question, 'Plan ideal?');
      expect(hidden.doubleAnswer!.isRevealed, isFalse);
      expect(hidden.doubleAnswer!.hasAnswered('a'), isTrue);

      final ChatMessage revealed = ChatMessage.fromMap('d2', <String, dynamic>{
        'type': 'double_answer',
        'doubleAnswer': <String, dynamic>{
          'question': 'Plan ideal?',
          'status': 'revealed',
          'answers': <String, String>{'a': 'Cafe', 'b': 'Paseo'},
        },
      });
      expect(revealed.doubleAnswer!.isRevealed, isTrue);
      expect(revealed.doubleAnswer!.answers['b'], 'Paseo');
    });

    test('parsea two_truths sin exponer lieIndex hasta reveal', () {
      final ChatMessage guessing = ChatMessage.fromMap('tt1', <String, dynamic>{
        'type': 'two_truths',
        'twoTruths': <String, dynamic>{
          'statements': <String>['Uno', 'Dos', 'Tres'],
          'status': 'guessing',
          'startedBy': 'a',
          'lieIndex': null,
        },
      });
      expect(guessing.type.isTwoTruths, isTrue);
      expect(guessing.twoTruths!.isRevealed, isFalse);
      expect(guessing.twoTruths!.lieIndex, isNull);

      final ChatMessage revealed = ChatMessage.fromMap('tt2', <String, dynamic>{
        'type': 'two_truths',
        'twoTruths': <String, dynamic>{
          'statements': <String>['Uno', 'Dos', 'Tres'],
          'status': 'revealed',
          'guessIndex': 1,
          'lieIndex': 1,
          'correct': true,
        },
      });
      expect(revealed.twoTruths!.isRevealed, isTrue);
      expect(revealed.twoTruths!.correct, isTrue);
      expect(revealed.twoTruths!.lieIndex, 1);
    });
  });
}
