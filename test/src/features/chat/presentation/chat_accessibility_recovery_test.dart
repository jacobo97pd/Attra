import 'dart:async';

import 'package:attra/src/features/chat/data/chat_service.dart';
import 'package:attra/src/features/chat/domain/chat.dart';
import 'package:attra/src/features/chat/domain/chat_message.dart';
import 'package:attra/src/features/chat/presentation/chat_detail_screen.dart';
import 'package:attra/src/features/chat/presentation/chats_screen.dart';
import 'package:attra/src/features/chat/presentation/voice_note_bubble.dart';
import 'package:attra/src/features/match/data/match_service.dart';
import 'package:attra/src/features/profile/data/profile_summary_repository.dart';
import 'package:attra/src/features/profile/domain/profile_summary.dart';
import 'package:attra/src/features/stories/data/story_service.dart';
import 'package:attra/src/features/stories/domain/story.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

class _Chats implements ChatService {
  List<Chat> chats = <Chat>[];
  bool failChats = false;
  bool failMessages = false;
  bool failSend = false;
  int chatSubscriptions = 0;
  int messageSubscriptions = 0;
  int sends = 0;
  Stream<List<ChatMessage>>? messageFrames;

  @override
  Stream<List<Chat>> observeChats(String uid) {
    chatSubscriptions++;
    return failChats
        ? Stream<List<Chat>>.error(StateError('offline'))
        : Stream<List<Chat>>.value(chats);
  }

  @override
  Stream<Chat?> observeChatById(String chatId) =>
      Stream<Chat?>.value(_chat('bea'));

  @override
  Stream<List<ChatMessage>> observeMessages(String chatId, {int limit = 100}) {
    messageSubscriptions++;
    return failMessages
        ? Stream<List<ChatMessage>>.error(StateError('offline'))
        : messageFrames ??
            Stream<List<ChatMessage>>.value(const <ChatMessage>[]);
  }

  @override
  Future<void> markAsRead(String chatId) async {}

  @override
  Future<String> sendMessage({
    required String chatId,
    required String text,
    String? gameSessionId,
  }) async {
    sends++;
    if (failSend) throw const ChatServiceException('No se pudo enviar.');
    return 'sent-$sends';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Matches implements MatchService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Summaries implements ProfileSummaryRepository {
  @override
  Future<ProfileSummary> fetch(String uid) async =>
      ProfileSummary(uid: uid, displayName: 'Perfil $uid', photoUrl: '');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _VoicePlayer implements VoiceNotePlayerController {
  final StreamController<PlayerState> states =
      StreamController<PlayerState>.broadcast();
  int toggles = 0;

  @override
  Stream<PlayerState> get playerStateStream => states.stream;

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Duration? get duration => const Duration(seconds: 12);

  @override
  bool isCurrent(String url) => true;

  @override
  Future<void> toggle(String url) async {
    toggles++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Stories implements StoryService {
  @override
  Stream<Map<String, List<Story>>> observeLiveStoriesForMatches({
    String excludeUid = '',
    Set<String> excludedOwners = const <String>{},
  }) =>
      Stream<Map<String, List<Story>>>.value(<String, List<Story>>{
        'bea': <Story>[
          Story.fromMap('story', <String, dynamic>{
            'ownerUid': 'bea',
            'mediaType': 'image',
            'status': 'active',
            'imageUrl': '',
          }),
        ],
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Chat _chat(String other, {int unread = 0, bool hasAttra = false}) =>
    Chat.fromMap(
      'me_$other',
      <String, dynamic>{
        'matchId': 'me_$other',
        'users': <String>['me', other],
        'status': 'active',
        'hasAttra': hasAttra,
        if (unread > 0) ...<String, dynamic>{
          'lastMessageType': 'text',
          'lastMessage': 'Hola',
          'lastMessageSenderId': other,
          'unreadCountByUser': <String, int>{'me': unread},
        },
      },
    );

double _contrast(Color a, Color b) {
  final double x = a.computeLuminance();
  final double y = b.computeLuminance();
  return ((x > y ? x : y) + 0.05) / ((x > y ? y : x) + 0.05);
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: child));
  await tester.pumpAndSettle();
}

Widget _list(_Chats chats, {StoryService? stories}) => Scaffold(
      body: ChatsScreen(
        currentUid: 'me',
        chatService: chats,
        matchService: _Matches(),
        summaries: _Summaries(),
        storyService: stories,
      ),
    );

Widget _detail(_Chats chats) => ChatDetailScreen(
      chatId: 'me_bea',
      currentUid: 'me',
      other: const ProfileSummary(uid: 'bea', displayName: 'Bea', photoUrl: ''),
      chatService: chats,
      matchService: _Matches(),
    );

void main() {
  for (final bool reduced in <bool>[false, true]) {
    testWidgets('repeated photo URLs have distinct flights, reduced=$reduced',
        (WidgetTester tester) async {
      final _Chats service = _Chats()
        ..messageFrames = Stream<List<ChatMessage>>.value(<ChatMessage>[
          for (final String id in <String>['photo-a', 'photo-b'])
            ChatMessage.fromMap(id, <String, dynamic>{
              'senderId': 'bea',
              'type': 'image',
              'media': <String, dynamic>{
                'downloadUrl': '',
                'mimeType': 'image/jpeg'
              },
            }),
        ]);
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child!,
        ),
        home: _detail(service),
      ));
      await tester.pumpAndSettle();
      final Finder photos = find.byWidgetPredicate((Widget widget) =>
          widget is Hero && widget.tag.toString().startsWith('chat-photo-'));
      final List<Hero> flights = tester.widgetList<Hero>(photos).toList();
      expect(flights, hasLength(2));
      expect(flights.map((Hero hero) => hero.tag).toSet(), hasLength(2));
      for (final Element element in photos.evaluate()) {
        final HeroMode mode = tester.widget<HeroMode>(find
            .ancestor(
                of: find.byWidget(element.widget),
                matching: find.byType(HeroMode))
            .first);
        expect(mode.enabled, !reduced);
      }
      if (!reduced) {
        await tester.tap(photos.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        // The previous route's local tickers are muted during a flight. That
        // must not disable its source Hero before the navigator can use it.
        final Finder sourcePhoto = find
            .descendant(
              of: find.byType(ChatDetailScreen, skipOffstage: false),
              matching: find.byType(Hero, skipOffstage: false),
              skipOffstage: false,
            )
            .first;
        final HeroMode sourceMode = tester.widget<HeroMode>(find
            .ancestor(
                of: sourcePhoto,
                matching: find.byType(HeroMode, skipOffstage: false))
            .first);
        expect(sourceMode.enabled, isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(InteractiveViewer), findsOneWidget);
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
      }
      expect(service.sends, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'incoming stream updates are immediate and do not replay a bubble',
      (WidgetTester tester) async {
    final StreamController<List<ChatMessage>> frames =
        StreamController<List<ChatMessage>>.broadcast();
    addTearDown(frames.close);
    final _Chats service = _Chats()..messageFrames = frames.stream;
    // The subscription starts after this first frame; no network is involved.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(MaterialApp(theme: AppTheme.dark, home: _detail(service)));
    await tester.pump();
    final ChatMessage message =
        ChatMessage.fromMap('incoming', <String, dynamic>{
      'senderId': 'bea',
      'type': 'text',
      'text': 'Un mensaje nuevo',
    });
    frames.add(<ChatMessage>[message]);
    await tester.pump();
    expect(find.text('Un mensaje nuevo'), findsOneWidget);
    final Offset position = tester.getTopLeft(find.text('Un mensaje nuevo'));
    frames.add(<ChatMessage>[message]);
    await tester.pump();
    expect(find.text('Un mensaje nuevo'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Un mensaje nuevo')), position);
    expect(service.sends, 0);
    expect(tester.takeException(), isNull);
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.llfbandit.record/messages'),
            (MethodCall call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.llfbandit.record/messages'), null);
  });

  testWidgets('chat badges retain contrast on the dark primary surface',
      (WidgetTester tester) async {
    final _Chats service = _Chats()
      ..chats = <Chat>[
        _chat('bea', unread: 7),
        _chat('ana', hasAttra: true),
      ];
    await _pump(tester, _list(service));

    final Text count = tester.widget<Text>(find.text('7'));
    final CircleAvatar badge = tester.widget<CircleAvatar>(find
        .ancestor(of: find.text('7'), matching: find.byType(CircleAvatar))
        .first);
    expect(_contrast(count.style!.color!, badge.backgroundColor!),
        greaterThanOrEqualTo(4.5));
    final Icon star = tester.widget<Icon>(find.byIcon(Icons.star));
    final CircleAvatar attra = tester.widget<CircleAvatar>(find
        .ancestor(
            of: find.byIcon(Icons.star), matching: find.byType(CircleAvatar))
        .first);
    expect(_contrast(star.color!, attra.backgroundColor!),
        greaterThanOrEqualTo(3));
  });

  testWidgets('chat list error is recoverable and does not show an empty inbox',
      (WidgetTester tester) async {
    final _Chats service = _Chats()..failChats = true;
    await _pump(tester, _list(service));
    expect(
        find.text('No se pudieron cargar tus conversaciones.'), findsOneWidget);
    expect(find.text('Aún no tienes matches'), findsNothing);

    service
      ..failChats = false
      ..chats = <Chat>[_chat('bea', unread: 1)];
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(service.chatSubscriptions, 2);
    expect(service.sends, 0);
    expect(find.text('Perfil bea'), findsOneWidget);
    expect(
        find.text('No se pudieron cargar tus conversaciones.'), findsNothing);
  });

  testWidgets('story avatar keeps an accessible tap action inside a chat row',
      (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      final _Chats service = _Chats()..chats = <Chat>[_chat('bea', unread: 1)];
      await _pump(tester, _list(service, stories: _Stories()));

      final Finder story = find.bySemanticsLabel('Ver historias de Perfil bea');
      expect(story, findsOneWidget);
      expect(
          tester
              .getSemantics(story)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('messages error retries the read stream without sending anything',
      (WidgetTester tester) async {
    final _Chats service = _Chats()..failMessages = true;
    await _pump(tester, _detail(service));
    expect(find.text('No se pudieron cargar los mensajes.'), findsOneWidget);
    expect(find.text('Aún no hay mensajes. Saluda 👋'), findsNothing);

    final int subscriptionsBeforeRetry = service.messageSubscriptions;
    service.failMessages = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(service.messageSubscriptions, greaterThan(subscriptionsBeforeRetry));
    expect(service.sends, 0);
    expect(find.text('Aún no hay mensajes. Saluda 👋'), findsOneWidget);
    expect(find.text('No se pudieron cargar los mensajes.'), findsNothing);
  });

  testWidgets('send and failed message retry expose usable named controls',
      (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      final _Chats service = _Chats()..failSend = true;
      await _pump(tester, _detail(service));
      final Finder send = find.byTooltip('Enviar mensaje');
      expect(tester.getSemantics(send), isSemantics(isButton: true));
      expect(tester.getSize(send).height, greaterThanOrEqualTo(48));
      await tester.enterText(find.byType(TextField), 'Hola Bea');
      await tester.tap(send);
      await tester.pumpAndSettle();

      final Finder retry = find.widgetWithText(TextButton, 'Reintentar');
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));
      expect(
          tester
              .getSemantics(retry)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue);
      expect(service.sends, 1);
      service.failSend = false;
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(service.sends, 2);
      expect(find.text('Reintentar'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'voice note button labels play and pause and keeps a 48 point target',
      (WidgetTester tester) async {
    final _VoicePlayer player = _VoicePlayer();
    addTearDown(player.states.close);
    await _pump(
      tester,
      Scaffold(
        body: VoiceNoteBubble(
          media: const MediaInfo(
            storagePath: 'voice.m4a',
            downloadUrl: 'https://example.invalid/voice.m4a',
            mimeType: 'audio/mp4',
            durationMs: 12000,
          ),
          mine: true,
          controller: player,
        ),
      ),
    );
    final Finder play = find.byTooltip('Reproducir nota de voz');
    expect(tester.getSize(play).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(play).width, greaterThanOrEqualTo(48));
    await tester.tap(play);
    expect(player.toggles, 1);
    player.states.add(PlayerState(true, ProcessingState.ready));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pausar nota de voz'), findsOneWidget);
  });
}
