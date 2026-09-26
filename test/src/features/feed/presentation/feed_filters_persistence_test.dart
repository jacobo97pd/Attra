import 'package:attra/src/features/auth/data/device_location_source.dart';
import 'package:attra/src/features/auth/domain/app_user.dart';
import 'package:attra/src/features/auth/domain/location_refresh_policy.dart';
import 'package:attra/src/features/auth/domain/resolved_place.dart';
import 'package:attra/src/features/chat/data/chat_service.dart';
import 'package:attra/src/features/feed/domain/feed_exclusions.dart';
import 'package:attra/src/features/feed/domain/feed_filters.dart';
import 'package:attra/src/features/feed/presentation/feed_screen.dart';
import 'package:attra/src/features/feed/presentation/feed_top_bar.dart';
import 'package:attra/src/features/match/data/match_service.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Filtros del feed guardados y con UNA sola verdad para el radio y la edad
/// (C23/C42/C09), con la pantalla real.
void main() {
  final Finder chipDistancia =
      find.byKey(const ValueKey<String>('feed-chip-distance'));

  testWidgets(
      'arranca con el radio y la edad guardados, y el slider parte de ahí',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    final List<FeedFilters> guardados = <FeedFilters>[];
    await tester.pumpWidget(_host(
      user: _yo(maxDistanceKm: 300, ageMin: 25, ageMax: 35),
      profiles: <SeedProfile>[_perfil('a', 'Ana', age: 30)],
      onSave: guardados.add,
    ));
    await tester.pumpAndSettle();

    // El chip dice el radio que se aplica (antes: "Distancia" apagado, que se
    // leía como "sin límite" mientras el feed cortaba en el del onboarding).
    expect(find.descendant(of: chipDistancia, matching: find.text('300 km')),
        findsOneWidget);
    expect(tester.widget<FeedFilterChip>(chipDistancia).active, isTrue);

    // El slider parte de 300 (antes: 100 fijos, y con tope en 200 —quien
    // eligió 300 en el onboarding no podía volver—).
    await tester.tap(chipDistancia);
    await tester.pumpAndSettle();
    expect(find.text('Hasta 300 km'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('quick-filter-apply')));
    await tester.pumpAndSettle();

    // Aplicar SIN tocar nada guarda lo mismo, no el doble.
    expect(guardados, hasLength(1));
    expect(guardados.single.maxDistanceKm, 300);
    expect(guardados.single.minAge, 25);
    expect(guardados.single.maxAge, 35);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el rango de edad del onboarding se aplica, y es recíproco',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(_host(
      // Tengo 58 y busco 25-60.
      user: _yo(age: 58, ageMin: 25, ageMax: 60),
      profiles: <SeedProfile>[
        _perfil('joven', 'Joven', age: 21),
        // Me cabe en el rango, pero ella busca 22-30: yo no quepo en el suyo.
        _perfil('lucia', 'Lucía', age: 24, extra: <String, dynamic>{
          'preferredAgeMin': 22,
          'preferredAgeMax': 30,
        }),
        // Cabe en el mío y yo en el suyo.
        _perfil('marta', 'Marta', age: 50, extra: <String, dynamic>{
          'preferredAgeMin': 45,
          'preferredAgeMax': 65,
        }),
      ],
    ));
    await tester.pumpAndSettle();

    expect(await _recorrerMazo(tester), <String>['Marta, 50']);
  });

  testWidgets(
      'sin Plus los filtros avanzados guardados NO se aplican; con Plus sí, y '
      'al caducar dejan de aplicarse sin reiniciar',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    final List<SeedProfile> perfiles = <SeedProfile>[
      _perfil('fuma', 'Fuma', extra: <String, dynamic>{'smoking': 'regularly'}),
      _perfil('nofuma', 'Nofuma', extra: <String, dynamic>{'smoking': 'never'}),
    ];
    final AppUser yo = _yo(saved: <String, dynamic>{
      'smoking': 'never',
      'dealbreakers': <String>['smoking'],
    });
    final ValueNotifier<bool> plus = ValueNotifier<bool>(true);
    addTearDown(plus.dispose);
    await tester.pumpWidget(ValueListenableBuilder<bool>(
      valueListenable: plus,
      builder: (_, bool isPlus, __) =>
          _host(user: yo, profiles: perfiles, isPlus: isPlus),
    ));
    await tester.pumpAndSettle();

    // Con Plus, el "no fuma" guardado sobrevive al reinicio y excluye.
    expect(await _recorrerMazo(tester), <String>['Nofuma, 30']);

    // Caduca Plus con la app abierta: sin reiniciar, deja de excluir.
    plus.value = false;
    await tester.pumpAndSettle();
    expect((await _recorrerMazo(tester)).toSet(),
        <String>{'Fuma, 30', 'Nofuma, 30'});
  });
}

AppUser _yo({
  int? maxDistanceKm,
  int? age,
  int? ageMin,
  int? ageMax,
  Map<String, dynamic> saved = const <String, dynamic>{},
}) {
  return AppUser(
    uid: 'yo',
    email: 'yo@example.test',
    displayName: 'Yo',
    photoUrl: '',
    onboardingCompleted: true,
    profileCompleted: true,
    profileCompletionPercent: 100,
    isBot: false,
    maxDistanceKm: maxDistanceKm,
    age: age,
    preferredAgeMin: ageMin,
    preferredAgeMax: ageMax,
    savedFeedFilters: saved,
  );
}

SeedProfile _perfil(
  String id,
  String nombre, {
  int age = 30,
  Map<String, dynamic> extra = const <String, dynamic>{},
}) {
  return SeedProfile.fromMap(id, <String, dynamic>{
    'displayName': nombre,
    'age': age,
    'isBot': false,
    'bio': 'Hola',
    ...extra,
  });
}

Widget _host({
  required AppUser user,
  required List<SeedProfile> profiles,
  bool isPlus = false,
  void Function(FeedFilters)? onSave,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: FeedScreen(
        user: user,
        isPlus: isPlus,
        onLoadSeedProfiles: () async => profiles,
        matchService: _MatchServiceStub(),
        chatService: _ChatServiceStub(),
        locationSource: _SinGps(),
        onDeviceLocation: _noGuardar,
        placeResolver: const _SinSitio(),
        onSaveFilters:
            onSave == null ? null : (FeedFilters f) async => onSave(f),
      ),
    ),
  );
}

/// "Nombre, edad" de cada carta del mazo, pasando carta a carta.
Future<List<String>> _recorrerMazo(WidgetTester tester) async {
  final List<String> vistos = <String>[];
  final Finder carta = find.byKey(const ValueKey<String>('feed-swipe-card'));
  final RegExp nombreEdad = RegExp(r'^\S+, \d+$');
  for (int i = 0; i < 20 && carta.evaluate().isNotEmpty; i++) {
    final String quien = tester
        .widgetList<Text>(find.byType(Text))
        .map((Text t) => t.data ?? '')
        .firstWhere(nombreEdad.hasMatch, orElse: () => '');
    if (quien.isEmpty) break;
    vistos.add(quien);
    await tester.drag(carta, const Offset(-260, 0));
    await tester.pumpAndSettle();
  }
  return vistos;
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
  @override
  Future<FeedExclusions> fetchExcludedUids(String uid) async =>
      const FeedExclusions();

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
