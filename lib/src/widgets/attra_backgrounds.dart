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
    final List<Color> resolvedColors = colors ??
        <Color>[
          context.colors.bg,
          Color.lerp(
            context.colors.bg,
            context.colors.accentDeep,
            Theme.of(context).brightness == Brightness.dark ? 0.10 : 0.05,
          )!,
          context.colors.bg,
        ];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient:
            LinearGradient(begin: begin, end: end, colors: resolvedColors),
      ),
      child: child,
    );
  }
}

/// Fondo del shell principal: conserva la tinta de marca en la cabecera y
/// transiciona enseguida a blanco para que el contenido respire sobre una base
/// predominantemente clara.
///
/// Los cortes se calculan en píxeles lógicos para que el tramo oscuro termine
/// bajo el wordmark de la AppBar tanto en móviles compactos como altos.
class AttraAppShellBackground extends StatelessWidget {
  const AttraAppShellBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  static const Color _headerInk = AppColors.black;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color contentColor = isDark ? context.colors.bg : Colors.white;
    final double topInset = MediaQuery.paddingOf(context).top;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        final double safeHeight = height <= 0 ? 1 : height;

        // La tinta se mantiene hasta el borde inferior del logo (28 px) y el
        // fundido termina poco después de la AppBar. El resto queda en blanco.
        final double darkStop =
            ((topInset + (kToolbarHeight * 0.76)) / safeHeight)
                .clamp(0.0, 0.28);
        final double whiteStop = ((topInset + kToolbarHeight + 36) / safeHeight)
            .clamp(darkStop + 0.04, 0.38);

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                _headerInk,
                _headerInk,
                contentColor,
                contentColor,
              ],
              stops: <double>[0, darkStop, whiteStop, 1],
            ),
          ),
          child: child,
        );
      },
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
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: context.colors.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: context.colors.surfaceLine),
        ),
        child: child,
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
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
            color: Colors.black.withValues(alpha: isDark ? 0.14 : 0.07),
            blurRadius: 14,
            offset: const Offset(0, 5),
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
