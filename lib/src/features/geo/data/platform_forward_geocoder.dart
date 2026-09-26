import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';

import '../../auth/data/platform_place_resolver.dart';
import '../domain/travel_destination_resolver.dart';

/// Geocodificación DIRECTA ("Cádiz, Spain" → coordenadas) con el
/// geocodificador del sistema. Segunda fuente de la cadena: solo se llega aquí
/// si la ciudad no tiene centro en el dataset offline (homónimos lejanos).
///
/// En web no existe (el plugin no tiene implementación) y en iOS CLGeocoder va
/// por tasa: por eso va detrás del dataset y nunca lanza.
class PlatformForwardGeocoder implements TravelDestinationResolver {
  const PlatformForwardGeocoder();

  @override
  Future<TravelDestination?> resolve({
    required String iso2,
    required String city,
    String countryName = '',
  }) async {
    if (kIsWeb) return null;
    final String query = <String>[city.trim(), countryName.trim()]
        .where((String s) => s.isNotEmpty)
        .join(', ');
    if (query.isEmpty) return null;
    try {
      await setLocaleIdentifier(PlatformPlaceResolver.localeIdentifier);
      final List<Location> found = await locationFromAddress(query);
      if (found.isEmpty) return null;
      final Location first = found.first;
      if (!TravelDestination.isValid(first.latitude, first.longitude)) {
        return null;
      }
      return TravelDestination(
        latitude: first.latitude,
        longitude: first.longitude,
        source: TravelGeoSource.device,
      );
    } catch (error) {
      // Sin red, sin servicio o pasado de tasa: la cadena sigue con la
      // siguiente fuente.
      debugPrint('[geo] no se pudo situar el destino: $error');
      return null;
    }
  }
}
