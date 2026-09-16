import 'package:attra/src/features/match/data/match_service.dart';
import 'package:attra/src/features/stories/data/story_service.dart';
import 'package:attra/src/features/stories/domain/story.dart';
import 'package:attra/src/features/stories/presentation/story_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _StoryService implements StoryService {
  final List<String> views = <String>[];

  @override
  Future<void> viewStory(String storyId) async => views.add(storyId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MatchService implements MatchService {
  final List<Map<String, String?>> reports = <Map<String, String?>>[];
  final List<String> blocks = <String>[];
  bool failBlock = false;

  @override
  Future<String> reportUser({
    required String reportedUid,
    required String reason,
    String details = '',
    String? matchId,
    String? chatId,
    String? messageId,
    String? storyId,
  }) async {
    reports.add(<String, String?>{
      'reportedUid': reportedUid,
      'reason': reason,
      'storyId': storyId,
    });
    return 'report-1';
  }

  @override
  Future<void> blockUser(String blockedUid) async {
    if (failBlock) throw const MatchServiceException('Error de conexión.');
    blocks.add(blockedUid);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Story _story(String id, {String ownerUid = 'other'}) =>
    Story.fromMap(id, <String, dynamic>{
      'ownerUid': ownerUid,
      'displayName': 'Ana',
      'mediaType': 'image',
      // Missing media exercises the watchdog without native/network plugins.
      'imageUrl': '',
      'status': 'active',
      'expiresAt': DateTime.now().add(const Duration(hours: 1)),
    });

void main() {
  late _StoryService stories;
  late _MatchService matches;
  const Key menu = ValueKey<String>('story-viewer-safety');

  setUp(() {
    stories = _StoryService();
    matches = _MatchService();
  });

  Future<void> open(WidgetTester tester, {bool mine = false}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (BuildContext context) {
        return TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => StoryViewerScreen(
              stories: <Story>[
                _story('first', ownerUid: mine ? 'me' : 'other'),
                _story('second', ownerUid: mine ? 'me' : 'other'),
              ],
              initialIndex: 0,
              currentUid: 'me',
              storyService: stories,
              matchService: matches,
            ),
          )),
          child: const Text('Abrir historias'),
        );
      })),
    ));
    await tester.tap(find.text('Abrir historias'));
    await tester.pumpAndSettle();
  }

  testWidgets('reportar conserva la historia durante la elección del motivo',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester);
    await tester.tap(find.byKey(menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reportar'));
    await tester.pumpAndSettle();
    // A broken story used to advance while a moderation sheet was open.
    await tester.pump(const Duration(seconds: 4));
    expect(stories.views, <String>['first']);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Otro'), 180,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Otro'));
    await tester.pumpAndSettle();
    expect(matches.reports, <Map<String, String?>>[
      <String, String?>{
        'reportedUid': 'other',
        'reason': 'other',
        'storyId': 'first',
      },
    ]);
    // After reporting, playback resumes instead of remaining paused forever.
    await tester.pump(const Duration(seconds: 4));
    expect(stories.views, <String>['first', 'second']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final bool fails in <bool>[false, true]) {
    testWidgets(
        'bloqueo ${fails ? 'fallido conserva' : 'correcto cierra'} el visor',
        (WidgetTester tester) async {
      matches.failBlock = fails;
      await open(tester);
      await tester.tap(find.byKey(menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bloquear'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Bloquear'));
      await tester.pumpAndSettle();
      expect(find.byType(StoryViewerScreen),
          fails ? findsOneWidget : findsNothing);
      expect(matches.blocks, fails ? isEmpty : <String>['other']);
      if (fails) expect(find.text('Error de conexión.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('las historias propias no ofrecen bloquearse a uno mismo',
      (WidgetTester tester) async {
    await open(tester, mine: true);
    expect(find.byKey(menu), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
