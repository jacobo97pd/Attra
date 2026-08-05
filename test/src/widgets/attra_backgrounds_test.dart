import 'package:attra/src/theme/app_theme.dart';
import 'package:attra/src/theme/attra_colors.dart';
import 'package:attra/src/widgets/attra_backgrounds.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'el fondo del shell es oscuro arriba y mayoritariamente claro',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const AttraAppShellBackground(
            child: SizedBox.expand(
              key: ValueKey<String>('shell-content'),
            ),
          ),
        ),
      );

      final Finder decorationFinder = find.descendant(
        of: find.byType(AttraAppShellBackground),
        matching: find.byType(DecoratedBox),
      );
      expect(decorationFinder, findsOneWidget);

      final DecoratedBox decoratedBox =
          tester.widget<DecoratedBox>(decorationFinder);
      final BoxDecoration decoration = decoratedBox.decoration as BoxDecoration;
      expect(decoration.gradient, isA<LinearGradient>());

      final LinearGradient gradient = decoration.gradient! as LinearGradient;
      expect(gradient.begin, Alignment.topCenter);
      expect(gradient.end, Alignment.bottomCenter);
      expect(gradient.colors.first, AttraColors.dark.bg);
      expect(gradient.colors[1], AttraColors.dark.bg);

      final Color paperColor = gradient.colors.last;
      expect(gradient.colors[gradient.colors.length - 2], paperColor);
      expect(paperColor.computeLuminance(), greaterThan(0.85));

      final List<double> stops = gradient.stops!;
      expect(stops.length, gradient.colors.length);
      expect(stops.first, 0);
      expect(stops.last, 1);
      for (int index = 1; index < stops.length; index += 1) {
        expect(stops[index], greaterThanOrEqualTo(stops[index - 1]));
      }

      final double clearAreaStart = stops[stops.length - 2];
      expect(clearAreaStart, lessThanOrEqualTo(0.38));
      expect(1 - clearAreaStart, greaterThan(0.60));
    },
  );
}
