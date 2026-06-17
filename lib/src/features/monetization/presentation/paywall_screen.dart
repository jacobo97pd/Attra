import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_backgrounds.dart';
import '../../../widgets/attra_badges.dart';
import '../../../widgets/attra_buttons.dart';
import '../domain/subscription_tier.dart';

/// Paywall premium: compara Free / Attra Plus / Attra Pro con cards de producto,
/// degradados, badges y CTA destacados. La verificación de compra y la concesión
/// del plan son SIEMPRE backend; el cliente nunca concede tier ni saldo.
class PaywallScreen extends StatelessWidget {
  const PaywallScreen({
    super.key,
    required this.currentTier,
    this.onBuyPlus,
    this.onBuyPro,
    this.onRestore,
  });

  final SubscriptionTier currentTier;
  final VoidCallback? onBuyPlus;
  final VoidCallback? onBuyPro;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
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
                    if (onRestore != null)
                      TextButton(
                          onPressed: onRestore,
                          child: const Text('Restaurar')),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0,
                      AppSpacing.lg, AppSpacing.xl),
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
                          color: AppColors.surfaceHigh,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusPill),
                          border: Border.all(color: AppColors.surfaceLine),
                        ),
                        child: Text('Tu plan: ${currentTier.label}',
                            style: theme.textTheme.labelLarge),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _PlanCard(
                      kind: AttraBadgeKind.plus,
                      title: 'Attra Plus',
                      price: '9,99 € / mes',
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
                      onTap: currentTier.atLeast(SubscriptionTier.plus)
                          ? null
                          : onBuyPlus,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _PlanCard(
                      kind: AttraBadgeKind.pro,
                      title: 'Attra Pro',
                      price: '19,99 € / mes',
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
                      onTap: currentTier == SubscriptionTier.pro
                          ? null
                          : onBuyPro,
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
    final Color accentText = onLight ? AppColors.black : AppColors.textPrimary;
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
                  color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.md),
          ...features.map((String f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.check_circle,
                        size: 18, color: gradient.last),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                        child: Text(f, style: theme.textTheme.bodyMedium)),
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
                  foregroundColor: onLight ? AppColors.black : null,
                ),
        ],
      ),
    );
  }
}
