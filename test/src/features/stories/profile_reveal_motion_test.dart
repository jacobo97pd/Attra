import 'package:attra/src/features/stories/presentation/profile_reveal_screen.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('authorized reveal stops blur on reduced motion and keeps action',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ValueNotifier<bool> reduced = ValueNotifier<bool>(false);
    addTearDown(reduced.dispose);
    int opens = 0;
    await tester.pumpWidget(ValueListenableBuilder<bool>(
      valueListenable: reduced,
      builder: (_, bool value, __) => MaterialApp(
        themeAnimationDuration: Duration.zero,
        theme: AppTheme.dark,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: value),
          child: child!,
        ),
        home: ProfileRevealScreen(
            name: 'Alex', age: 30, photoUrl: '', onOpenProfile: () => opens++),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ImageFiltered), findsOneWidget);
    final AnimationController reveal = tester
        .widget<AnimatedBuilder>(find
            .ancestor(
                of: find.byType(ImageFiltered),
                matching: find.byType(AnimatedBuilder))
            .first)
        .animation as AnimationController;
    expect(reveal.duration, const Duration(milliseconds: 1400));
    expect(reveal.isAnimating, isTrue);
    reduced.value = true;
    await tester.pump();
    expect(find.byType(ImageFiltered), findsNothing);
    expect(reveal.isAnimating, isFalse);
    expect(reveal.value, 1);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.tap(find.byKey(const ValueKey<String>('reveal-open-profile')));
    expect(opens, 1);
    reduced.value = false;
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
