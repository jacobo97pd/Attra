import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../widgets/attra_backgrounds.dart';

/// Fondo de vídeo en bucle infinito para la pantalla de login.
///
/// - Ocupa TODA la pantalla (BoxFit.cover, sin barras negras).
/// - Loop eterno, silenciado, autoarranque.
/// - Capa de oscurecido encima para legibilidad del contenido.
/// - Si el vídeo no carga o la plataforma no lo soporta (web/desktop),
///   cae con elegancia al degradado de marca (AttraGradientBackground).
class LoginVideoBackground extends StatefulWidget {
  const LoginVideoBackground({
    super.key,
    required this.child,
    this.asset = 'assets/login/attraloginvideoprueba.mp4',
  });

  final Widget child;
  final String asset;

  @override
  State<LoginVideoBackground> createState() => _LoginVideoBackgroundState();
}

class _LoginVideoBackgroundState extends State<LoginVideoBackground>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;
  bool _reduceMotion = true;
  bool _tickerEnabled = false;
  bool _foreground = true;
  Future<void>? _playbackTask;

  bool get _shouldPlay =>
      !_reduceMotion && _tickerEnabled && _foreground && !_failed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final AppLifecycleState? lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _initVideo();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _requestPlaybackSync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = false;
    if (state == AppLifecycleState.resumed) {
      // Las preferencias pueden haber cambiado sin frames en segundo plano.
      // Espera a que MediaQuery se actualice antes de decidir si reproducir.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed) {
          return;
        }
        _foreground = true;
        _requestPlaybackSync();
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    } else {
      _requestPlaybackSync();
    }
  }

  bool _isCurrent(VideoPlayerController controller) =>
      mounted && identical(_controller, controller);

  Future<void> _initVideo() async {
    // En algunas plataformas de escritorio video_player no está soportado;
    // dejamos el fallback al degradado.
    final VideoPlayerController controller = VideoPlayerController.asset(
      widget.asset,
      // La reproducción de este fondo la gobierna este State: el observador
      // interno del plugin podría reanudarla al volver a primer plano aunque
      // Reduce Motion se haya activado mientras la app estaba en segundo plano.
      videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
    );
    _controller = controller;
    try {
      await controller.initialize();
      if (!_isCurrent(controller)) return;
      await controller.setLooping(true);
      if (!_isCurrent(controller)) return;
      await controller.setVolume(0);
      if (!_isCurrent(controller)) return;
      setState(() => _ready = true);
      _requestPlaybackSync();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('LoginVideoBackground: no se pudo cargar el vídeo -> $e');
      }
      if (!_isCurrent(controller)) return;
      setState(() => _failed = true);
    }
  }

  void _requestPlaybackSync() {
    final VideoPlayerController? controller = _controller;
    if (!_ready || controller == null || _playbackTask != null) return;
    _playbackTask = _syncPlayback(controller).whenComplete(() {
      _playbackTask = null;
    });
  }

  Future<void> _syncPlayback(VideoPlayerController controller) async {
    try {
      // Serializa play/pause y vuelve a leer la preferencia tras cada await.
      // Un play ya pendiente nunca puede terminar después de nuestro pause.
      while (_isCurrent(controller)) {
        final bool shouldPlay = _shouldPlay;
        if (shouldPlay == controller.value.isPlaying) return;
        if (shouldPlay) {
          await controller.play();
        } else {
          await controller.pause();
        }
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('LoginVideoBackground: error de reproducción -> $error');
      }
      if (_isCurrent(controller)) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final VideoPlayerController? controller = _controller;
    _controller = null;
    if (controller != null) {
      final Future<void>? playback = _playbackTask;
      // El plugin crea su temporizador al completar play. Disponer después de
      // la orden en vuelo evita dejar ese temporizador vivo tras salir.
      unawaited(playback == null
          ? controller.dispose()
          : playback.whenComplete(controller.dispose));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? controller = _controller;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // 1) Capa de fondo: vídeo a pantalla completa o degradado de fallback.
        if (_ready && controller != null && !_failed)
          // FittedBox + SizedBox con el tamaño nativo del vídeo => BoxFit.cover
          // exacto, sin deformar y sin franjas negras.
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          )
        else
          // Fallback (carga/sin soporte): degradado de marca para que la
          // pantalla nunca quede en blanco ni con un parpadeo brusco.
          const AttraGradientBackground(child: SizedBox.expand()),

        // 2) Oscurecido + viñeteado para legibilidad del formulario.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color(0xCC0C0D10), // arriba: 80% negro
                Color(0x990C0D10), // centro: ~60%
                Color(0xE60C0D10), // abajo: 90% (zona de botones)
              ],
              stops: <double>[0.0, 0.45, 1.0],
            ),
          ),
        ),

        // 4) Contenido del login.
        widget.child,
      ],
    );
  }
}
