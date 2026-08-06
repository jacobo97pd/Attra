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

  /// Base de Attra Plus: "que te vean y ver quién te quiere".
  ///
  /// Incluye `monthlyBoost` porque el grant mensual de Boosts pasa a ser REAL
  /// (1 al mes para Plus, ver `MonetizationFeatureFlags.monthlyBoostsForTier`).
  /// Antes esta feature solo la tenían Premium/Pro y no regalaba nada.
  ///
  /// NO incluye `unlimitedLikes`: Plus se queda en `plusDailyLikes` (100/día).
  /// Solo `expandedLikes`, que es lo que activa ese tramo.
  static const List<PremiumFeature> _plusFeatures = <PremiumFeature>[
    PremiumFeature.expandedLikes,
    PremiumFeature.rewind,
    PremiumFeature.plusFilters,
    PremiumFeature.advancedDeclaredFilters,
    PremiumFeature.limitedLikesPreview,
    PremiumFeature.seeAllLikes,
    PremiumFeature.incognitoMode,
    PremiumFeature.attrasMonthlyGrant,
    PremiumFeature.travelMode,
    PremiumFeature.monthlyBoost,
  ];

  /// Lo que Premium/Pro añaden sobre Plus: alcance (likes ilimitados y
  /// prioridad en descubrimiento).
  static const List<PremiumFeature> _reachFeatures = <PremiumFeature>[
    PremiumFeature.unlimitedLikes,
    PremiumFeature.discoveryPriority,
  ];

  /// IA visual: EXCLUSIVA de Pro. `premium` (tier retirado de la venta) se
  /// queda con todo lo demás pero sin IA.
  static const List<PremiumFeature> _aiFeatures = <PremiumFeature>[
    PremiumFeature.aiVisualEngine,
    PremiumFeature.aiVisualTraitFilters,
    PremiumFeature.visualReferenceSearch,
    PremiumFeature.aiVisualRanking,
    PremiumFeature.aiExplanations,
    PremiumFeature.aiDataControls,
  ];

  /// Features por defecto de cada tier.
  ///
  /// Antes eran tres listas literales independientes y DIVERGÍAN sin querer
  /// (era trivial añadir algo a Plus y olvidarse de Premium/Pro, que se supone
  /// que lo incluyen todo). Ahora se componen por `rank`, así que "Pro incluye
  /// todo lo de Plus" es una propiedad estructural, no una lista que mantener.
  ///
  /// `readReceipts` sale de TODOS los tiers a propósito: no está implementado
  /// en ninguna parte del código (grep: solo aparecía en estas listas), así que
  /// venderlo era publicidad engañosa. No se borra del enum porque hay docs de
  /// entitlements en base que pueden traerlo y romper el parseo sería peor;
  /// además, quien lo tuviera guardado no pierde nada real (no hacía nada).
  static List<PremiumFeature> defaultFeaturesForTier(SubscriptionTier tier) {
    if (tier == SubscriptionTier.free) {
      // Free no tiene features de pago. Su 1 Attra al mes NO va por aquí:
      // `hasFeature` corta en seco para Free, así que el grant se decide con
      // el flag `freeMonthlyAttras` y lo aplica el backend.
      return const <PremiumFeature>[];
    }
    final List<PremiumFeature> features = <PremiumFeature>[..._plusFeatures];
    if (tier.atLeast(SubscriptionTier.premium)) {
      features.addAll(_reachFeatures);
    }
    if (tier.atLeast(SubscriptionTier.pro)) {
      features.addAll(_aiFeatures);
    }
    return List<PremiumFeature>.unmodifiable(features);
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
