import 'dart:async';

import 'package:attra/src/features/auth/presentation/login_video_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// La plataforma falsa solo sustituye al plugin de vídeo en estas pruebas.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  late VideoPlayerPlatform original;
  late _VideoPlatform video;
  late ValueNotifier<bool> reduced;

  setUp(() {
    original = VideoPlayerPlatform.instance;
    video = _VideoPlatform();
    VideoPlayerPlatform.instance = video;
    reduced = ValueNotifier<bool>(false);
  });

  tearDown(() {
    reduced.dispose();
    VideoPlayerPlatform.instance = original;
  });

  testWidgets('Reduce Motion inicial conserva el vídeo pausado y el contenido',
      (WidgetTester tester) async {
    reduced.value = true;
    await tester.pumpWidget(_host(reduced));
    await tester.pumpAndSettle();

    expect(video.asset, 'assets/login/attraloginvideoprueba.mp4');
    expect(video.playCalls, 0);
    expect(video.playing, isFalse);
    expect(find.text('Entrar en Attra'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('cambiar la preferencia pausa y reanuda la misma instancia',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(reduced));
    await tester.pumpAndSettle();
    expect(video.playing, isTrue);
    expect(video.creations, 1);

    reduced.value = true;
    await tester.pumpAndSettle();
    expect(video.playing, isFalse);
    final int pauses = video.pauseCalls;

    reduced.value = false;
    await tester.pumpAndSettle();
    expect(video.playing, isTrue);
    expect(video.creations, 1);
    expect(video.pauseCalls, pauses);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('la inicialización tardía respeta la preferencia más reciente',
      (WidgetTester tester) async {
    video.autoInitialize = false;
    await tester.pumpWidget(_host(reduced));
    await tester.pump();
    reduced.value = true;
    await tester.pump();
    video.initialize();
    await tester.pumpAndSettle();

    expect(video.playCalls, 0);
    expect(video.playing, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('el retorno de segundo plano no ignora Reduce Motion',
      (WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(_host(reduced));
    await tester.pumpAndSettle();
    expect(video.playing, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(video.playing, isFalse);
    reduced.value = true;
    await tester.pump();
    final int plays = video.playCalls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(video.playCalls, plays);
    expect(video.playing, isFalse);

    reduced.value = false;
    await tester.pumpAndSettle();
    expect(video.playing, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('un play en vuelo termina antes de aplicar la pausa solicitada',
      (WidgetTester tester) async {
    final Completer<void> pendingPlay = Completer<void>();
    video.nextPlay = pendingPlay;
    await tester.pumpWidget(_host(reduced));
    await tester.pump();
    expect(video.playCalls, 1);

    reduced.value = true;
    await tester.pump();
    pendingPlay.complete();
    await tester.pumpAndSettle();
    expect(video.playing, isFalse);
    expect(video.commands.last, 'pause');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Widget _host(ValueNotifier<bool> reduced) => ValueListenableBuilder<bool>(
      valueListenable: reduced,
      builder: (BuildContext context, bool reduceMotion, _) => MaterialApp(
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: const Scaffold(
          body: LoginVideoBackground(child: Text('Entrar en Attra')),
        ),
      ),
    );

class _VideoPlatform extends VideoPlayerPlatform {
  bool autoInitialize = true;
  bool playing = false;
  int playCalls = 0;
  int pauseCalls = 0;
  int creations = 0;
  String? asset;
  Completer<void>? nextPlay;
  final List<String> commands = <String>[];
  late final StreamController<VideoEvent> _events =
      StreamController<VideoEvent>.broadcast(onListen: () {
    if (autoInitialize) scheduleMicrotask(initialize);
  });

  void initialize() => _events.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 8),
        size: const Size(1080, 1920),
      ));

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async {
    creations += 1;
    asset = dataSource.asset;
    return 1;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events.stream;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> play(int playerId) async {
    playCalls += 1;
    commands.add('play');
    final Completer<void>? pending = nextPlay;
    nextPlay = null;
    if (pending != null) await pending.future;
    playing = true;
  }

  @override
  Future<void> pause(int playerId) async {
    pauseCalls += 1;
    commands.add('pause');
    playing = false;
  }

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Widget buildView(int playerId) => const SizedBox.expand();

  @override
  Future<void> dispose(int playerId) async {
    playing = false;
    await _events.close();
  }
}
