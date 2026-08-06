import 'package:flutter/material.dart';

/// Estado GLOBAL del modo de tema (claro/oscuro/sistema). La MaterialApp escucha
/// este notifier para repintar al instante; la persistencia vive en los ajustes
/// del usuario (`settings['appearance.themeMode']`) y se vuelca aquí al cargar
/// la sesión o al cambiar el toggle de Ajustes.
///
/// El DEFAULT es OSCURO, no "seguir al sistema": Attra es una marca de fondo
/// negro (login, splash, feed) y arrancar en claro por seguir el ajuste del
/// móvil rompía esa identidad para la mayoría de usuarios. Quien prefiera claro
/// o seguir al sistema lo elige en Ajustes → Apariencia, y esa elección manda.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController([super.initial = ThemeMode.dark]);

  /// Singleton sencillo (sin dependencias). Se lee en app.dart.
  static final ThemeController instance = ThemeController();

  void set(ThemeMode mode) {
    if (value != mode) value = mode;
  }

  /// Mapea el string guardado en ajustes a ThemeMode.
  ///
  /// Sin valor guardado (usuario nuevo, o ajuste ausente) el default es OSCURO.
  /// Solo se sale de ahí si el usuario lo eligió explícitamente.
  static ThemeMode fromWire(Object? raw) {
    switch ((raw ?? '').toString().trim().toLowerCase()) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.dark;
    }
  }

  static String toWire(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
      case ThemeMode.dark:
        return 'dark';
    }
  }
}
