import 'package:flutter/material.dart';

/// Paleta centralizada de Attra: oscura, premium y con intención.
/// Única fuente de verdad de color — las pantallas NO deben hardcodear colores.
///
/// Paleta ganadora (deseo + sofisticación + confianza + premium):
///   Fondo principal   Negro Attra   #0E0E10
///   Superficies/cards Carbón        #1A1A1D
///   Texto principal   Blanco cálido #FFFEFD
///   Texto secundario  Gris suave    #A7A7AD
///   CTA principal     Rojo coral    #FF4F68   (acción/botones → attraRed)
///   Like / deseo      Rojo vino     #D71945   (wineRed)
///   Premium           Champagne     #D8B76E   (gold)
///   Seguridad         Azul noche    #1E2A44   (nightBlue)
///   Match positivo    Verde suave   #4E8F70   (success)
///   IA Pro            Violeta       #6C4DFF / Morado #3A2449  (solo IA)
class AppColors {
  const AppColors._();

  // --- Fondos (negro Attra / carbón) ---
  static const Color black = Color(0xFF0E0E10); // negro Attra (scaffold)
  static const Color surface = Color(0xFF1A1A1D); // carbón (cards)
  static const Color surfaceHigh = Color(0xFF232327); // carbón elevado
  static const Color surfaceLine = Color(0xFF2E2E34); // bordes/divisores

  // --- Acción principal: rojo coral (CTA) ---
  // `attraRed` es el acento de acción de toda la app => rojo coral #FF4F68.
  static const Color attraRed = Color(0xFFFF4F68); // CTA principal (coral)
  static const Color attraRedDeep = Color(0xFFD71945); // presionado / profundo
  static const Color coral = Color(0xFFFF5A6E); // coral claro (gradientes)

  // --- Like / deseo: rojo vino ---
  static const Color wineRed = Color(0xFFD71945); // like / deseo / hearts
  static const Color wine = Color(0xFF1C0E14); // maroon oscuro (fondos/tintes)

  // --- Texto (blanco cálido + grises) ---
  static const Color textPrimary = Color(0xFFFFFEFD); // blanco cálido
  static const Color textSecondary = Color(0xFFA7A7AD); // gris suave
  static const Color textMuted = Color(0xFF6E707A);

  // --- Acentos de estado / semánticos ---
  static const Color gold = Color(0xFFD8B76E); // Champagne (premium/Plus)
  static const Color success = Color(0xFF4E8F70); // Verde suave (match sano)
  static const Color nightBlue = Color(0xFF1E2A44); // Azul noche (seguridad)
  static const Color danger = Color(0xFFE5484D); // error (rojo, no CTA)

  // --- IA Pro (SOLO IA: no usar en el resto de la app) ---
  static const Color aiViolet = Color(0xFF6C4DFF); // violeta tecnológico
  static const Color aiPurpleDark = Color(0xFF3A2449); // morado oscuro

  // --- Degradados de marca ---
  /// Fondo premium oscuro con matiz vino sutil (pantallas/overlays).
  static const List<Color> brandBackground = <Color>[
    Color(0xFF120A0E),
    Color(0xFF1A0E14),
    Color(0xFF0E0E10),
  ];

  /// Degradado de acción (botones/CTA destacados): vino → coral → coral claro.
  static const List<Color> action = <Color>[
    wineRed,
    attraRed,
    coral,
  ];

  /// Degradado EMOCIONAL de match: deseo → emoción → premio.
  /// (#D71945 → #FF5A6E → #D8B76E) — exclusivo de la pantalla de match.
  static const List<Color> match = <Color>[
    Color(0xFFD71945),
    Color(0xFFFF5A6E),
    Color(0xFFD8B76E),
  ];

  /// Degradado Attra Plus: champagne (acceso prioritario). Botón claro → usar
  /// texto oscuro para legibilidad (ver AttraPrimaryButton.foregroundColor).
  static const List<Color> plus = <Color>[
    Color(0xFFE6C77F),
    Color(0xFFC99B45),
  ];

  /// Degradado Attra Pro: negro → vino (premium, sin violeta).
  static const List<Color> pro = <Color>[
    Color(0xFF1C0E14),
    wineRed,
  ];

  /// Degradado IA Pro (SOLO IA): morado oscuro → violeta tecnológico.
  static const List<Color> ai = <Color>[
    aiPurpleDark,
    aiViolet,
  ];

  /// Velo para legibilidad sobre fotos (de transparente a negro).
  static const List<Color> photoScrim = <Color>[
    Colors.transparent,
    Colors.transparent,
    Color(0xCC000000),
  ];
}
