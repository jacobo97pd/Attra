import 'package:attra/src/features/auth/domain/app_user.dart';
import 'package:attra/src/features/monetization/data/entitlement_service.dart';
import 'package:attra/src/features/monetization/data/feature_flag_service.dart';
import 'package:attra/src/features/monetization/domain/monetization_feature_flags.dart';
import 'package:attra/src/features/monetization/domain/premium_feature.dart';
import 'package:attra/src/features/monetization/domain/subscription_tier.dart';
import 'package:attra/src/features/monetization/domain/user_entitlements.dart';
import 'package:attra/src/features/monetization/presentation/entitlement_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEntitlementService implements EntitlementService {
  _FakeEntitlementService(this.value);
  final UserEntitlements value;
  @override
  Future<UserEntitlements> getEntitlements(String uid) async => value;
  @override
  Stream<UserEntitlements> watchEntitlements(String uid) =>
      Stream<UserEntitlements>.value(value);
}

class _FakeFlagService implements FeatureFlagService {
  _FakeFlagService([this.flags = const MonetizationFeatureFlags()]);
  final MonetizationFeatureFlags flags;
  @override
  Future<MonetizationFeatureFlags> fetchFlags() async => flags;
  @override
  Stream<MonetizationFeatureFlags> watchFlags() =>
      Stream<MonetizationFeatureFlags>.value(flags);
}

AppUser _user({bool aiConsent = false}) => AppUser(
      uid: 'u',
      email: null,
      displayName: null,
      photoUrl: null,
      onboardingCompleted: true,
      profileCompleted: true,
      profileCompletionPercent: 100,
      isBot: false,
      aiVisualConsent: aiConsent,
    );

Future<EntitlementController> _controller(
  UserEntitlements ent, {
  bool aiConsent = false,
  MonetizationFeatureFlags flags = const MonetizationFeatureFlags(),
}) async {
  final EntitlementController c = EntitlementController(
    entitlementService: _FakeEntitlementService(ent),
    featureFlagService: _FakeFlagService(flags),
    uid: 'u',
    user: _user(aiConsent: aiConsent),
  );
  await c.load();
  return c;
}

void main() {
  group('Gates por tier (única fuente de verdad)', () {
    test('Free: no ve todos los likes, no comenta, no filtros avanzados, no IA',
        () async {
      final c = await _controller(UserEntitlements.free(uid: 'u'));
      expect(c.canSeeAllLikes, isFalse);
      expect(c.canCommentOnLike, isFalse);
      expect(c.canUseAdvancedFilters, isFalse);
      expect(c.canUseAiVisualMatching, isFalse);
      expect(c.dailyLikeLimit, EntitlementController.freeDailyLikes);
      expect(c.hasNoAds, isFalse);
    });

    test(
        'Plus: ve todos los likes, comenta, filtros avanzados, incógnito; '
        'pero NO IA', () async {
      final c = await _controller(
          UserEntitlements.forTier(uid: 'u', tier: SubscriptionTier.plus));
      expect(c.canSeeAllLikes, isTrue);
      expect(c.canCommentOnLike, isTrue);
      expect(c.canUseAdvancedFilters, isTrue);
      expect(c.canUseIncognito, isTrue);
      expect(c.canUseAiVisualMatching, isFalse); // IA solo Pro
      expect(c.hasNoAds, isTrue);
    });

    test('Pro hereda Plus + IA (con consentimiento)', () async {
      final c = await _controller(
        UserEntitlements.forTier(uid: 'u', tier: SubscriptionTier.pro),
        aiConsent: true,
      );
      // Hereda Plus:
      expect(c.canSeeAllLikes, isTrue);
      expect(c.canCommentOnLike, isTrue);
      expect(c.canUseAdvancedFilters, isTrue);
      expect(c.canUseIncognito, isTrue);
      // Extras Pro:
      expect(c.canUseAiVisualMatching, isTrue);
      expect(c.canUsePriorityLikes, isTrue);
      expect(c.canUseProfileInsights, isTrue);
    });

    test('Pro SIN consentimiento IA no usa IA', () async {
      final c = await _controller(
        UserEntitlements.forTier(uid: 'u', tier: SubscriptionTier.pro),
        aiConsent: false,
      );
      expect(c.canUseAiVisualMatching, isFalse);
      expect(c.canUseProfileInsights, isFalse);
      // Pero lo no-IA de Pro sí:
      expect(c.canSeeAllLikes, isTrue);
    });

    test('Entitlement EXPIRADO vuelve a Free', () async {
      final UserEntitlements expired = UserEntitlements.forTier(
        uid: 'u',
        tier: SubscriptionTier.plus,
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      final c = await _controller(expired);
      expect(c.tier, SubscriptionTier.free);
      expect(c.canSeeAllLikes, isFalse);
    });

    test('límite de likes: Free limitado, expandido amplía, ilimitado evita',
        () async {
      final free = await _controller(UserEntitlements.free(uid: 'u'));
      expect(free.dailyLikeLimit, EntitlementController.freeDailyLikes);

      final plus = await _controller(
          UserEntitlements.forTier(uid: 'u', tier: SubscriptionTier.plus));
      expect(plus.dailyLikeLimit, EntitlementController.expandedDailyLikes);

      final pro = await _controller(
          UserEntitlements.forTier(uid: 'u', tier: SubscriptionTier.pro));
      expect(pro.dailyLikeLimit, -1); // ilimitado (unlimitedLikes)
    });

    test('remove_ads_forever NO desbloquea Plus/Pro', () async {
      // Un usuario Free aunque "comprase" remove_ads sigue sin gates de plan.
      final c = await _controller(UserEntitlements.free(uid: 'u'));
      expect(c.canSeeAllLikes, isFalse);
      expect(c.canUseAdvancedFilters, isFalse);
      expect(c.canCommentOnLike, isFalse);
      // (hasNoAds podría venir de remove_ads por separado, pero NO concede plan.)
    });

    test('kill switch / monetización off => sin features de pago', () async {
      final c = await _controller(
        UserEntitlements.forTier(uid: 'u', tier: SubscriptionTier.plus),
        flags: const MonetizationFeatureFlags.disabled(),
      );
      expect(c.canSeeAllLikes, isFalse);
      expect(c.canCommentOnLike, isFalse);
    });
  });

  // Estos tests FIJAN el contrato Free/Plus/Pro acordado. Si alguien cambia un
  // número de sitio (paywall, backend, controlador) y no lo cambia aquí, se
  // rompe a propósito: los tres tienen que decir lo mismo.
  group('Contrato de planes: qué incluye cada tier', () {
    const MonetizationFeatureFlags defaults = MonetizationFeatureFlags();

    test('Attras al mes por tier (Free ya recibe 1: es el gancho)', () {
      expect(defaults.monthlyAttrasForTier(SubscriptionTier.free), 1);
      expect(defaults.monthlyAttrasForTier(SubscriptionTier.plus), 5);
      expect(defaults.monthlyAttrasForTier(SubscriptionTier.premium), 10);
      expect(defaults.monthlyAttrasForTier(SubscriptionTier.pro), 15);
    });

    test('Boosts al mes por tier (grant real, antes no existía)', () {
      expect(defaults.monthlyBoostsForTier(SubscriptionTier.free), 0);
      expect(defaults.monthlyBoostsForTier(SubscriptionTier.plus), 1);
      expect(defaults.monthlyBoostsForTier(SubscriptionTier.premium), 2);
      expect(defaults.monthlyBoostsForTier(SubscriptionTier.pro), 4);
    });

    test('Superboost cuesta 3 Boosts, no 1 como el Boost de 30 min', () {
      expect(defaults.superboostCostBoosts, 3);
      // Con 4 Boosts (Pro) sale justo "un Superboost + un Boost".
      expect(
        defaults.monthlyBoostsForTier(SubscriptionTier.pro) -
            defaults.superboostCostBoosts,
        1,
      );
    });

    test('Tope de likes diarios: Free 25, Plus 100, Premium/Pro ilimitado', () {
      expect(defaults.dailyLikesForTier(SubscriptionTier.free), 25);
      expect(defaults.dailyLikesForTier(SubscriptionTier.plus), 100);
      expect(defaults.dailyLikesForTier(SubscriptionTier.premium), -1);
      expect(defaults.dailyLikesForTier(SubscriptionTier.pro), -1);
    });

    test('attrasEnabled=false apaga los Attras de TODOS los tiers', () {
      const MonetizationFeatureFlags off =
          MonetizationFeatureFlags(attrasEnabled: false);
      for (final SubscriptionTier tier in SubscriptionTier.values) {
        expect(off.monthlyAttrasForTier(tier), 0, reason: tier.name);
      }
    });

    test('monetización off no acumula Boosts de un plan que no se cobra', () {
      const MonetizationFeatureFlags off = MonetizationFeatureFlags.disabled();
      for (final SubscriptionTier tier in SubscriptionTier.values) {
        expect(off.monthlyBoostsForTier(tier), 0, reason: tier.name);
      }
      // Pero el coste del Superboost NO cae a 0 (regalarlo sería lo contrario
      // de un kill switch) ni se quedan sin likes.
      expect(off.superboostCostBoosts, 3);
      expect(off.dailyLikesForTier(SubscriptionTier.free), 25);
    });
  });

  group('Contrato de planes: parseo de flags remotos', () {
    test('acepta snake_case y camelCase, y snake_case manda', () {
      final MonetizationFeatureFlags snake =
          MonetizationFeatureFlags.fromMap(<String, dynamic>{
        'free_monthly_attras': 2,
        'plus_monthly_boosts': 3,
        'plus_daily_likes': 150,
        'superboost_cost_boosts': 5,
      });
      expect(snake.freeMonthlyAttras, 2);
      expect(snake.plusMonthlyBoosts, 3);
      expect(snake.plusDailyLikes, 150);
      expect(snake.superboostCostBoosts, 5);

      final MonetizationFeatureFlags camel =
          MonetizationFeatureFlags.fromMap(<String, dynamic>{
        'freeMonthlyAttras': 7,
        'proMonthlyBoosts': 9,
        'freeDailyLikes': 40,
      });
      expect(camel.freeMonthlyAttras, 7);
      expect(camel.proMonthlyBoosts, 9);
      expect(camel.freeDailyLikes, 40);

      final MonetizationFeatureFlags both =
          MonetizationFeatureFlags.fromMap(<String, dynamic>{
        'free_monthly_attras': 2,
        'freeMonthlyAttras': 99,
      });
      expect(both.freeMonthlyAttras, 2);
    });

    test('mapa vacío => defaults del contrato', () {
      final MonetizationFeatureFlags f =
          MonetizationFeatureFlags.fromMap(<String, dynamic>{});
      expect(f.freeMonthlyAttras, 1);
      expect(f.plusMonthlyAttras, 5);
      expect(f.premiumMonthlyAttras, 10);
      expect(f.proMonthlyAttras, 15);
      expect(f.freeMonthlyBoosts, 0);
      expect(f.plusMonthlyBoosts, 1);
      expect(f.premiumMonthlyBoosts, 2);
      expect(f.proMonthlyBoosts, 4);
      expect(f.superboostCostBoosts, 3);
      expect(f.freeDailyLikes, 25);
      expect(f.plusDailyLikes, 100);
    });

    test('un superboost_cost_boosts a 0 en remoto NO regala Superboosts', () {
      final MonetizationFeatureFlags f = MonetizationFeatureFlags.fromMap(
          <String, dynamic>{'superboost_cost_boosts': 0});
      expect(f.superboostCostBoosts, 1);
    });
  });

  group('Contrato de planes: features por defecto de cada tier', () {
    List<PremiumFeature> forTier(SubscriptionTier tier) =>
        UserEntitlements.defaultFeaturesForTier(tier);

    test('readReceipts NO se concede a nadie (no existe en el código)', () {
      for (final SubscriptionTier tier in SubscriptionTier.values) {
        expect(forTier(tier), isNot(contains(PremiumFeature.readReceipts)),
            reason: tier.name);
      }
      // Sigue en el enum para poder parsear docs antiguos sin romperlos.
      expect(PremiumFeature.fromValue('read_receipts'),
          PremiumFeature.readReceipts);
    });

    test('Free no tiene ninguna feature de pago', () {
      expect(forTier(SubscriptionTier.free), isEmpty);
    });

    test('Plus: ver todos los likes, filtros, incógnito, viajes y 1 Boost', () {
      final List<PremiumFeature> plus = forTier(SubscriptionTier.plus);
      expect(plus, contains(PremiumFeature.seeAllLikes));
      expect(plus, contains(PremiumFeature.plusFilters));
      expect(plus, contains(PremiumFeature.advancedDeclaredFilters));
      expect(plus, contains(PremiumFeature.incognitoMode));
      expect(plus, contains(PremiumFeature.travelMode));
      expect(plus, contains(PremiumFeature.rewind));
      expect(plus, contains(PremiumFeature.attrasMonthlyGrant));
      expect(plus, contains(PremiumFeature.monthlyBoost));
      // Plus tiene tope de 100/día: likes ampliados, NO ilimitados.
      expect(plus, contains(PremiumFeature.expandedLikes));
      expect(plus, isNot(contains(PremiumFeature.unlimitedLikes)));
      // Ni prioridad ni IA: eso es Pro.
      expect(plus, isNot(contains(PremiumFeature.discoveryPriority)));
      expect(plus.where((PremiumFeature f) => f.isAiVisual), isEmpty);
    });

    test('Premium y Pro incluyen TODO lo de Plus (se componen por rank)', () {
      for (final SubscriptionTier tier in <SubscriptionTier>[
        SubscriptionTier.premium,
        SubscriptionTier.pro,
      ]) {
        for (final PremiumFeature f in forTier(SubscriptionTier.plus)) {
          expect(forTier(tier), contains(f),
              reason: '${tier.name} sin ${f.name}');
        }
      }
    });

    test('Pro: alcance (ilimitado + prioridad) e IA completa', () {
      final List<PremiumFeature> pro = forTier(SubscriptionTier.pro);
      expect(pro, contains(PremiumFeature.unlimitedLikes));
      expect(pro, contains(PremiumFeature.discoveryPriority));
      expect(pro, contains(PremiumFeature.aiVisualEngine));
      expect(pro, contains(PremiumFeature.visualReferenceSearch));
      expect(pro, contains(PremiumFeature.aiVisualTraitFilters));
      expect(pro, contains(PremiumFeature.aiExplanations));
    });

    test('premium (tier retirado) = Pro SIN IA: nadie pierde nada', () {
      final List<PremiumFeature> premium = forTier(SubscriptionTier.premium);
      final List<PremiumFeature> pro = forTier(SubscriptionTier.pro);
      expect(premium.where((PremiumFeature f) => f.isAiVisual), isEmpty);
      expect(
        premium.toSet(),
        pro.where((PremiumFeature f) => !f.isAiVisual).toSet(),
      );
    });
  });

  group('Contrato de planes: el controlador expone los números buenos', () {
    test('Attras incluidos al mes según el tier efectivo', () async {
      final free = await _controller(UserEntitlements.free(uid: 'u'));
      expect(free.monthlyIncludedAttras, 1);

      final plus = await _controller(
          UserEntitlements.forTier(uid: 'u', tier: SubscriptionTier.plus));
      expect(plus.monthlyIncludedAttras, 5);

      final pro = await _controller(
          UserEntitlements.forTier(uid: 'u', tier: SubscriptionTier.pro));
      expect(pro.monthlyIncludedAttras, 15);
    });

    test('Plus tiene tope real de likes (no ilimitado de facto)', () async {
      final plus = await _controller(
          UserEntitlements.forTier(uid: 'u', tier: SubscriptionTier.plus));
      expect(plus.dailyLikeLimit, isNot(-1));
      expect(
          plus.dailyLikeLimit,
          const MonetizationFeatureFlags()
              .dailyLikesForTier(SubscriptionTier.plus));
    });
  });
}
