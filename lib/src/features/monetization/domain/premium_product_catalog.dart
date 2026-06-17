import 'subscription_tier.dart';

enum PremiumProductType { attraPack, subscription }

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
  });

  final String id;
  final PremiumProductType type;
  final String title;
  final String description;
  final SubscriptionTier? tier;
  final BillingPeriod billingPeriod;
  final int attraAmount;

  bool get isSubscription => type == PremiumProductType.subscription;
  bool get isAttraPack => type == PremiumProductType.attraPack;
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
    ),
    PremiumProductDefinition(
      id: 'attra_pack_25',
      type: PremiumProductType.attraPack,
      title: '25 Attras',
      description: 'Mas margen para destacar sin esperar al siguiente grant.',
      attraAmount: 25,
    ),
    PremiumProductDefinition(
      id: 'attra_pack_50',
      type: PremiumProductType.attraPack,
      title: '50 Attras',
      description: 'Pack grande para usuarios frecuentes.',
      attraAmount: 50,
    ),
    PremiumProductDefinition(
      id: 'attra_plus_monthly',
      type: PremiumProductType.subscription,
      title: 'Attra Plus mensual',
      description: 'Mas control y Attras mensuales sin IA visual avanzada.',
      tier: SubscriptionTier.plus,
      billingPeriod: BillingPeriod.monthly,
    ),
    PremiumProductDefinition(
      id: 'attra_plus_yearly',
      type: PremiumProductType.subscription,
      title: 'Attra Plus anual',
      description: 'Plus durante un ano con mejor precio efectivo.',
      tier: SubscriptionTier.plus,
      billingPeriod: BillingPeriod.yearly,
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
    ),
    PremiumProductDefinition(
      id: 'attra_pro_lifetime',
      type: PremiumProductType.subscription,
      title: 'Attra Pro IA lifetime',
      description: 'Acceso Pro IA sin renovacion. Sujeto al modelo comercial.',
      tier: SubscriptionTier.pro,
      billingPeriod: BillingPeriod.lifetime,
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
}
