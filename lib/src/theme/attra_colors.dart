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
    required this.accent,
    required this.accentDeep,
    required this.accentSoft,
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

  /// Acento del tema. En OSCURO es el coral de marca; en CLARO ("Piedra") es un
  /// pizarra sobrio. Se consume vía `AppTheme._build` (colorScheme.primary,
  /// botones, chips, nav, inputs…), de modo que todo el chrome Material se tiñe
  /// según el tema sin tocar cada widget.
  final Color accent;

  /// Variante profunda del acento (estados pulsados, gradiente).
  final Color accentDeep;

  /// Variante suave del acento (fondos/tintes, ~10-20% opacidad ya resuelta).
  final Color accentSoft;

  /// Color de contraste para colocar SOBRE [accent] (texto/icono de botones).
  Color get onAccent =>
      accent.computeLuminance() > 0.55 ? const Color(0xFF2C3139) : Colors.white;

  /// Paleta OSCURA: idéntica a la actual (coral de marca sobre grafito).
  static const AttraColors dark = AttraColors(
    bg: Color(0xFF0E0E10),
    surface: Color(0xFF1A1A1D),
    surfaceHigh: Color(0xFF232327),
    surfaceLine: Color(0xFF2E2E34),
    textPrimary: Color(0xFFFFFEFD),
    textSecondary: Color(0xFFA7A7AD),
    textMuted: Color(0xFF6E707A),
    accent: Color(0xFFFF4F68), // coral de marca
    accentDeep: Color(0xFFD71945),
    accentSoft: Color(0x33FF4F68),
  );

  /// Paleta CLARA = "Piedra": blanco frío + tonos piedra suaves, con acento
  /// PIZARRA sobrio (no coral), sereno y minimalista.
  static const AttraColors light = AttraColors(
    bg: Color(0xFFF3F5F7), // blanco frío piedra (scaffold)
    surface: Color(0xFFFFFFFF), // tarjetas blancas
    surfaceHigh: Color(0xFFE7EAEF), // inputs/chips
    surfaceLine: Color(0xFFDADEE5), // bordes
    textPrimary: Color(0xFF2C3139), // pizarra oscuro
    textSecondary: Color(0xFF737A85), // gris azulado medio
    textMuted: Color(0xFFA6ADB8), // gris piedra suave
    accent: Color(0xFF8E99A8), // pizarra sobrio (acento Piedra)
    accentDeep: Color(0xFF6D798B), // pizarra profundo (pulsado)
    accentSoft: Color(0xFFE6EAF0), // pizarra muy suave (tintes)
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
    Color? accent,
    Color? accentDeep,
    Color? accentSoft,
  }) {
    return AttraColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      surfaceLine: surfaceLine ?? this.surfaceLine,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      accentDeep: accentDeep ?? this.accentDeep,
      accentSoft: accentSoft ?? this.accentSoft,
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
      accent: Color.lerp(accent, other.accent, t)!,
      accentDeep: Color.lerp(accentDeep, other.accentDeep, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
    );
  }
}

/// Acceso cómodo: `context.colors.bg`, `context.colors.textPrimary`…
/// Si por lo que sea no hay extensión registrada, cae a la paleta oscura.
extension AttraColorsX on BuildContext {
  AttraColors get colors =>
      Theme.of(this).extension<AttraColors>() ?? AttraColors.dark;
}
