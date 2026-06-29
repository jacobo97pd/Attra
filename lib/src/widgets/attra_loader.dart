import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/attra_colors.dart';

/// Loader de marca: el logo ATTRA respirando con escala y halo suave.
/// Sustituye a los spinners genericos en procesos con espera real.
///
/// Uso suelto:
/// ```dart
/// const AttraLogoLoader(size: 64, label: 'Subiendo video...')
/// ```
///
/// Uso como overlay durante una tarea async:
/// ```dart
/// await runWithAttraLoader(
///   context,
///   () => repo.uploadVideo(...),
///   message: 'Subiendo video...',
/// );
/// ```
class AttraLogoLoader extends StatefulWidget {
  const AttraLogoLoader({
    super.key,
    this.size = 72,
    this.label,
  });

  /// Lado del logo en su tamano base.
  final double size;

  /// Texto opcional bajo el logo, por ejemplo "Subiendo foto...".
  final String? label;

  @override
  State<AttraLogoLoader> createState() => _AttraLogoLoaderState();
}

class _AttraLogoLoaderState extends State<AttraLogoLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  late final Animation<double> _breath = CurvedAnimation(
    parent: _c,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AnimatedBuilder(
          animation: _breath,
          builder: (BuildContext context, Widget? child) {
            final double t = _breath.value;
            final double scale = lerpDouble(0.92, 1.08, t)!;
            final double glow = lerpDouble(16, 38, t)!;
            final double glowAlpha = lerpDouble(0.22, 0.5, t)!;
            return Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.attraRed.withValues(alpha: glowAlpha),
                    blurRadius: glow,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Transform.scale(scale: scale, child: child),
            );
          },
          child: Image.asset(
            'assets/images/ATTRA.png',
            height: widget.size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
        if (widget.label != null) ...<Widget>[
          const SizedBox(height: 18),
          Text(
            widget.label!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// Capa a pantalla completa: oscurece y difumina el fondo.
/// Bloquea la interaccion mientras dura la tarea.
class AttraLoadingOverlay extends StatelessWidget {
  const AttraLoadingOverlay({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(color: Colors.black.withValues(alpha: 0.55)),
            ),
          ),
          Center(child: AttraLogoLoader(size: 76, label: message)),
        ],
      ),
    );
  }
}

/// Ejecuta [task] mostrando el overlay de marca encima de todo y lo retira al
/// terminar, tambien si lanza. Devuelve el resultado de la tarea.
///
/// No requiere tocar el estado de la pantalla: envuelve la llamada async.
Future<T> runWithAttraLoader<T>(
  BuildContext context,
  Future<T> Function() task, {
  String? message,
}) async {
  final OverlayState overlay = Overlay.of(context, rootOverlay: true);
  final OverlayEntry entry = OverlayEntry(
    builder: (BuildContext _) => AttraLoadingOverlay(message: message),
  );
  overlay.insert(entry);
  try {
    return await task();
  } finally {
    entry.remove();
  }
}
