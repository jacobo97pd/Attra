import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';

import '../domain/resolved_place.dart';

/// Geocodificación inversa con el geocodificador DEL SISTEMA (CLGeocoder en
/// iOS, Geocoder en Android).
///
/// Por qué el del sistema y no un servicio propio: no necesita clave de API ni
/// cuenta de facturación, y las coordenadas no salen de la plataforma que ya
/// las tiene. Mandar la posición de nuestros usuarios a un tercero para
/// averiguar el nombre de su ciudad sería empeorar su privacidad a cambio de
/// nada.
///
/// iOS limita CLGeocoder por tasa (del orden de decenas de peticiones por
/// hora). Por eso esto se llama SOLO cuando la persona se ha movido de verdad,
/// no en cada arranque: quien decide es la política de refresco.
class PlatformPlaceResolver implements PlaceResolver {
  const PlatformPlaceResolver();

  @override
  Future<ResolvedPlace?> resolve({
    required double latitude,
    required double longitude,
  }) async {
    // En web no hay geocodificador de plataforma: se sale antes de tocar el
    // canal, que ahí lanzaría.
    if (kIsWeb) return null;
    try {
      final List<Placemark> marks =
          await placemarkFromCoordinates(latitude, longitude);
      if (marks.isEmpty) return null;
      final Placemark m = marks.first;
      // `locality` es la ciudad; cuando viene vacía (zonas rurales, algunos
      // dispositivos) se cae a la subdivisión y luego a la provincia, en vez de
      // dejar la ciudad en blanco y borrar la que ya había.
      final String city = <String?>[
        m.locality,
        m.subAdministrativeArea,
        m.administrativeArea,
      ].firstWhere(
        (String? v) => (v ?? '').trim().isNotEmpty,
        orElse: () => '',
      )!
          .trim();
      return ResolvedPlace(
        city: city,
        countryName: (m.country ?? '').trim(),
        countryIso2: (m.isoCountryCode ?? '').trim().toUpperCase(),
      );
    } catch (error) {
      // Sin red, sin servicio o pasado de tasa. No poder nombrar la ciudad NO
      // puede impedir guardar unas coordenadas buenas: se devuelve null y quien
      // llama conserva el sitio anterior.
      debugPrint('[geo] no se pudo resolver la ciudad: $error');
      return null;
    }
  }
}
