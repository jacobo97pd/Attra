import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_backgrounds.dart';
import '../../../widgets/attra_badges.dart';
import '../../../widgets/attra_buttons.dart';
import '../data/iap_service.dart';
import '../domain/subscription_tier.dart';

/// Verifica una suscripción comprada por IAP en el backend. Devuelve true si se
/// concedió el plan.
typedef VerifySubscription = Future<bool> Function({
  required String productId,
  required String platform,
  required String verificationData,
  String? purchaseId,
  String? period,
});

/// Paywall premium: compara Free / Attra Plus / Attra Pro con cards de producto.
/// La compra abre la pasarela NATIVA (Google Play / App Store) y la concesión es
/// SIEMPRE backend (verifyPurchase); el cliente nunca concede tier ni saldo.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({
    super.key,
    required this.currentTier,
    this.verifySubscription,
    this.onPurchased,
    this.plusProductId = 'attra_plus',
    this.proProductId = 'attra_pro',
    this.plusMonthlyProductId = 'attra_plus_monthly',
    this.plusYearlyProductId = 'attra_plus_yearly',
    this.proMonthlyProductId = 'attra_pro_monthly',
    this.proYearlyProductId = 'attra_pro_yearly',
  });

  final SubscriptionTier currentTier;

  /// Verificación server-side (la inyecta home_shell con BoostService).
  final VerifySubscription? verifySubscription;

  /// Se llama tras conceder el plan (para refrescar entitlements).
  final VoidCallback? onPurchased;

  final String plusProductId;
  final String proProductId;
  final String plusMonthlyProductId;
  final String plusYearlyProductId;
  final String proMonthlyProductId;
  final String proYearlyProductId;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  late final IapService _iap;
  bool _busy = false;
  // Periodo elegido (planes básicos de Play): false = mensual, true = anual.
  bool _yearly = false;
  final Map<String, String> _pendingPeriodsByProductId = <String, String>{};

  Set<String> get _ids => <String>{
        widget.plusProductId,
        widget.plusMonthlyProductId,
        widget.plusYearlyProductId,
        widget.proProductId,
        widget.proMonthlyProductId,
        widget.proYearlyProductId,
      };

  String get _period => _yearly ? 'yearly' : 'monthly';

  /// Oferta según el periodo:
  /// - iOS/App Store suele usar IDs separados por periodo.
  /// - Android/Play puede devolver varios planes básicos bajo el mismo ID.
  ProductDetails? _offerFor({
    required String baseProductId,
    required String monthlyProductId,
    required String yearlyProductId,
  }) {
    final String periodProductId = _yearly ? yearlyProductId : monthlyProductId;
    final ProductDetails? periodProduct = _iap.productById(periodProductId);
    if (periodProduct != null) return periodProduct;

    final List<ProductDetails> offers = _iap.offersFor(baseProductId);
    if (offers.isEmpty) return null;
    if (offers.length == 1) return _yearly ? null : offers.first;
    return _yearly ? offers.last : offers.first;
  }

  ProductDetails? _plusOffer() => _offerFor(
        baseProductId: widget.plusProductId,
        monthlyProductId: widget.plusMonthlyProductId,
        yearlyProductId: widget.plusYearlyProductId,
      );

  ProductDetails? _proOffer() => _offerFor(
        baseProductId: widget.proProductId,
        monthlyProductId: widget.proMonthlyProductId,
        yearlyProductId: widget.proYearlyProductId,
      );

  @override
  void initState() {
    super.initState();
    _iap = IapService()
      ..deliver = _deliver
      ..onDelivered = (_) {
        widget.onPurchased?.call();
        if (mounted) Navigator.of(context).maybePop();
      }
      ..addListener(_onIap);
    if (widget.verifySubscription != null) {
      _iap.init(productIds: _ids);
    }
  }

  @override
  void dispose() {
    _iap.removeListener(_onIap);
    _iap.dispose();
    super.dispose();
  }

  void _onIap() {
    if (!mounted) return;
    setState(() => _busy = _iap.isBusy);
    final String? err = _iap.error;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  String? _platform() {
    if (kIsWeb) return null;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'app_store';
      case TargetPlatform.android:
        return 'play_store';
      default:
        return null;
    }
  }

  Future<IapDeliveryResult> _deliver(PurchaseDetails purchase) async {
    final VerifySubscription? verify = widget.verifySubscription;
    final String? platform = _platform();
    if (verify == null || platform == null) {
      return const IapDeliveryResult(
          delivered: false, message: 'Verificación no disponible.');
    }
    final bool ok = await verify(
      productId: purchase.productID,
      platform: platform,
      verificationData: purchase.verificationData.serverVerificationData,
      purchaseId: purchase.purchaseID,
      period: _periodForPurchase(purchase.productID),
    );
    if (ok) {
      _pendingPeriodsByProductId.remove(purchase.productID);
    }
    return IapDeliveryResult(
      delivered: ok,
      message: ok ? null : 'No se pudo verificar la compra.',
    );
  }

  String _periodForPurchase(String productId) {
    if (productId.endsWith('_yearly')) return 'yearly';
    if (productId.endsWith('_monthly')) return 'monthly';
    return _pendingPeriodsByProductId[productId] ?? _period;
  }

  Future<void> _buyPlan({
    required ProductDetails? offer,
    required String fallbackProductId,
  }) async {
    if (_busy) return;
    if (widget.verifySubscription == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compras disponibles próximamente.')));
      return;
    }
    if (offer == null) {
      await _iap
          .buy(fallbackProductId); // deja que IapService informe del error
      return;
    }
    _pendingPeriodsByProductId[offer.id] = _period;
    final bool started = await _iap.buyProduct(offer);
    if (!started) {
      _pendingPeriodsByProductId.remove(offer.id);
    }
  }

  String _priceFor({
    required ProductDetails? offer,
    required String monthlyFallback,
    required String yearlyFallback,
  }) {
    if (offer == null) return _yearly ? yearlyFallback : monthlyFallback;
    return _yearly ? '${offer.price} / año' : '${offer.price} / mes';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SubscriptionTier currentTier = widget.currentTier;
    final ProductDetails? plusOffer = _plusOffer();
    final ProductDetails? proOffer = _proOffer();
    return Scaffold(
      body: AttraGradientBackground(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, 0),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const Spacer(),
                    if (widget.verifySubscription != null)
                      TextButton(
                          onPressed: _busy ? null : () => _iap.restore(),
                          child: const Text('Restaurar')),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
                  children: <Widget>[
                    Text('Desbloquea Attra',
                        style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 6),
                    Text(
                      'Más visibilidad, control total y la IA visual más avanzada.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: context.colors.surfaceHigh,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusPill),
                          border: Border.all(color: context.colors.surfaceLine),
                        ),
                        child: Text('Tu plan: ${currentTier.label}',
                            style: theme.textTheme.labelLarge),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // Selector mensual / anual (planes básicos de Play).
                    _PeriodToggle(
                      yearly: _yearly,
                      onChanged: (bool v) => setState(() => _yearly = v),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _PlanCard(
                      kind: AttraBadgeKind.plus,
                      title: 'Attra Plus',
                      price: _priceFor(
                        offer: plusOffer,
                        monthlyFallback: '9,99 € / mes',
                        yearlyFallback: '99,99 € / año',
                      ),
                      tagline: 'Ventajas sociales y más alcance',
                      highlightLabel: 'Más popular',
                      features: const <String>[
                        'Ve a todas las personas que te dan like',
                        'Comenta fotos al dar like',
                        'Filtros avanzados',
                        'Modo incógnito',
                        'Sin anuncios',
                        'Pack mensual de Attras',
                      ],
                      // Plus = negro → champagne (acceso prioritario premium).
                      gradient: AppColors.plus,
                      owned: currentTier.atLeast(SubscriptionTier.plus),
                      ctaLabel: currentTier.atLeast(SubscriptionTier.plus)
                          ? 'Plan actual'
                          : 'Hazte Plus',
                      onTap:
                          (currentTier.atLeast(SubscriptionTier.plus) || _busy)
                              ? null
                              : () => _buyPlan(
                                    offer: plusOffer,
                                    fallbackProductId: _yearly
                                        ? widget.plusYearlyProductId
                                        : widget.plusMonthlyProductId,
                                  ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _PlanCard(
                      kind: AttraBadgeKind.pro,
                      title: 'Attra Pro',
                      price: _priceFor(
                        offer: proOffer,
                        monthlyFallback: '19,99 € / mes',
                        yearlyFallback: '199,99 € / año',
                      ),
                      tagline: 'Todo Plus + IA visual flagship',
                      highlightLabel: 'IA avanzada',
                      features: const <String>[
                        'Todo lo de Plus, incluido',
                        'IA visual: encuentra parecidos a tu referencia',
                        'Recomendaciones inteligentes',
                        'Likes prioritarios y boost',
                        'Insights para mejorar tu perfil',
                        'Filtros por preferencias visuales',
                      ],
                      gradient: AppColors.pro,
                      owned: currentTier == SubscriptionTier.pro,
                      ctaLabel: currentTier == SubscriptionTier.pro
                          ? 'Plan actual'
                          : 'Hazte Pro',
                      onTap: (currentTier == SubscriptionTier.pro || _busy)
                          ? null
                          : () => _buyPlan(
                                offer: proOffer,
                                fallbackProductId: _yearly
                                    ? widget.proYearlyProductId
                                    : widget.proMonthlyProductId,
                              ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'La compra se verifica en el servidor. Los Attras son un '
                      'consumible aparte y no dependen de la suscripción. '
                      'Cancela cuando quieras.',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Conmutador Mensual / Anual (planes básicos de la suscripción).
class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({required this.yearly, required this.onChanged});

  final bool yearly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: context.colors.surfaceLine),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
              child: _segment(
                  context, 'Mensual', !yearly, () => onChanged(false))),
          Expanded(
              child: _segment(
                  context, 'Anual · ahorra', yearly, () => onChanged(true))),
        ],
      ),
    );
  }

  Widget _segment(
      BuildContext context, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient:
              active ? const LinearGradient(colors: AppColors.action) : null,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : context.colors.textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.kind,
    required this.title,
    required this.price,
    required this.tagline,
    required this.features,
    required this.gradient,
    required this.ctaLabel,
    required this.owned,
    this.highlightLabel,
    this.onTap,
  });

  final AttraBadgeKind kind;
  final String title;
  final String price;
  final String tagline;
  final List<String> features;
  final List<Color> gradient;
  final String ctaLabel;
  final bool owned;
  final String? highlightLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Plus usa champagne (claro) => texto oscuro sobre sus acentos para que se lea.
    final bool onLight = kind == AttraBadgeKind.plus;
    final Color accentText =
        onLight ? context.colors.bg : context.colors.textPrimary;
    return AttraCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      borderColor: gradient.last.withValues(alpha: 0.55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AttraPremiumBadge(kind),
              const Spacer(),
              if (highlightLabel != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: gradient),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Text(highlightLabel!,
                      style: TextStyle(
                          color: accentText,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(tagline, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(price,
              style: theme.textTheme.titleLarge?.copyWith(
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.md),
          ...features.map((String f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.check_circle, size: 18, color: gradient.last),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(f, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              )),
          const SizedBox(height: AppSpacing.lg),
          owned
              ? AttraGhostButton(label: ctaLabel, onPressed: null)
              : AttraPrimaryButton(
                  label: ctaLabel,
                  onPressed: onTap,
                  gradient: gradient,
                  foregroundColor: onLight ? context.colors.bg : null,
                ),
        ],
      ),
    );
  }
}
