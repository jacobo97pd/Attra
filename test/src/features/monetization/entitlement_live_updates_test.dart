import 'dart:async';

import 'package:attra/src/features/monetization/data/entitlement_service.dart';
import 'package:attra/src/features/monetization/data/feature_flag_service.dart';
import 'package:attra/src/features/monetization/domain/monetization_feature_flags.dart';
import 'package:attra/src/features/monetization/domain/subscription_tier.dart';
import 'package:attra/src/features/monetization/domain/user_entitlements.dart';
import 'package:attra/src/features/monetization/presentation/entitlement_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Servicio con stream controlable: así se puede simular que el backend
/// concede el plan DESPUÉS de que la pantalla haya cargado, que es justo lo
/// que pasa al comprar.
class _StreamEntitlementService implements EntitlementService {
  _StreamEntitlementService(this.initial);

  final UserEntitlements initial;
  final StreamController<UserEntitlements> controller =
      StreamController<UserEntitlements>.broadcast();
  int getCalls = 0;
  int watchCalls = 0;

  @override
  Future<UserEntitlements> getEntitlements(String uid) async {
    getCalls++;
    return initial;
  }

  @override
  Stream<UserEntitlements> watchEntitlements(String uid) {
    watchCalls++;
    return controller.stream;
  }
}

class _StreamFlagService implements FeatureFlagService {
  final StreamController<MonetizationFeatureFlags> controller =
      StreamController<MonetizationFeatureFlags>.broadcast();
  int watchCalls = 0;

  @override
  Future<MonetizationFeatureFlags> fetchFlags() async =>
      const MonetizationFeatureFlags();

  @override
  Stream<MonetizationFeatureFlags> watchFlags() {
    watchCalls++;
    return controller.stream;
  }
}

UserEntitlements _pro(String uid) => UserEntitlements.forTier(
      uid: uid,
      tier: SubscriptionTier.pro,
      source: EntitlementSource.appStore,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );

void main() {
  group('EntitlementController en vivo', () {
    test('el plan concedido tras la compra llega sin volver a cargar',
        () async {
      final _StreamEntitlementService ents =
          _StreamEntitlementService(UserEntitlements.free(uid: 'u'));
      final _StreamFlagService flags = _StreamFlagService();
      final EntitlementController controller = EntitlementController(
        entitlementService: ents,
        featureFlagService: flags,
        uid: 'u',
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.tier, SubscriptionTier.free,
          reason: 'de partida no hay plan');

      // El backend concede Pro un instante después de que el cliente cargase.
      // Antes esto no llegaba: el usuario pagaba y la app seguía en free hasta
      // reiniciar.
      int avisos = 0;
      controller.addListener(() => avisos++);
      ents.controller.add(_pro('u'));
      await Future<void>.delayed(Duration.zero);

      expect(controller.tier, SubscriptionTier.pro);
      expect(avisos, greaterThan(0), reason: 'la UI tiene que enterarse');
    });

    // Viaje en pausa (plan caducado, viaje guardado): cada `load()` posterior
    // (tras una compra, un Boost, Ajustes) ponía `isLoading` a true, el feed
    // contaba el viaje durante la recarga y se recargaba dos veces, vaciando
    // el mazo. Lo que el feed mira ahora es solo la PRIMERA carga.
    test('solo la primera carga cuenta como "plan aún desconocido"', () async {
      final _StreamEntitlementService ents =
          _StreamEntitlementService(UserEntitlements.free(uid: 'u'));
      final _StreamFlagService flags = _StreamFlagService();
      final EntitlementController controller = EntitlementController(
        entitlementService: ents,
        featureFlagService: flags,
        uid: 'u',
      );
      addTearDown(controller.dispose);

      expect(controller.isFirstLoadPending, isTrue,
          reason: 'arranca como Free sin saberlo todavía');
      await controller.load();
      expect(controller.isFirstLoadPending, isFalse);

      final List<bool> vistos = <bool>[];
      controller.addListener(() => vistos.add(controller.isFirstLoadPending));
      await controller.load();

      expect(vistos, isNotEmpty, reason: 'la recarga sí notifica');
      expect(vistos.every((bool pending) => !pending), isTrue,
          reason: 'una recarga no vuelve a dar el plan por desconocido');
    });

    test('se suscribe una sola vez aunque se recargue varias veces', () async {
      final _StreamEntitlementService ents =
          _StreamEntitlementService(UserEntitlements.free(uid: 'u'));
      final _StreamFlagService flags = _StreamFlagService();
      final EntitlementController controller = EntitlementController(
        entitlementService: ents,
        featureFlagService: flags,
        uid: 'u',
      );
      addTearDown(controller.dispose);

      await controller.load();
      await controller.load();
      await controller.load();

      expect(ents.watchCalls, 1);
      expect(flags.watchCalls, 1);
    });

    test('un error del stream no degrada el plan ya concedido', () async {
      final _StreamEntitlementService ents =
          _StreamEntitlementService(_pro('u'));
      final _StreamFlagService flags = _StreamFlagService();
      final EntitlementController controller = EntitlementController(
        entitlementService: ents,
        featureFlagService: flags,
        uid: 'u',
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.tier, SubscriptionTier.pro);

      ents.controller.addError(StateError('sin red'));
      await Future<void>.delayed(Duration.zero);

      expect(controller.tier, SubscriptionTier.pro,
          reason: 'quedarse sin red no puede quitarle el plan a quien pagó');
    });

    test('los flags remotos también llegan en vivo', () async {
      final _StreamEntitlementService ents =
          _StreamEntitlementService(UserEntitlements.free(uid: 'u'));
      final _StreamFlagService flags = _StreamFlagService();
      final EntitlementController controller = EntitlementController(
        entitlementService: ents,
        featureFlagService: flags,
        uid: 'u',
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.flags.visualSearchEnabled, isTrue);

      // Un kill switch tiene que hacer efecto sin reiniciar la app.
      flags.controller.add(const MonetizationFeatureFlags.disabled());
      await Future<void>.delayed(Duration.zero);

      expect(controller.flags.visualSearchEnabled, isFalse);
    });

    test('tras dispose un evento tardío no revienta', () async {
      final _StreamEntitlementService ents =
          _StreamEntitlementService(UserEntitlements.free(uid: 'u'));
      final _StreamFlagService flags = _StreamFlagService();
      final EntitlementController controller = EntitlementController(
        entitlementService: ents,
        featureFlagService: flags,
        uid: 'u',
      );

      await controller.load();
      controller.dispose();

      // No debe lanzar: notifyListeners sobre un ChangeNotifier destruido
      // explota, y el stream sigue vivo un instante más que la pantalla.
      ents.controller.add(_pro('u'));
      flags.controller.add(const MonetizationFeatureFlags());
      await Future<void>.delayed(Duration.zero);
    });
  });
}
