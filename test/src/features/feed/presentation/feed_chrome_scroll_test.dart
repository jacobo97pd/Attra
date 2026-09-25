import 'package:attra/src/features/chat/data/chat_service.dart';
import 'package:attra/src/features/feed/presentation/feed_screen.dart';
import 'package:attra/src/features/feed/presentation/feed_top_bar.dart';
import 'package:attra/src/features/match/data/match_service.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// La cabecera del feed al estilo Hinge, con la pantalla REAL montada: bajar por
/// una ficha esconde los filtros (y avisa al shell para que esconda la barra de
/// navegación) y enseña el nombre; subir lo devuelve todo.
void main() {
  final Finder filtros =
      find.byKey(const ValueKey<String>('feed-top-bar-filters'));
  final Finder titulo =
      find.byKey(const ValueKey<String>('feed-top-bar-title'));

  testWidgets('bajar pliega los filtros y enseña el nombre; subir los devuelve',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    final List<bool> avisos = <bool>[];
    await tester.pumpWidget(_FeedHost(
      profiles: <SeedProfile>[_profile('zoe', 'Zoe')],
      onChromeHiddenChanged: avisos.add,
    ));
    await tester.pumpAndSettle();

    expect(filtros, findsOneWidget);
    expect(titulo, findsNothing);

    await tester.drag(_ficha('zoe'), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(filtros, findsNothing);
    expect(find.descendant(of: titulo, matching: find.text('Zoe')),
        findsOneWidget);
    expect(avisos, <bool>[true]);

    // Subir un poco, sin llegar arriba, ya los devuelve.
    await tester.drag(_ficha('zoe'), const Offset(0, 120));
    await tester.pumpAndSettle();

    expect(filtros, findsOneWidget);
    expect(titulo, findsNothing);
    expect(avisos, <bool>[true, false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la siguiente ficha empieza arriba y con los filtros a la vista',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    final List<bool> avisos = <bool>[];
    await tester.pumpWidget(_FeedHost(
      profiles: <SeedProfile>[_profile('zoe', 'Zoe'), _profile('ada', 'Ada')],
      onChromeHiddenChanged: avisos.add,
    ));
    await tester.pumpAndSettle();

    await tester.drag(_cualquierFicha, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(filtros, findsNothing);

    // Pasar: deslizar la tarjeta a la izquierda.
    await tester.drag(
      find.byKey(const ValueKey<String>('feed-swipe-card')),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();

    expect(filtros, findsOneWidget,
        reason: 'la cabecera plegada era de la ficha anterior');
    expect(avisos.last, isFalse);
    final ScrollableState scroll = tester.state<ScrollableState>(
      find
          .descendant(of: _cualquierFicha, matching: find.byType(Scrollable))
          .first,
    );
    expect(scroll.position.pixels, 0,
        reason: 'la tarjeta se reutiliza entre fichas: sin clave por perfil, '
            'la siguiente persona salía a media ficha');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Distancia se pone desde su chip y el chip queda relleno',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(_FeedHost(
      profiles: <SeedProfile>[_profile('zoe', 'Zoe')],
    ));
    await tester.pumpAndSettle();

    final Finder chip =
        find.byKey(const ValueKey<String>('feed-chip-distance'));
    expect(tester.widget<FeedFilterChip>(chip).active, isFalse);

    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('Hasta 100 km'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('quick-filter-apply')));
    await tester.pumpAndSettle();

    expect(tester.widget<FeedFilterChip>(chip).active, isTrue);
    // El contador del botón de todos los filtros también lo cuenta.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('feed-filter-bar')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin Plus, Altura lleva al paywall y no abre un editor inútil',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    int paywall = 0;
    await tester.pumpWidget(_FeedHost(
      profiles: <SeedProfile>[_profile('zoe', 'Zoe')],
      onOpenUpgrade: () => paywall++,
    ));
    await tester.pumpAndSettle();

    // La fila se desplaza en horizontal, como la de Hinge: en un móvil normal
    // "Altura" ya asoma cortado por la derecha.
    final Finder altura = find.widgetWithText(FeedFilterChip, 'Altura');
    await tester.ensureVisible(altura);
    await tester.pumpAndSettle();
    await tester.tap(altura);
    await tester.pumpAndSettle();

    expect(paywall, 1);
    expect(
        find.byKey(const ValueKey<String>('quick-filter-apply')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('las acciones del shell van fijas en la fila de filtros',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(_FeedHost(
      profiles: <SeedProfile>[_profile('zoe', 'Zoe')],
      headerActions: const <Widget>[
        Icon(Icons.notifications_none_rounded, key: ValueKey<String>('bell')),
      ],
    ));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
          of: filtros, matching: find.byKey(const ValueKey<String>('bell'))),
      findsOneWidget,
    );
    // Y no hay logo ni título de pantalla ocupando una fila.
    expect(find.text('Descubrir'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Finder _ficha(String id) =>
    find.byKey(ValueKey<String>('feed-profile-scroll-$id'));

/// La ficha que esté en pantalla. El orden lo decide el pipeline del feed
/// (ranking, Boost, "te dio like"…) y el test no debe inventárselo.
final Finder _cualquierFicha = find.byWidgetPredicate((Widget w) {
  final Key? key = w.key;
  return w is ListView &&
      key is ValueKey<String> &&
      key.value.startsWith('feed-profile-scroll-');
});

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _FeedHost extends StatelessWidget {
  const _FeedHost({
    required this.profiles,
    this.onChromeHiddenChanged,
    this.onOpenUpgrade,
    this.headerActions = const <Widget>[],
  });

  final List<SeedProfile> profiles;
  final ValueChanged<bool>? onChromeHiddenChanged;
  final VoidCallback? onOpenUpgrade;
  final List<Widget> headerActions;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: FeedScreen(
          user: null,
          onLoadSeedProfiles: () async => profiles,
          matchService: _MatchServiceStub(),
          chatService: _ChatServiceStub(),
          onChromeHiddenChanged: onChromeHiddenChanged,
          onOpenUpgrade: onOpenUpgrade,
          headerActions: headerActions,
        ),
      ),
    );
  }
}

/// Ficha larga: tiene que dar para bajar por ella.
SeedProfile _profile(String id, String name) {
  return SeedProfile(
    id: id,
    displayName: name,
    city: 'Madrid',
    country: 'Espana',
    bio: List<String>.filled(40, 'Una bio larga de prueba.').join(' '),
    gender: 'female',
    interestedIn: const <String>[],
    orientation: const <String>['heterosexual'],
    age: 30,
    jobTitle: 'Disenadora',
    company: 'Atelier',
    interests: const <String>['Arte', 'Cine', 'Viajar', 'Cocina', 'Correr'],
    photoUrl: '',
    isBot: false,
    botProfileVersion: 0,
    botScenario: '',
    seedQualityScore: 100,
    photos: const <AdditionalPhoto>[],
  );
}

class _MatchServiceStub implements MatchService {
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
