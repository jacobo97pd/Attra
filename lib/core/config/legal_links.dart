import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Enlaces legales públicos de Attra (Firebase Hosting).
///
/// ÚNICA fuente de verdad de las URLs legales de la app. Apple exige
/// (Guideline 3.1.2(c) y 1.2) enlaces FUNCIONALES al EULA y a la política de
/// privacidad dentro de la app: en el login (antes de registrarse), en el
/// paywall de suscripciones y en Ajustes.
///
/// Las mismas URLs deben estar en App Store Connect:
/// - Privacy Policy URL  -> [privacyUrl]
/// - App Description EULA -> [eulaUrl] (licencia estándar de Apple)
/// - Condiciones de la comunidad -> [termsUrl]
class LegalLinks {
  const LegalLinks._();

  /// Raíz del sitio público (Firebase Hosting del proyecto attra-database).
  static const String baseUrl = 'https://attra-database.web.app';

  /// Versión de las condiciones aceptadas en el login. Se guarda en
  /// `users/{uid}/consentRecords`. Súbela al publicar nuevas condiciones.
  static const String termsVersion = '2026-09-13';

  /// Condiciones de uso del servicio y normas de la comunidad.
  /// Incluye la cláusula de tolerancia cero con contenido ofensivo y usuarios
  /// abusivos que exige la Guideline 1.2.
  static const String termsUrl = '$baseUrl/terms.html';

  /// Contrato de licencia estándar aplicable a la app distribuida por Apple.
  static const String eulaUrl =
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

  /// Política de privacidad.
  static const String privacyUrl = '$baseUrl/privacy.html';

  /// Estándares de seguridad infantil.
  static const String childSafetyUrl = '$baseUrl/child-safety.html';

  /// Soporte / contacto.
  static const String supportUrl = '$baseUrl/support.html';

  /// Eliminación de cuenta y datos.
  static const String deleteAccountUrl = '$baseUrl/delete-account.html';

  /// Abre un enlace legal en el navegador externo. Devuelve false si el
  /// dispositivo no pudo abrirlo (el llamante avisa al usuario).
  static Future<bool> open(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('LegalLinks.open falló para $url: $error');
      return false;
    }
  }
}
