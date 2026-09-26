import 'place_names.dart';

/// Reglas PURAS de un viaje guardado en `users/{uid}.settings.travel`, las
/// mismas que aplica el backend al publicar la ficha
/// (functions/src/discovery.ts: `travelUntilMs`, `travelExpired`,
/// `centerMatchesDestination`) y tool/backfill_travel_geo.py. Si divergen, el
/// feed del viajero se mide desde un sitio y su ficha se publica en otro.
class TravelRules {
  const TravelRules._();

  /// Duración máxima creíble de un viaje. La app escribe 30 días
  /// (`UserRepository.travelDuration`); el resto es margen. Un fin más lejano
  /// solo sale de un documento escrito a mano (`settings` no valida tipos) y
  /// el backend lo trata como caducado: el cliente hace lo mismo para no
  /// seguir "de viaje" mientras los demás ya le ven en casa.
  static const Duration maxTravelSpan = Duration(days: 90);

  /// Fin efectivo del viaje: el MÁS TARDÍO entre `untilAt` (Timestamp, el
  /// nuevo) y el `until` ISO de versiones anteriores.
  ///
  /// Antes mandaba `untilAt`: una versión antigua que reactivaba el viaje
  /// solo renovaba `until`, el `untilAt` viejo ganaba y el viaje recién puesto
  /// salía caducado (aviso "Tu viaje ha terminado" y apagado). La app nueva
  /// escribe los dos con el mismo valor.
  static DateTime? effectiveUntil(DateTime? untilAt, DateTime? until) {
    if (untilAt == null) return until;
    if (until == null) return untilAt;
    return until.isAfter(untilAt) ? until : untilAt;
  }

  /// Pasó la fecha, o está tan lejos que no es creíble. Sin fecha = vigente.
  static bool isOver(DateTime? until, DateTime now) =>
      until != null &&
      (!until.isAfter(now) || until.isAfter(now.add(maxTravelSpan)));

  /// ¿El centro guardado (`lat/lng`) es el del destino ACTUAL?
  ///
  /// Las versiones anteriores cambian ciudad o país con un merge que no toca
  /// `lat/lng`, y un viaje a un país entero (la demo de App Review: "España"
  /// sin ciudad) heredaba el centro de un viaje anterior: el feed se medía
  /// desde Cádiz con 500 km de radio y dejaba fuera Barcelona o Bilbao. Así
  /// que:
  ///  - sin ciudad no hay centro (un país entero no lo tiene por diseño);
  ///  - `geoCity`/`geoIso2`, la ciudad y el ISO2 para los que se resolvió,
  ///    tienen que casar con los de ahora. Si no existen (centros guardados
  ///    antes de estos campos) basta con que haya ciudad.
  static bool centerMatchesDestination({
    required Object? city,
    required Object? iso2,
    Object? geoCity,
    Object? geoIso2,
  }) {
    final String dest = PlaceNames.normalize(city is String ? city : '');
    if (dest.isEmpty) return false;
    if (geoCity is String && PlaceNames.normalize(geoCity) != dest) {
      return false;
    }
    if (geoIso2 is String && normalizeIso2(geoIso2) != normalizeIso2(iso2)) {
      return false;
    }
    return true;
  }

  /// ISO2 en mayúsculas, o '' si no lo es (igual que `normalizeIso2` del
  /// backend).
  static String normalizeIso2(Object? value) {
    final String s = value is String ? value.trim().toUpperCase() : '';
    return RegExp(r'^[A-Z]{2}$').hasMatch(s) ? s : '';
  }
}
