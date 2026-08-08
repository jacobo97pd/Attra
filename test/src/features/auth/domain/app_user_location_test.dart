import 'package:attra/src/features/auth/domain/app_user.dart';
import 'package:attra/src/features/auth/domain/location_refresh_policy.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Puente entre `users/{uid}.location` y la política de refresco.
///
/// Es el eslabón que faltaba: `location.updatedAt` YA se escribía, pero nadie lo
/// leía, así que el cliente solo podía preguntarse "¿hay coordenadas?" y la
/// ubicación se quedaba congelada desde el registro. Si este parseo se rompe, el
/// fallo vuelve en silencio (o se pide GPS en cada arranque).
void main() {
  const double lat = 39.4699;
  const double lng = -0.3763;

  AppUser userWith(Map<String, dynamic> location) =>
      AppUser.fromDocument(_FakeDoc(<String, dynamic>{
        'uid': 'u1',
        'displayName': 'Alex',
        'location': location,
      }));

  test('lee la marca de frescura guardada como Timestamp', () {
    final DateTime at = DateTime.utc(2026, 8, 5, 10, 30);
    final AppUser user = userWith(<String, dynamic>{
      'latitude': lat,
      'longitude': lng,
      'updatedAt': Timestamp.fromDate(at),
      'permissionStatus': 'granted',
    });

    // `Timestamp.toDate()` devuelve hora LOCAL: se compara el instante.
    expect(user.locationUpdatedAt!.isAtSameMomentAs(at), isTrue);
    expect(user.locationPermissionStatus, 'granted');
    expect(user.storedLocation.hasCoordinates, isTrue);
    expect(user.storedLocation.updatedAt!.isAtSameMomentAs(at), isTrue);
  });

  test('lee la marca guardada como texto ISO (la escribe el onboarding)', () {
    final AppUser user = userWith(<String, dynamic>{
      'latitude': lat,
      'longitude': lng,
      'updatedAt': '2026-08-05T10:30:00.000Z',
    });

    expect(user.locationUpdatedAt, DateTime.utc(2026, 8, 5, 10, 30));
  });

  test('sin marca: la política lo trata como "edad desconocida", no como fresca',
      () {
    final AppUser user = userWith(<String, dynamic>{
      'latitude': lat,
      'longitude': lng,
    });

    expect(user.locationUpdatedAt, isNull);
    expect(user.locationPermissionStatus, 'unknown');
    expect(
      LocationRefreshPolicy.decide(
        stored: user.storedLocation,
        now: DateTime.utc(2026, 8, 5, 12, 0),
        permission: LocationAuthorization.granted,
        trigger: LocationRefreshTrigger.appStart,
      ).reason,
      LocationRefreshReason.unknownAge,
    );
  });

  test('lee la marca de la MEDICIÓN y es la que manda sobre la de escritura',
      () {
    final AppUser user = userWith(<String, dynamic>{
      'latitude': lat,
      'longitude': lng,
      // Escrita hace un minuto (la escritura se confirmó al recuperar red), pero
      // MEDIDA hace cinco horas: con `updatedAt` a secas quedaba sellada como
      // fresquísima y no se volvía a mirar en 4 h, justo tras cambiar de ciudad.
      'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 5, 11, 59)),
      'fixedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 5, 7, 0)),
    });

    expect(
      LocationRefreshPolicy.decide(
        stored: user.storedLocation,
        now: DateTime.utc(2026, 8, 5, 12, 0),
        permission: LocationAuthorization.granted,
        trigger: LocationRefreshTrigger.appResume,
      ).reason,
      LocationRefreshReason.stale,
    );
  });

  group('modo viaje caducado', () {
    AppUser travelingUntil(String? until) =>
        AppUser.fromDocument(_FakeDoc(<String, dynamic>{
          'uid': 'u1',
          'settings': <String, dynamic>{
            'travel': <String, dynamic>{
              'active': true,
              'city': 'Madrid',
              'country': 'España',
              if (until != null) 'until': until,
            },
          },
        }));

    test('un viaje vigente sigue siendo un viaje', () {
      final AppUser user = travelingUntil(
          DateTime.now().add(const Duration(days: 10)).toIso8601String());

      expect(user.isTraveling, isTrue);
    });

    test('un viaje que caducó ya no cuenta (el backend tampoco lo publica)', () {
      // Es el caso más común: activó el viaje y nunca lo apagó. El backend caduca
      // a los 30 días y publica su ubicación REAL, mientras el cliente seguía
      // anclando su feed al destino, sin gastar GPS y sin avisar: sus coordenadas
      // se congelaban para siempre.
      final AppUser user = travelingUntil(
          DateTime.now().subtract(const Duration(days: 1)).toIso8601String());

      expect(user.isTraveling, isFalse);
    });

    test('sin fecha de fin se respeta (viajes creados antes de la caducidad)',
        () {
      expect(travelingUntil(null).isTraveling, isTrue);
    });
  });

  test('sin ubicación ninguna: no revienta y pide coordenadas', () {
    final AppUser user = AppUser.fromDocument(_FakeDoc(<String, dynamic>{
      'uid': 'u1',
    }));

    expect(user.storedLocation.hasCoordinates, isFalse);
    expect(
      LocationRefreshPolicy.decide(
        stored: user.storedLocation,
        now: DateTime.utc(2026, 8, 5, 12, 0),
        permission: LocationAuthorization.granted,
        trigger: LocationRefreshTrigger.appStart,
      ).reason,
      LocationRefreshReason.missing,
    );
  });
}

// ignore_for_file: subtype_of_sealed_class

/// Documento de mentira: `AppUser.fromDocument` solo usa `data()` y `id`.
///
/// `DocumentSnapshot` está marcado como sealed para que nadie lo implemente en
/// producción; aquí es la única forma de probar el parseo sin arrancar Firebase.
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
