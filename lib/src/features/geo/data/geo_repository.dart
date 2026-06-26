import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

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

  List<Country>? _countries;
  Map<String, Country>? _byIso2;
  final Map<String, List<String>> _citiesCache = <String, List<String>>{};

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

  /// Normaliza para comparar: minúsculas, sin acentos, espacios colapsados.
  static String normalize(String input) {
    final String lower = input.toLowerCase().trim();
    if (lower.isEmpty) {
      return '';
    }
    final StringBuffer buffer = StringBuffer();
    for (final int codeUnit in lower.runes) {
      final String ch = String.fromCharCode(codeUnit);
      buffer.write(_diacritics[ch] ?? ch);
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

const Map<String, String> _diacritics = <String, String>{
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'ā': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ø': 'o',
  'ō': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ñ': 'n',
  'ç': 'c',
  'ß': 'ss',
  'œ': 'oe',
  'æ': 'ae',
};
