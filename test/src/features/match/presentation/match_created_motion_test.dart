import 'package:attra/src/features/match/presentation/match_created_dialog.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Reduce Motion elimina el zoom y conserva la acción de match',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ValueNotifier<bool> reduced = ValueNotifier<bool>(true);
    addTearDown(reduced.dispose);
    int openedChat = 0;

    await tester.pumpWidget(ValueListenableBuilder<bool>(
      valueListenable: reduced,
      builder: (BuildContext context, bool reduceMotion, _) => MaterialApp(
        theme: AppTheme.dark,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: TextButton(
              onPressed: () => showMatchCreatedDialog(
                context,
                name: 'Alex',
                photoUrl: null,
                hasAttra: false,
                onOpenChat: () => openedChat += 1,
              ),
              child: const Text('Abrir match'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Abrir match'));
    await tester.pumpAndSettle();

    final Finder matchTitle = find.text('A ti y a Alex les gusta mutuamente');
    Finder zoom() => find.ancestor(
          of: matchTitle,
          matching: find.byType(ScaleTransition),
        );
    expect(matchTitle, findsOneWidget);
    expect(zoom(), findsNothing);

    reduced.value = false;
    await tester.pump();
    expect(zoom(), findsOneWidget);
    reduced.value = true;
    await tester.pump();
    expect(zoom(), findsNothing);

    await tester.tap(find.text('Enviar mensaje'));
    await tester.pumpAndSettle();
    expect(openedChat, 1);
    expect(find.text('Abrir match'), findsOneWidget);
    expect(matchTitle, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
