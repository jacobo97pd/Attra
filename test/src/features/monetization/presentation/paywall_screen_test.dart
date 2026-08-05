import 'package:attra/src/features/monetization/domain/subscription_tier.dart';
import 'package:attra/src/features/monetization/presentation/paywall_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// App Store Guideline 3.1.2(c): la pantalla de compra debe mostrar título,
/// duración y precio de la suscripción, y enlaces FUNCIONALES al EULA y a la
/// política de privacidad.
void main() {
  testWidgets('el paywall muestra título, duración, precio y enlaces legales',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: PaywallScreen(currentTier: SubscriptionTier.free),
    ));
    await tester.pumpAndSettle();

    // Título de cada suscripción.
    expect(find.text('Attra Plus'), findsOneWidget);
    expect(find.text('Attra Pro'), findsOneWidget);

    // Duración (mensual por defecto) y precio.
    expect(
      find.textContaining('se renueva automáticamente cada mes'),
      findsNWidgets(2),
    );
    expect(find.text('9,99 € / mes'), findsOneWidget);
    expect(find.text('19,99 € / mes'), findsOneWidget);

    // Enlaces legales funcionales dentro del flujo de compra.
    expect(
      find.byKey(const ValueKey<String>('legal-link-terms')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('legal-link-privacy')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('el plan anual muestra la duración y el precio por mes',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: PaywallScreen(currentTier: SubscriptionTier.free),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Anual'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('se renueva automáticamente cada año'),
      findsNWidgets(2),
    );
    expect(find.text('99,99 € / año'), findsOneWidget);
    expect(find.text('Equivale a 8,33 € / mes'), findsOneWidget);
    expect(find.text('199,99 € / año'), findsOneWidget);
    expect(find.text('Equivale a 16,67 € / mes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
