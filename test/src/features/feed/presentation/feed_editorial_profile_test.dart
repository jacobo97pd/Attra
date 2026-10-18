import 'package:attra/src/features/chat/data/chat_service.dart';
import 'package:attra/src/features/feed/presentation/feed_screen.dart';
import 'package:attra/src/features/match/data/match_service.dart';
import 'package:attra/src/features/match/domain/match_flow_result.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:attra/src/widgets/attra_editorial.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Matches implements MatchService {
  final List<({String uid, String? promptId, String? question, String? answer})>
      likes =
      <({String uid, String? promptId, String? question, String? answer})>[];

  @override
  Future<MatchFlowResult> sendLike(
    String toUid, {
    String? targetPhotoId,
    String? comment,
    String? promptId,
    String? promptQuestion,
    String? promptAnswer,
  }) async {
    likes.add((
      uid: toUid,
      promptId: promptId,
      question: promptQuestion,
      answer: promptAnswer,
    ));
    return const MatchFlowResult.liked();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Chats implements ChatService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const SeedProfile _profile = SeedProfile(
  id: 'alex',
  displayName: 'Alexandra María de la Fuente',
  city: 'Madrid',
  country: 'España',
  bio: 'Me gusta caminar por la ciudad y descubrir lugares nuevos.',
  gender: 'female',
  interestedIn: <String>[],
  orientation: <String>['heterosexual'],
  age: 30,
  jobTitle: 'Diseñadora',
  company: 'Estudio',
  interests: <String>['Arte', 'Senderismo'],
  photoUrl: '',
  isBot: false,
  botProfileVersion: 0,
  botScenario: '',
  seedQualityScore: 100,
  photos: <AdditionalPhoto>[
    AdditionalPhoto(
      url: 'https://example.invalid/alex.jpg',
      storagePath: 'profiles/alex/photo.jpg',
      source: 'upload',
      order: 0,
    ),
  ],
  profilePrompts: <PublicPrompt>[
    PublicPrompt(
      id: 'weekend',
      question: 'Mi plan de domingo',
      answer: 'Un paseo largo y una sobremesa todavía más larga.',
    ),
  ],
);

Future<void> _pump(WidgetTester tester, _Matches matches,
    {double scale = 1}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark,
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: FeedScreen(
        user: null,
        onLoadSeedProfiles: () async => <SeedProfile>[_profile],
        matchService: matches,
        chatService: _Chats(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('photo controls remain visible and usable at 320 and 200 percent',
      (WidgetTester tester) async {
    final _Matches matches = _Matches();
    await _pump(tester, matches, scale: 2);
    for (final String key in <String>[
      'feed-pass-profile-button',
      'feed-rewind-button',
      'feed-safety-button',
      'feed-photo-attra-action-profiles/alex/photo.jpg',
      'feed-photo-like-action-profiles/alex/photo.jpg',
    ]) {
      final Finder control = find.byKey(ValueKey<String>(key));
      expect(control, findsOneWidget);
      expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
      expect(control.hitTestable(), findsOneWidget);
    }
    expect(matches.likes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'editorial prompt retains its response action and original target',
      (WidgetTester tester) async {
    final _Matches matches = _Matches();
    await _pump(tester, matches);
    final Finder prompt =
        find.byKey(const ValueKey<String>('feed-prompt-respond-weekend'));
    final Finder scrollable = find
        .descendant(
          of: find.byKey(const ValueKey<String>('feed-profile-scroll-alex')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(prompt, 180, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(find.byType(AttraPromptNote), findsOneWidget);
    expect(tester.getSize(prompt).height, greaterThanOrEqualTo(48));
    await tester.tap(prompt);
    await tester.pumpAndSettle();
    expect(matches.likes, isEmpty);
    await tester.tap(find.text('Enviar Like'));
    await tester.pumpAndSettle();

    expect(
        matches.likes,
        <({String uid, String? promptId, String? question, String? answer})>[
          (
            uid: 'alex',
            promptId: 'weekend',
            question: 'Mi plan de domingo',
            answer: 'Un paseo largo y una sobremesa todavía más larga.',
          ),
        ]);
    expect(tester.takeException(), isNull);
  });
}
