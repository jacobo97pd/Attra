import 'package:flutter/material.dart';

import '../theme/attra_colors.dart';
import '../theme/app_spacing.dart';
import 'attra_glass.dart';
import 'attra_motion.dart';

/// Acción principal con estados Material, altura flexible y superficie tonal.
class AttraPrimaryButton extends StatelessWidget {
  const AttraPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.gradient,
    this.foregroundColor,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;
  final List<Color>? gradient;

  /// Color del texto/icono. Por defecto blanco cálido; útil para botones claros
  /// (p. ej. champagne en Plus) donde conviene texto oscuro para legibilidad.
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !loading;
    final Color fg = foregroundColor ??
        (gradient == null ? context.colors.onAccent : Colors.white);
    final BorderRadius radius = BorderRadius.circular(AppSpacing.radiusPill);
    final Widget button = FilledButton(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        backgroundColor:
            gradient == null ? context.colors.accent : Colors.transparent,
        foregroundColor: fg,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (loading)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
              child: MediaQuery.disableAnimationsOf(context)
                  ? const Icon(Icons.more_horiz, size: 20)
                  : SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: context.colors.textMuted,
                      ),
                    ),
            )
          else if (icon != null) ...<Widget>[
            Icon(icon, size: 20),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );

    return Semantics(
      liveRegion: loading,
      child: AttraPressFeedback(
          enabled: enabled,
          child: SizedBox(
            width: expand ? double.infinity : null,
            child: gradient == null || !enabled
                ? button
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: gradient!.first,
                      borderRadius: radius,
                    ),
                    child: button,
                  ),
          )),
    );
  }
}

/// Botón secundario: grafito sólido, pill.
class AttraSecondaryButton extends StatelessWidget {
  const AttraSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return AttraPressFeedback(
        enabled: onPressed != null,
        child: SizedBox(
          width: expand ? double.infinity : null,
          child: icon == null
              ? ElevatedButton(onPressed: onPressed, child: Text(label))
              : ElevatedButton.icon(
                  onPressed: onPressed,
                  icon: Icon(icon, size: 20),
                  label: Text(label),
                ),
        ));
  }
}

/// Icono circular flotante sobre una foto o un vídeo: cerrar, más opciones,
/// reportar, deshacer... Antes cada pantalla (tarjeta del feed, historias, en
/// vivo, cámara de perfil) repetía su propio `Material` + `IconButton` con el
/// mismo 45% de negro plano. Desde la maqueta "Liquid Glass" del 19 de
/// octubre de 2026, es [AttraGlassIconButton] por debajo: mismo sitio para el
/// tamaño del área de toque y la respuesta al tacto, ahora en vidrio.
class AttraCircleIconButton extends StatelessWidget {
  const AttraCircleIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 48,
    this.background,
  });

  /// El contenido del botón: normalmente un `Icon`, pero admite cualquier
  /// widget (p. ej. un `CircularProgressIndicator` mientras carga algo).
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  /// Lado del círculo. El área de toque crece con él.
  final double size;

  /// Tinte del vidrio. `null` = neutro (blanco); se puede dar un color, por
  /// ejemplo el champagne de Plus/Attra.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return AttraGlassIconButton(
      icon: icon,
      onPressed: onPressed,
      tooltip: tooltip,
      size: size,
      tint: background,
    );
  }
}

/// Botón fantasma (ghost): solo borde, sin relleno.
class AttraGhostButton extends StatelessWidget {
  const AttraGhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return AttraPressFeedback(
        enabled: onPressed != null,
        child: SizedBox(
          width: expand ? double.infinity : null,
          child: icon == null
              ? OutlinedButton(onPressed: onPressed, child: Text(label))
              : OutlinedButton.icon(
                  onPressed: onPressed,
                  icon: Icon(icon, size: 20),
                  label: Text(label),
                ),
        ));
  }
}
