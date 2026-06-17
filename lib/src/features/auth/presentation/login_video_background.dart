import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../theme/app_colors.dart';
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

class _LoginVideoBackgroundState extends State<LoginVideoBackground> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    // En algunas plataformas de escritorio video_player no está soportado;
    // dejamos el fallback al degradado.
    final VideoPlayerController controller =
        VideoPlayerController.asset(widget.asset);
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('LoginVideoBackground: no se pudo cargar el vídeo -> $e');
      }
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
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

        // 3) Tinte rojo sutil de marca encima del oscurecido.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.35),
              radius: 1.1,
              colors: <Color>[
                AppColors.attraRed.withValues(alpha: 0.10),
                Colors.transparent,
              ],
            ),
          ),
        ),

        // 4) Contenido del login.
        widget.child,
      ],
    );
  }
}
