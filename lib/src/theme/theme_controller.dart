import 'package:flutter/material.dart';

/// Estado GLOBAL del modo de tema (claro/oscuro/sistema). La MaterialApp escucha
/// este notifier para repintar al instante; la persistencia vive en los ajustes
/// del usuario (`settings['appearance.themeMode']`) y se vuelca aquí al cargar
/// la sesión o al cambiar el toggle de Ajustes.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController([super.initial = ThemeMode.dark]);

  /// Singleton sencillo (sin dependencias). Se lee en app.dart.
  static final ThemeController instance = ThemeController();

  void set(ThemeMode mode) {
    if (value != mode) value = mode;
  }

  /// Mapea el string guardado en ajustes a ThemeMode (default: oscuro).
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
