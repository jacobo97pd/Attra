import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../theme/app_colors.dart';
import '../domain/story.dart';
import 'blind_wall_controller.dart';

/// Visor A CIEGAS a pantalla completa: Discover por dentro.
///
/// Solo se muestran NOMBRE y EDAD. Nada de estudios, trabajo, bio, intereses,
/// prompts ni verificaciones: eso se desbloquea con el match. La idea del
/// producto es conocer a la persona por lo que cuenta, no por su ficha.
///
/// Navegación: toque a la derecha avanza, a la izquierda retrocede y, al pasar
/// la última historia, se salta a la SIGUIENTE PERSONA. Deslizar da like o pasa,
/// y el botón central manda un Super Attra. Ninguna de esas acciones se resuelve
/// aquí: todas vuelven al feed por [BlindWallController] para que compartan gate
/// de likes, contadores, métricas, rewind y anuncios.
///
/// No hay música ni pista de audio propia: lo único que suena es el audio del
/// vídeo que ha grabado esa persona.
class BlindStoryViewerScreen extends StatefulWidget {
  const BlindStoryViewerScreen({super.key, required this.controller});

  final BlindWallController controller;

  @override
  State<BlindStoryViewerScreen> createState() => _BlindStoryViewerScreenState();
}

class _BlindStoryViewerScreenState extends State<BlindStoryViewerScreen>
    with SingleTickerProviderStateMixin {
  /// Desplazamiento a partir del cual el gesto cuenta como like/pase.
  static const double _swipeThreshold = 90;

  /// Cuánto dura una historia de imagen cuando el autor no fijó duración.
  static const int _defaultImageSeconds = 5;

  BlindWallPerson? _person;
  int _storyIndex = 0;

  VideoPlayerController? _video;
  Timer? _imageTimer;
  Duration _imageElapsed = Duration.zero;
  Duration _imageDuration = const Duration(seconds: _defaultImageSeconds);
  DateTime? _lastImageTick;
  String? _mediaError;
  bool _paused = false;

  /// Acción en vuelo (like/pase/Attra): bloquea la entrada hasta que el feed
  /// responde, para no enviar dos likes con un doble gesto.
  bool _busy = false;

  /// Acción YA decidida pero todavía animándose (los 240 ms del deslizamiento).
  ///
  /// `_busy` solo se levanta cuando termina la animación, así que durante ese
  /// cuarto de segundo los botones seguían activos: tocar "Paso" y acto seguido
  /// "Me gusta" cancelaba la primera animación, disparaba su acción, avanzaba de
  /// persona y el like acababa cayendo sobre la SIGUIENTE, a la que el usuario
  /// no había visto nada.
  bool _actionPending = false;

  /// Entrada bloqueada: ya hay una acción decidida (animándose o en vuelo).
  bool get _locked => _busy || _actionPending;

  late final AnimationController _swipeAnim;
  Animation<double>? _swipeTween;

  /// Identifica la animación de deslizamiento en curso. `reset()` CANCELA la
  /// anterior y su `whenCompleteOrCancel` se dispara igual: sin este contador,
  /// una animación abortada ejecutaba su acción sobre otra persona.
  int _swipeSeq = 0;
  double _dx = 0;
  double _screenWidth = 360;

  /// Story que se está reproduciendo ahora mismo. El índice no vale como ancla:
  /// la lista de la persona cambia sola cuando una de sus historias caduca.
  String? _currentStoryId;

  Story? get _story {
    final List<Story> stories = _person?.stories ?? const <Story>[];
    if (stories.isEmpty) return null;
    // Clamp: una historia puede caducar mientras se está viendo y el grupo se
    // encoge por debajo del índice actual.
    return stories[_storyIndex.clamp(0, stories.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    _swipeAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
        final Animation<double>? tween = _swipeTween;
        if (tween != null) setState(() => _dx = tween.value);
      });
    _person = widget.controller.current;
    widget.controller.addListener(_onWallChanged);
    // El aviso de "vista" tiene que salir del frame de construcción: marca
    // vistas hace setState en el feed y eso revienta si se llama durante build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onWallChanged);
    _swipeAnim.dispose();
    _imageTimer?.cancel();
    _video?.dispose();
    super.dispose();
  }

  /// Cierra ESTE visor.
  ///
  /// Con algo encima (el diálogo de match, el sheet del límite de pendientes,
  /// el menú de seguridad) un `pop` se llevaría por delante la pantalla
  /// equivocada, así que en ese caso se saca esta ruta de la pila sin tocar el
  /// resto.
  void _closeSelf() {
    if (!mounted) return;
    final NavigatorState navigator = Navigator.of(context);
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route == null || route.isCurrent) {
      navigator.maybePop();
      return;
    }
    navigator.removeRoute(route);
  }

  /// El feed manda: cuando cambia la persona actual (like, pase, rewind, una
  /// historia caducada o un bloqueo), el visor se resincroniza.
  void _onWallChanged() {
    if (!mounted) return;
    if (widget.controller.shouldClose) {
      _closeSelf();
      return;
    }
    final BlindWallPerson? next = widget.controller.current;
    if (next == null) {
      _closeSelf();
      return;
    }
    final bool samePerson = next.uid == _person?.uid;
    // Reanclaje por storyId: a la MISMA persona se le puede caducar una historia
    // mientras se la estás viendo. Con el índice a pelo, la lista se encogía por
    // debajo, `_storyIndex` pasaba a señalar otra historia mientras seguía
    // sonando la anterior, la barra de segmentos mentía y al acabar el vídeo se
    // saltaba a la siguiente persona sin haber enseñado la última.
    final int anchored = samePerson
        ? next.stories.indexWhere((Story s) => s.storyId == _currentStoryId)
        : -1;
    setState(() {
      _person = next;
      if (!samePerson) {
        _storyIndex = 0;
      } else if (anchored >= 0) {
        _storyIndex = anchored;
      } else if (_storyIndex >= next.stories.length) {
        _storyIndex = next.stories.isEmpty ? 0 : next.stories.length - 1;
      }
    });
    // Se recarga si cambia la persona o si la historia que sonaba ya no está. Si
    // sigue estando (el caso normal: el stream emite hasta cuando alguien, en
    // cualquier parte, ve una historia ajena) NO se toca el reproductor.
    // Con una acción decidida NO se arranca nada: el diálogo de match y el
    // revelado del perfil se abren después, y si no, la siguiente persona se
    // ponía a sonar por detrás de la celebración. Lo arranca [_act] al terminar.
    if (anchored < 0 && !_locked) _load();
  }

  Future<void> _load() async {
    _imageTimer?.cancel();
    _video?.dispose();
    _video = null;
    if (!mounted) return;
    setState(() {
      _mediaError = null;
      _paused = false;
      _imageElapsed = Duration.zero;
      _lastImageTick = null;
    });
    final Story? story = _story;
    _currentStoryId = story?.storyId;
    if (story == null) return;
    widget.controller.onStoriesSeen(<Story>[story]);

    if (story.isImage) {
      if (story.imageUrl.isEmpty) {
        setState(() => _mediaError = 'Esta historia no tiene imagen.');
        return;
      }
      _imageDuration = Duration(
        seconds: story.durationSeconds > 0
            ? story.durationSeconds
            : _defaultImageSeconds,
      );
      _lastImageTick = DateTime.now();
      _imageTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _onImageTick(),
      );
      setState(() {});
      return;
    }
    if (story.videoUrl.isEmpty) {
      setState(() => _mediaError = 'Esta historia no tiene vídeo.');
      return;
    }
    final VideoPlayerController controller =
        VideoPlayerController.networkUrl(Uri.parse(story.videoUrl));
    _video = controller;
    try {
      await controller.initialize().timeout(const Duration(seconds: 20));
      // Mientras se inicializaba puede haberse pasado de historia o de persona:
      // sin esta comprobación el vídeo viejo se ponía a sonar encima del nuevo.
      if (!mounted || !identical(_video, controller)) {
        controller.dispose();
        return;
      }
      controller
        ..addListener(_onVideoTick)
        ..setVolume(1)
        ..play();
      setState(() {});
    } catch (_) {
      if (mounted && identical(_video, controller)) {
        setState(() => _mediaError = 'No se pudo reproducir el vídeo.');
      }
    }
  }

  void _onVideoTick() {
    final VideoPlayerController? controller = _video;
    if (controller == null || !mounted) return;
    final VideoPlayerValue value = controller.value;
    if (value.isInitialized &&
        !value.isPlaying &&
        !_paused &&
        value.duration > Duration.zero &&
        value.position >= value.duration) {
      _next();
    } else {
      setState(() {});
    }
  }

  void _onImageTick() {
    if (!mounted) return;
    final Story? story = _story;
    if (story == null || !story.isImage) return;
    final DateTime now = DateTime.now();
    final DateTime? last = _lastImageTick;
    if (last != null && !_paused) _imageElapsed += now.difference(last);
    _lastImageTick = now;
    if (_imageElapsed >= _imageDuration) {
      _next();
    } else {
      setState(() {});
    }
  }

  void _next() {
    if (_locked) return;
    final BlindWallPerson? person = _person;
    if (person == null) return;
    if (_storyIndex < person.stories.length - 1) {
      setState(() => _storyIndex += 1);
      _load();
      return;
    }
    // Se acabaron sus historias: siguiente PERSONA. Mirar no es opinar, así que
    // no se manda ni like ni pase; el feed sí cuenta la impresión.
    _imageTimer?.cancel();
    _video?.pause();
    widget.controller.onSkip();
  }

  /// Retrocede DENTRO de la persona. No vuelve a la persona anterior a
  /// propósito: a esa ya se le mandó un like o un pase, y "des-verla" no
  /// desharía la acción (para eso está el rewind del feed, con su gate de plan).
  void _prev() {
    if (_locked) return;
    if (_storyIndex == 0) {
      // En la primera historia el toque izquierdo la reinicia, que es lo que
      // espera quien se ha perdido algo.
      _load();
      return;
    }
    setState(() => _storyIndex -= 1);
    _load();
  }

  void _pause() {
    if (_mediaError != null) return;
    _video?.pause();
    setState(() => _paused = true);
  }

  void _resume() {
    if (_mediaError != null) return;
    _lastImageTick = DateTime.now();
    _video?.play();
    setState(() => _paused = false);
  }

  void _runTo(double target, {VoidCallback? onDone}) {
    final int seq = ++_swipeSeq;
    _swipeTween = Tween<double>(begin: _dx, end: target).animate(
      CurvedAnimation(parent: _swipeAnim, curve: Curves.easeOut),
    );
    _swipeAnim
      ..reset()
      ..forward().whenCompleteOrCancel(() {
        // Solo la ÚLTIMA animación lanzada ejecuta su acción: `reset()` cancela
        // la anterior y dispara su callback igualmente, y esa acción iba a caer
        // sobre la persona equivocada.
        if (seq != _swipeSeq || !mounted) return;
        onDone?.call();
      });
  }

  /// Ejecuta una acción del feed y libera la entrada pase lo que pase. Si la
  /// acción avanza de persona, [_onWallChanged] ya habrá reseteado el gesto.
  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    _imageTimer?.cancel();
    _video?.pause();
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _actionPending = false;
          _dx = 0;
        });
        // Arranca lo que toque: la historia de la persona siguiente si la acción
        // avanzó, o la misma si no llegó a hacerlo (sin Attras, límite de
        // pendientes, error de red). Sin esto se quedaba congelada con el
        // temporizador ya cancelado.
        _load();
      }
    }
  }

  Future<void> _like() async {
    if (_locked) return;
    // La entrada se bloquea AQUÍ, no en `_act`: entre el gate y el final de la
    // animación hay casi medio segundo en el que se podía decidir otra cosa.
    setState(() => _actionPending = true);
    // Mismo gate que la tarjeta del feed (límite de conversaciones pendientes).
    final bool allowed = await widget.controller.beforeLike();
    if (!mounted) return;
    if (!allowed) {
      setState(() => _actionPending = false);
      _runTo(0);
      return;
    }
    _runTo(_screenWidth * 1.2,
        onDone: () => unawaited(_act(widget.controller.onLike)));
  }

  void _pass() {
    if (_locked) return;
    setState(() => _actionPending = true);
    _runTo(-_screenWidth * 1.2,
        onDone: () => unawaited(_act(widget.controller.onPass)));
  }

  void _superAttra() {
    if (_locked) return;
    unawaited(_act(widget.controller.onSuperAttra));
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_locked) return;
    setState(() => _dx += details.delta.dx);
  }

  void _onDragEnd(DragEndDetails details) {
    if (_locked) return;
    if (_dx.abs() <= _swipeThreshold) {
      _runTo(0);
      return;
    }
    if (_dx > 0) {
      unawaited(_like());
    } else {
      _pass();
    }
  }

  double get _progress {
    final Story? story = _story;
    if (story == null) return 0;
    if (story.isImage) {
      if (_imageDuration <= Duration.zero) return 0;
      return (_imageElapsed.inMilliseconds / _imageDuration.inMilliseconds)
          .clamp(0.0, 1.0);
    }
    final VideoPlayerController? controller = _video;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.duration <= Duration.zero) {
      return 0;
    }
    return (controller.value.position.inMilliseconds /
            controller.value.duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final BlindWallPerson? person = _person;
    _screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: Colors.black,
      body: person == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : GestureDetector(
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Transform.translate(
                    offset: Offset(_dx, 0),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        Positioned.fill(child: _mediaLayer()),
                        const _Scrim(top: true),
                        const _Scrim(top: false),
                        if (_story?.visualOverlays.isNotEmpty ?? false)
                          _overlaysLayer(),
                      ],
                    ),
                  ),
                  SafeArea(
                    child: Column(
                      children: <Widget>[
                        const SizedBox(height: 6),
                        _segments(person),
                        _header(person),
                        const Spacer(),
                        _actionBar(),
                      ],
                    ),
                  ),
                  if (_paused)
                    const IgnorePointer(
                      child: Center(
                        child: Icon(Icons.play_arrow_rounded,
                            color: Colors.white70, size: 72),
                      ),
                    ),
                  IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 120),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _SwipeStamp(
                            progress:
                                (-_dx / _swipeThreshold).clamp(0.0, 1.0),
                            icon: Icons.close_rounded,
                            label: 'Paso',
                          ),
                          _SwipeStamp(
                            progress: (_dx / _swipeThreshold).clamp(0.0, 1.0),
                            icon: Icons.favorite_rounded,
                            label: 'Me gusta',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _mediaLayer() {
    final Story? story = _story;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Zona izquierda = atrás, resto = adelante (patrón universal de stories).
      onTapUp: (TapUpDetails details) {
        if (details.localPosition.dx < _screenWidth * 0.32) {
          _prev();
        } else {
          _next();
        }
      },
      onLongPressStart: (_) => _pause(),
      onLongPressEnd: (_) => _resume(),
      child: _mediaError != null || story == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.hide_image_outlined,
                        color: Colors.white70, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      _mediaError ?? 'Esta historia ya no está disponible.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            )
          : story.isImage
              ? CachedNetworkImage(
                  imageUrl: story.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (BuildContext context, String url) =>
                      const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget:
                      (BuildContext context, String url, Object error) =>
                          const Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: Colors.white70, size: 48),
                  ),
                )
              : _videoLayer(),
    );
  }

  Widget _videoLayer() {
    final VideoPlayerController? controller = _video;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }

  Widget _segments(BlindWallPerson person) {
    final double progress = _progress;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < person.stories.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    value: i < _storyIndex
                        ? 1.0
                        : i == _storyIndex
                            ? progress
                            : 0.0,
                    backgroundColor: Colors.white.withValues(alpha: 0.28),
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Cabecera del visor. Aquí SOLO va nombre y edad: cualquier dato extra
  /// (ciudad, trabajo, verificación…) rompe el "a ciegas".
  Widget _header(BlindWallPerson person) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  person.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    shadows: <Shadow>[
                      Shadow(blurRadius: 8, color: Colors.black87),
                    ],
                  ),
                ),
                Text(
                  'Su perfil se desbloquea con el match',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (widget.controller.onSafety != null)
            IconButton(
              key: const ValueKey<String>('blind-viewer-safety'),
              tooltip: 'Reportar o bloquear',
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onPressed: () {
                _pause();
                widget.controller.onSafety!();
              },
            ),
          IconButton(
            tooltip: 'Cerrar',
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _overlaysLayer() {
    final Story? story = _story;
    if (story == null) return const SizedBox.shrink();
    final Size size = MediaQuery.of(context).size;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          for (final StoryOverlay overlay in story.visualOverlays)
            _BlindOverlayView(overlay: overlay, canvasSize: size),
        ],
      ),
    );
  }

  Widget _actionBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          _ActionButton(
            key: const ValueKey<String>('blind-viewer-pass'),
            icon: Icons.close_rounded,
            label: 'Paso',
            color: Colors.white,
            onTap: _locked ? null : _pass,
          ),
          _ActionButton(
            key: const ValueKey<String>('blind-viewer-attra'),
            icon: Icons.star_rounded,
            label: 'Super Attra',
            color: AppColors.gold,
            big: true,
            onTap: _locked ? null : _superAttra,
          ),
          _ActionButton(
            key: const ValueKey<String>('blind-viewer-like'),
            icon: Icons.favorite_rounded,
            label: 'Me gusta',
            color: AppColors.attraRed,
            onTap: _locked ? null : () => unawaited(_like()),
          ),
        ],
      ),
    );
  }
}

/// Sello de like/pase que aparece según se arrastra.
class _SwipeStamp extends StatelessWidget {
  const _SwipeStamp({
    required this.progress,
    required this.icon,
    required this.label,
  });

  final double progress;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0.02) return const SizedBox(width: 96);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Opacity(
        opacity: progress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.big = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final double size = big ? 68 : 56;
    return Semantics(
      button: true,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Material(
            color: Colors.white.withValues(alpha: 0.14),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(icon,
                    color: onTap == null ? Colors.white38 : color,
                    size: big ? 34 : 28),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Scrim extends StatelessWidget {
  const _Scrim({required this.top});
  final bool top;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
        child: Container(
          height: top ? 170 : 260,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: <Color>[
                Colors.black.withValues(alpha: 0.6),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Texto/sticker superpuesto de la historia, en su posición normalizada.
class _BlindOverlayView extends StatelessWidget {
  const _BlindOverlayView({required this.overlay, required this.canvasSize});

  final StoryOverlay overlay;
  final Size canvasSize;

  @override
  Widget build(BuildContext context) {
    final bool sticker = overlay.type == StoryOverlayType.sticker;
    final double width = sticker ? 120 : 240;
    final double height = sticker ? 90 : 92;
    return Positioned(
      left: overlay.x * canvasSize.width - width / 2,
      top: overlay.y * canvasSize.height - height / 2,
      width: width,
      height: height,
      child: Transform.rotate(
        angle: overlay.rotation,
        child: Transform.scale(
          scale: overlay.scale,
          child: sticker
              ? Center(
                  child:
                      Text(overlay.text, style: const TextStyle(fontSize: 48)))
              : Container(
                  alignment: Alignment.center,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: overlay.background
                        ? Colors.black.withValues(alpha: 0.55)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    overlay.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: switch (overlay.align) {
                      StoryOverlayAlign.left => TextAlign.left,
                      StoryOverlayAlign.center => TextAlign.center,
                      StoryOverlayAlign.right => TextAlign.right,
                    },
                    style: TextStyle(
                      color: Color(overlay.colorValue),
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.08,
                      shadows: const <Shadow>[
                        Shadow(blurRadius: 8, color: Colors.black87),
                        Shadow(blurRadius: 2, color: Colors.black),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
