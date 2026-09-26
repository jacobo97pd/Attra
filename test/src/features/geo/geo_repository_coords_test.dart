import 'dart:convert';
import 'dart:io';

import 'package:attra/src/features/geo/data/geo_repository.dart';
import 'package:attra/src/features/geo/data/travel_destination_resolvers.dart';
import 'package:attra/src/features/geo/domain/travel_destination_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Centros de ciudad del dataset offline: son el origen del feed de quien
/// viaja. Si nombres y coordenadas salieran de descargas distintas, cada índice
/// podría apuntar a otra ciudad y el viaje a Cádiz acabaría centrado en
/// cualquier otro sitio sin que nada fallara.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final GeoRepository geo = GeoRepository.instance;

  void expectNear(({double lat, double lng})? p, double lat, double lng) {
    expect(p, isNotNull);
    expect(p!.lat, closeTo(lat, 0.02));
    expect(p.lng, closeTo(lng, 0.02));
  }

  test('nombres y coordenadas están alineados en TODOS los países', () {
    final List<dynamic> countries =
        json.decode(File('assets/geo/countries.json').readAsStringSync())
            as List<dynamic>;
    expect(countries, isNotEmpty);
    for (final dynamic c in countries) {
      final String iso2 = (c as Map<String, dynamic>)['iso2'] as String;
      final List<dynamic> names =
          json.decode(File('assets/geo/cities/$iso2.json').readAsStringSync())
              as List<dynamic>;
      final List<dynamic> coords =
          json.decode(File('assets/geo/coords/$iso2.json').readAsStringSync())
              as List<dynamic>;
      expect(coords.length, names.length,
          reason: '$iso2: nombres y coordenadas desalineados');
      expect(c['cityCount'], names.length, reason: iso2);
      for (final dynamic e in coords) {
        if (e == null) continue;
        final List<dynamic> p = e as List<dynamic>;
        expect((p[0] as num).abs(), lessThanOrEqualTo(9000), reason: iso2);
        expect((p[1] as num).abs(), lessThanOrEqualTo(18000), reason: iso2);
      }
    }
  });

  test('ES/Cádiz y ES/Cadiz dan el mismo centro (~36.53, -6.29)', () async {
    expectNear(await geo.cityCoordinates('ES', 'Cádiz'), 36.53, -6.29);
    expectNear(await geo.cityCoordinates('ES', 'Cadiz'), 36.53, -6.29);
    expectNear(await geo.cityCoordinates('es', ' cadiz '), 36.53, -6.29);
  });

  test('otras ciudades del caso: Madrid, Jerez y El Puerto', () async {
    expectNear(await geo.cityCoordinates('ES', 'Madrid'), 40.42, -3.70);
    expectNear(
        await geo.cityCoordinates('ES', 'Jerez de la Frontera'), 36.69, -6.14);
    expectNear(await geo.cityCoordinates('ES', 'El Puerto de Santa Maria'),
        36.64, -6.26);
  });

  test('ciudad inventada, país vacío o ambigua: null', () async {
    expect(await geo.cityCoordinates('ES', 'Cadizz'), isNull);
    expect(await geo.cityCoordinates('', 'Cadiz'), isNull);
    // Homónimos a cientos de km en el mismo país: sin centro fiable.
    expect(await geo.cityCoordinates('US', 'Springfield'), isNull);
  });

  test('país por nombre en cualquier idioma', () async {
    expect(await geo.iso2ForCountryName('España'), 'ES');
    expect(await geo.iso2ForCountryName('Spain'), 'ES');
    expect(await geo.iso2ForCountryName('Espanya'), 'ES');
    expect(await geo.iso2ForCountryName('Spanien'), 'ES');
    expect(await geo.iso2ForCountryName('Grecia'), 'GR');
    expect(await geo.iso2ForCountryName('Narnia'), '');
  });

  test('la cadena offline sitúa el destino con el dataset', () async {
    final TravelDestination? d = await buildOfflineTravelDestinationResolver()
        .resolve(iso2: 'ES', city: 'Cádiz', countryName: 'Spain');
    expect(d, isNotNull);
    expect(d!.source, TravelGeoSource.asset);
    expect(d.latitude, closeTo(36.53, 0.02));
    // Registro antiguo sin ISO2: se deduce del nombre del país.
    final TravelDestination? legacy =
        await buildOfflineTravelDestinationResolver()
            .resolve(iso2: '', city: 'Cadiz', countryName: 'España');
    expect(legacy?.longitude, closeTo(-6.29, 0.02));
    // A un país entero no se le pone centro (ocultaría al viajero en casi todo
    // el país con el radio de cada uno).
    expect(
        await buildOfflineTravelDestinationResolver()
            .resolve(iso2: 'ES', city: '', countryName: 'Spain'),
        isNull);
  });
}
