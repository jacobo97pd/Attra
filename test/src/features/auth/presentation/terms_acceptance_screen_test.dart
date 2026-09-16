import 'package:attra/src/features/auth/presentation/terms_acceptance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('la sesión restaurada exige marcar la casilla para continuar',
      (WidgetTester tester) async {
    int accepted = 0;
    int signedOut = 0;
    await tester.pumpWidget(MaterialApp(
      home: TermsAcceptanceScreen(
        onAccept: () => accepted++,
        onSignOut: () => signedOut++,
      ),
    ));
    expect(find.textContaining('tolerancia cero'), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('legal-link-terms')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('legal-link-privacy')),
        findsOneWidget);
    final Finder proceed =
        find.byKey(const ValueKey<String>('session-terms-continue'));
    await tester.tap(proceed);
    expect(accepted, 0);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(proceed);
    expect(accepted, 1);
    await tester.tap(find.text('Cerrar sesión'));
    expect(signedOut, 1);
  });

  testWidgets(
      'el gate es accesible con texto grande y muestra errores de guardado',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: TermsAcceptanceScreen(
        errorMessage: 'No se pudo guardar la aceptación.',
        onAccept: () {},
        onSignOut: () {},
      ),
    ));
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continuar'));
    expect(find.text('No se pudo guardar la aceptación.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
