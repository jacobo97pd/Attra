import 'place_names.dart';

/// De dónde salió el centro del destino de un viaje. Es lo que se guarda en
/// `settings.travel.geoSource` ('asset' | 'device' | 'server' | 'none').
enum TravelGeoSource {
  /// Dataset offline empaquetado (assets/geo/coords): funciona sin red, en web
  /// y en tests. Es la fuente principal.
  asset,

  /// Geocodificador del sistema (solo móvil, limitado por tasa en iOS).
  device,

  /// Callable `resolveTravelDestination` (Places en servidor, sirve en web).
  server,

  /// No se pudo situar: el viaje se guarda igual, a nivel de país.
  none;

  String get wireName => name;

  static TravelGeoSource fromWire(Object? value) {
    for (final TravelGeoSource s in TravelGeoSource.values) {
      if (s.name == value) return s;
    }
    return TravelGeoSource.none;
  }
}

/// Centro de la ciudad de destino. NUNCA es la ubicación real del usuario.
class TravelDestination {
  const TravelDestination({
    required this.latitude,
    required this.longitude,
    required this.source,
  });

  final double latitude;
  final double longitude;
  final TravelGeoSource source;

  /// Coordenadas creíbles: finitas y dentro de rango. Todo lo que venga de
  /// fuera (geocodificador, callable, documento) pasa por aquí antes de usarse
  /// como centro del feed o de la ficha pública.
  static bool isValid(double? lat, double? lng) =>
      lat != null &&
      lng != null &&
      lat.isFinite &&
      lng.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180;

  @override
  String toString() => 'TravelDestination($latitude, $longitude, $source)';
}

/// Resultado de guardar un viaje, para que la hoja pueda avisar cuando la
/// ciudad no se ha podido situar (el feed se quedará en el país, con la ciudad
/// delante, en vez de centrarse en ella).
class TravelApplyResult {
  const TravelApplyResult({required this.located});

  /// true = el destino tiene centro (o se está apagando el viaje).
  final bool located;
}

/// Quién sitúa un destino (país + ciudad) en el mapa.
abstract class TravelDestinationResolver {
  /// null si no se pudo situar. NUNCA lanza: no poder situar la ciudad no
  /// puede impedir que se guarde el viaje (se queda a nivel de país).
  Future<TravelDestination?> resolve({
    required String iso2,
    required String city,
    String countryName = '',
  });
}

/// Prueba las fuentes EN ORDEN y se queda con la primera que acierta
/// (dataset offline → geocodificador del sistema → servidor). Recuerda lo
/// resuelto en memoria: el feed y la auto-reparación de la sesión preguntan por
/// el mismo destino y el geocodificador de iOS va por tasa.
class ChainedTravelDestinationResolver implements TravelDestinationResolver {
  ChainedTravelDestinationResolver(this._sources);

  final List<TravelDestinationResolver> _sources;
  final Map<String, TravelDestination> _cache = <String, TravelDestination>{};

  @override
  Future<TravelDestination?> resolve({
    required String iso2,
    required String city,
    String countryName = '',
  }) async {
    final String code = iso2.trim().toUpperCase();
    // Sin ISO2 (registros antiguos) vale el nombre del país: la fuente del
    // dataset lo traduce a código.
    final String country =
        code.isNotEmpty ? code : PlaceNames.normalize(countryName);
    final String key = '$country|${PlaceNames.normalize(city)}';
    // Un viaje a un país entero (sin ciudad) no tiene centro por diseño: un
    // centroide de país más el radio de cada uno ocultaría al viajero en casi
    // todo el país.
    if (country.isEmpty || PlaceNames.normalize(city).isEmpty) return null;
    final TravelDestination? cached = _cache[key];
    if (cached != null) return cached;
    for (final TravelDestinationResolver source in _sources) {
      TravelDestination? hit;
      try {
        hit = await source.resolve(
            iso2: code, city: city.trim(), countryName: countryName.trim());
      } catch (_) {
        hit = null;
      }
      if (hit != null &&
          TravelDestination.isValid(hit.latitude, hit.longitude)) {
        _cache[key] = hit;
        return hit;
      }
    }
    return null;
  }
}
