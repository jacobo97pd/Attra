import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'attra_motion.dart';

/// Material "vidrio esmerilado" estilo iOS 26 (Liquid Glass): el tratamiento
/// aprobado en la maqueta del 19 de octubre de 2026 para chat, feed y
/// navegación. Receta: degradado translúcido diagonal + desenfoque del
/// contenido de detrás + borde fino + una sombra interior arriba (luz) y
/// otra abajo (profundidad) + un brillo radial superior en la esquina.
///
/// [blur] desenfoca de verdad lo que hay detrás (`BackdropFilter`), que tiene
/// coste real de GPU: se deja fuera en elementos pequeños y repetidos (los
/// chips de un filtro, que van varios a la vez en una lista horizontal) y se
/// reserva para superficies grandes y pocas a la vez (los botones de la
/// tarjeta, la hoja de un chat, la barra de navegación). Sin blur, el
/// degradado y el brillo solos ya leen como "vidrio", solo que sin desenfocar
/// lo de detrás.
class AttraGlassSurface extends StatelessWidget {
  const AttraGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.tint,
    this.blur = true,
    this.blurSigma = 20,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// Color del reflejo. `null` = vidrio neutro (blanco). Un color (p. ej. el
  /// champagne de Plus/Attra) lo tiñe sin perder la transparencia.
  final Color? tint;
  final bool blur;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final Color base = tint ?? Colors.white;
    final Widget glass = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            base.withValues(alpha: tint == null ? 0.20 : 0.34),
            base.withValues(alpha: tint == null ? 0.05 : 0.10),
            base.withValues(alpha: tint == null ? 0.10 : 0.16),
          ],
        ),
        border: Border.all(color: base.withValues(alpha: 0.26)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          // Brillo superior: simula la luz que coge el borde del cristal.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                gradient: RadialGradient(
                  center: const Alignment(-0.6, -1.1),
                  radius: 1.1,
                  colors: <Color>[
                    Colors.white.withValues(alpha: 0.30),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
    if (!blur) {
      return ClipRRect(borderRadius: borderRadius, child: glass);
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: glass,
      ),
    );
  }
}

/// Botón en forma de burbuja (pill) sobre el material de vidrio: "Pasar",
/// "Enviar Like", "Enviar Attra"... Reutiliza [AttraPressFeedback] (escala +
/// vibración al tocar), así que no hay dos sistemas de respuesta al tacto.
class AttraGlassPillButton extends StatelessWidget {
  const AttraGlassPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tint,
    this.expand = false,
    this.blur = true,
    this.foregroundColor,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final Color? tint;
  final bool expand;
  final bool blur;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final BorderRadius radius = BorderRadius.circular(AppSpacing.radiusPill);
    final Color fg = foregroundColor ??
        (enabled ? Colors.white : Colors.white.withValues(alpha: 0.4));
    final Widget content = ConstrainedBox(
      // Mismo mínimo de 48 px que el resto de controles: área de toque antes
      // de que el vidrio decida cuánto alto le pide el texto.
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              IconTheme(data: IconThemeData(color: fg, size: 18), child: icon!),
              const SizedBox(width: AppSpacing.sm),
            ],
            Flexible(
              // Excluido aquí, NO en el nodo de fuera: así el `InkWell` de
              // abajo sigue aportando su acción de toque (y de foco) al
              // nodo del botón; lo único que no debe duplicarse es esta
              // etiqueta de texto, que ya la lleva el `Semantics` de fuera.
              child: ExcludeSemantics(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: fg, fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      // Fuerza un nodo propio: sin esto, en algún reconstruido (se vio con
      // movimiento reducido) el nodo del botón se fundía con el de la lista
      // de debajo y perdía su acción de toque.
      container: true,
      button: true,
      enabled: enabled,
      label: label,
      child: AttraPressFeedback(
        enabled: enabled,
        child: SizedBox(
          width: expand ? double.infinity : null,
          // Sin `Opacity`: a 1.0 Flutter la quita del árbol de render, y esa
          // diferencia de estructura entre habilitado/deshabilitado es lo que
          // desbarataba la semántica con movimiento reducido (el nodo de
          // "Pasar" se fundía con el de la tarjeta de debajo). Deshabilitado
          // ya se nota en el texto más tenue (`fg` arriba); el vidrio no
          // necesita apagarse entero para eso.
          child: AttraGlassSurface(
            borderRadius: radius,
            tint: tint,
            blur: blur,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: onPressed,
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Icono circular en vidrio: deshacer, reportar, notificaciones... Mismo
/// área de toque (48 px por defecto) que el resto de botones circulares.
class AttraGlassIconButton extends StatelessWidget {
  const AttraGlassIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 48,
    this.tint,
    this.blur = true,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? tint;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(size / 2);
    final Widget button = AttraPressFeedback(
      enabled: onPressed != null,
      child: SizedBox(
        width: size,
        height: size,
        child: AttraGlassSurface(
          borderRadius: radius,
          tint: tint,
          blur: blur,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Center(
                child: IconTheme(
                  data: const IconThemeData(color: Colors.white, size: 20),
                  child: icon,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
