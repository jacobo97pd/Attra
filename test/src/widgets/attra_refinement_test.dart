import 'dart:ui' show SemanticsAction;

import 'package:attra/src/features/onboarding/presentation/interested_in_picker.dart';
import 'package:attra/src/features/security/presentation/lock_screen.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:attra/src/widgets/attra_badges.dart';
import 'package:attra/src/widgets/attra_destination_bar.dart';
import 'package:attra/src/widgets/attra_editorial.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final bool dark in <bool>[true, false]) {
    testWidgets(
        'flexible content and currency remain usable at 320/200% ($dark)',
        (WidgetTester tester) async {
      _size(tester, const Size(320, 600));
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        final List<int> calls = <int>[];
        await tester.pumpWidget(MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: _largeText,
          home: Scaffold(
              body: SingleChildScrollView(
                  child: AttraContentFrame(
            padding: const EdgeInsets.all(16),
            child: Column(children: <Widget>[
              AttraCoin(balance: 12345678, onTap: () => calls.add(0)),
              const SizedBox(height: 16),
              const AttraLabel(
                  label: 'Un distintivo que puede ocupar varias líneas',
                  icon: Icons.star,
                  champagne: true),
              const SizedBox(height: 16),
              AttraAdaptiveGrid(children: <Widget>[
                for (int i = 1; i <= 3; i++)
                  Column(children: <Widget>[
                    Text(
                        'Respuesta personal $i, con una descripción extensa que debe leerse completa.'),
                    FilledButton(
                        onPressed: () => calls.add(i),
                        child: Text('Acción $i')),
                  ]),
              ]),
            ]),
          ))),
        ));
        final Finder coin =
            find.bySemanticsLabel('Attras disponibles: 12345678');
        expect(
            tester
                .getSemantics(coin)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isTrue);
        expect(tester.getSize(find.byType(AttraCoin)).height,
            greaterThanOrEqualTo(48));
        await tester.tap(coin);
        for (int i = 1; i <= 3; i++) {
          await tester.ensureVisible(find.text('Acción $i'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Acción $i'));
        }
        expect(calls, <int>[0, 1, 2, 3]);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('selected choice retains its action and announces selection',
      (WidgetTester tester) async {
    int taps = 0;
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
              body: SelectablePill(
                  label: 'Amistad', selected: true, onTap: () => taps++))));
      expect(tester.getSemantics(find.byType(SelectablePill)),
          isSemantics(isSelected: true, isButton: true));
      expect(tester.getSize(find.byType(SelectablePill)).height,
          greaterThanOrEqualTo(48));
      await tester.tap(find.text('Amistad'));
      expect(taps, 1);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'PIN remains scrollable and returns the same digits in a short window',
      (WidgetTester tester) async {
    _size(tester, const Size(320, 360));
    String? result;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        builder: _largeText,
        home: Builder(
            builder: (BuildContext context) => Scaffold(
                    body: TextButton(
                  onPressed: () async => result = await Navigator.of(context)
                      .push<String>(MaterialPageRoute<String>(
                          builder: (_) => const PinEntryScreen(
                              title: 'Crea un PIN',
                              subtitle: 'Lo pedirás para abrir Attra.'))),
                  child: const Text('Configurar'),
                )))));
    await tester.tap(find.text('Configurar'));
    await tester.pumpAndSettle();
    for (final String digit in <String>['1', '2', '3', '4']) {
      await tester.ensureVisible(find.text(digit));
      await tester.pumpAndSettle();
      await tester.tap(find.text(digit));
      await tester.pumpAndSettle();
    }
    expect(result, '1234');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'expanded navigation keeps the same destinations and dispatches once',
      (WidgetTester tester) async {
    _size(tester, const Size(1000, 800));
    final List<int> selected = <int>[];
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
            body: Row(children: <Widget>[
          AttraDestinationBar(
              rail: true,
              selectedIndex: 0,
              onDestinationSelected: selected.add,
              destinations: const <NavigationDestination>[
                NavigationDestination(
                    icon: Icon(Icons.explore), label: 'Descubrir'),
                NavigationDestination(
                    icon: Icon(Icons.favorite), label: 'Conexiones'),
                NavigationDestination(icon: Icon(Icons.forum), label: 'Chats'),
                NavigationDestination(
                    icon: Icon(Icons.person), label: 'Perfil'),
              ]),
          const Expanded(child: Text('Contenido')),
        ]))));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.text('Chats'));
    expect(selected, <int>[2]);
    expect(tester.takeException(), isNull);
  });
}

Widget _largeText(BuildContext context, Widget? child) => MediaQuery(
    data:
        MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
    child: child!);

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
