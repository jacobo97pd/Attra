import 'package:attra/src/features/monetization/domain/premium_product_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

/// El enrutador de compras decide el destino de cada recibo por el PRODUCTO, no
/// por la pantalla abierta.
///
/// Antes cada pantalla solo sabía entregar los suyos: si llegaba la compra de un
/// pack de Boosts con el paywall abierto, el paywall la mandaba a
/// `verifyPurchase`, el backend la rechazaba por producto desconocido y el
/// usuario se quedaba sin saldo habiendo pagado.
void main() {
  group('Catálogo de productos: clasificación consumible / suscripción', () {
    test('los consumibles se reconocen por su kind', () {
      final Set<String> ids = PremiumProductCatalog.consumableIds;
      expect(ids, isNotEmpty);
      for (final String id in ids) {
        final PremiumProductDefinition? def = PremiumProductCatalog.byId(id);
        expect(def, isNotNull, reason: '$id debe existir en el catálogo');
        expect(
          (def!.consumableKind ?? '').isNotEmpty,
          isTrue,
          reason: '$id se declara consumible pero no tiene kind',
        );
        expect(
          def.consumableAmount,
          greaterThan(0),
          reason: '$id abonaría 0 unidades: el usuario pagaría por nada',
        );
      }
    });

    test('los ids de suscripción NO se clasifican como consumibles', () {
      const List<String> subscriptionIds = <String>[
        'attra_plus',
        'attra_plus_monthly',
        'attra_plus_yearly',
        'attra_pro',
        'attra_pro_monthly',
        'attra_pro_yearly',
      ];
      for (final String id in subscriptionIds) {
        expect(
          PremiumProductCatalog.consumableIds.contains(id),
          isFalse,
          reason: '$id iría a grantConsumable en vez de a verifyPurchase',
        );
      }
    });

    test('cada consumible tiene kind conocido por el backend', () {
      const Set<String> known = <String>{'boost', 'swipe', 'attra'};
      for (final String id in PremiumProductCatalog.consumableIds) {
        final String kind = PremiumProductCatalog.byId(id)!.consumableKind!;
        expect(
          known,
          contains(kind),
          reason: 'kind "$kind" de $id no lo entiende grantConsumable',
        );
      }
    });
  });

  group('Periodo deducido del id, nunca del selector en pantalla', () {
    // Réplica exacta de PurchaseDeliveryRouter._periodOf. Una compra restaurada
    // o diferida puede llegar con el selector en "Anual" siendo mensual; fiarse
    // de la pantalla le daba un año de plan al backend.
    String? periodOf(String productId) {
      if (productId.endsWith('_yearly')) return 'yearly';
      if (productId.endsWith('_monthly')) return 'monthly';
      return null;
    }

    test('se deduce de los sufijos', () {
      expect(periodOf('attra_plus_monthly'), 'monthly');
      expect(periodOf('attra_pro_yearly'), 'yearly');
    });

    test('sin sufijo NO se inventa: decide el backend', () {
      expect(periodOf('attra_plus'), isNull);
      expect(periodOf('attra_pro'), isNull);
    });
  });
}
