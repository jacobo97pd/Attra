import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum AttraBadgeKind { plus, pro, attra }

/// Badge premium para Plus / Pro / Attra. Pequeño, elegante, con degradado.
class AttraPremiumBadge extends StatelessWidget {
  const AttraPremiumBadge(this.kind, {super.key, this.compact = false});

  final AttraBadgeKind kind;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (String label, List<Color> grad, IconData icon) = switch (kind) {
      AttraBadgeKind.plus => (
          'PLUS',
          <Color>[AppColors.attraRedDeep, AppColors.attraRed],
          Icons.workspace_premium,
        ),
      AttraBadgeKind.pro => (
          'PRO',
          AppColors.pro,
          Icons.auto_awesome,
        ),
      AttraBadgeKind.attra => (
          'ATTRA',
          <Color>[AppColors.wine, AppColors.attraRed, AppColors.gold],
          Icons.star,
        ),
    };
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8, vertical: compact ? 2 : 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: grad),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: compact ? 10 : 12, color: Colors.white),
          SizedBox(width: compact ? 3 : 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 9 : 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastilla redonda con el icono/saldo de Attra (moneda premium propia).
class AttraCoin extends StatelessWidget {
  const AttraCoin({super.key, required this.balance, this.onTap});

  final int balance;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: <Color>[AppColors.wine, AppColors.attraRedDeep]),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.star, size: 15, color: AppColors.gold),
              const SizedBox(width: 6),
              Text('$balance',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}
