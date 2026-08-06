import 'package:attra/src/features/monetization/domain/premium_product_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

/// El enrutador de compras decide a qué backend va cada recibo mirando
/// `consumableKind`. Un producto consumible SIN kind se enruta como si fuera
/// una suscripción, `verifyPurchase` lo rechaza por producto desconocido y el
/// usuario paga sin recibir nada. Le pasaba a los tres packs de Attras.
void main() {
  group('Todo pack de consumible es enrutable', () {
    test('los packs de Attras se reconocen como consumibles', () {
      for (final PremiumProductDefinition pack
          in PremiumProductCatalog.attraPacks) {
        expect(
          pack.consumableKind,
          'attra',
          reason: '${pack.id} se enrutaría a verifyPurchase y se perdería',
        );
        expect(
          pack.consumableAmount,
          pack.attraAmount,
          reason: '${pack.id} abonaría una cantidad distinta a la vendida',
        );
      }
    });

    test('NINGÚN pack (Attras, Boosts, Swipes) se queda sin kind', () {
      final List<PremiumProductDefinition> packs = <PremiumProductDefinition>[
        ...PremiumProductCatalog.attraPacks,
        ...PremiumProductCatalog.boostPacks,
        ...PremiumProductCatalog.swipePacks,
      ];
      expect(packs, isNotEmpty);
      for (final PremiumProductDefinition pack in packs) {
        expect(
          (pack.consumableKind ?? '').isNotEmpty,
          isTrue,
          reason: '${pack.id} es un pack pero no declara consumableKind',
        );
        expect(pack.consumableAmount, greaterThan(0),
            reason: '${pack.id} abonaría 0 unidades');
        expect(
          PremiumProductCatalog.consumableIds,
          contains(pack.id),
          reason: '${pack.id} no entraría en los ids que vigila la sesión',
        );
      }
    });

    test('las suscripciones NO se confunden con consumibles', () {
      for (final PremiumProductDefinition p
          in PremiumProductCatalog.products.where(
        (PremiumProductDefinition p) => p.isSubscription,
      )) {
        expect(
          PremiumProductCatalog.consumableIds.contains(p.id),
          isFalse,
          reason: '${p.id} iría a grantConsumable en vez de a verifyPurchase',
        );
      }
    });

    test('los kinds son los que entiende el backend', () {
      const Set<String> known = <String>{'attra', 'boost', 'swipe'};
      for (final String id in PremiumProductCatalog.consumableIds) {
        expect(known, contains(PremiumProductCatalog.byId(id)!.consumableKind));
      }
    });
  });
}
