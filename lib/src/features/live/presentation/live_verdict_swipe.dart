import 'package:flutter/material.dart';

import '../../../theme/app_spacing.dart';
import '../../../theme/attra_colors.dart';
import '../domain/live_session.dart';

/// Gesto de veredicto del vivo: IZQUIERDA = paso, DERECHA = me interesa.
///
/// Reutiliza el patrón del feed (arrastre horizontal, rotación proporcional y
/// dos señales que aparecen según la dirección) porque es el gesto que el
/// usuario ya tiene aprendido: cambiarlo aquí obligaría a re-aprender una
/// decisión que además es irreversible.
///
/// Diferencia con el feed: el umbral es MÁS ALTO. En el feed un swipe de más
/// se arregla con un rewind; aquí un `like` accidental deja el móvil de otra
/// persona con un match que nadie pidió, así que exigimos un gesto claro.
class LiveVerdictSwipe extends StatefulWidget {
  const LiveVerdictSwipe({
    super.key,
    required this.child,
    required this.onVerdict,
    this.enabled = true,
    this.returnToCenter = false,
  });

  final Widget child;
  final ValueChanged<LiveVerdict> onVerdict;
  final bool enabled;

  /// Vuelve al centro tras decidir.
  ///
  /// Se usa DURANTE la llamada: ahí el hijo es el vídeo del otro y dejarlo
  /// volado fuera de pantalla apagaría la imagen de alguien con quien se
  /// sigue hablando. En la tarjeta final del veredicto, en cambio, interesa
  /// que salga volando (la decisión ya está tomada).
  final bool returnToCenter;

  @override
  State<LiveVerdictSwipe> createState() => _LiveVerdictSwipeState();
}

class _LiveVerdictSwipeState extends State<LiveVerdictSwipe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(() {
      if (_animation != null) setState(() => _dx = _animation!.value);
    });

  Animation<double>? _animation;
  double _dx = 0;
  double _width = 1;

  /// 32 % del ancho: por encima del ~25 % habitual del feed, a propósito.
  double get _threshold => _width * 0.32;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _runTo(double target, {VoidCallback? onDone}) {
    _animation = Tween<double>(begin: _dx, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller
      ..reset()
      ..forward().whenCompleteOrCancel(() => onDone?.call());
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;
    setState(() => _dx += details.delta.dx);
  }

  void _onDragEnd(DragEndDetails details) {
    if (!widget.enabled) {
      _runTo(0);
      return;
    }
    if (_dx.abs() > _threshold) {
      final bool like = _dx > 0;
      _runTo(
        like ? _width * 1.4 : -_width * 1.4,
        onDone: () {
          widget.onVerdict(like ? LiveVerdict.like : LiveVerdict.pass);
          if (widget.returnToCenter && mounted) {
            setState(() => _dx = 0);
          }
        },
      );
    } else {
      _runTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _width = constraints.maxWidth <= 0 ? 1 : constraints.maxWidth;
        final double likeOpacity = (_dx / _threshold).clamp(0.0, 1.0);
        final double passOpacity = (-_dx / _threshold).clamp(0.0, 1.0);
        return GestureDetector(
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          child: Transform.translate(
            offset: Offset(_dx, 0),
            child: Transform.rotate(
              angle: (_dx / _width) * 0.18,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  widget.child,
                  Positioned(
                    top: 32,
                    left: 24,
                    child: _VerdictBadge(
                      opacity: passOpacity,
                      icon: Icons.close_rounded,
                      label: 'PASO',
                    ),
                  ),
                  Positioned(
                    top: 32,
                    right: 24,
                    child: _VerdictBadge(
                      opacity: likeOpacity,
                      icon: Icons.favorite_rounded,
                      label: 'ME INTERESA',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VerdictBadge extends StatelessWidget {
  const _VerdictBadge({
    required this.opacity,
    required this.icon,
    required this.label,
  });

  final double opacity;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0.01) return const SizedBox.shrink();
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botonera equivalente al gesto.
///
/// ACCESIBILIDAD, no adorno: un veredicto que solo se pueda dar deslizando
/// deja fuera a quien navega con lector de pantalla o tiene poca movilidad, y
/// aquí no darlo significa perder el match.
class LiveVerdictButtons extends StatelessWidget {
  const LiveVerdictButtons({
    super.key,
    required this.onVerdict,
    this.enabled = true,
  });

  final ValueChanged<LiveVerdict> onVerdict;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _RoundAction(
          key: const ValueKey<String>('live-verdict-pass'),
          icon: Icons.close_rounded,
          tooltip: 'Paso',
          onPressed: enabled ? () => onVerdict(LiveVerdict.pass) : null,
        ),
        const SizedBox(width: AppSpacing.xxl),
        _RoundAction(
          key: const ValueKey<String>('live-verdict-like'),
          icon: Icons.favorite_rounded,
          tooltip: 'Me interesa',
          filled: true,
          onPressed: enabled ? () => onVerdict(LiveVerdict.like) : null,
        ),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final AttraColors colors = context.colors;
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: filled ? colors.accent : colors.surfaceHigh,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Icon(
                icon,
                size: 28,
                color: filled ? colors.onAccent : colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
