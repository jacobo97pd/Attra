import 'package:attra/src/features/chat/data/chat_service.dart';
import 'package:attra/src/features/chat/data/reply_suggestion_service.dart';
import 'package:attra/src/features/chat/domain/chat.dart';
import 'package:attra/src/features/chat/domain/chat_message.dart';
import 'package:attra/src/features/chat/presentation/chat_detail_screen.dart';
import 'package:attra/src/features/chat/presentation/chats_screen.dart';
import 'package:attra/src/features/connection_lab/presentation/demo_challenge_screen.dart';
import 'package:attra/src/features/match/data/match_service.dart';
import 'package:attra/src/features/profile/data/profile_summary_repository.dart';
import 'package:attra/src/features/profile/domain/profile_summary.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:attra/src/widgets/attra_editorial.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Chats implements ChatService {
  List<Chat> chats = <Chat>[];
  List<ChatMessage> messages = <ChatMessage>[];
  final List<String> sent = <String>[];

  @override
  Stream<List<Chat>> observeChats(String uid) =>
      Stream<List<Chat>>.value(chats);

  @override
  Stream<Chat?> observeChatById(String chatId) => Stream<Chat?>.value(_chat());

  @override
  Stream<List<ChatMessage>> observeMessages(String chatId, {int limit = 100}) =>
      Stream<List<ChatMessage>>.value(messages);

  @override
  Future<void> markAsRead(String chatId) async {}

  @override
  Future<String> sendMessage({
    required String chatId,
    required String text,
    String? gameSessionId,
  }) async {
    sent.add(text);
    return 'sent-${sent.length}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Matches implements MatchService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Replies implements ReplySuggestionService {
  int calls = 0;

  @override
  Future<List<String>> suggest({required String chatId}) async {
    calls++;
    return const <String>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Summaries implements ProfileSummaryRepository {
  @override
  Future<ProfileSummary> fetch(String uid) async => ProfileSummary(
      uid: uid, displayName: 'Beatriz de los Ángeles', photoUrl: '');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Chat _chat() => Chat.fromMap('me_bea', <String, dynamic>{
      'matchId': 'me_bea',
      'users': <String>['me', 'bea'],
      'status': 'active',
      'lastMessageType': 'text',
      'lastMessage': '¿Te apetece que quedemos esta semana?',
      'lastMessageSenderId': 'bea',
      'unreadCountByUser': <String, int>{'me': 7},
    });

Future<void> _pump(WidgetTester tester, Widget screen,
    {double width = 320,
    double height = 1000,
    double scale = 2,
    double keyboard = 0}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark,
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        viewInsets: EdgeInsets.only(bottom: keyboard),
      ),
      child: child!,
    ),
    home: screen,
  ));
  await tester.pumpAndSettle();
}

Widget _detail(_Chats chats, {_Replies? replies}) => ChatDetailScreen(
      chatId: 'me_bea',
      currentUid: 'me',
      other: const ProfileSummary(
          uid: 'bea', displayName: 'Beatriz de los Ángeles', photoUrl: ''),
      chatService: chats,
      matchService: _Matches(),
      icebreakersEnabled: true,
      replySuggestionService: replies,
    );

void main() {
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

  testWidgets('inbox names and previews remain usable at 320 and 200% text',
      (WidgetTester tester) async {
    final _Chats service = _Chats()..chats = <Chat>[_chat()];
    await _pump(
        tester,
        Scaffold(
          body: ChatsScreen(
            currentUid: 'me',
            chatService: service,
            matchService: _Matches(),
            summaries: _Summaries(),
          ),
        ));

    await tester.ensureVisible(find.text('Beatriz de los Ángeles'));
    expect(find.text('¿Te apetece que quedemos esta semana?'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(service.sent, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('photo context and full-width composer preserve chat actions',
      (WidgetTester tester) async {
    final _Chats service = _Chats()
      ..messages = <ChatMessage>[
        const ChatMessage(
          id: 'context',
          senderId: 'bea',
          receiverId: 'me',
          type: MessageType.attraContext,
          text: 'Me encanta ese lugar. ¿Dónde hiciste la foto?',
          status: MessageStatus.sent,
          relatedPhotoDeleted: true,
        ),
      ];
    await _pump(tester, _detail(service));

    expect(find.byType(AttraPhotoNote), findsOneWidget);
    expect(find.text('Te envió un Attra'), findsOneWidget);
    expect(find.text('Respondió a una foto que ya no está disponible'),
        findsOneWidget);
    expect(tester.getSize(find.byType(TextField)).width,
        greaterThanOrEqualTo(280));
    for (final String label in <String>[
      'Proponer plan',
      'Más',
      'Grabar nota de voz',
      'Enviar mensaje'
    ]) {
      final Size size = tester.getSize(find.byTooltip(label));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField), 'Hola Bea');
    await tester.tap(find.byTooltip('Enviar mensaje'));
    await tester.pumpAndSettle();
    expect(service.sent, <String>['Hola Bea']);

    await tester.tap(find.byTooltip('Más'));
    await tester.pumpAndSettle();
    expect(find.text('Enviar foto'), findsOneWidget);
    expect(find.text('Foto bomba'), findsOneWidget);
    expect(find.text('Juegos y rompehielos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guided tools disclose all three existing actions',
      (WidgetTester tester) async {
    final _Chats service = _Chats();
    final _Replies replies = _Replies();
    await _pump(tester, _detail(service, replies: replies),
        width: 800, scale: 1);

    await tester.tap(find.text('AI Challenge'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Start Challenge'));
    await tester.tap(find.text('Start Challenge'));
    await tester.pumpAndSettle();
    expect(find.byType(DemoChallengeScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(DemoChallengeScreen))).pop();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Suggest opener'));
    await tester.tap(find.text('Suggest opener'));
    await tester.pumpAndSettle();
    expect(replies.calls, 1);

    await tester.ensureVisible(find.text('Play quick game'));
    await tester.tap(find.text('Play quick game'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(service.sent, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard and multiline entry leave usable controls at 320/200%',
      (WidgetTester tester) async {
    final _Chats service = _Chats();
    await _pump(tester, _detail(service), height: 640, keyboard: 240);
    await tester.enterText(
        find.byType(TextField), 'Primera línea\nSegunda línea\nTercera línea');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).maxLines, 2);
    final Rect composer =
        tester.getRect(find.byKey(const ValueKey<String>('chat-composer')));
    expect(composer.bottom, lessThanOrEqualTo(400));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('AI Challenge'));
    await tester.pumpAndSettle();
    expect(find.text('Start Challenge'), findsOneWidget);
    expect(tester.getRect(find.byTooltip('Enviar mensaje')).bottom,
        lessThanOrEqualTo(400));
    expect(service.sent, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
