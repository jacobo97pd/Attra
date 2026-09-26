import 'package:attra/src/features/chat/data/chat_service.dart';
import 'package:attra/src/features/match/data/match_service.dart';
import 'package:attra/src/features/match/domain/like.dart';
import 'package:attra/src/features/match/domain/user_match.dart';
import 'package:attra/src/features/match/presentation/likes_received_screen.dart';
import 'package:attra/src/features/profile/data/profile_summary_repository.dart';
import 'package:attra/src/features/profile/domain/profile_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// C41: la pestaña Matches enseñaba (y contaba) matches cuya conversación se
/// había cerrado con elegancia, con un "Enviar mensaje" hacia un chat donde ya
/// no se puede escribir. El servicio falso los entrega sin filtrar.
UserMatch _match(String other, String status, {String? journeyStatus}) =>
    UserMatch.fromMap('me_$other', <String, dynamic>{
      'users': <String>['me', other],
      'userA': 'me',
      'userB': other,
      'status': status,
      if (journeyStatus != null) 'journeyStatus': journeyStatus,
    });

class _FakeMatchService implements MatchService {
  @override
  Stream<List<Like>> observeReceivedLikes(String uid) =>
      Stream<List<Like>>.value(const <Like>[]);

  @override
  Stream<List<Like>> observeSentLikes(String uid) =>
      Stream<List<Like>>.value(const <Like>[]);

  @override
  Stream<List<UserMatch>> observeMatches(String uid) =>
      Stream<List<UserMatch>>.value(<UserMatch>[
        _match('ana', 'active'),
        _match('bea', 'active', journeyStatus: 'archived'),
        _match('carla', 'closed'),
      ]);

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

class _FakeChatService implements ChatService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('la pestaña Matches solo enseña y cuenta los matches vivos',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LikesReceivedScreen(
          currentUid: 'me',
          matchService: _FakeMatchService(),
          chatService: _FakeChatService(),
          summaries: _FakeSummaries(),
          canSeeAllLikes: true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Contador de la pestaña: 1 (antes contaba también el cerrado).
    final Finder matchesTab = find.ancestor(
      of: find.text('Matches'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: matchesTab.first, matching: find.text('1')),
      findsOneWidget,
    );

    await tester.tap(find.text('Matches'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Perfil ana'), findsOneWidget);
    expect(find.textContaining('Perfil bea'), findsNothing);
    expect(find.textContaining('Perfil carla'), findsNothing);
  });
}
