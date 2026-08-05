import 'package:attra/src/features/chat/data/chat_service.dart';
import 'package:attra/src/features/feed/presentation/feed_screen.dart';
import 'package:attra/src/features/match/data/match_service.dart';
import 'package:attra/src/features/match/domain/match_flow_result.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'quita el dock y coloca Attra a la izquierda y like a la derecha de la foto',
    (WidgetTester tester) async {
      _usePhoneViewport(tester);
      final _MatchServiceStub matchService = _MatchServiceStub();

      await tester.pumpWidget(
        _FeedHost(
          profiles: <SeedProfile>[_profile('zoe', 'Zoe')],
          matchService: matchService,
        ),
      );
      await tester.pumpAndSettle();

      const String photoId = 'profiles/zoe/photo-42.jpg';
      final Finder attra = find.byKey(
        const ValueKey<String>('feed-photo-attra-action-$photoId'),
      );
      final Finder like = find.byKey(
        const ValueKey<String>('feed-photo-like-action-$photoId'),
      );

      for (final String oldKey in <String>[
        'feed-action-dock',
        'feed-pass-action',
        'feed-attra-action',
        'feed-like-action',
      ]) {
        expect(find.byKey(ValueKey<String>(oldKey)), findsNothing);
      }
      expect(attra, findsOneWidget);
      expect(like, findsOneWidget);
      expect(tester.getCenter(attra).dx, lessThan(tester.getCenter(like).dx));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Attra desde una foto conserva el perfil y targetPhotoId',
    (WidgetTester tester) async {
      _usePhoneViewport(tester);
      final _MatchServiceStub matchService = _MatchServiceStub();

      await tester.pumpWidget(
        _FeedHost(
          profiles: <SeedProfile>[_profile('zoe', 'Zoe')],
          matchService: matchService,
          attrasBalance: 2,
        ),
      );
      await tester.pumpAndSettle();

      const String photoId = 'profiles/zoe/photo-42.jpg';
      await tester.tap(
        find.byKey(
          const ValueKey<String>('feed-photo-attra-action-$photoId'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('photo-response-submit-attra')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('photo-response-submit-attra')),
      );
      await tester.pumpAndSettle();

      expect(matchService.sendAttraCalls, 1);
      expect(matchService.lastAttraToUid, 'zoe');
      expect(matchService.lastAttraTargetPhotoId, photoId);
      expect(tester.takeException(), isNull);
    },
  );
}

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _FeedHost extends StatelessWidget {
  const _FeedHost({
    required this.profiles,
    required this.matchService,
    this.attrasBalance = 0,
  });

  final List<SeedProfile> profiles;
  final MatchService matchService;
  final int attrasBalance;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: FeedScreen(
          user: null,
          onLoadSeedProfiles: () async => profiles,
          matchService: matchService,
          chatService: _ChatServiceStub(),
          attrasBalance: attrasBalance,
        ),
      ),
    );
  }
}

SeedProfile _profile(String id, String name) {
  return SeedProfile(
    id: id,
    displayName: name,
    city: 'Madrid',
    country: 'Espana',
    bio: 'Una bio de prueba.',
    gender: 'female',
    interestedIn: const <String>[],
    orientation: const <String>['heterosexual'],
    age: 30,
    jobTitle: 'Disenadora',
    company: 'Atelier',
    interests: const <String>['Arte'],
    photoUrl: '',
    isBot: false,
    botProfileVersion: 0,
    botScenario: '',
    seedQualityScore: 100,
    photos: const <AdditionalPhoto>[
      AdditionalPhoto(
        url: 'https://example.com/photo-42.jpg',
        storagePath: 'profiles/zoe/photo-42.jpg',
        source: 'upload',
        order: 0,
      ),
    ],
  );
}

class _MatchServiceStub implements MatchService {
  int sendAttraCalls = 0;
  String? lastAttraToUid;
  String? lastAttraTargetPhotoId;

  @override
  Future<MatchFlowResult> sendAttra(
    String toUid, {
    String? targetPhotoId,
    String? comment,
    String? promptId,
    String? promptQuestion,
    String? promptAnswer,
  }) async {
    sendAttraCalls++;
    lastAttraToUid = toUid;
    lastAttraTargetPhotoId = targetPhotoId;
    return const MatchFlowResult.liked();
  }

  @override
  Future<void> passProfile(String toUid) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Llamada inesperada: ${invocation.memberName}');
  }
}

class _ChatServiceStub implements ChatService {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Llamada inesperada: ${invocation.memberName}');
  }
}
