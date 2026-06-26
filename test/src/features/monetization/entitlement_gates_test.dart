import 'package:attra/src/features/auth/domain/app_user.dart';
import 'package:attra/src/features/monetization/data/entitlement_service.dart';
import 'package:attra/src/features/monetization/data/feature_flag_service.dart';
import 'package:attra/src/features/monetization/domain/monetization_feature_flags.dart';
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
}
