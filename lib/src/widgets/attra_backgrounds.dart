import 'package:flutter/material.dart';

import '../theme/attra_colors.dart';
import '../theme/app_spacing.dart';

/// Fondo tonal compartido. Conserva la API histórica de las pantallas.
class AttraGradientBackground extends StatelessWidget {
  const AttraGradientBackground({
    super.key,
    required this.child,
    this.colors,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });

  final Widget child;
  final List<Color>? colors;
  final Alignment begin;
  final Alignment end;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: context.colors.bg, child: child);
  }
}

/// Fondo continuo del shell. La fotografía aporta el color y la profundidad.
class AttraAppShellBackground extends StatelessWidget {
  const AttraAppShellBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  static Color contentColorOf(BuildContext context) => context.colors.bg;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: contentColorOf(context), child: child);
  }
}

/// Superficie tonal opaca; conserva la API histórica sin simular cristal.
class AttraGlassCard extends StatelessWidget {
  const AttraGlassCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.card,
    this.radius = AppSpacing.radiusLg,
    this.blur = 18,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final double blur;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget content = Padding(padding: padding, child: child);
    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius),
              child: content,
            ),
    );
  }
}

/// Superficie tonal. Solo dibuja un borde cuando expresa un estado explícito.
class AttraCard extends StatelessWidget {
  const AttraCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.card,
    this.radius = AppSpacing.radiusLg,
    this.onTap,
    this.gradient,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;
  final List<Color>? gradient;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final Widget content = Padding(padding: padding, child: child);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          color: gradient == null ? context.colors.surface : gradient!.first,
          borderRadius: BorderRadius.circular(radius),
          border: borderColor == null ? null : Border.all(color: borderColor!),
        ),
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(radius),
                child: content,
              ),
      ),
    );
  }
}
