import 'package:attra/src/theme/app_theme.dart';
import 'package:attra/src/widgets/attra_loader.dart';
import 'package:attra/src/widgets/attra_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('los loaders detienen y reanudan sus tickers con la preferencia',
      (WidgetTester tester) async {
    final ValueNotifier<bool> reduced = ValueNotifier<bool>(false);
    addTearDown(reduced.dispose);
    await tester.pumpWidget(_host(reduced: reduced));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    reduced.value = true;
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.text('Subiendo foto'), findsOneWidget);
    expect(find.text('Enviando foto'), findsOneWidget);

    reduced.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('los loaders ocultos dejan de solicitar frames',
      (WidgetTester tester) async {
    final ValueNotifier<bool> reduced = ValueNotifier<bool>(false);
    final ValueNotifier<bool> visible = ValueNotifier<bool>(true);
    addTearDown(reduced.dispose);
    addTearDown(visible.dispose);
    await tester.pumpWidget(_host(reduced: reduced, visible: visible));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    visible.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);

    visible.value = true;
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('la carga sigue anunciada aunque no haya animación',
      (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final ValueNotifier<bool> reduced = ValueNotifier<bool>(true);
    addTearDown(reduced.dispose);
    try {
      await tester.pumpWidget(_host(reduced: reduced));
      await tester.pumpAndSettle();

      for (final String label in <String>[
        'Subiendo foto',
        'Enviando foto',
        'Cargando perfiles',
      ]) {
        final Finder status = find.bySemanticsLabel(label);
        expect(status, findsOneWidget);
        expect(tester.getSemantics(status),
            matchesSemantics(label: label, isLiveRegion: true));
      }
      expect(tester.binding.transientCallbackCount, 0);
    } finally {
      semantics.dispose();
    }
  });
}

Widget _host({
  required ValueNotifier<bool> reduced,
  ValueNotifier<bool>? visible,
}) {
  return ValueListenableBuilder<bool>(
    valueListenable: reduced,
    builder: (BuildContext context, bool reduceMotion, _) {
      return MaterialApp(
        theme: AppTheme.dark,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: visible ?? reduced,
            builder: (BuildContext context, bool value, _) => TickerMode(
              enabled: visible == null || value,
              child: const Column(
                children: <Widget>[
                  AttraLogoLoader(label: 'Subiendo foto'),
                  AttraInlineLoader(label: 'Enviando foto'),
                  Expanded(child: AttraProfileCardSkeleton()),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
