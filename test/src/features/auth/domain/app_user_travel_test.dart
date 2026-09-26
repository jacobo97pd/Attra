import 'package:attra/src/features/auth/domain/app_user.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parseo del viaje (centro del destino, fin) y del país comparable (ISO2).
///
/// El viaje ahora guarda el CENTRO de la ciudad de destino (`lat/lng`): es el
/// punto desde el que se mide el feed del viajero. Tiene que leerse igual de
/// bien de un documento nuevo que de uno escrito por una versión anterior (sin
/// centro y con la fecha de fin en ISO).
void main() {
  AppUser parse(Map<String, dynamic> data) =>
      AppUser.fromDocument(_FakeDoc(<String, dynamic>{'uid': 'u1', ...data}));

  test('viaje nuevo: centro, origen y fin como Timestamp', () {
    final DateTime until = DateTime.utc(2030, 1, 15, 12);
    final AppUser user = parse(<String, dynamic>{
      'settings': <String, dynamic>{
        'travel': <String, dynamic>{
          'active': true,
          'iso2': 'es',
          'city': 'Cadiz',
          'country': 'Spain',
          'lat': 36.5267,
          'lng': -6.2891,
          'geoSource': 'asset',
          'until': until.toIso8601String(),
          'untilAt': Timestamp.fromDate(until),
        },
      },
    });

    expect(user.isTraveling, isTrue);
    expect(user.travelIso2, 'ES');
    expect(user.travelLat, 36.5267);
    expect(user.travelLng, -6.2891);
    expect(user.travelGeoSource, 'asset');
    expect(user.hasTravelOrigin, isTrue);
    expect(user.travelUntil!.isAtSameMomentAs(until), isTrue);
  });

  test('viaje antiguo: solo el ISO `until` y sin centro', () {
    final AppUser user = parse(<String, dynamic>{
      'settings': <String, dynamic>{
        'travel': <String, dynamic>{
          'active': true,
          'iso2': 'ES',
          'city': 'Cadiz',
          'country': 'Spain',
          'until':
              DateTime.now().add(const Duration(days: 5)).toIso8601String(),
        },
      },
    });

    expect(user.isTraveling, isTrue);
    expect(user.hasTravelOrigin, isFalse);
    expect(user.travelGeoSource, '');
  });

  test('untilAt manda sobre el ISO antiguo', () {
    final AppUser user = parse(<String, dynamic>{
      'settings': <String, dynamic>{
        'travel': <String, dynamic>{
          'active': true,
          'country': 'Spain',
          'until':
              DateTime.now().add(const Duration(days: 5)).toIso8601String(),
          'untilAt': Timestamp.fromDate(
              DateTime.now().subtract(const Duration(days: 1))),
        },
      },
    });

    expect(user.isTraveling, isFalse);
    expect(user.travelExpired, isTrue,
        reason: 'sigue marcado como activo con la fecha pasada: hay que '
            'apagarlo');
  });

  test('un centro fuera de rango no se usa (settings no valida tipos)', () {
    final AppUser user = parse(<String, dynamic>{
      'settings': <String, dynamic>{
        'travel': <String, dynamic>{
          'active': true,
          'country': 'Spain',
          'lat': 136.5,
          'lng': '-6.29',
        },
      },
    });

    expect(user.travelLat, isNull);
    expect(user.hasTravelOrigin, isFalse);
  });

  test('ISO2 del país: el del geocodificador y, si no, el del onboarding', () {
    expect(
        parse(<String, dynamic>{
          'profile': <String, dynamic>{
            'currentCountryName': 'Espanya',
            'currentCountryIso2': 'es',
            'currentCountryCode': 'PT',
          },
        }).countryIso2,
        'ES');
    expect(
        parse(<String, dynamic>{
          'profile': <String, dynamic>{'currentCountryCode': 'pt'},
        }).countryIso2,
        'PT');
    expect(parse(<String, dynamic>{}).countryIso2, '');
  });

  test('dónde se resolvió el sitio por última vez', () {
    final AppUser user = parse(<String, dynamic>{
      'location': <String, dynamic>{
        'latitude': 38.72,
        'longitude': -9.14,
        'placeLat': 40.42,
        'placeLng': -3.70,
      },
    });

    expect(user.storedLocation.placeLatitude, 40.42);
    expect(user.storedLocation.placeLongitude, -3.70);
  });
}

// ignore_for_file: subtype_of_sealed_class

/// Documento de mentira: `AppUser.fromDocument` solo usa `data()` y `id`.
class _FakeDoc implements DocumentSnapshot<Map<String, dynamic>> {
  _FakeDoc(this._data);

  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  String get id => (_data['uid'] as String?) ?? 'u1';

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Llamada inesperada: ${invocation.memberName}');
  }
}
