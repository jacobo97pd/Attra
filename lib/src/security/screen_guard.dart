import 'package:flutter/foundation.dart';
import 'package:screen_protector/screen_protector.dart';

/// Protección anti-captura/grabación de pantalla para contenido sensible
/// (sobre todo las fotos bomba de un solo visionado).
///
/// Solo actúa en Android e iOS; en web y escritorio es **no-op** (las APIs
/// nativas no existen y el navegador no permite bloquear capturas), así que no
/// rompe el flujo de pruebas en web.
///
/// Realidad por plataforma (importante, no es garantía absoluta):
///  - **Android**: `FLAG_SECURE` bloquea capturas, grabación de pantalla y
///    oculta la app de "Recientes".
///  - **iOS**: Apple no permite bloquear capturas; se usa una capa segura que
///    oculta el contenido en la mayoría de capturas/grabaciones y se difumina
///    en el app switcher. Además se puede DETECTAR la captura (callback).
///  - **Web/escritorio**: imposible; queda como no-op.
class ScreenGuard {
  const ScreenGuard._();

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Activa la protección: evita capturas (Android) / capa segura (iOS) y
  /// difumina el contenido en el app switcher. Best-effort.
  static Future<void> enable() async {
    if (!isSupported) return;
    try {
      await ScreenProtector.preventScreenshotOn();
      await ScreenProtector.protectDataLeakageOn();
    } catch (_) {
      // Si el plugin no está disponible en runtime, no rompemos la UI.
    }
  }

  /// Desactiva la protección al salir del contenido sensible.
  static Future<void> disable() async {
    if (!isSupported) return;
    try {
      await ScreenProtector.preventScreenshotOff();
      await ScreenProtector.protectDataLeakageOff();
    } catch (_) {}
  }

  /// Registra callbacks de DETECCIÓN (solo iOS dispara de forma fiable): útil
  /// para avisar al emisor o marcar la foto bomba como capturada. En Android la
  /// captura ya está bloqueada, así que normalmente no se dispara.
  static void addCaptureListeners({
    required VoidCallback onScreenshot,
    required VoidCallback onScreenRecord,
  }) {
    if (!isSupported) return;
    try {
      ScreenProtector.addListener(
        onScreenshot,
        (bool isCaptured) {
          if (isCaptured) onScreenRecord();
        },
      );
    } catch (_) {}
  }

  static void removeCaptureListeners() {
    if (!isSupported) return;
    try {
      ScreenProtector.removeListener();
    } catch (_) {}
  }
}
