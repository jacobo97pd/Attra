import 'package:attra/src/features/chat/data/chat_service.dart';
import 'package:attra/src/features/match/data/match_service.dart';
import 'package:attra/src/features/match/domain/like.dart';
import 'package:attra/src/features/match/domain/user_match.dart';
import 'package:attra/src/features/match/presentation/likes_received_screen.dart';
import 'package:attra/src/features/profile/data/profile_summary_repository.dart';
import 'package:attra/src/features/profile/domain/profile_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Ve a todas las personas que te dan like» es la ventaja nº1 que vende el
/// paywall de Attra Plus. Estaba prometida y cobrada, pero sin aplicar: la
/// tenía todo el mundo gratis.
Like _like(String from) => Like(
      fromUid: from,
      toUid: 'me',
      type: LikeType.like,
      status: LikeStatus.active,
    );

class _FakeMatchService implements MatchService {
  @override
  Stream<List<Like>> observeReceivedLikes(String uid) =>
      Stream<List<Like>>.value(<Like>[_like('a'), _like('b'), _like('c')]);

  @override
  Stream<List<Like>> observeSentLikes(String uid) =>
      Stream<List<Like>>.value(const <Like>[]);

  @override
  Stream<List<UserMatch>> observeMatches(String uid) =>
      Stream<List<UserMatch>>.value(const <UserMatch>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSummaries implements ProfileSummaryRepository {
  @override
  Future<ProfileSummary> fetch(String uid) async => ProfileSummary(
        uid: uid,
        displayName: 'Perfil $uid',
        photoUrl: '',
      );

  @override
  ProfileSummary? peek(String uid) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChatService implements ChatService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host({required bool canSeeAllLikes, VoidCallback? onUpgrade}) {
  return MaterialApp(
    home: LikesReceivedScreen(
      currentUid: 'me',
      matchService: _FakeMatchService(),
      chatService: _FakeChatService(),
      summaries: _FakeSummaries(),
      canSeeAllLikes: canSeeAllLikes,
      onUpgrade: onUpgrade,
    ),
  );
}

void main() {
  testWidgets('Free: solo se revela el primer like y aparece el muro',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    bool upgradeTapped = false;
    await tester.pumpWidget(
      _host(canSeeAllLikes: false, onUpgrade: () => upgradeTapped = true),
    );
    await tester.pumpAndSettle();

    // 3 likes recibidos -> 2 bloqueados.
    expect(
      find.byKey(const ValueKey<String>('locked-like-card')),
      findsNWidgets(2),
    );
    expect(
      find.byKey(const ValueKey<String>('unlock-likes-banner')),
      findsOneWidget,
    );
    // El muro dice cuántos hay ocultos: dato real, no promesa vaga.
    expect(find.textContaining('2 personas más'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('unlock-likes-cta')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('unlock-likes-cta')));
    await tester.pumpAndSettle();
    expect(upgradeTapped, isTrue);
  });

  testWidgets('Plus: se ven todos, sin muro ni tarjetas bloqueadas',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(canSeeAllLikes: true));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey<String>('locked-like-card')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('unlock-likes-banner')),
      findsNothing,
    );
  });
}
