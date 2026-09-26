import 'package:attra/src/features/auth/data/device_location_source.dart';
import 'package:attra/src/features/auth/domain/app_user.dart';
import 'package:attra/src/features/auth/domain/location_refresh_policy.dart';
import 'package:attra/src/features/auth/domain/resolved_place.dart';
import 'package:attra/src/features/chat/data/chat_service.dart';
import 'package:attra/src/features/feed/domain/feed_exclusions.dart';
import 'package:attra/src/features/feed/domain/slow_dating.dart';
import 'package:attra/src/features/feed/presentation/feed_screen.dart';
import 'package:attra/src/features/match/data/match_service.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// La "segunda vuelta" y las exclusiones del feed, con la pantalla REAL.
///
/// C06/C15/C16: la segunda vuelta restaba TODOS los pases del conjunto de
/// excluidos, que mezclaba pases, likes, matches y bloqueos; quien estaba fuera
/// por un pase Y algo duro volvía al feed (el bloqueado, quien TE bloqueó, a
/// quien mandaste un Attra, a quien reportaste en directo).
/// D09: si la lectura de exclusiones fallaba, el feed seguía con nadie fuera.
/// C45: con Slow Dating, la segunda vuelta se recortaba siempre a los mismos 12.
void main() {
  final Finder segundaVuelta = find.text('Dar una segunda vuelta');

  testWidgets(
      'la segunda vuelta solo repone pases: nunca bloqueados (en los dos '
      'sentidos), Attras ni reportes del directo', (WidgetTester tester) async {
    _usePhoneViewport(tester);
    final _MatchServiceStub service = _MatchServiceStub(
      exclusions: const FeedExclusions(
        liked: <String>{'attra'},
        passed: <String>{
          'pasado',
          'bloqueado',
          'me_bloqueo',
          'attra',
        },
        permanentlyPassed: <String>{'reportado'},
        // Solo sé que 'me_bloqueo' me bloqueó por el match en 'blocked'.
        matched: <String>{'me_bloqueo'},
        blocked: <String>{'bloqueado'},
      ),
    );
    await tester.pumpWidget(_host(
      service: service,
      profiles: <SeedProfile>[
        _perfil('pasado', 'Pasado'),
        _perfil('bloqueado', 'Bloqueado'),
        _perfil('me_bloqueo', 'Bloqueador'),
        _perfil('attra', 'Conattra'),
        _perfil('reportado', 'Reportado'),
      ],
    ));
    await tester.pumpAndSettle();

    // Todos excluidos en el feed normal: se ofrece la segunda vuelta, y la
    // cifra es la de quien de verdad puede volver (antes contaba bloqueados).
    expect(segundaVuelta, findsOneWidget);
    expect(find.textContaining('las 1 personas que pasaste'), findsOneWidget);

    await tester.tap(segundaVuelta);
    await tester.pumpAndSettle();

    expect(await _recorrerMazo(tester), <String>['Pasado']);
  });

  testWidgets(
      'si no se puede leer a quién excluir, NO se enseña a nadie (y se puede '
      'reintentar)', (WidgetTester tester) async {
    _usePhoneViewport(tester);
    final _MatchServiceStub service =
        _MatchServiceStub(exclusions: FeedExclusions.unavailable);
    await tester.pumpWidget(_host(
      service: service,
      profiles: <SeedProfile>[
        _perfil('bloqueado', 'Bloqueado'),
        _perfil('nuevo', 'Nuevo'),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('feed-swipe-card')), findsNothing);
    expect(find.textContaining('No hemos podido comprobar'), findsOneWidget);

    // Vuelve la red: "Reintentar" carga con las exclusiones buenas.
    service.exclusions = const FeedExclusions(blocked: <String>{'bloqueado'});
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(await _recorrerMazo(tester), <String>['Nuevo']);
  });

  testWidgets(
      'si una lectura falla DESPUÉS de una buena, se cubre con la buena '
      '(el bloqueado no vuelve)', (WidgetTester tester) async {
    _usePhoneViewport(tester);
    final _MatchServiceStub service = _MatchServiceStub(
      exclusions: const FeedExclusions(blocked: <String>{'bloqueado'}),
    );
    await tester.pumpWidget(_host(
      service: service,
      profiles: <SeedProfile>[
        _perfil('bloqueado', 'Bloqueado'),
        _perfil('nuevo', 'Nuevo'),
      ],
    ));
    await tester.pumpAndSettle();
    expect(await _recorrerMazo(tester), <String>['Nuevo']);

    // La lectura de bloqueos se cae (token que se refresca, `unavailable`).
    // Antes: una lectura caída = conjunto vacío = el bloqueado de vuelta.
    service.exclusions = const FeedExclusions(
      failed: <ExclusionSource>{ExclusionSource.blocks},
    );
    await tester.tap(find.text('Recargar'));
    await tester.pumpAndSettle();

    final List<String> mazo = await _recorrerMazo(tester);
    expect(mazo, isNot(contains('Bloqueado')));
    expect(mazo, contains('Nuevo'));
  });

  testWidgets('con Slow Dating, la segunda vuelta no se recorta a 12',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    const int pases = SlowDatingRanker.curatedLimit + 3;
    final List<SeedProfile> perfiles = <SeedProfile>[
      for (int i = 0; i < pases; i++) _perfil('p$i', 'Pasada$i'),
    ];
    final _MatchServiceStub service = _MatchServiceStub(
      exclusions: FeedExclusions(
        passed: <String>{for (final SeedProfile p in perfiles) p.id},
      ),
    );
    await tester.pumpWidget(_host(
      service: service,
      profiles: perfiles,
      user: _yo(slowDating: true),
    ));
    await tester.pumpAndSettle();

    expect(
        find.textContaining('las $pases personas que pasaste'), findsOneWidget);
    await tester.tap(segundaVuelta);
    await tester.pumpAndSettle();

    expect((await _recorrerMazo(tester)).length, pases,
        reason: 'volver a pasar no excluye: con el recorte salían siempre los '
            'mismos 12 y el resto eran inalcanzables');
  });
}

AppUser _yo({bool slowDating = false}) {
  return AppUser(
    uid: 'yo',
    email: 'yo@example.test',
    displayName: 'Yo',
    photoUrl: '',
    onboardingCompleted: true,
    profileCompleted: true,
    profileCompletionPercent: 100,
    isBot: false,
    slowDatingEnabled: slowDating,
  );
}

SeedProfile _perfil(String id, String nombre) {
  return SeedProfile.fromMap(id, <String, dynamic>{
    'displayName': nombre,
    'age': 30,
    'isBot': false,
    'bio': 'Hola',
  });
}

Widget _host({
  required _MatchServiceStub service,
  required List<SeedProfile> profiles,
  AppUser? user,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: FeedScreen(
        user: user ?? _yo(),
        onLoadSeedProfiles: () async => profiles,
        matchService: service,
        chatService: _ChatServiceStub(),
        locationSource: _SinGps(),
        onDeviceLocation: _noGuardar,
        placeResolver: const _SinSitio(),
      ),
    ),
  );
}

/// Nombres de todo el mazo, en orden: pasa carta a carta hasta agotarlo.
Future<List<String>> _recorrerMazo(WidgetTester tester) async {
  final List<String> vistos = <String>[];
  final Finder carta = find.byKey(const ValueKey<String>('feed-swipe-card'));
  for (int i = 0; i < 30 && carta.evaluate().isNotEmpty; i++) {
    final String quien = _quien(tester);
    if (quien.isEmpty) break;
    vistos.add(quien);
    await tester.drag(carta, const Offset(-260, 0));
    await tester.pumpAndSettle();
  }
  return vistos;
}

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

Future<void> _noGuardar({
  required double latitude,
  required double longitude,
  required DateTime fixedAt,
  String? permissionStatus,
  bool? permissionGranted,
  ResolvedPlace? place,
}) async {}

class _SinSitio implements PlaceResolver {
  const _SinSitio();

  @override
  Future<ResolvedPlace?> resolve({
    required double latitude,
    required double longitude,
  }) async =>
      null;
}

class _SinGps implements DeviceLocationSource {
  @override
  Future<LocationAuthorization> authorization() async =>
      LocationAuthorization.granted;

  @override
  Future<LocationAuthorization> requestAuthorization() async =>
      LocationAuthorization.granted;

  @override
  Future<LocationFix?> lastKnownFix() async => null;

  @override
  Future<LocationFix?> currentFix({
    Duration timeout = const Duration(seconds: 8),
  }) async =>
      null;
}

class _MatchServiceStub implements MatchService {
  _MatchServiceStub({required this.exclusions});

  /// Lo que "devuelve el servidor". Mutable para simular fallos entre cargas.
  FeedExclusions exclusions;

  @override
  Future<FeedExclusions> fetchExcludedUids(String uid) async => exclusions;

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
