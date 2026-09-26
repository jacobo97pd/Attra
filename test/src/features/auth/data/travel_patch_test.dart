import 'package:attra/src/features/auth/data/user_repository.dart';
import 'package:attra/src/features/geo/domain/travel_destination_resolver.dart';
import 'package:attra/src/features/settings/domain/settings_catalog.dart';
import 'package:attra/src/features/settings/domain/setting_definition.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lo que se guarda en `users/{uid}.settings.travel` (contrato compartido con el
/// backend: discovery.ts y el barrido horario lo leen tal cual).
void main() {
  final DateTime now = DateTime.utc(2026, 9, 1, 12);

  test('activar con centro: lat/lng redondeados, origen y las DOS fechas', () {
    final Map<String, dynamic> t = UserRepository.buildTravelPatch(
      active: true,
      iso2: 'es',
      city: ' Cadiz ',
      country: 'Spain',
      latitude: 36.526712,
      longitude: -6.289134,
      geoSource: TravelGeoSource.asset,
      now: now,
    );

    expect(t['active'], isTrue);
    expect(t['iso2'], 'ES');
    expect(t['city'], 'Cadiz');
    expect(t['lat'], 36.5267);
    expect(t['lng'], -6.2891);
    expect(t['geoSource'], 'asset');
    // `until` (ISO) lo siguen leyendo las versiones anteriores de la app.
    expect(
        t['until'], now.add(UserRepository.travelDuration).toIso8601String());
    expect((t['untilAt'] as Timestamp).toDate().toUtc(),
        now.add(UserRepository.travelDuration));
  });

  test('activar sin centro: se guarda igual, a nivel de país', () {
    final Map<String, dynamic> t = UserRepository.buildTravelPatch(
      active: true,
      iso2: 'ES',
      city: 'Villanueva',
      country: 'Spain',
      geoSource: TravelGeoSource.server,
      now: now,
    );

    expect(t['lat'], isNull);
    expect(t['lng'], isNull);
    expect(t['geoSource'], 'none', reason: 'sin centro no hay origen');
  });

  test('apagar CONSERVA el destino y borra centro y fechas', () {
    final Map<String, dynamic> t = UserRepository.buildTravelPatch(
      active: false,
      iso2: 'ES',
      city: 'Cadiz',
      country: 'Spain',
      latitude: 36.53,
      longitude: -6.29,
      geoSource: TravelGeoSource.asset,
      now: now,
    );

    expect(t['active'], isFalse);
    expect(t['country'], 'Spain',
        reason: 'la hoja reabre con el destino puesto y se reactiva de un '
            'toque');
    expect(t['city'], 'Cadiz');
    expect(t['lat'], isNull);
    expect(t['until'], isNull);
    expect(t['untilAt'], isNull);
  });

  test('Ajustes ya no tiene un "Modo viaje" que no hacía nada', () {
    // Escribía `settings['location.travelMode']`, que nadie leía: salía apagado
    // estando de viaje y apagarlo no cambiaba ni el feed ni la ficha.
    final Iterable<String> keys =
        SettingsCatalog.allDefinitions.map((SettingDefinition d) => d.key);
    expect(keys, isNot(contains('location.travelMode')));
  });
}
