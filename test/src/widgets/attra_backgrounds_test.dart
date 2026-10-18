import 'package:attra/src/theme/app_theme.dart';
import 'package:attra/src/theme/attra_colors.dart';
import 'package:attra/src/widgets/attra_backgrounds.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final Brightness brightness in Brightness.values) {
    testWidgets(
      'el fondo continuo conserva el contraste en $brightness',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final ThemeData theme =
            brightness == Brightness.dark ? AppTheme.dark : AppTheme.light;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const AttraAppShellBackground(
              child: SizedBox.expand(
                key: ValueKey<String>('shell-content'),
              ),
            ),
          ),
        );

        final Finder backgroundFinder = find.descendant(
          of: find.byType(AttraAppShellBackground),
          matching: find.byType(ColoredBox),
        );
        expect(backgroundFinder, findsOneWidget);
        final Color background =
            tester.widget<ColoredBox>(backgroundFinder).color;
        final AttraColors colors = theme.extension<AttraColors>()!;
        expect(background, colors.bg);
        expect(
            tester.getSize(find.byKey(const ValueKey<String>('shell-content'))),
            const Size(390, 844));
        final double contrast = (colors.textPrimary.computeLuminance() + 0.05) /
            (background.computeLuminance() + 0.05);
        expect(
            contrast > 1 ? contrast : 1 / contrast, greaterThanOrEqualTo(4.5));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
