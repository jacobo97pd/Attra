import 'package:attra/src/features/tutorial/presentation/tutorial_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'el tutorial cabe con texto grande y se completa en cuatro pasos',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_host(textScale: 2.2));
      await tester.pumpAndSettle();

      expect(find.text('Bienvenido a Attra'), findsOneWidget);
      expect(find.text('Paso 1 de 4'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(tester.takeException(), isNull);

      for (final String title in <String>[
        'Descubre a tu manera',
        'Conecta de verdad',
        'Tú tienes el control',
      ]) {
        await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      expect(find.text('Paso 4 de 4'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar en Attra'));
      await tester.pumpAndSettle();
      expect(find.text('Tutorial cerrado'), findsOneWidget);
    },
  );

  testWidgets('permite saltarlo sin recorrer páginas obligatorias',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Saltar tutorial'));
    await tester.pumpAndSettle();

    expect(find.text('Tutorial cerrado'), findsOneWidget);
  });
}

Widget _host({double textScale = 1}) {
  return MaterialApp(
    builder: (BuildContext context, Widget? child) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      );
    },
    initialRoute: '/tutorial',
    routes: <String, WidgetBuilder>{
      '/': (_) => const Scaffold(body: Text('Tutorial cerrado')),
      '/tutorial': (_) => const TutorialScreen(),
    },
  );
}
