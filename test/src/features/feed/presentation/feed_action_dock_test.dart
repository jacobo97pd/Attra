import 'package:attra/src/features/chat/data/chat_service.dart';
import 'package:attra/src/features/feed/presentation/feed_screen.dart';
import 'package:attra/src/features/match/data/match_service.dart';
import 'package:attra/src/features/match/domain/match_flow_result.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:attra/src/widgets/attra_motion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('drag and return reuse the full profile content subtree',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    final _MatchServiceStub matches = _MatchServiceStub();
    await tester.pumpWidget(_FeedHost(
      profiles: <SeedProfile>[_profile('zoe', 'Zoe')],
      matchService: matches,
    ));
    await tester.pumpAndSettle();
    final Finder content =
        find.byKey(const ValueKey<String>('feed-motion-content'));
    final Widget body = tester.widget<AttraStateTransition>(content).child;
    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(content));
    await gesture.moveBy(const Offset(35, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(identical(tester.widget<AttraStateTransition>(content).child, body),
        isTrue);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(identical(tester.widget<AttraStateTransition>(content).child, body),
        isTrue);
    await tester.pumpAndSettle();
    expect(matches.passedUids, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final bool reduceMotion in <bool>[false, true]) {
    testWidgets(
      'pasar sin gesto conserva destino y espera de envío (reduceMotion=$reduceMotion)',
      (WidgetTester tester) async {
        _usePhoneViewport(tester);
        final _MatchServiceStub matchService = _MatchServiceStub();
        final SemanticsHandle semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(_FeedHost(
            profiles: <SeedProfile>[_profile('zoe', 'Zoe')],
            matchService: matchService,
            reduceMotion: reduceMotion,
          ));
          await tester.pumpAndSettle();

          final Finder pass =
              find.byKey(const ValueKey<String>('feed-pass-profile-button'));
          expect(tester.getSize(pass).height, greaterThanOrEqualTo(48));
          expect(
              tester.getSemantics(pass),
              isSemantics(
                  label: 'Pasar',
                  isButton: true,
                  hasEnabledState: true,
                  isEnabled: true,
                  isFocusable: true,
                  hasTapAction: true));
          for (final String key in <String>[
            'feed-rewind-button',
            'feed-safety-button',
            'feed-photo-attra-action-profiles/zoe/photo-42.jpg',
            'feed-photo-like-action-profiles/zoe/photo-42.jpg',
          ]) {
            final Size size = tester.getSize(find.byKey(ValueKey<String>(key)));
            expect(size.width, greaterThanOrEqualTo(48));
            expect(size.height, greaterThanOrEqualTo(48));
          }
          await tester.tap(pass);
          await tester.tap(pass);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(matchService.passedUids, isEmpty);
          await tester.pumpAndSettle();
          expect(matchService.passedUids, <String>['zoe']);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

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
    this.reduceMotion = false,
  });

  final List<SeedProfile> profiles;
  final MatchService matchService;
  final int attrasBalance;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light,
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
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
  final List<String> passedUids = <String>[];

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
  Future<void> passProfile(String toUid) async {
    passedUids.add(toUid);
  }

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
