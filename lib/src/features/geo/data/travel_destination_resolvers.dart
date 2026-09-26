import '../domain/travel_destination_resolver.dart';
import 'geo_repository.dart';
import 'platform_forward_geocoder.dart';
import 'travel_destination_callable.dart';

/// Primera fuente: el dataset offline (assets/geo/coords, alineado con
/// assets/geo/cities). Sin red, en web y en tests.
class AssetTravelDestinationResolver implements TravelDestinationResolver {
  AssetTravelDestinationResolver({GeoRepository? geo})
      : _geo = geo ?? GeoRepository.instance;

  final GeoRepository _geo;

  @override
  Future<TravelDestination?> resolve({
    required String iso2,
    required String city,
    String countryName = '',
  }) async {
    // Registros antiguos sin ISO2: se deduce del nombre del país guardado.
    final String code = iso2.trim().isNotEmpty
        ? iso2.trim().toUpperCase()
        : await _geo.iso2ForCountryName(countryName);
    if (code.isEmpty) return null;
    final ({double lat, double lng})? point =
        await _geo.cityCoordinates(code, city);
    if (point == null) return null;
    return TravelDestination(
      latitude: point.lat,
      longitude: point.lng,
      source: TravelGeoSource.asset,
    );
  }
}

/// Cadena completa para ACTIVAR un viaje (y la auto-reparación de la sesión):
/// dataset → geocodificador del sistema → servidor.
TravelDestinationResolver buildTravelDestinationResolver() =>
    ChainedTravelDestinationResolver(<TravelDestinationResolver>[
      AssetTravelDestinationResolver(),
      const PlatformForwardGeocoder(),
      CallableTravelDestinationResolver(),
    ]);

/// Solo el dataset: lo usa el feed para centrar un viaje antiguo sin
/// coordenadas guardadas. Pintar el feed no puede depender de la red ni gastar
/// cuota del geocodificador.
TravelDestinationResolver buildOfflineTravelDestinationResolver() =>
    ChainedTravelDestinationResolver(<TravelDestinationResolver>[
      AssetTravelDestinationResolver(),
    ]);
