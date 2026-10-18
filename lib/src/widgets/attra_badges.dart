import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/attra_colors.dart';

/// A readable, tonal label. Champagne is reserved for a meaningful distinction.
class AttraLabel extends StatelessWidget {
  const AttraLabel(
      {super.key,
      required this.label,
      this.icon,
      this.champagne = false,
      this.compact = false});
  final String label;
  final IconData? icon;
  final bool champagne;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color foreground =
        champagne ? AppColors.brandInk : context.colors.textPrimary;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12, vertical: compact ? 4 : 6),
      decoration: BoxDecoration(
        color: champagne ? AppColors.gold : context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 6),
        ],
        Flexible(
            child: Text(label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foreground, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

enum AttraBadgeKind { plus, pro, attra }

/// Membresía o tipo de interés; el distintivo no concede ningún derecho.
class AttraPremiumBadge extends StatelessWidget {
  const AttraPremiumBadge(this.kind, {super.key, this.compact = false});

  final AttraBadgeKind kind;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (String label, IconData icon) = switch (kind) {
      AttraBadgeKind.plus => (
          'PLUS',
          Icons.workspace_premium,
        ),
      AttraBadgeKind.pro => (
          'PRO',
          Icons.auto_awesome,
        ),
      AttraBadgeKind.attra => (
          'ATTRA',
          Icons.star,
        ),
    };
    return AttraLabel(
        label: label,
        icon: icon,
        champagne: kind == AttraBadgeKind.attra,
        compact: compact);
  }
}

/// Pastilla redonda con el icono/saldo de Attra (moneda premium propia).
class AttraCoin extends StatelessWidget {
  const AttraCoin({super.key, required this.balance, this.onTap});

  final int balance;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Attras disponibles: $balance',
      button: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
          color: context.colors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            excludeFromSemantics: true,
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              constraints: BoxConstraints(
                  minHeight: onTap == null ? 0 : AppSpacing.touchTarget),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.star, size: 15, color: AppColors.gold),
                  const SizedBox(width: 6),
                  Flexible(
                      child: Text('$balance',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: context.colors.textPrimary))),
                ],
              ),
            ),
          )),
    );
  }
}
