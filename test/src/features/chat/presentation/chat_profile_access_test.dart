import 'dart:async';

import 'package:attra/src/features/chat/data/chat_service.dart';
import 'package:attra/src/features/chat/domain/chat.dart';
import 'package:attra/src/features/chat/domain/chat_message.dart';
import 'package:attra/src/features/chat/presentation/chat_detail_screen.dart';
import 'package:attra/src/features/match/data/match_service.dart';
import 'package:attra/src/features/profile/domain/profile_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// C17: tras un bloqueo, quien había sido bloqueado podía abrir el chat y, desde
/// la cabecera, cargar el perfil completo de quien le bloqueó.
class _FakeChatService implements ChatService {
  _FakeChatService(this._chat);

  final Stream<Chat?> Function() _chat;

  @override
  Future<void> markAsRead(String chatId) async {}

  @override
  Stream<Chat?> observeChatById(String chatId) => _chat();

  @override
  Stream<List<ChatMessage>> observeMessages(String chatId, {int limit = 100}) =>
      Stream<List<ChatMessage>>.value(const <ChatMessage>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMatchService implements MatchService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Chat _chat(String status) => Chat.fromMap('me_bea', <String, dynamic>{
      'matchId': 'me_bea',
      'users': <String>['me', 'bea'],
      'status': status,
    });

const ProfileSummary _bea =
    ProfileSummary(uid: 'bea', displayName: 'Bea', photoUrl: '');

Future<List<String>> _pump(
  WidgetTester tester,
  Stream<Chat?> Function() chat,
) async {
  // La grabadora de notas de voz se crea con la pantalla: sin plugin en los
  // tests, su canal se contesta en vacío.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('com.llfbandit.record/messages'),
    (MethodCall call) async => null,
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'), null));

  final List<String> loads = <String>[];
  await tester.pumpWidget(MaterialApp(
    home: ChatDetailScreen(
      chatId: 'me_bea',
      currentUid: 'me',
      other: _bea,
      chatService: _FakeChatService(chat),
      matchService: _FakeMatchService(),
      loadProfile: (String uid) async {
        loads.add(uid);
        return null;
      },
    ),
  ));
  await tester.pump();
  await tester.pump();
  return loads;
}

Finder get _chevron => find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.chevron_right),
    );

Finder get _header =>
    find.descendant(of: find.byType(AppBar), matching: find.text('Bea'));

void main() {
  testWidgets('chat activo: la cabecera abre el perfil',
      (WidgetTester tester) async {
    final List<String> loads =
        await _pump(tester, () => Stream<Chat?>.value(_chat('active')));

    expect(_chevron, findsOneWidget);
    await tester.tap(_header);
    await tester.pump();
    expect(loads, <String>['bea']);
  });

  testWidgets('chat bloqueado: la cabecera ya no lleva al perfil',
      (WidgetTester tester) async {
    final List<String> loads =
        await _pump(tester, () => Stream<Chat?>.value(_chat('blocked')));

    expect(_chevron, findsNothing);
    await tester.tap(_header);
    await tester.pump();
    expect(loads, isEmpty);
  });

  testWidgets('match deshecho: tampoco', (WidgetTester tester) async {
    final List<String> loads =
        await _pump(tester, () => Stream<Chat?>.value(_chat('closed')));

    expect(_chevron, findsNothing);
    await tester.tap(_header);
    await tester.pump();
    expect(loads, isEmpty);
  });

  testWidgets(
      'tocando antes de que llegue el chat (entrada por push) se comprueba '
      'el estado antes de enseñar nada', (WidgetTester tester) async {
    final StreamController<Chat?> chat = StreamController<Chat?>.broadcast();
    addTearDown(chat.close);
    final List<String> loads = await _pump(tester, () => chat.stream);

    // Aún sin chat: el gesto está, pero la decisión se toma al tocar.
    await tester.tap(_header);
    await tester.pump();
    chat.add(_chat('blocked'));
    await tester.pump();
    await tester.pump();

    expect(loads, isEmpty);
    expect(find.text('Este perfil ya no está disponible.'), findsOneWidget);
  });
}
