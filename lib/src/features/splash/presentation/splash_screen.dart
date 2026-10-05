import 'package:flutter/material.dart';

import '../../../widgets/attra_backgrounds.dart';
import '../../../widgets/attra_loader.dart';

/// Pantalla de arranque: se ve mientras se resuelve la sesión.
///
/// Usa [AttraLogoLoader], el MISMO "logo respirando" de los overlays de subida
/// (foto, vídeo...). Antes el splash metía el símbolo en una tarjeta con
/// borde y sombra fija: quedaba como una miniatura recortada, no como la
/// marca. Al reutilizar el loader de marca, el primer y el enésimo "cargando"
/// de la app se ven igual, y cualquier retoque futuro del loader (tamaño,
/// velocidad, halo) se aplica aquí sin tocar nada.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _didPrecacheLogo = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrecacheLogo) return;
    _didPrecacheLogo = true;
    precacheImage(const AssetImage('assets/images/ATTRA.png'), context);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: AttraGradientBackground(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        child: Center(
          child: AttraLogoLoader(
            size: 108,
            label: 'Conexiones que importan',
          ),
        ),
      ),
    );
  }
}
