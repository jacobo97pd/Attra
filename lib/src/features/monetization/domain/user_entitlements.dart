import 'monetization_feature_flags.dart';
import 'premium_feature.dart';
import 'subscription_tier.dart';

enum EntitlementSource {
  none('none'),
  appStore('app_store'),
  playStore('play_store'),
  admin('admin'),
  promo('promo');

  const EntitlementSource(this.wireName);

  final String wireName;

  static EntitlementSource fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final EntitlementSource source in EntitlementSource.values) {
      if (source.wireName == raw || source.name.toLowerCase() == raw) {
        return source;
      }
    }
    return EntitlementSource.none;
  }
}

class UserEntitlements {
  const UserEntitlements({
    required this.uid,
    required this.tier,
    required this.source,
    required this.expiresAt,
    required this.renewsAt,
    required this.isLifetime,
    required this.features,
  });

  factory UserEntitlements.free({required String uid}) {
    return UserEntitlements.forTier(uid: uid, tier: SubscriptionTier.free);
  }

  factory UserEntitlements.forTier({
    required String uid,
    required SubscriptionTier tier,
    EntitlementSource source = EntitlementSource.none,
    DateTime? expiresAt,
    DateTime? renewsAt,
    bool isLifetime = false,
    List<PremiumFeature>? features,
  }) {
    return UserEntitlements(
      uid: uid,
      tier: tier,
      source: source,
      expiresAt: expiresAt,
      renewsAt: renewsAt,
      isLifetime: isLifetime,
      features: features ?? defaultFeaturesForTier(tier),
    );
  }

  factory UserEntitlements.fromMap(String uid, Map<String, dynamic> map) {
    final SubscriptionTier tier = SubscriptionTier.fromValue(map['tier']);
    final List<PremiumFeature> parsedFeatures =
        ((map['features'] as List<dynamic>?) ?? <dynamic>[])
            .map(PremiumFeature.fromValue)
            .whereType<PremiumFeature>()
            .toList(growable: false);

    return UserEntitlements.forTier(
      uid: uid,
      tier: tier,
      source: EntitlementSource.fromValue(map['source']),
      expiresAt: _asDate(map['expiresAt']),
      renewsAt: _asDate(map['renewsAt']),
      isLifetime: _asBool(map['isLifetime']),
      features: parsedFeatures.isEmpty ? null : parsedFeatures,
    );
  }

  final String uid;
  final SubscriptionTier tier;
  final EntitlementSource source;
  final DateTime? expiresAt;
  final DateTime? renewsAt;
  final bool isLifetime;
  final List<PremiumFeature> features;

  bool get isPaid => tier.isPaid;

  bool isActiveAt(DateTime now) {
    if (tier == SubscriptionTier.free) {
      return true;
    }
    if (isLifetime) {
      return true;
    }
    final DateTime? expiry = expiresAt;
    return expiry == null || expiry.isAfter(now);
  }

  SubscriptionTier effectiveTierAt(DateTime now) {
    return isActiveAt(now) ? tier : SubscriptionTier.free;
  }

  bool hasFeature(
    PremiumFeature feature, {
    MonetizationFeatureFlags flags = const MonetizationFeatureFlags(),
    bool aiVisualConsent = false,
    DateTime? at,
  }) {
    final DateTime now = at ?? DateTime.now();
    final SubscriptionTier effectiveTier = effectiveTierAt(now);
    if (effectiveTier == SubscriptionTier.free) {
      return false;
    }
    if (!flags.isTierEnabled(effectiveTier)) {
      return false;
    }
    if (!flags.isFeatureEnabled(feature)) {
      return false;
    }
    if (feature.isAiVisual && !aiVisualConsent) {
      return false;
    }
    return features.contains(feature);
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'tier': tier.wireName,
      'source': source.wireName,
      'expiresAt': expiresAt?.toIso8601String(),
      'renewsAt': renewsAt?.toIso8601String(),
      'isLifetime': isLifetime,
      'features': features
          .map((PremiumFeature feature) => feature.wireName)
          .toList(growable: false),
    };
  }

  static List<PremiumFeature> defaultFeaturesForTier(SubscriptionTier tier) {
    switch (tier) {
      case SubscriptionTier.free:
        return const <PremiumFeature>[];
      case SubscriptionTier.plus:
        // Plus (segun spec Free/Plus/Pro): ver todos los likes, comentar,
        // filtros avanzados, incognito. La IA visual queda SOLO para Pro.
        return const <PremiumFeature>[
          PremiumFeature.expandedLikes,
          PremiumFeature.rewind,
          PremiumFeature.plusFilters,
          PremiumFeature.advancedDeclaredFilters,
          PremiumFeature.limitedLikesPreview,
          PremiumFeature.seeAllLikes,
          PremiumFeature.incognitoMode,
          PremiumFeature.attrasMonthlyGrant,
          PremiumFeature.travelMode,
        ];
      case SubscriptionTier.premium:
        return const <PremiumFeature>[
          PremiumFeature.expandedLikes,
          PremiumFeature.unlimitedLikes,
          PremiumFeature.rewind,
          PremiumFeature.plusFilters,
          PremiumFeature.limitedLikesPreview,
          PremiumFeature.seeAllLikes,
          PremiumFeature.discoveryPriority,
          PremiumFeature.incognitoMode,
          PremiumFeature.advancedDeclaredFilters,
          PremiumFeature.monthlyBoost,
          PremiumFeature.readReceipts,
          PremiumFeature.attrasMonthlyGrant,
          PremiumFeature.travelMode,
        ];
      case SubscriptionTier.pro:
        return const <PremiumFeature>[
          PremiumFeature.expandedLikes,
          PremiumFeature.unlimitedLikes,
          PremiumFeature.rewind,
          PremiumFeature.plusFilters,
          PremiumFeature.limitedLikesPreview,
          PremiumFeature.seeAllLikes,
          PremiumFeature.discoveryPriority,
          PremiumFeature.incognitoMode,
          PremiumFeature.advancedDeclaredFilters,
          PremiumFeature.monthlyBoost,
          PremiumFeature.readReceipts,
          PremiumFeature.attrasMonthlyGrant,
          PremiumFeature.travelMode,
          PremiumFeature.aiVisualEngine,
          PremiumFeature.aiVisualTraitFilters,
          PremiumFeature.visualReferenceSearch,
          PremiumFeature.aiVisualRanking,
          PremiumFeature.aiExplanations,
          PremiumFeature.aiDataControls,
        ];
    }
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  static DateTime? _asDate(Object? value) {
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}
