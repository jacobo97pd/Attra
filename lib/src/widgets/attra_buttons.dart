import 'package:flutter/material.dart';

import '../theme/attra_colors.dart';
import '../theme/app_spacing.dart';

/// Botón primario premium: degradado de acción (vino→rojo→coral), pill, con
/// icono opcional y estado de carga. CTA principal de la app.
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
    final List<Color> fill = gradient ??
        <Color>[
          context.colors.accent,
          context.colors.accent,
        ];
    final Color fg = foregroundColor ??
        (gradient == null ? context.colors.onAccent : Colors.white);
    final Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: enabled
              ? fill
              : <Color>[context.colors.surfaceHigh, context.colors.surfaceHigh],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: enabled
              ? context.colors.accent.withValues(alpha: 0.32)
              : context.colors.surfaceLine,
        ),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (loading)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: context.colors.textSecondary,
              ),
            )
          else ...<Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: AppSpacing.sm),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled ? fg : context.colors.textMuted,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: content,
        ),
      ),
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
    return SizedBox(
      width: expand ? double.infinity : null,
      child: icon == null
          ? ElevatedButton(onPressed: onPressed, child: Text(label))
          : ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 20),
              label: Text(label),
            ),
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
    return SizedBox(
      width: expand ? double.infinity : null,
      child: icon == null
          ? OutlinedButton(onPressed: onPressed, child: Text(label))
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 20),
              label: Text(label),
            ),
    );
  }
}
