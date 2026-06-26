import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Servicio de anuncios (AdMob). Inicializa el SDK y resuelve el ad unit id del
/// anuncio nativo según plataforma. En DEBUG usa los IDs de TEST de Google
/// (siempre rellenan, no generan ingresos ni riesgo de baneo). En release se
/// usan los reales (defínelos al publicar — ver constantes abajo).
///
/// Solo móvil: en web/desktop es no-op (AdMob no aplica).
class AdsService {
  AdsService._();
  static final AdsService instance = AdsService._();

  bool _initialized = false;
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  // --- IDs de TEST de Google (válidos en cualquier app, solo desarrollo) ---
  static const String _testNativeAndroid =
      'ca-app-pub-3940256099942544/2247696110';
  static const String _testNativeIos = 'ca-app-pub-3940256099942544/3986624511';

  // --- IDs REALES (rellénalos con los de tu cuenta AdMob al publicar) ---
  static const String _prodNativeAndroid = '';
  static const String _prodNativeIos = '';

  Future<void> init() async {
    if (_initialized || !supported) return;
    _initialized = true;
    try {
      await MobileAds.instance.initialize();
    } catch (e) {
      if (kDebugMode) debugPrint('[ads] init falló -> $e');
    }
  }

  /// Ad unit id del anuncio nativo. Test en debug; real en release (si está
  /// definido, si no cae al test para no romper).
  String get nativeAdUnitId {
    final bool android = !kIsWeb && Platform.isAndroid;
    if (kReleaseMode) {
      final String prod = android ? _prodNativeAndroid : _prodNativeIos;
      if (prod.isNotEmpty) return prod;
    }
    return android ? _testNativeAndroid : _testNativeIos;
  }
}
