import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/attra_colors.dart';
import '../theme/app_spacing.dart';

/// Fondo premium con degradado de marca (vino oscuro → carbón). Úsalo como base
/// de pantallas destacadas (splash, login, paywall, IA…).
class AttraGradientBackground extends StatelessWidget {
  const AttraGradientBackground({
    super.key,
    required this.child,
    this.colors = AppColors.brandBackground,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });

  final Widget child;
  final List<Color> colors;
  final Alignment begin;
  final Alignment end;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: begin, end: end, colors: colors),
      ),
      child: child,
    );
  }
}

/// Tarjeta con glassmorphism controlado (blur + velo translúcido + borde sutil).
/// Para overlays/cards sobre fondos con degradado.
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
    final Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: child,
        ),
      ),
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: card,
    );
  }
}

/// Tarjeta sólida grafito con borde y sombra elegante (premium, no exagerada).
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
    final Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? context.colors.surface : null,
        gradient: gradient == null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient!),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? context.colors.surfaceLine),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: content,
      ),
    );
  }
}
