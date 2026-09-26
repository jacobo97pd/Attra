import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../domain/place_names.dart';

/// País con metadatos para el selector (nombre, ISO2, bandera emoji, región).
class Country {
  const Country({
    required this.name,
    required this.iso2,
    required this.emoji,
    required this.region,
  });

  final String name;
  final String iso2;
  final String emoji;
  final String region;

  factory Country.fromMap(Map<String, dynamic> map) {
    return Country(
      name: (map['name'] as String?) ?? '',
      iso2: ((map['iso2'] as String?) ?? '').toUpperCase(),
      emoji: (map['emoji'] as String?) ?? '',
      region: (map['region'] as String?) ?? '',
    );
  }
}

/// Acceso a los datos geográficos offline empaquetados en assets/geo.
///
/// - `countries.json` se carga una vez (lista completa de países reales).
/// - Las ciudades se cargan de forma perezosa por país (`cities/<ISO2>.json`),
///   así en web solo se descarga el país seleccionado, no los 2.4 MB enteros.
class GeoRepository {
  GeoRepository._();
  static final GeoRepository instance = GeoRepository._();

  static const String _countriesAsset = 'assets/geo/countries.json';
  static const String _countryNamesAsset = 'assets/geo/country_names.json';

  List<Country>? _countries;
  Map<String, Country>? _byIso2;
  Map<String, String>? _countryNames;
  final Map<String, List<String>> _citiesCache = <String, List<String>>{};
  final Map<String, List<({double lat, double lng})?>> _coordsCache =
      <String, List<({double lat, double lng})?>>{};

  Future<List<Country>> loadCountries() async {
    final List<Country>? cached = _countries;
    if (cached != null) {
      return cached;
    }
    final String raw = await rootBundle.loadString(_countriesAsset);
    final List<dynamic> decoded = json.decode(raw) as List<dynamic>;
    final List<Country> countries = decoded
        .whereType<Map<String, dynamic>>()
        .map(Country.fromMap)
        .where((Country c) => c.iso2.isNotEmpty)
        .toList(growable: false);
    _countries = countries;
    _byIso2 = <String, Country>{
      for (final Country c in countries) c.iso2: c,
    };
    return countries;
  }

  Future<Country?> countryByIso2(String iso2) async {
    await loadCountries();
    return _byIso2?[iso2.toUpperCase()];
  }

  Future<List<String>> loadCities(String iso2) async {
    final String key = iso2.toUpperCase();
    final List<String>? cached = _citiesCache[key];
    if (cached != null) {
      return cached;
    }
    try {
      final String raw =
          await rootBundle.loadString('assets/geo/cities/$key.json');
      final List<dynamic> decoded = json.decode(raw) as List<dynamic>;
      final List<String> cities =
          decoded.whereType<String>().toList(growable: false);
      _citiesCache[key] = cities;
      return cities;
    } catch (_) {
      _citiesCache[key] = const <String>[];
      return const <String>[];
    }
  }

  /// Sugerencias de ciudades de un país que casan con [query].
  /// Prioriza las que empiezan por el texto, luego las que lo contienen.
  Future<List<String>> searchCities(
    String iso2,
    String query, {
    int limit = 25,
  }) async {
    final List<String> cities = await loadCities(iso2);
    final String q = normalize(query);
    if (q.isEmpty) {
      return cities.take(limit).toList(growable: false);
    }
    final List<String> startsWith = <String>[];
    final List<String> contains = <String>[];
    for (final String city in cities) {
      final String n = normalize(city);
      if (n.startsWith(q)) {
        startsWith.add(city);
      } else if (n.contains(q)) {
        contains.add(city);
      }
      if (startsWith.length >= limit) {
        break;
      }
    }
    final List<String> out = <String>[...startsWith];
    for (final String city in contains) {
      if (out.length >= limit) {
        break;
      }
      out.add(city);
    }
    return out;
  }

  /// Devuelve el nombre canónico de la ciudad (tal cual aparece en el dataset)
  /// si existe en el país indicado; null si no es una ciudad real.
  Future<String?> canonicalCity(String iso2, String city) async {
    final String n = normalize(city);
    if (n.isEmpty) {
      return null;
    }
    final List<String> cities = await loadCities(iso2);
    for (final String c in cities) {
      if (normalize(c) == n) {
        return c;
      }
    }
    return null;
  }

  Future<bool> isValidCity(String iso2, String city) async {
    return (await canonicalCity(iso2, city)) != null;
  }

  /// Coordenadas de cada ciudad, ALINEADAS índice a índice con
  /// `cities/<ISO2>.json` (las dos salen de la misma descarga del dataset, ver
  /// tool/gen_geo_assets.mjs). `null` = sin centro fiable (homónimos lejanos).
  Future<List<({double lat, double lng})?>> loadCityCoordinates(
      String iso2) async {
    final String key = iso2.toUpperCase();
    final List<({double lat, double lng})?>? cached = _coordsCache[key];
    if (cached != null) {
      return cached;
    }
    try {
      final String raw =
          await rootBundle.loadString('assets/geo/coords/$key.json');
      final List<dynamic> decoded = json.decode(raw) as List<dynamic>;
      final List<({double lat, double lng})?> coords =
          decoded.map<({double lat, double lng})?>((dynamic e) {
        if (e is List && e.length == 2 && e[0] is num && e[1] is num) {
          return (
            lat: (e[0] as num).toDouble() / 100,
            lng: (e[1] as num).toDouble() / 100,
          );
        }
        return null;
      }).toList(growable: false);
      _coordsCache[key] = coords;
      return coords;
    } catch (_) {
      _coordsCache[key] = const <({double lat, double lng})?>[];
      return const <({double lat, double lng})?>[];
    }
  }

  /// Centro de [city] en el país [iso2], o null si la ciudad no existe, es
  /// ambigua o el fichero de coordenadas no casa con el de nombres.
  ///
  /// Casa con [normalize], así que 'Cádiz' y 'Cadiz' dan el mismo punto: el
  /// selector guarda la grafía del dataset y los perfiles la de siempre.
  Future<({double lat, double lng})?> cityCoordinates(
    String iso2,
    String city,
  ) async {
    final String n = normalize(city);
    if (n.isEmpty || iso2.trim().isEmpty) {
      return null;
    }
    final List<String> cities = await loadCities(iso2);
    final List<({double lat, double lng})?> coords =
        await loadCityCoordinates(iso2);
    // Desalineados = datos de dos descargas distintas: cualquier índice podría
    // apuntar a otra ciudad, así que no se da ninguno por bueno.
    if (coords.length != cities.length) {
      return null;
    }
    for (int i = 0; i < cities.length; i++) {
      if (normalize(cities[i]) == n) {
        return coords[i];
      }
    }
    return null;
  }

  /// ISO2 de un país escrito con su nombre en cualquier idioma del dataset
  /// ('España', 'Spain', 'Espagne', 'Espanya'…), o '' si no se reconoce. Es
  /// para registros antiguos que guardaron solo el nombre.
  Future<String> iso2ForCountryName(String name) async {
    final String n = normalize(name);
    if (n.isEmpty) {
      return '';
    }
    Map<String, String>? byName = _countryNames;
    if (byName == null) {
      try {
        final String raw = await rootBundle.loadString(_countryNamesAsset);
        final Map<String, dynamic> decoded =
            json.decode(raw) as Map<String, dynamic>;
        byName = <String, String>{
          for (final MapEntry<String, dynamic> e in decoded.entries)
            if (e.value is String) e.key: (e.value as String).toUpperCase(),
        };
      } catch (_) {
        byName = const <String, String>{};
      }
      _countryNames = byName;
    }
    return byName[n] ?? '';
  }

  /// Normaliza para comparar: minúsculas, sin acentos, espacios colapsados.
  /// La regla vive en [PlaceNames] (pura) para que el dominio la comparta.
  static String normalize(String input) => PlaceNames.normalize(input);
}
