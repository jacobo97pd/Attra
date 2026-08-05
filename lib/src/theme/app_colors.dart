import 'package:flutter/material.dart';

/// Colores de marca y semánticos de Attra.
///
/// Los neutros adaptativos viven en [AttraColors]. Estas constantes mantienen
/// compatibilidad con superficies deliberadamente oscuras (login, splash y
/// overlays) y con features que todavía no consumen la extensión de tema.
class AppColors {
  const AppColors._();

  // Neutros editoriales: una escala acromática, sobria y de alto contraste.
  static const Color black = Color(0xFF111111);
  static const Color surface = Color(0xFF1D1D1D);
  static const Color surfaceHigh = Color(0xFF2A2A2A);
  static const Color surfaceLine = Color(0xFF404040);

  // Marca: tinta, grafito y grises. Los aliases históricos se conservan para
  // no romper consumidores mientras toda la app migra a la paleta neutral.
  static const Color brandInk = Color(0xFF171717);
  static const Color brandGraphite = Color(0xFF343434);
  static const Color brandNeutral = Color(0xFF707070);
  static const Color brandSilver = Color(0xFFA6A6A6);
  static const Color attraRed = brandNeutral;
  static const Color attraRedDeep = brandInk;
  static const Color coral = brandSilver;

  // Like / deseo: negro y grafito, sin asociarlo a una alerta.
  static const Color wineRed = brandGraphite;
  static const Color wine = black;

  // Texto sobre fondos oscuros de marca.
  static const Color textPrimary = Color(0xFFFAFAFA);
  static const Color textSecondary = Color(0xFFC8C8C8);
  static const Color textMuted = Color(0xFF999999);

  // Acentos semánticos.
  static const Color gold = Color(0xFFC8A66A);
  static const Color success = Color(0xFF80A08B);
  static const Color nightBlue = Color(0xFF55706A);
  static const Color danger = Color(0xFFC53F4E);

  /// Tinte histórico del vídeo de acceso. Queda aislado para que neutralizar la
  /// aplicación no cambie ni el archivo ni la apariencia de ese fondo.
  static const Color loginVideoTint = Color(0xFFB4375D);

  // IA Pro: ciruela sobria, reservada para contexto IA.
  static const Color aiViolet = Color(0xFF8F789F);
  static const Color aiPurpleDark = Color(0xFF312636);

  /// Fondo oscuro editorial para splash, login y overlays de marca.
  static const List<Color> brandBackground = <Color>[
    Color(0xFF242424),
    Color(0xFF181818),
    black,
  ];

  /// Acción principal de marca: negro a grafito, con contraste AA en blanco.
  static const List<Color> action = <Color>[
    brandInk,
    brandGraphite,
  ];

  /// Exclusivo de momentos celebratorios de match.
  static const List<Color> match = <Color>[
    brandInk,
    brandGraphite,
    brandSilver,
  ];

  /// Membresía Plus: champagne, siempre con foreground oscuro.
  static const List<Color> plus = <Color>[
    Color(0xFFD7BA7D),
    Color(0xFFB78B43),
  ];

  /// Membresía Pro: tinta y grafito.
  static const List<Color> pro = <Color>[
    black,
    brandGraphite,
  ];

  /// IA Pro: ciruela, sin neón.
  static const List<Color> ai = <Color>[
    aiPurpleDark,
    aiViolet,
  ];

  /// Velo para legibilidad sobre fotografías.
  static const List<Color> photoScrim = <Color>[
    Colors.transparent,
    Colors.transparent,
    Color(0xCC000000),
  ];
}
