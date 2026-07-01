import 'subscription_tier.dart';

enum PremiumProductType { attraPack, boostPack, swipePack, subscription }

enum BillingPeriod { none, monthly, yearly, lifetime }

class PremiumProductDefinition {
  const PremiumProductDefinition({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    this.tier,
    this.billingPeriod = BillingPeriod.none,
    this.attraAmount = 0,
    this.consumableKind,
    this.consumableAmount = 0,
    this.badge,
  });

  final String id;
  final PremiumProductType type;
  final String title;
  final String description;
  final SubscriptionTier? tier;
  final BillingPeriod billingPeriod;
  final int attraAmount;

  /// Etiqueta comercial opcional ("Más comprado", "Ahorro", "Mejor precio"…).
  /// La fija el catálogo para resaltar packs; la UI solo la pinta.
  final String? badge;

  /// Para boosts/swipes: el `kind` que espera el backend (`grantConsumable`)
  /// y cuántas unidades concede esta compra. Única fuente de verdad de las
  /// cantidades (la UI ya no las escribe a mano).
  final String? consumableKind;
  final int consumableAmount;

  bool get isSubscription => type == PremiumProductType.subscription;
  bool get isAttraPack => type == PremiumProductType.attraPack;
  bool get isBoostPack => type == PremiumProductType.boostPack;
  bool get isSwipePack => type == PremiumProductType.swipePack;
}

class PremiumProductCatalog {
  const PremiumProductCatalog._();

  static const List<PremiumProductDefinition> products =
      <PremiumProductDefinition>[
    PremiumProductDefinition(
      id: 'attra_pack_3',
      type: PremiumProductType.attraPack,
      title: '3 Attras',
      description: 'Destaca tres likes con una senal especial.',
      attraAmount: 3,
    ),
    PremiumProductDefinition(
      id: 'attra_pack_10',
      type: PremiumProductType.attraPack,
      title: '10 Attras',
      description: 'Pack equilibrado para destacar intereses clave.',
      attraAmount: 10,
      badge: 'Más comprado',
    ),
    PremiumProductDefinition(
      id: 'attra_pack_50',
      type: PremiumProductType.attraPack,
      title: '50 Attras',
      description: 'Pack grande para usuarios frecuentes.',
      attraAmount: 50,
      badge: 'Mejor precio',
    ),
    // ── Consumibles: Boosts y Swipes ───────────────────────────────────────
    PremiumProductDefinition(
      id: 'attra_boost_1',
      type: PremiumProductType.boostPack,
      title: '1 Boost',
      description: 'Sube al frente del feed un rato.',
      consumableKind: 'boost',
      consumableAmount: 1,
    ),
    PremiumProductDefinition(
      id: 'attra_boost_5',
      type: PremiumProductType.boostPack,
      title: '5 Boosts',
      description: 'Pack ahorro de Boosts.',
      consumableKind: 'boost',
      consumableAmount: 5,
      badge: 'Ahorro',
    ),
    PremiumProductDefinition(
      id: 'attra_swipes_25',
      type: PremiumProductType.swipePack,
      title: '25 Attra Swipes',
      description: 'Likes extra cuando se acaban los del día.',
      consumableKind: 'swipe',
      consumableAmount: 25,
      badge: 'Más comprado',
    ),
    PremiumProductDefinition(
      id: 'attra_plus_monthly',
      type: PremiumProductType.subscription,
      title: 'Attra Plus mensual',
      description: 'Mas control y Attras mensuales sin IA visual avanzada.',
      tier: SubscriptionTier.plus,
      billingPeriod: BillingPeriod.monthly,
      badge: 'Más popular',
    ),
    PremiumProductDefinition(
      id: 'attra_plus_yearly',
      type: PremiumProductType.subscription,
      title: 'Attra Plus anual',
      description: 'Plus durante un ano con mejor precio efectivo.',
      tier: SubscriptionTier.plus,
      billingPeriod: BillingPeriod.yearly,
      badge: 'Ahorro',
    ),
    PremiumProductDefinition(
      id: 'attra_premium_monthly',
      type: PremiumProductType.subscription,
      title: 'Attra Premium mensual',
      description: 'Likes recibidos, prioridad moderada y filtros avanzados.',
      tier: SubscriptionTier.premium,
      billingPeriod: BillingPeriod.monthly,
    ),
    PremiumProductDefinition(
      id: 'attra_premium_yearly',
      type: PremiumProductType.subscription,
      title: 'Attra Premium anual',
      description: 'Premium durante un ano con mejor precio efectivo.',
      tier: SubscriptionTier.premium,
      billingPeriod: BillingPeriod.yearly,
      badge: 'Ahorro',
    ),
    PremiumProductDefinition(
      id: 'attra_pro_monthly',
      type: PremiumProductType.subscription,
      title: 'Attra Pro IA mensual',
      description: 'Premium mas IA visual consentida y explicable.',
      tier: SubscriptionTier.pro,
      billingPeriod: BillingPeriod.monthly,
    ),
    PremiumProductDefinition(
      id: 'attra_pro_yearly',
      type: PremiumProductType.subscription,
      title: 'Attra Pro IA anual',
      description: 'Pro IA durante un ano con mejor precio efectivo.',
      tier: SubscriptionTier.pro,
      billingPeriod: BillingPeriod.yearly,
      badge: 'Ahorro',
    ),
  ];

  static PremiumProductDefinition? byId(String id) {
    for (final PremiumProductDefinition product in products) {
      if (product.id == id) {
        return product;
      }
    }
    return null;
  }

  static List<PremiumProductDefinition> productsForTier(
    SubscriptionTier tier,
  ) {
    return products
        .where((PremiumProductDefinition product) => product.tier == tier)
        .toList(growable: false);
  }

  static List<PremiumProductDefinition> get attraPacks => products
      .where((PremiumProductDefinition product) => product.isAttraPack)
      .toList(growable: false);

  static List<PremiumProductDefinition> get boostPacks => products
      .where((PremiumProductDefinition product) => product.isBoostPack)
      .toList(growable: false);

  static List<PremiumProductDefinition> get swipePacks => products
      .where((PremiumProductDefinition product) => product.isSwipePack)
      .toList(growable: false);
}
