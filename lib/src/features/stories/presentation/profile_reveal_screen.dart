import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../widgets/attra_image.dart';

/// La RECOMPENSA del muro a ciegas: hecho el match, se revela quién es.
///
/// Durante todo Discover solo se han visto nombre, edad e historias. Esta
/// pantalla existe para que el desbloqueo se NOTE: la foto entra desenfocada y
/// se aclara, y de ahí se entra al perfil completo. Sin este paso, el match
/// desde el muro se sentía igual que un match cualquiera y la mecánica de "a
/// ciegas" no pagaba nada.
class ProfileRevealScreen extends StatefulWidget {
  const ProfileRevealScreen({
    super.key,
    required this.name,
    required this.age,
    required this.photoUrl,
    required this.onOpenProfile,
  });

  final String name;
  final int? age;
  final String photoUrl;

  /// Abre el perfil completo. Lo resuelve quien llama (el feed), para no meter
  /// la pantalla de perfil dentro del módulo de historias.
  final VoidCallback onOpenProfile;

  static Future<void> show(
    BuildContext context, {
    required String name,
    required int? age,
    required String photoUrl,
    required VoidCallback onOpenProfile,
  }) {
    AttraImage.precache(context, photoUrl);
    return Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => ProfileRevealScreen(
        name: name,
        age: age,
        photoUrl: photoUrl,
        onOpenProfile: onOpenProfile,
      ),
      transitionsBuilder: (_, Animation<double> animation, __, Widget child) =>
          FadeTransition(opacity: animation, child: child),
    ));
  }

  @override
  State<ProfileRevealScreen> createState() => _ProfileRevealScreenState();
}

class _ProfileRevealScreenState extends State<ProfileRevealScreen>
    with SingleTickerProviderStateMixin {
  /// Desenfoque inicial: suficiente para que no se distinga la cara.
  static const double _maxBlur = 28;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _label {
    final int? age = widget.age;
    if (age == null || age <= 0) return widget.name;
    return '${widget.name}, $age';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, Widget? child) {
              final double blur =
                  _maxBlur * (1 - Curves.easeOutCubic.transform(_controller.value));
              return ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: blur,
                  sigmaY: blur,
                  tileMode: TileMode.decal,
                ),
                child: child,
              );
            },
            child: AttraImage(
              url: widget.photoUrl,
              fit: BoxFit.cover,
              fallbackInitial:
                  widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
            ),
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.black.withValues(alpha: 0.45),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                  stops: const <double>[0, 0.45, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      tooltip: 'Cerrar',
                      icon:
                          const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Ya no vais a ciegas',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                      shadows: <Shadow>[
                        Shadow(blurRadius: 12, color: Colors.black87),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Has hecho match viendo solo lo que quiso contar. Ahora sí: mira quién es de verdad.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 15,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    key: const ValueKey<String>('reveal-open-profile'),
                    onPressed: widget.onOpenProfile,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Ver su perfil completo'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Ahora no',
                        style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
