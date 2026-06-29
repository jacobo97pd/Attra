import 'package:flutter/material.dart';

/// Colores NEUTROS dependientes del tema (claro/oscuro). Los colores de MARCA
/// (attraRed, coral, gold, gradientes…) viven en [AppColors] y NO cambian con el
/// modo (identidad de marca). Aquí solo los fondos/superficies/texto, que sí
/// se invierten entre claro y oscuro.
///
/// Uso: `context.colors.bg`, `context.colors.surface`, etc. (ver extension
/// abajo). Se registra como ThemeExtension en AppTheme.light/dark.
@immutable
class AttraColors extends ThemeExtension<AttraColors> {
  const AttraColors({
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.surfaceLine,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
  });

  /// Fondo principal (scaffold).
  final Color bg;

  /// Superficie de tarjetas/sheets.
  final Color surface;

  /// Superficie elevada (inputs, chips, tiles).
  final Color surfaceHigh;

  /// Bordes y divisores.
  final Color surfaceLine;

  /// Texto principal.
  final Color textPrimary;

  /// Texto secundario.
  final Color textSecondary;

  /// Texto atenuado (hints, captions).
  final Color textMuted;

  /// Paleta OSCURA: idéntica a la actual (no cambia nada en modo oscuro).
  static const AttraColors dark = AttraColors(
    bg: Color(0xFF0E0E10),
    surface: Color(0xFF1A1A1D),
    surfaceHigh: Color(0xFF232327),
    surfaceLine: Color(0xFF2E2E34),
    textPrimary: Color(0xFFFFFEFD),
    textSecondary: Color(0xFFA7A7AD),
    textMuted: Color(0xFF6E707A),
  );

  /// Paleta CLARA: misma intención premium, invertida y suave (no blanco puro
  /// agresivo). Mantiene contraste accesible.
  static const AttraColors light = AttraColors(
    bg: Color(0xFFF6F6F8), // gris muy claro (scaffold)
    surface: Color(0xFFFFFFFF), // tarjetas blancas
    surfaceHigh: Color(0xFFEDEDF1), // inputs/chips
    surfaceLine: Color(0xFFE0E0E6), // bordes
    textPrimary: Color(0xFF15151A), // casi negro cálido
    textSecondary: Color(0xFF565660), // gris medio
    textMuted: Color(0xFF9A9AA3), // gris suave
  );

  @override
  AttraColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceHigh,
    Color? surfaceLine,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
  }) {
    return AttraColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      surfaceLine: surfaceLine ?? this.surfaceLine,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
    );
  }

  @override
  AttraColors lerp(ThemeExtension<AttraColors>? other, double t) {
    if (other is! AttraColors) return this;
    return AttraColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      surfaceLine: Color.lerp(surfaceLine, other.surfaceLine, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
    );
  }
}

/// Acceso cómodo: `context.colors.bg`, `context.colors.textPrimary`…
/// Si por lo que sea no hay extensión registrada, cae a la paleta oscura.
extension AttraColorsX on BuildContext {
  AttraColors get colors =>
      Theme.of(this).extension<AttraColors>() ?? AttraColors.dark;
}
