import 'package:attra/src/features/chat/data/chat_service.dart';
import 'package:attra/src/features/chat/domain/chat.dart';
import 'package:attra/src/features/chat/presentation/chats_screen.dart';
import 'package:attra/src/features/match/data/match_service.dart';
import 'package:attra/src/features/profile/data/profile_summary_repository.dart';
import 'package:attra/src/features/profile/domain/profile_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// C17/C24: tras bloquear o deshacer el match, la otra persona seguía en la
/// lista de Chats de los dos, a menudo en "Matches nuevos". El bloqueo promete
/// "no volveréis a veros en la app".
///
/// El servicio falso devuelve los chats SIN filtrar (como hacía el stream
/// antes): la pantalla tiene que apartarlos por sí misma.
class _FakeChatService implements ChatService {
  _FakeChatService(this.chats);

  final List<Chat> chats;

  @override
  Stream<List<Chat>> observeChats(String uid) =>
      Stream<List<Chat>>.value(chats);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMatchService implements MatchService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSummaries implements ProfileSummaryRepository {
  @override
  Future<ProfileSummary> fetch(String uid) async =>
      ProfileSummary(uid: uid, displayName: 'Perfil $uid', photoUrl: '');

  @override
  ProfileSummary? peek(String uid) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Chat _chat(
  String other,
  String status, {
  String? lastType,
  String? closedBy,
}) =>
    Chat.fromMap('me_$other', <String, dynamic>{
      'matchId': 'me_$other',
      'users': <String>['me', other],
      'status': status,
      if (lastType != null) 'lastMessageType': lastType,
      if (lastType != null) 'lastMessage': 'último de $other',
      if (lastType != null) 'lastMessageSenderId': other,
      if (lastType != null)
        'lastMessageAt': DateTime.utc(2026, 9, 1).toIso8601String(),
      if (closedBy != null) 'closedByUserId': closedBy,
    });

Future<void> _pump(WidgetTester tester, List<Chat> chats) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ChatsScreen(
        currentUid: 'me',
        chatService: _FakeChatService(chats),
        matchService: _FakeMatchService(),
        summaries: _FakeSummaries(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('bloqueados y matches deshechos desaparecen de la lista',
      (WidgetTester tester) async {
    await _pump(tester, <Chat>[
      _chat('ana', 'active'), // match nuevo vivo
      _chat('bea', 'blocked', lastType: 'like_context'), // nuevo bloqueado
      _chat('carla', 'blocked', lastType: 'text'), // conversación bloqueada
      _chat('dani', 'closed'), // match deshecho sin conversación
      _chat('eva', 'closed', lastType: 'text'), // deshecho con conversación
      _chat('fran', 'closed', lastType: 'closure', closedBy: 'fran'),
      _chat('gala', 'active', lastType: 'text'),
    ]);

    expect(find.text('Matches nuevos'), findsOneWidget);
    expect(find.text('Perfil ana'), findsOneWidget);
    expect(find.text('Perfil gala'), findsOneWidget);

    for (final String hidden in <String>['bea', 'carla', 'dani', 'eva']) {
      expect(find.text('Perfil $hidden'), findsNothing, reason: hidden);
    }
  });

  testWidgets(
      'un cierre con elegancia queda archivado en Conversaciones, nunca en '
      '"Matches nuevos"', (WidgetTester tester) async {
    await _pump(tester, <Chat>[
      _chat('fran', 'closed', lastType: 'closure', closedBy: 'fran'),
    ]);

    expect(find.text('Matches nuevos'), findsNothing);
    expect(find.text('Conversaciones'), findsOneWidget);
    expect(find.text('Perfil fran'), findsOneWidget);
    expect(find.text('último de fran'), findsOneWidget);
  });

  testWidgets('si solo quedaban chats bloqueados, se ve la lista vacía',
      (WidgetTester tester) async {
    await _pump(tester, <Chat>[
      _chat('bea', 'blocked'),
      _chat('dani', 'closed'),
    ]);

    expect(find.text('Perfil bea'), findsNothing);
    expect(find.text('Perfil dani'), findsNothing);
    expect(find.text('Matches nuevos'), findsNothing);
    expect(find.text('Conversaciones'), findsNothing);
  });
}
