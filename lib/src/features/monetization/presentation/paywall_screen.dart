import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_backgrounds.dart';
import '../../../widgets/attra_badges.dart';
import '../../../widgets/attra_buttons.dart';
import '../../../widgets/legal_links_row.dart';
import '../data/iap_service.dart';
import '../domain/price_format.dart';
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
    this.iapService,
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

  /// Servicio de compras COMPARTIDO por toda la sesión (lo inyecta home_shell
  /// desde PurchaseDeliveryRouter). Se inyecta en lugar de crear uno propio
  /// para que exista UNA sola suscripción a `purchaseStream`: la que vive
  /// mientras dura la sesión y entrega también las compras que se resuelven con
  /// esta pantalla ya cerrada. Si es null, la pantalla se comporta como un
  /// escaparate sin compras (útil en tests).
  final IapService? iapService;

  /// Verificación server-side. Solo se usa cuando NO hay [iapService]; el
  /// enrutador de sesión ya sabe a qué backend va cada producto.
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

  /// True si el servicio lo creó esta pantalla (y por tanto le toca cerrarlo).
  bool _ownsIap = false;

  /// Callbacks que tuviera el servicio COMPARTIDO antes de que esta pantalla se
  /// enganchase. Se restauran al salir: un callback de una pantalla ya destruida
  /// que sobrevive el resto de la sesión dispara snackbars y `Navigator` sobre un
  /// contexto muerto.
  void Function(PurchaseDetails purchase)? _previousOnDelivered;
  void Function(int restored)? _previousOnRestoreFinished;

  /// Handler propio guardado en un campo: así en dispose se comprueba que sigue
  /// siendo el nuestro antes de desinstalarlo (y no se pisa el de otra pantalla).
  late final void Function(PurchaseDetails purchase) _deliveredHandler =
      _onDelivered;

  /// Restaurar en curso: el aviso de "compras restauradas" lo da
  /// [onRestoreFinished], así que no se cierra la pantalla hasta entonces.
  bool _restoring = false;
  bool _closeAfterRestore = false;

  @override
  void initState() {
    super.initState();
    final IapService? shared = widget.iapService;
    if (shared != null) {
      _iap = shared..addListener(_onIap);
      // El servicio compartido ya entrega la compra, pero nadie refrescaba ni
      // cerraba ESTA pantalla al conseguirlo: el usuario pagaba, el backend
      // concedía el plan y el paywall se quedaba exactamente igual, como si la
      // compra no hubiera ocurrido.
      _previousOnDelivered = _iap.onDelivered;
      _previousOnRestoreFinished = _iap.onRestoreFinished;
      _iap.onDelivered = _deliveredHandler;
      _iap.clearError();
      return;
    }
    // Camino heredado: sin enrutador de sesión, la pantalla se apaña sola.
    _ownsIap = true;
    _iap = IapService()
      ..deliver = _deliver
      ..onDelivered = _deliveredHandler
      ..addListener(_onIap);
    if (widget.verifySubscription != null) {
      _iap.init(productIds: _ids);
    }
  }

  @override
  void dispose() {
    _iap.removeListener(_onIap);
    if (identical(_iap.onDelivered, _deliveredHandler)) {
      _iap.onDelivered = _previousOnDelivered;
    }
    // El callback de restaurar se instalaba sobre el servicio de SESIÓN y no se
    // retiraba nunca: seguía vivo (con el contexto de esta pantalla) durante el
    // resto de la sesión.
    _iap.onRestoreFinished = _previousOnRestoreFinished;
    // El servicio compartido sobrevive a esta pantalla: cerrarlo aquí volvería a
    // dejar las compras diferidas sin quien las entregue.
    if (_ownsIap) _iap.dispose();
    super.dispose();
  }

  /// Se llama cuando el backend ha CONCEDIDO una compra entregada.
  void _onDelivered(PurchaseDetails purchase) {
    // Refrescar entitlements siempre: aunque lo comprado no sea de esta pantalla.
    widget.onPurchased?.call();
    if (!mounted) return;
    // El servicio es compartido: por él también pasan los packs de consumibles
    // (Boosts/Swipes). Solo cerramos con una suscripción de este paywall.
    if (!_ids.contains(purchase.productID)) return;
    if (_restoring) {
      // Con un restaurar en curso, cerrar ahora se comería el mensaje que
      // explica cuántas compras se recuperaron.
      _closeAfterRestore = true;
      return;
    }
    _confirmAndClose('¡Listo! Tu plan ya está activo.');
  }

  void _confirmAndClose(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).maybePop();
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

  bool get _canPurchase =>
      widget.iapService != null || widget.verifySubscription != null;

  /// Restaurar con RESPUESTA. Antes el botón no decía nada: ni cuando restauraba
  /// ni cuando no había nada que restaurar, así que parecía roto. Apple exige
  /// que el restaurar sea funcional y verificable.
  Future<void> _restore() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    _restoring = true;
    _closeAfterRestore = false;
    _iap.onRestoreFinished = (int restored) {
      _restoring = false;
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(
          restored > 0
              ? 'Compras restauradas: $restored.'
              : 'No hay compras anteriores que restaurar con esta cuenta.',
        ),
      ));
      widget.onPurchased?.call();
      // Si el plan se ha concedido durante el restaurar, la pantalla ya no tiene
      // nada que ofrecer: se cierra DESPUÉS de dar el aviso.
      if (_closeAfterRestore) {
        _closeAfterRestore = false;
        Navigator.of(context).maybePop();
      }
    };
    await _iap.restore();
    // Si el flujo terminó sin pasar por el callback (no disponible, otro
    // restaurar en curso), no dejamos la pantalla marcada como "restaurando".
    _restoring = false;
  }

  Future<void> _buyPlan({
    required ProductDetails? offer,
    required String fallbackProductId,
  }) async {
    if (_busy) return;
    if (!_canPurchase) {
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
    // También en el servicio de sesión: si esta pantalla se cierra antes de que
    // la tienda resuelva, es el enrutador quien entrega la compra y necesita
    // saber si el usuario eligió mensual o anual.
    _iap.notePendingPeriod(offer.id, _period);
    final bool started = await _iap.buyProduct(offer);
    if (!started) {
      _pendingPeriodsByProductId.remove(offer.id);
    }
  }

  /// Precio REAL de la tienda. Devuelve null si aún no se conoce.
  ///
  /// Nunca se inventa un precio: mostrar uno hardcodeado que no coincide con el
  /// del escaparate del usuario (los precios cambian por país y por moneda) es
  /// justo lo que penaliza la Guideline 3.1.2(c).
  String? _priceFor(ProductDetails? offer) {
    if (offer == null) return null;
    return _yearly ? '${offer.price} / año' : '${offer.price} / mes';
  }

  /// Guideline 3.1.2(c): duración de la suscripción, visible en cada plan.
  String get _lengthLabel => _yearly
      ? 'Suscripción de 1 año · se renueva automáticamente cada año'
      : 'Suscripción de 1 mes · se renueva automáticamente cada mes';

  /// Precio por unidad (por mes) del plan anual, con el MISMO formato que el
  /// precio de la tienda. Ver price_format.dart.
  String? _unitPriceFor(ProductDetails? offer) {
    if (!_yearly || offer == null) return null;
    final String? monthly = monthlyEquivalentOf(offer.price, offer.rawPrice);
    return monthly == null ? null : 'Equivale a $monthly / mes';
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
                    if (_canPurchase)
                      TextButton(
                          onPressed: _busy ? null : _restore,
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
                      'Más visibilidad, control de tu perfil y búsqueda con IA '
                      'visual.',
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
                      price: _priceFor(plusOffer),
                      lengthLabel: _lengthLabel,
                      unitPrice: _unitPriceFor(plusOffer),
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
                      // Un usuario Pro tiene Plus incluido, pero su plan
                      // actual NO es Plus: decirlo confunde y sugiere una
                      // bajada de plan que aquí no existe.
                      ctaLabel: currentTier == SubscriptionTier.plus
                          ? 'Plan actual'
                          : currentTier.atLeast(SubscriptionTier.plus)
                              ? 'Incluido en tu plan'
                              : 'Hazte Plus',
                      // Sin precio de la tienda no se puede comprar: dejar el
                      // botón activo solo lleva a un error (Guideline 3.1.2(c)).
                      onTap: (currentTier.atLeast(SubscriptionTier.plus) ||
                              _busy ||
                              plusOffer == null)
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
                      price: _priceFor(proOffer),
                      lengthLabel: _lengthLabel,
                      unitPrice: _unitPriceFor(proOffer),
                      tagline: 'Todo Plus + búsqueda con IA visual',
                      highlightLabel: 'IA visual',
                      // Solo se promete lo que existe de verdad en la app. Se
                      // quitaron "Recomendaciones inteligentes" (el orden del
                      // feed es el mismo para todos los planes) y "Filtros por
                      // preferencias visuales" (no hay ninguna pantalla que los
                      // ofrezca): vender funciones inexistentes es motivo de
                      // rechazo en la App Store y de reclamación del usuario.
                      features: const <String>[
                        'Todo lo de Plus, incluido',
                        'IA visual: perfiles parecidos a tu foto de referencia',
                        'Búsqueda por descripción: escribe cómo es tu tipo',
                        'Sugerencias para mejorar tus fotos y tu bio',
                        'Tus likes se muestran los primeros',
                        // El % que ve Pro sale de los intereses en común (o de la
                        // señal de afinidad del backend), no de la IA visual:
                        // decir "IA" aquí prometía algo que no calcula ninguna IA.
                        '% de afinidad por intereses en los likes que recibes',
                      ],
                      gradient: AppColors.pro,
                      owned: currentTier == SubscriptionTier.pro,
                      ctaLabel: currentTier == SubscriptionTier.pro
                          ? 'Plan actual'
                          : 'Hazte Pro',
                      onTap: (currentTier == SubscriptionTier.pro ||
                              _busy ||
                              proOffer == null)
                          ? null
                          : () => _buyPlan(
                                offer: proOffer,
                                fallbackProductId: _yearly
                                    ? widget.proYearlyProductId
                                    : widget.proMonthlyProductId,
                              ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // Guideline 3.1.2(c): condiciones de la renovación
                    // automática + enlaces FUNCIONALES al EULA y a la política
                    // de privacidad, dentro del propio flujo de compra.
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: context.colors.surfaceHigh,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusLg),
                        border: Border.all(color: context.colors.surfaceLine),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('Condiciones de la suscripción',
                              style: theme.textTheme.titleSmall),
                          const SizedBox(height: 6),
                          Text(
                            'Attra Plus y Attra Pro son suscripciones de '
                            'renovación automática (1 mes o 1 año según el '
                            'plan elegido). El pago se carga en tu cuenta de '
                            'App Store o Google Play al confirmar la compra. '
                            'La suscripción se renueva automáticamente por el '
                            'mismo periodo salvo que la canceles al '
                            'menos 24 horas antes del final del periodo en '
                            'curso; el importe de la renovación se cobra en '
                            'las 24 horas previas. Puedes gestionarla o '
                            'cancelarla desde los ajustes de tu cuenta de la '
                            'tienda. Eliminar la app no cancela la '
                            'suscripción. Los Attras son un consumible aparte '
                            'y no dependen de la suscripción. El precio final '
                            'e impuestos se muestran en la pantalla de pago '
                            'de la tienda.',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          const AttraLegalLinksRow(
                            alignment: WrapAlignment.start,
                          ),
                        ],
                      ),
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
    required this.lengthLabel,
    required this.tagline,
    required this.features,
    required this.gradient,
    required this.ctaLabel,
    required this.owned,
    this.unitPrice,
    this.highlightLabel,
    this.onTap,
  });

  final AttraBadgeKind kind;
  final String title;

  /// Precio REAL de la tienda. Null mientras no se conozca: nunca se sustituye
  /// por uno inventado (Guideline 3.1.2(c)).
  final String? price;

  /// Guideline 3.1.2(c): duración de la suscripción de renovación automática.
  final String lengthLabel;

  /// Precio por unidad (por mes) cuando el plan es anual.
  final String? unitPrice;
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
          // Sin datos de la tienda no se muestra importe alguno.
          Text(price ?? 'Precio no disponible ahora mismo',
              style: theme.textTheme.titleLarge?.copyWith(
                  color: price == null
                      ? context.colors.textSecondary
                      : context.colors.textPrimary,
                  fontSize: price == null ? 15 : null,
                  fontWeight:
                      price == null ? FontWeight.w600 : FontWeight.w800)),
          if (unitPrice != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(unitPrice!, style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 4),
          Text(lengthLabel, style: theme.textTheme.bodySmall),
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
