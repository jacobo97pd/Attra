import 'package:attra/core/config/legal_links.dart';
import 'package:attra/src/features/monetization/data/iap_service.dart';
import 'package:attra/src/features/monetization/data/storekit_pending_transactions.dart';
import 'package:attra/src/features/monetization/domain/subscription_tier.dart';
import 'package:attra/src/features/monetization/presentation/paywall_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class _SubscriptionStore implements InAppPurchase {
  final List<String> purchaseAttempts = <String>[];
  final List<ProductDetails> products = <ProductDetails>[
    for (final String tier in <String>['plus', 'pro'])
      for (final bool yearly in <bool>[false, true])
        ProductDetails(
          id: 'attra_${tier}_${yearly ? 'yearly' : 'monthly'}',
          title: 'Attra $tier',
          description: 'Suscripción',
          price: yearly ? r'$179.99' : r'$19.99',
          rawPrice: yearly ? 179.99 : 19.99,
          currencyCode: 'USD',
        ),
  ];

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(
        productDetails: products.where((p) => ids.contains(p.id)).toList(),
        notFoundIDs: const <String>[],
      );

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    purchaseAttempts.add(purchaseParam.productDetails.id);
    return false;
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// App Store Guideline 3.1.2(c): la pantalla de compra debe mostrar título,
/// duración y precio de la suscripción, y enlaces FUNCIONALES al EULA y a la
/// política de privacidad.
void main() {
  for (final (String name, Size size) in <(String, Size)>[
    ('iPad vertical', const Size(820, 1180)),
    ('iPad horizontal', const Size(1180, 820)),
    ('teléfono compacto', const Size(320, 568)),
  ]) {
    testWidgets('los enlaces legales se pueden abrir sin scroll en $name',
        (WidgetTester tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const MethodChannel channel =
          MethodChannel('plugins.flutter.io/url_launcher');
      final List<MethodCall> launches = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall call) async {
          launches.add(call);
          return true;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      await tester.pumpWidget(const MaterialApp(
        home: PaywallScreen(currentTier: SubscriptionTier.free),
      ));
      await tester.pumpAndSettle();

      // Los documentos deben poder abrirse desde el primer momento, también
      // en el iPad de revisión y sin recorrer las ventajas de los planes.
      final Finder terms =
          find.byKey(const ValueKey<String>('legal-link-terms'));
      final Finder privacy =
          find.byKey(const ValueKey<String>('legal-link-privacy'));
      final Finder eula = find.byKey(const ValueKey<String>('legal-link-eula'));
      expect(terms.hitTestable(), findsOneWidget);
      expect(privacy.hitTestable(), findsOneWidget);
      expect(eula.hitTestable(), findsOneWidget);
      await tester.tap(terms);
      await tester.pumpAndSettle();
      await tester.tap(eula);
      await tester.pumpAndSettle();
      await tester.tap(privacy);
      await tester.pumpAndSettle();

      expect(launches.map((MethodCall call) => call.method),
          <String>['launch', 'launch', 'launch']);
      expect(launches.map((MethodCall call) => call.arguments['url']), <String>[
        LegalLinks.termsUrl,
        LegalLinks.eulaUrl,
        LegalLinks.privacyUrl,
      ]);
      for (final MethodCall call in launches) {
        expect(call.arguments['useSafariVC'], isFalse);
        expect(call.arguments['useWebView'], isFalse);
      }
      expect(tester.takeException(), isNull);
    });
  }

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

    // Duración (mensual por defecto), siempre visible.
    expect(
      find.textContaining('se renueva automáticamente cada mes'),
      findsNWidgets(2),
    );

    // Sin datos de StoreKit NO se inventa ningún precio: enseñar uno
    // hardcodeado que no coincide con el del escaparate del usuario es lo que
    // penaliza la Guideline 3.1.2(c).
    expect(find.text('Precio no disponible ahora mismo'), findsNWidgets(2));
    expect(find.textContaining('€'), findsNothing);
    expect(find.textContaining(r'$'), findsNothing);

    // Enlaces legales funcionales dentro del flujo de compra.
    expect(
      find.byKey(const ValueKey<String>('legal-link-terms')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('legal-link-privacy')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('legal-link-eula')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('el plan anual cambia la duración mostrada',
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
    // Tampoco aquí se inventa precio ni equivalencia mensual.
    expect(find.text('Precio no disponible ahora mismo'), findsNWidgets(2));
    expect(find.textContaining('Equivale a'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el precio de tienda y el producto comprado siguen el periodo',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final _SubscriptionStore store = _SubscriptionStore();
    final IapService service = IapService(
      iap: store,
      pendingTransactions: StoreKitPendingTransactions(isIos: false),
    );
    await service.init(
      productIds: store.products.map((p) => p.id).toSet(),
    );
    addTearDown(service.dispose);

    await tester.pumpWidget(MaterialApp(
      home: PaywallScreen(
        currentTier: SubscriptionTier.free,
        iapService: service,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text(r'$19.99 / mes'), findsNWidgets(2));
    expect(find.textContaining('Equivale a'), findsNothing);
    await tester.tap(find.text('Hazte Plus'));
    await tester.pumpAndSettle();
    expect(store.purchaseAttempts, <String>['attra_plus_monthly']);

    await tester.tap(find.text('Anual'));
    await tester.pumpAndSettle();
    expect(find.text(r'$179.99 / año'), findsNWidgets(2));
    expect(find.text(r'Equivale a $15.00 / mes'), findsNWidgets(2));
    expect(find.textContaining('se renueva automáticamente cada año'),
        findsNWidgets(2));
    await tester.tap(find.text('Hazte Plus'));
    await tester.pumpAndSettle();
    expect(store.purchaseAttempts,
        <String>['attra_plus_monthly', 'attra_plus_yearly']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
