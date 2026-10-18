import 'package:attra/src/features/chat/data/chat_service.dart';
import 'package:attra/src/features/feed/presentation/feed_screen.dart';
import 'package:attra/src/features/match/data/match_service.dart';
import 'package:attra/src/features/match/domain/match_flow_result.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un flick corto y rápido completa el gesto igual que uno largo.
///
/// Antes `_onDragEnd` solo miraba cuánto había viajado el dedo (`_dx.abs() >
/// _threshold`, 100 px): un toque decidido y rápido que no llegara a esos 100
/// px volvía al centro como si hubiera sido un roce sin querer. Es el mismo
/// criterio que usa `Dismissible` del propio Flutter (velocidad > 700 px/s).
void main() {
  testWidgets(
      'un flick corto hacia la derecha da like aunque no cruce el umbral de distancia',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    final _MatchServiceStub service = _MatchServiceStub();
    await tester.pumpWidget(_FeedHost(
      matchService: service,
      profiles: <SeedProfile>[_profile('zoe', 'Zoe'), _profile('ada', 'Ada')],
    ));
    await tester.pumpAndSettle();
    // El orden de las tarjetas lo pone el ranking, no el test.
    final String primera = _quien(tester).toLowerCase();

    // 60 px es menos de la mitad del umbral de distancia (100 px): con solo
    // la regla antigua, esto habría vuelto al centro.
    await tester.fling(
      find.byKey(const ValueKey<String>('feed-swipe-card')),
      const Offset(60, 0),
      2000,
    );
    await tester.pumpAndSettle();

    expect(service.liked, <String>[primera]);
    expect(service.passed, isEmpty);
  });

  testWidgets(
      'un flick corto hacia la izquierda pasa aunque no cruce el umbral de distancia',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    final _MatchServiceStub service = _MatchServiceStub();
    await tester.pumpWidget(_FeedHost(
      matchService: service,
      profiles: <SeedProfile>[_profile('zoe', 'Zoe'), _profile('ada', 'Ada')],
    ));
    await tester.pumpAndSettle();
    final String primera = _quien(tester).toLowerCase();

    await tester.fling(
      find.byKey(const ValueKey<String>('feed-swipe-card')),
      const Offset(-60, 0),
      2000,
    );
    await tester.pumpAndSettle();

    expect(service.passed, <String>[primera]);
    expect(service.liked, isEmpty);
  });

  testWidgets(
      'un roce lento y corto NO cuenta: ni la distancia ni la velocidad lo piden',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    final _MatchServiceStub service = _MatchServiceStub();
    await tester.pumpWidget(_FeedHost(
      matchService: service,
      profiles: <SeedProfile>[_profile('zoe', 'Zoe'), _profile('ada', 'Ada')],
    ));
    await tester.pumpAndSettle();

    // Mismo recorrido que el flick (60 px) pero lento: por debajo de los
    // 700 px/s, así que no debe ni dar like ni pasar.
    await tester.fling(
      find.byKey(const ValueKey<String>('feed-swipe-card')),
      const Offset(60, 0),
      200,
    );
    await tester.pumpAndSettle();

    expect(service.liked, isEmpty);
    expect(service.passed, isEmpty);
  });
}

/// Nombre de quien está en la tarjeta (la ficha lo pinta como «Zoe, 30»). El
/// orden lo decide el ranking del feed, no este test.
String _quien(WidgetTester tester) {
  for (final Text texto in tester.widgetList<Text>(find.byType(Text))) {
    final String data = texto.data ?? '';
    if (data.endsWith(', 30')) return data.substring(0, data.length - 4);
  }
  return '';
}

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _FeedHost extends StatelessWidget {
  const _FeedHost({required this.profiles, required this.matchService});

  final List<SeedProfile> profiles;
  final MatchService matchService;

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
    photos: const <AdditionalPhoto>[],
  );
}

class _MatchServiceStub implements MatchService {
  final List<String> passed = <String>[];
  final List<String> liked = <String>[];

  @override
  Future<void> passProfile(String toUid) async => passed.add(toUid);

  @override
  Future<MatchFlowResult> sendLike(
    String toUid, {
    String? targetPhotoId,
    String? comment,
    String? promptId,
    String? promptQuestion,
    String? promptAnswer,
  }) async {
    liked.add(toUid);
    return const MatchFlowResult.liked();
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
