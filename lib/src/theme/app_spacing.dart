import 'package:flutter/widgets.dart';

/// Espaciados y radios constantes (escala 4pt). Úsalos en vez de números sueltos.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  // Radios con jerarquía: controles < tarjetas < superficies destacadas.
  // `radiusPill` se reserva para chips, badges y controles segmentados.
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  static const double radiusXl = 28;
  static const double radiusPill = 999;

  static const EdgeInsets screen = EdgeInsets.all(lg);
  static const EdgeInsets card = EdgeInsets.all(lg);
}
