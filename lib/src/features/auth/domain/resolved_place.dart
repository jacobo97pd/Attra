/// Ciudad y país resueltos a partir de unas coordenadas.
///
/// POR QUÉ EXISTE: `profile.currentCity` y `profile.currentCountryName` los
/// escribía SOLO el selector manual del onboarding. Al hacer que las
/// coordenadas se refresquen solas, esos dos campos se quedaron desfasados
/// respecto a ellas — y eso es PEOR que tenerlo todo rancio a la vez: al cruzar
/// una frontera tus coordenadas dicen Lisboa y tu país sigue diciendo España,
/// así que la regla de país te enseña a españoles y la de radio los descarta a
/// todos. El feed se vacía y, sobre todo, los demás dejan de verte, porque el
/// país que publicas es de otro sitio.
class ResolvedPlace {
  const ResolvedPlace({
    required this.city,
    required this.countryName,
    required this.countryIso2,
  });

  final String city;
  final String countryName;

  /// ISO-3166 alfa-2 en mayúsculas. Vacío si el sistema no lo devolvió.
  final String countryIso2;

  /// Solo sirve si trae país: la ciudad sin país no permite filtrar y
  /// sobrescribir con la mitad del dato es peor que no tocar nada.
  bool get isUsable => countryName.trim().isNotEmpty;

  @override
  String toString() => 'ResolvedPlace($city, $countryName, $countryIso2)';
}

/// Quién traduce coordenadas a un sitio.
///
/// Es una interfaz porque la implementación real habla con el geocodificador
/// del sistema (CLGeocoder en iOS, Geocoder en Android): canal nativo, que en
/// `flutter test` no existe. Todo lo que decide QUÉ hacer con el resultado vive
/// fuera y sí se prueba.
abstract class PlaceResolver {
  /// `null` si no se pudo resolver. NUNCA lanza: no poder nombrar la ciudad no
  /// puede impedir que se guarden unas coordenadas buenas.
  Future<ResolvedPlace?> resolve({
    required double latitude,
    required double longitude,
  });
}

/// Decide si merece la pena reescribir ciudad y país.
///
/// Se evita la escritura cuando el sitio no ha cambiado: cada una arrastra una
/// republicación de `discovery` por el trigger de backend, y el geocodificador
/// de iOS además está limitado por tasa.
bool shouldUpdatePlace({
  required ResolvedPlace? resolved,
  required String currentCity,
  required String currentCountryName,
}) {
  if (resolved == null || !resolved.isUsable) return false;
  final String city = resolved.city.trim().toLowerCase();
  final String country = resolved.countryName.trim().toLowerCase();
  return city != currentCity.trim().toLowerCase() ||
      country != currentCountryName.trim().toLowerCase();
}
