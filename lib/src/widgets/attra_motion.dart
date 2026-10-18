import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

/// Curves from Emil Design Engineering. Durations belong to each interaction;
/// gesture completion clocks and service work never depend on these helpers.
abstract final class AttraMotion {
  static const Curve enter = Cubic(0.23, 1, 0.32, 1);
  static const Curve change = Cubic(0.77, 0, 0.175, 1);

  static bool enabledOf(BuildContext context) =>
      !MediaQuery.disableAnimationsOf(context) &&
      TickerMode.valuesOf(context).enabled;

  static Duration durationOf(BuildContext context, Duration duration) =>
      enabledOf(context) ? duration : Duration.zero;

  /// Scroll activities require a positive duration. Static navigation uses the
  /// matching jump API; it must not manufacture a tiny animated scroll.
  static Future<void> pageTo(
      BuildContext context, PageController controller, int page,
      {required Duration duration, required Curve curve}) {
    if (!enabledOf(context)) {
      controller.jumpToPage(page);
      return Future<void>.value();
    }
    return controller.animateToPage(page, duration: duration, curve: curve);
  }

  /// Outgoing visuals must never retain tappable controls or spoken labels.
  static Widget switcherLayout(Widget? current, List<Widget> previous) => Stack(
        alignment: Alignment.center,
        children: <Widget>[
          for (final Widget child in previous)
            IgnorePointer(child: ExcludeSemantics(child: child)),
          if (current != null) current,
        ],
      );
}

/// Pointer-only feedback around an existing native control. It owns no action,
/// gesture recognizer or semantics, and never delays the control's callback.
class AttraPressFeedback extends StatefulWidget {
  const AttraPressFeedback({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  State<AttraPressFeedback> createState() => _AttraPressFeedbackState();
}

class _AttraPressFeedbackState extends State<AttraPressFeedback> {
  int? _pointer;

  void _down(PointerDownEvent event) {
    if (!widget.enabled ||
        _pointer != null ||
        event.buttons != kPrimaryButton) {
      return;
    }
    // Tacto sutil en el propio toque, no en el resultado: es la confirmación
    // de "te he oído" que antes solo daba el ripple de Material. selectionClick
    // es el más discreto de los tres (el mismo que usa iOS en un picker), así
    // que aguanta bien usarse en CUALQUIER botón sin cansar.
    HapticFeedback.selectionClick();
    setState(() => _pointer = event.pointer);
  }

  void _release(PointerEvent event) {
    if (_pointer == event.pointer) setState(() => _pointer = null);
  }

  @override
  void didUpdateWidget(covariant AttraPressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _pointer = null;
  }

  @override
  Widget build(BuildContext context) {
    final bool animate = widget.enabled && AttraMotion.enabledOf(context);
    // El control nativo de debajo (IconButton, FilledButton...) sigue
    // pintando SU ripple salvo que se le diga lo contrario, así que sin esto
    // cada toque mostraba dos respuestas a la vez: el círculo de Material
    // expandiéndose Y la escala. Con el escalado ya activo, el ripple sobra
    // y la suma de los dos es lo que hace que un botón "se sienta" genérico.
    // Solo se apaga cuando el escalado SÍ va a animar: con movimiento
    // reducido el ripple nativo sigue siendo la única señal, y quitarla sin
    // sustituto habría dejado el botón mudo para quien lo pidió así.
    // El Theme envuelve SIEMPRE (solo cambia su `data`), nunca solo cuando
    // `animate` es true: si `animate` cambia a mitad de un toque (se activa
    // "reducir movimiento" con el dedo todavía puesto), insertar o quitar un
    // ancestro distinto ahí cambia la FORMA del árbol en ese punto y Flutter
    // tira el control nativo y lo vuelve a crear de cero, perdiendo el puntero
    // que tenía agarrado. Con el wrapper constante, lo único que cambia es el
    // valor que lee — el control de debajo nunca se entera.
    final ThemeData ambientTheme = Theme.of(context);
    final Widget effectiveChild = Theme(
      data: animate
          ? ambientTheme.copyWith(splashFactory: NoSplash.splashFactory)
          : ambientTheme,
      child: widget.child,
    );
    return Listener(
      onPointerDown: _down,
      onPointerUp: _release,
      onPointerCancel: _release,
      child: TweenAnimationBuilder<double>(
        tween:
            Tween<double>(begin: 1, end: animate && _pointer != null ? .98 : 1),
        duration: animate
            ? Duration(milliseconds: _pointer != null ? 100 : 140)
            : Duration.zero,
        curve: AttraMotion.enter,
        builder: (BuildContext context, double scale, Widget? child) =>
            Transform.scale(
          scale: scale,
          // Preserve the native control's full touch target while painting.
          transformHitTests: false,
          child: child,
        ),
        child: effectiveChild,
      ),
    );
  }
}

/// A small continuity cue when [value] changes. Initial content is immediate;
/// stream rebuilds of the same value do not replay. Only the current child is
/// present, so expired/private content and old callbacks cannot linger.
class AttraStateTransition extends StatefulWidget {
  const AttraStateTransition({
    super.key,
    required this.value,
    required this.child,
    this.duration = const Duration(milliseconds: 180),
    this.offset = const Offset(0, .015),
    this.beginOpacity = 1,
  });

  final Object? value;
  final Widget child;
  final Duration duration;
  final Offset offset;
  final double beginOpacity;

  @override
  State<AttraStateTransition> createState() => _AttraStateTransitionState();
}

class _AttraStateTransitionState extends State<AttraStateTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );
  late final Animation<double> _curve =
      _controller.drive(CurveTween(curve: AttraMotion.enter));
  bool _enabled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enabled = AttraMotion.enabledOf(context);
    if (!_enabled) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant AttraStateTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (widget.value != oldWidget.value && _enabled) {
      // A rapid update replaces the content immediately and finishes the cue
      // already in flight, without jumping back to the starting position.
      _controller.forward(from: _controller.isAnimating ? null : 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        alwaysIncludeSemantics: true,
        opacity:
            Tween<double>(begin: widget.beginOpacity, end: 1).animate(_curve),
        child: SlideTransition(
          position: Tween<Offset>(begin: widget.offset, end: Offset.zero)
              .animate(_curve),
          transformHitTests: false,
          child: widget.child,
        ),
      );
}
