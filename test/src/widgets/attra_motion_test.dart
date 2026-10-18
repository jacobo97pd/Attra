import 'package:attra/src/theme/app_theme.dart';
import 'package:attra/src/widgets/attra_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('press feedback never delays, duplicates or shrinks the target',
      (WidgetTester tester) async {
    int calls = 0;
    await tester.pumpWidget(_host(AttraPressFeedback(
      child: TextButton(onPressed: () => calls++, child: const Text('Acción')),
    )));
    final Rect target = tester.getRect(find.byType(TextButton));
    final TestGesture gesture = await tester.startGesture(target.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_scale(tester), closeTo(.98, .001));
    expect(tester.getRect(find.byType(AttraPressFeedback)), target);
    final Transform transform = tester.widget<Transform>(find
        .descendant(
            of: find.byType(AttraPressFeedback),
            matching: find.byType(Transform))
        .first);
    expect(transform.transformHitTests, isFalse);
    expect(calls, 0);
    await gesture.up();
    expect(calls, 1);
    await tester.pumpAndSettle();
    expect(_scale(tester), 1);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard activation stays immediate without press movement',
      (WidgetTester tester) async {
    final FocusNode focus = FocusNode();
    addTearDown(focus.dispose);
    int calls = 0;
    await tester.pumpWidget(_host(AttraPressFeedback(
      child: TextButton(
          focusNode: focus,
          onPressed: () => calls++,
          child: const Text('Acción')),
    )));
    focus.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 40));
    expect(_scale(tester), 1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(calls, 1);
  });

  testWidgets('cancelled pointer releases feedback without invoking the action',
      (WidgetTester tester) async {
    int calls = 0;
    await tester.pumpWidget(_host(AttraPressFeedback(
      child: TextButton(onPressed: () => calls++, child: const Text('Acción')),
    )));
    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(find.byType(TextButton)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(_scale(tester), 1);
    expect(calls, 0);
  });

  testWidgets('reduced motion can change during a press without losing action',
      (WidgetTester tester) async {
    final ValueNotifier<bool> reduced = ValueNotifier<bool>(false);
    addTearDown(reduced.dispose);
    int calls = 0;
    await tester.pumpWidget(ValueListenableBuilder<bool>(
        valueListenable: reduced,
        builder: (_, bool value, __) => _host(
            AttraPressFeedback(
              child: TextButton(
                  onPressed: () => calls++, child: const Text('Acción')),
            ),
            reduced: value)));
    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(find.byType(TextButton)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    reduced.value = true;
    await tester.pump();
    expect(_scale(tester), 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
      'state changes keep only current content and do not replay streams',
      (WidgetTester tester) async {
    final ValueNotifier<int> state = ValueNotifier<int>(0);
    final ValueNotifier<int> rebuild = ValueNotifier<int>(0);
    addTearDown(state.dispose);
    addTearDown(rebuild.dispose);
    await tester.pumpWidget(ValueListenableBuilder<int>(
      valueListenable: rebuild,
      builder: (_, __, ___) => ValueListenableBuilder<int>(
        valueListenable: state,
        builder: (_, int value, __) => _host(
            AttraStateTransition(value: value, child: Text('Estado $value'))),
      ),
    ));
    expect(_offset(tester), Offset.zero);
    expect(tester.binding.transientCallbackCount, 0);
    state.value = 1;
    await tester.pump();
    expect(find.text('Estado 0'), findsNothing);
    expect(find.text('Estado 1'), findsOneWidget);
    expect(_offset(tester).dy, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 55));
    final double progress = _offset(tester).dy;
    state.value = 2;
    await tester.pump();
    expect(_offset(tester).dy, lessThanOrEqualTo(progress));
    expect(find.text('Estado 1'), findsNothing);
    await tester.pumpAndSettle();
    rebuild.value++;
    await tester.pump();
    expect(_offset(tester), Offset.zero);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final bool reduced in <bool>[true, false]) {
    testWidgets('state cue stops when ${reduced ? 'reduced' : 'offstage'}',
        (WidgetTester tester) async {
      final ValueNotifier<int> state = ValueNotifier<int>(0);
      final ValueNotifier<bool> stop = ValueNotifier<bool>(false);
      addTearDown(state.dispose);
      addTearDown(stop.dispose);
      await tester.pumpWidget(ValueListenableBuilder<bool>(
        valueListenable: stop,
        builder: (_, bool stopped, __) => ValueListenableBuilder<int>(
          valueListenable: state,
          builder: (_, int value, __) => _host(
              TickerMode(
                  enabled: reduced || !stopped,
                  child: AttraStateTransition(
                      value: value, child: Text('Estado $value'))),
              reduced: reduced && stopped),
        ),
      ));
      state.value = 1;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      stop.value = true;
      await tester.pump();
      expect(_offset(tester), Offset.zero);
      expect(find.text('Estado 1'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      stop.value = false;
      await tester.pump();
      expect(_offset(tester), Offset.zero);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }
}

Widget _host(Widget child, {bool reduced = false}) => MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: AppTheme.dark,
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: Scaffold(body: Center(child: child)),
    );

double _scale(WidgetTester tester) => tester
    .widget<Transform>(find
        .descendant(
            of: find.byType(AttraPressFeedback),
            matching: find.byType(Transform))
        .first)
    .transform
    .storage[0];

Offset _offset(WidgetTester tester) => tester
    .widget<SlideTransition>(find
        .descendant(
            of: find.byType(AttraStateTransition),
            matching: find.byType(SlideTransition))
        .first)
    .position
    .value;
