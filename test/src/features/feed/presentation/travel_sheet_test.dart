import 'package:attra/src/features/feed/presentation/travel_sheet.dart';
import 'package:attra/src/features/geo/domain/travel_destination_resolver.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hoja del modo viajes. Se usa Andorra como destino porque su lista de
/// ciudades es pequeña: los ficheros grandes del dataset se decodifican en otro
/// isolate y no terminan dentro del reloj falso del test.
void main() {
  final Finder toggle = find.byKey(const ValueKey<String>('travel-toggle'));

  testWidgets('sin plan pero con un viaje puesto: se puede APAGAR', (
    WidgetTester tester,
  ) async {
    // Con el plan caducado la hoja solo enseñaba el muro de pago: quien tenía
    // un viaje puesto no podía volver a su ciudad sin pagar otra vez.
    final _Applies applies = _Applies();
    await _abrir(
      tester,
      canUseTravelMode: false,
      active: true,
      applies: applies,
    );

    expect(find.text('El modo viajes es Plus y Pro'), findsOneWidget);
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(applies.calls, hasLength(1));
    expect(applies.calls.single.active, isFalse);
    // Y no se puede volver a encender sin plan.
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
  });

  testWidgets('sin plan y sin viaje: solo el muro, nada que encender', (
    WidgetTester tester,
  ) async {
    await _abrir(
      tester,
      canUseTravelMode: false,
      active: false,
      applies: _Applies(),
    );
    expect(find.text('El modo viajes es Plus y Pro'), findsOneWidget);
    expect(toggle, findsNothing);
  });

  testWidgets('al apagar se CONSERVAN país y ciudad para reactivarlo', (
    WidgetTester tester,
  ) async {
    // Antes se guardaba el ISO2 sin el nombre: al reabrir, la hoja enseñaba el
    // país elegido y "Viajar aquí" desactivado.
    final _Applies applies = _Applies();
    await _abrir(
      tester,
      canUseTravelMode: true,
      active: true,
      city: 'Canillo',
      applies: applies,
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    final _Apply off = applies.calls.single;
    expect(off.active, isFalse);
    expect(off.iso2, 'AD');
    expect(off.country, 'Andorra');
    expect(off.city, 'Canillo');
  });

  testWidgets('el interruptor NO publica una ciudad inventada', (
    WidgetTester tester,
  ) async {
    // El botón ya lo rechazaba; el interruptor no miraba la ciudad y guardaba
    // "Canilloo" tal cual como ciudad pública.
    final _Applies applies = _Applies();
    await _abrir(
      tester,
      canUseTravelMode: true,
      active: false,
      applies: applies,
    );

    await tester.enterText(find.byType(TextField), 'Canilloo');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(applies.calls, isEmpty);
    expect(find.text('Elige una ciudad de la lista'), findsOneWidget);
  });

  testWidgets('una ciudad válida sí se activa con el interruptor', (
    WidgetTester tester,
  ) async {
    final _Applies applies = _Applies();
    await _abrir(
      tester,
      canUseTravelMode: true,
      active: false,
      applies: applies,
    );

    await tester.enterText(find.byType(TextField), 'Canillo');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(applies.calls.single.active, isTrue);
    expect(applies.calls.single.city, 'Canillo');
  });

  testWidgets('destino sin situar: se guarda y se AVISA de que es a nivel país',
      (WidgetTester tester) async {
    final _Applies applies = _Applies(located: false);
    await _abrir(
      tester,
      canUseTravelMode: true,
      active: false,
      applies: applies,
    );

    await tester.enterText(find.byType(TextField), 'Canillo');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(applies.calls.single.active, isTrue);
    expect(
        find.textContaining('No hemos podido situar Canillo'), findsOneWidget);
  });
}

Future<void> _abrir(
  WidgetTester tester, {
  required bool canUseTravelMode,
  required bool active,
  required _Applies applies,
  String city = '',
}) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () => showTravelSheet(
            context,
            canUseTravelMode: canUseTravelMode,
            active: active,
            iso2: 'AD',
            country: 'Andorra',
            city: city,
            onApply: applies.call,
          ),
          child: const Text('abrir'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

class _Apply {
  const _Apply(this.active, this.iso2, this.city, this.country);
  final bool active;
  final String iso2;
  final String city;
  final String country;
}

class _Applies {
  _Applies({this.located = true});

  final bool located;
  final List<_Apply> calls = <_Apply>[];

  Future<TravelApplyResult?> call({
    required bool active,
    String iso2 = '',
    String city = '',
    String country = '',
  }) async {
    calls.add(_Apply(active, iso2, city, country));
    return TravelApplyResult(located: located);
  }
}
