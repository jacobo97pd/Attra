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

  /// Idioma FIJO de los resultados. Sin él, el sistema contesta en el idioma
  /// del teléfono: un iPhone en catalán guardaba 'Espanya', uno en alemán
  /// 'Spanien', y con el país comparado por nombre esa gente desaparecía del
  /// feed de su propia ciudad. El país ya se compara por ISO2, pero el nombre
  /// sigue saliendo en fichas y banners y tiene que ser estable.
  static const String localeIdentifier = 'es_ES';

  @override
  Future<ResolvedPlace?> resolve({
    required double latitude,
    required double longitude,
  }) async {
    // En web no hay geocodificador de plataforma: se sale antes de tocar el
    // canal, que ahí lanzaría.
    if (kIsWeb) return null;
    try {
      // En iOS el plugin guarda el idioma en Dart y lo manda en CADA llamada;
      // en Android lo fija en el Geocoder nativo. Llamarlo siempre cubre los
      // dos y no cuesta nada.
      await setLocaleIdentifier(localeIdentifier);
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
      ]
          .firstWhere(
            (String? v) => (v ?? '').trim().isNotEmpty,
            orElse: () => '',
          )!
          .trim();
      final String iso2 = (m.isoCountryCode ?? '').trim().toUpperCase();
      return ResolvedPlace(
        city: city,
        countryName: (m.country ?? '').trim(),
        // Solo un ISO2 de verdad: algún geocodificador devuelve vacío o un
        // código raro, y publicarlo partiría el país en dos claves.
        countryIso2: RegExp(r'^[A-Z]{2}$').hasMatch(iso2) ? iso2 : '',
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
