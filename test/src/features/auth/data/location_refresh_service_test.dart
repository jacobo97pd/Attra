import 'dart:async';

import 'package:attra/src/features/auth/data/device_location_source.dart';
import 'package:attra/src/features/auth/data/location_refresh_service.dart';
import 'package:attra/src/features/auth/domain/location_refresh_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attra/src/features/auth/domain/resolved_place.dart';

/// Orquestación del refresco: qué se le pide al dispositivo, qué se guarda y qué
/// se le cuenta al usuario.
///
/// El GPS real (Geolocator) es canal nativo y no se puede probar, así que aquí se
/// sustituye por [_FakeSource]. Lo que se comprueba es la coreografía: que no se
/// gasta GPS cuando no toca, que se guarda cuando toca (y esa escritura es la que
/// republica `discovery/{uid}`) y que un fallo no se queda en silencio.
void main() {
  const double madridLat = 40.4168;
  const double madridLng = -3.7038;
  const double valenciaLat = 39.4699;
  const double valenciaLng = -0.3763;

  late DateTime clock;
  late _FakePersist persist;

  setUp(() {
    clock = DateTime.utc(2026, 8, 5, 12, 0);
    persist = _FakePersist();
  });

  LocationRefreshService service(_FakeSource source) => LocationRefreshService(
        source: source,
        persist: persist.call,
        clock: () => clock,
      );

  StoredLocation madrid({Duration? age}) => StoredLocation(
        latitude: madridLat,
        longitude: madridLng,
        updatedAt: age == null ? null : clock.subtract(age),
      );

  test('mudanza detectada por la vía barata: se guarda sin tocar el GPS', () {
    // El caso del viajero que abre la app al llegar: la última posición conocida
    // del sistema ya es la nueva ciudad, así que no hace falta despertar el GPS.
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
      cached: LocationFix(
        latitude: valenciaLat,
        longitude: valenciaLng,
        timestamp: clock.subtract(const Duration(minutes: 2)),
        fromCache: true,
      ),
    );

    return service(source)
        .refresh(
      stored: madrid(age: const Duration(minutes: 30)),
      trigger: LocationRefreshTrigger.appResume,
    )
        .then((LocationRefreshOutcome out) {
      expect(out.persisted, isTrue);
      expect(out.persistReason, LocationPersistReason.moved);
      expect(source.currentFixCalls, 0,
          reason: 'la lectura cacheada es gratis: no se enciende el GPS ni el '
              'indicador de localización de iOS si con ella basta');
      expect(persist.calls, 1);
      expect(persist.lastLatitude, valenciaLat);
      expect(persist.lastPermissionStatus, 'granted');
      expect(persist.lastPermissionGranted, isTrue);
    });
  });

  test('caché vieja: no se guarda como actual, se pide fix', () async {
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
      cached: LocationFix(
        latitude: valenciaLat,
        longitude: valenciaLng,
        timestamp: clock.subtract(const Duration(hours: 5)),
        fromCache: true,
      ),
      current: const LocationFix(
          latitude: valenciaLat + 0.01, longitude: valenciaLng),
    );

    final LocationRefreshOutcome out = await service(source).refresh(
      stored: madrid(age: const Duration(hours: 6)),
      trigger: LocationRefreshTrigger.appStart,
    );

    expect(source.currentFixCalls, 1);
    expect(out.persisted, isTrue);
    expect(persist.lastLatitude, valenciaLat + 0.01);
  });

  test('caché vieja y ubicación fresca: no se toca el GPS y no se escribe',
      () async {
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
      cached: LocationFix(
        latitude: valenciaLat,
        longitude: valenciaLng,
        timestamp: clock.subtract(const Duration(hours: 5)),
        fromCache: true,
      ),
      current: const LocationFix(
          latitude: valenciaLat, longitude: valenciaLng),
    );

    final LocationRefreshOutcome out = await service(source).refresh(
      stored: madrid(age: const Duration(minutes: 20)),
      trigger: LocationRefreshTrigger.appResume,
    );

    expect(source.currentFixCalls, 0);
    expect(out.persisted, isFalse);
    expect(persist.calls, 0);
  });

  test('mismo sitio y marca reciente: ni escritura ni republicación', () async {
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
      cached: LocationFix(
        latitude: madridLat + 0.005,
        longitude: madridLng,
        timestamp: clock.subtract(const Duration(minutes: 1)),
        fromCache: true,
      ),
    );

    final LocationRefreshOutcome out = await service(source).refresh(
      stored: madrid(age: const Duration(minutes: 10)),
      trigger: LocationRefreshTrigger.appResume,
    );

    expect(out.persistReason, LocationPersistReason.unchanged);
    expect(persist.calls, 0);
    // Aunque no se guarde, la lectura sirve al feed como "yo" para la distancia.
    expect(out.fix, isNotNull);
  });

  test('marca rancia en el mismo sitio: se escribe para no repreguntar siempre',
      () async {
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
      current: const LocationFix(latitude: madridLat, longitude: madridLng),
    );

    final LocationRefreshOutcome out = await service(source).refresh(
      stored: madrid(age: const Duration(days: 30)),
      trigger: LocationRefreshTrigger.appStart,
    );

    expect(out.persisted, isTrue);
    expect(out.persistReason, LocationPersistReason.staleStamp);
  });

  group('permisos', () {
    test('denegado al arrancar: no se abre diálogo y se avisa en el feed',
        () async {
      final _FakeSource source =
          _FakeSource(permission: LocationAuthorization.denied);

      final LocationRefreshOutcome out = await service(source).refresh(
        stored: StoredLocation.empty,
        trigger: LocationRefreshTrigger.appStart,
      );

      expect(source.requestCalls, 0);
      expect(source.lastKnownCalls, 0);
      expect(source.currentFixCalls, 0);
      expect(out.notice, LocationNotice.permissionAskable,
          reason: 'antes esto se tragaba en silencio y el usuario veía gente de '
              'otra ciudad sin saber por qué');
    });

    test('gesto explícito: pide permiso y, si lo dan, refresca en el mismo acto',
        () async {
      final _FakeSource source = _FakeSource(
        permission: LocationAuthorization.denied,
        grantedOnRequest: LocationAuthorization.granted,
        current: const LocationFix(latitude: madridLat, longitude: madridLng),
      );

      final LocationRefreshOutcome out = await service(source).refresh(
        stored: StoredLocation.empty,
        trigger: LocationRefreshTrigger.manual,
      );

      expect(source.requestCalls, 1);
      expect(out.persisted, isTrue);
      expect(out.notice, LocationNotice.none);
    });

    test('gesto explícito y lo deniegan: no se toca el GPS y sigue el aviso',
        () async {
      final _FakeSource source = _FakeSource(
        permission: LocationAuthorization.denied,
        grantedOnRequest: LocationAuthorization.deniedForever,
      );

      final LocationRefreshOutcome out = await service(source).refresh(
        stored: StoredLocation.empty,
        trigger: LocationRefreshTrigger.manual,
      );

      expect(source.currentFixCalls, 0);
      expect(out.notice, LocationNotice.permissionBlocked);
    });

    test('localización del dispositivo apagada: se dice, no se intenta', () async {
      final _FakeSource source =
          _FakeSource(permission: LocationAuthorization.serviceDisabled);

      final LocationRefreshOutcome out = await service(source).refresh(
        stored: madrid(age: const Duration(days: 5)),
        trigger: LocationRefreshTrigger.appResume,
      );

      expect(source.currentFixCalls, 0);
      expect(out.notice, LocationNotice.serviceDisabled);
    });
  });

  test('modo viaje: se mantiene la ubicación real sin gastar GPS', () async {
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
      cached: LocationFix(
        latitude: valenciaLat,
        longitude: valenciaLng,
        timestamp: clock.subtract(const Duration(minutes: 3)),
        fromCache: true,
      ),
      current: const LocationFix(latitude: 0, longitude: 0),
    );

    final LocationRefreshOutcome out = await service(source).refresh(
      stored: madrid(age: const Duration(days: 4)),
      trigger: LocationRefreshTrigger.appResume,
      travelActive: true,
    );

    expect(source.currentFixCalls, 0);
    // La ubicación REAL se sigue guardando en users/{uid}: quien decide que
    // viajando no se publica es DiscoveryPublisher, no este servicio.
    expect(out.persisted, isTrue);
    expect(persist.lastLatitude, valenciaLat);
    expect(out.notice, LocationNotice.none);
  });

  test('un fix que falla no se reintenta en cada vuelta del fondo', () async {
    // Es el caso que justifica el cooldown: en interiores el fix falla, la
    // ubicación sigue rancia y el plan lo volvería a pedir en cada `resumed`.
    final _FakeSource source =
        _FakeSource(permission: LocationAuthorization.granted);
    final LocationRefreshService svc = service(source);

    await svc.refresh(
      stored: madrid(age: const Duration(days: 1)),
      trigger: LocationRefreshTrigger.appResume,
    );
    clock = clock.add(const Duration(minutes: 2));
    final LocationRefreshOutcome second = await svc.refresh(
      stored: madrid(age: const Duration(days: 1)),
      trigger: LocationRefreshTrigger.appResume,
    );

    expect(second.reason, LocationRefreshReason.cooldown);
    expect(source.currentFixCalls, 1);
    // La vía barata sí se sigue intentando: es gratis.
    expect(source.lastKnownCalls, 2);
  });

  test('pasado el cooldown vuelve a intentar el fix', () async {
    final _FakeSource source =
        _FakeSource(permission: LocationAuthorization.granted);
    final LocationRefreshService svc = service(source);

    await svc.refresh(
      stored: madrid(age: const Duration(days: 1)),
      trigger: LocationRefreshTrigger.appResume,
    );
    clock = clock.add(LocationRefreshPolicy.fixCooldown * 2);
    await svc.refresh(
      stored: madrid(age: const Duration(days: 1)),
      trigger: LocationRefreshTrigger.appResume,
    );

    expect(source.currentFixCalls, 2);
  });

  test('un gesto explícito ignora el cooldown', () async {
    final _FakeSource source =
        _FakeSource(permission: LocationAuthorization.granted);
    final LocationRefreshService svc = service(source);

    await svc.refresh(
      stored: madrid(age: const Duration(days: 1)),
      trigger: LocationRefreshTrigger.appResume,
    );
    clock = clock.add(const Duration(seconds: 30));
    await svc.refresh(
      stored: madrid(age: const Duration(days: 1)),
      trigger: LocationRefreshTrigger.manual,
    );

    expect(source.currentFixCalls, 2);
  });

  test('una ronda que no toca el dispositivo no arranca el cooldown', () async {
    // Si el permiso está denegado no se ha gastado nada: cuando el usuario lo
    // concede, el gesto siguiente tiene que poder refrescar ya.
    final _FakeSource source =
        _FakeSource(permission: LocationAuthorization.denied);
    final LocationRefreshService svc = service(source);

    await svc.refresh(
      stored: StoredLocation.empty,
      trigger: LocationRefreshTrigger.appStart,
    );

    expect(svc.lastFixAt, isNull);
  });

  test('la marca del servidor tarda en volver: no se repite el refresco',
      () async {
    // `location.updatedAt` se escribe con serverTimestamp: la relectura inmediata
    // del usuario puede devolver todavía la marca vieja (o ninguna). Sin memoria
    // de lo escrito, la política volvía a pedir GPS y a reescribir lo mismo.
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
      current: const LocationFix(latitude: valenciaLat, longitude: valenciaLng),
    );
    final LocationRefreshService svc = service(source);

    await svc.refresh(
      stored: madrid(age: const Duration(days: 2)),
      trigger: LocationRefreshTrigger.appStart,
    );
    expect(source.currentFixCalls, 1);
    expect(persist.calls, 1);

    // Segunda ronda con el usuario recargado pero SIN marca resuelta todavía.
    clock = clock.add(LocationRefreshPolicy.fixCooldown * 2);
    final LocationRefreshOutcome out = await svc.refresh(
      stored: const StoredLocation(
          latitude: valenciaLat, longitude: valenciaLng),
      trigger: LocationRefreshTrigger.appResume,
    );

    expect(out.reason, LocationRefreshReason.fresh);
    expect(source.currentFixCalls, 1);
    expect(persist.calls, 1);
  });

  test('otra sesión con marca más nueva manda sobre lo nuestro', () async {
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
      current: const LocationFix(latitude: valenciaLat, longitude: valenciaLng),
    );
    final LocationRefreshService svc = service(source);

    await svc.refresh(
      stored: madrid(age: const Duration(days: 2)),
      trigger: LocationRefreshTrigger.appStart,
    );

    // Otro dispositivo ha escrito una ubicación posterior: la del documento gana.
    clock = clock.add(const Duration(hours: 6));
    final LocationRefreshOutcome out = await svc.refresh(
      stored: StoredLocation(
        latitude: madridLat,
        longitude: madridLng,
        updatedAt: clock.subtract(const Duration(minutes: 10)),
      ),
      trigger: LocationRefreshTrigger.appResume,
    );

    expect(out.reason, LocationRefreshReason.fresh,
        reason: 'la marca del documento es de hace 10 minutos');
    expect(source.currentFixCalls, 1);
  });

  test('sin fix disponible no se inventa nada (el feed cae al país)', () async {
    final _FakeSource source =
        _FakeSource(permission: LocationAuthorization.granted);

    final LocationRefreshOutcome out = await service(source).refresh(
      stored: StoredLocation.empty,
      trigger: LocationRefreshTrigger.appStart,
    );

    expect(out.fix, isNull);
    expect(out.persisted, isFalse);
    expect(persist.calls, 0);
    expect(out.notice, LocationNotice.stale);
  });

  group('la caché no puede ganarle al fix que el plan pedía', () {
    test('caché de 25 min en la autovía: se pide el GPS igualmente', () async {
      // El caso reportado: coche Valencia→Madrid. Al llegar, la última posición
      // conocida es de hace 25 min y está en la A-3 (a ~90 km de Madrid).
      // Aceptarla como si fuera el fix la guardaba con marca NUEVA, dejaba al
      // usuario publicado a 90 km y bloqueaba cualquier intento durante horas:
      // ni "Actualizar" ni "Recargar" servían de nada.
      const double a3Lat = 39.9;
      const double a3Lng = -2.8;
      final _FakeSource source = _FakeSource(
        permission: LocationAuthorization.granted,
        cached: LocationFix(
          latitude: a3Lat,
          longitude: a3Lng,
          timestamp: clock.subtract(const Duration(minutes: 25)),
          fromCache: true,
        ),
        current: const LocationFix(latitude: madridLat, longitude: madridLng),
      );

      final LocationRefreshOutcome out = await service(source).refresh(
        stored: StoredLocation(
          latitude: valenciaLat,
          longitude: valenciaLng,
          updatedAt: clock.subtract(const Duration(hours: 6)),
        ),
        trigger: LocationRefreshTrigger.appResume,
      );

      expect(source.currentFixCalls, 1);
      expect(persist.lastLatitude, madridLat,
          reason: 'se guarda el fix de Madrid, no la caché de la autovía');
      expect(out.persisted, isTrue);
    });

    test('caché de hace un minuto: vale como fix y no se enciende el GPS',
        () async {
      // Si el sistema acaba de medir, el fix daría lo mismo gastando batería.
      final _FakeSource source = _FakeSource(
        permission: LocationAuthorization.granted,
        cached: LocationFix(
          latitude: madridLat,
          longitude: madridLng,
          timestamp: clock.subtract(const Duration(minutes: 1)),
          fromCache: true,
        ),
        current: const LocationFix(latitude: 0, longitude: 0),
      );

      await service(source).refresh(
        stored: StoredLocation(
          latitude: valenciaLat,
          longitude: valenciaLng,
          updatedAt: clock.subtract(const Duration(hours: 6)),
        ),
        trigger: LocationRefreshTrigger.appResume,
      );

      expect(source.currentFixCalls, 0);
      expect(persist.lastLatitude, madridLat);
    });

    test('si el fix falla, la caché utilizable sigue sirviendo de respaldo',
        () async {
      final _FakeSource source = _FakeSource(
        permission: LocationAuthorization.granted,
        cached: LocationFix(
          latitude: madridLat,
          longitude: madridLng,
          timestamp: clock.subtract(const Duration(minutes: 20)),
          fromCache: true,
        ),
      );

      final LocationRefreshOutcome out = await service(source).refresh(
        stored: madrid(age: const Duration(days: 2)),
        trigger: LocationRefreshTrigger.appResume,
      );

      expect(source.currentFixCalls, 1, reason: 'se intentó el fix primero');
      expect(out.fix, isNotNull);
    });
  });

  test('la marca guardada es la de la MEDICIÓN, no la de la escritura',
      () async {
    // `updatedAt` lo pone el servidor al confirmar: sin cobertura eso puede ser
    // horas después y en otra ciudad, y la posición vieja quedaba sellada como
    // recién medida (y por tanto "fresquísima") durante 4 h.
    final DateTime measuredAt = clock.subtract(const Duration(minutes: 10));
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
      current: LocationFix(
        latitude: valenciaLat,
        longitude: valenciaLng,
        timestamp: measuredAt,
      ),
    );

    await service(source).refresh(
      stored: madrid(age: const Duration(days: 1)),
      trigger: LocationRefreshTrigger.appStart,
    );

    expect(persist.lastFixedAt, measuredAt);
  });

  test('una escritura que no vuelve no mata el refresco del resto de la sesión',
      () async {
    // Túnel/avión: la future del `set()` de Firestore no completa hasta que el
    // servidor confirma. Sin tope, el intento no se soltaba nunca y TODAS las
    // rondas siguientes (cada vuelta del fondo, cada "Recargar", el toque en el
    // aviso) devolvían `inFlight` y no hacían absolutamente nada.
    persist.neverCompletes = true;
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
      current: const LocationFix(latitude: valenciaLat, longitude: valenciaLng),
    );
    // Tope corto para no esperar los 15 s reales de producción.
    final LocationRefreshService svc = LocationRefreshService(
      source: source,
      persist: persist.call,
      clock: () => clock,
      persistTimeout: const Duration(milliseconds: 50),
    );

    final LocationRefreshOutcome first = await svc.refresh(
      stored: madrid(age: const Duration(days: 1)),
      trigger: LocationRefreshTrigger.appStart,
    );

    expect(first.persistFailed, isTrue,
        reason: 'no se puede dar por guardada: la ronda siguiente debe reintentar');

    persist.neverCompletes = false;
    clock = clock.add(LocationRefreshPolicy.fixCooldown * 2);
    final LocationRefreshOutcome second = await svc.refresh(
      stored: madrid(age: const Duration(days: 1)),
      trigger: LocationRefreshTrigger.appResume,
    );

    expect(second.reason, isNot(LocationRefreshReason.inFlight));
    expect(second.persisted, isTrue);
  });

  test('permiso indeterminado: se intenta la vía barata y no se pisa el estado',
      () async {
    // `authorization()` devuelve `unknown` ante cualquier excepción del canal
    // nativo (plugin sin registrar al arrancar). Antes eso abortaba la ronda
    // entera y pintaba "no tenemos tu ubicación" a quien SÍ había dado permiso.
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.unknown,
      cached: LocationFix(
        latitude: valenciaLat,
        longitude: valenciaLng,
        timestamp: clock.subtract(const Duration(minutes: 1)),
        fromCache: true,
      ),
    );

    final LocationRefreshOutcome out = await service(source).refresh(
      stored: madrid(age: const Duration(minutes: 30)),
      trigger: LocationRefreshTrigger.appResume,
    );

    expect(source.currentFixCalls, 0);
    expect(out.persisted, isTrue);
    expect(persist.lastPermissionStatus, isNull,
        reason: '"no lo sabemos" no es "denegado": escribir unknown/false '
            'pisaría un granted bueno y Ajustes volvería a decir que no hay '
            'permiso');
    expect(persist.lastPermissionGranted, isNull);
    expect(out.notice, isNot(LocationNotice.permissionAskable));
  });

  test('si el gesto no consigue el permiso, el aviso pasa a Ajustes', () async {
    // iOS `restricted` (Screen Time/MDM): el diálogo no se abre NUNCA, así que
    // seguir ofreciendo "Activar" es un botón que no puede funcionar.
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.denied,
      grantedOnRequest: LocationAuthorization.denied,
    );

    final LocationRefreshOutcome out = await service(source).refresh(
      stored: StoredLocation.empty,
      trigger: LocationRefreshTrigger.manual,
    );

    expect(source.requestCalls, 1);
    expect(out.notice, LocationNotice.permissionBlocked);
  });

  test('si la escritura falla se marca y no se rompe nada', () async {
    persist.shouldThrow = true;
    final _FakeSource source = _FakeSource(
      permission: LocationAuthorization.granted,
      current: const LocationFix(latitude: valenciaLat, longitude: valenciaLng),
    );

    final LocationRefreshOutcome out = await service(source).refresh(
      stored: madrid(age: const Duration(days: 10)),
      trigger: LocationRefreshTrigger.appStart,
    );

    expect(out.persistFailed, isTrue);
    expect(out.persisted, isFalse);
    // La ubicación guardada sigue siendo la vieja: el aviso lo refleja.
    expect(out.notice, LocationNotice.stale);
    // Y el feed puede seguir usando la lectura para calcular distancias.
    expect(out.fix, isNotNull);
  });
}

/// GPS de mentira: sustituye a Geolocator (canal nativo, no probable).
class _FakeSource implements DeviceLocationSource {
  _FakeSource({
    required this.permission,
    this.grantedOnRequest,
    this.cached,
    this.current,
  });

  LocationAuthorization permission;
  final LocationAuthorization? grantedOnRequest;
  final LocationFix? cached;
  final LocationFix? current;

  int requestCalls = 0;
  int lastKnownCalls = 0;
  int currentFixCalls = 0;

  @override
  Future<LocationAuthorization> authorization() async => permission;

  @override
  Future<LocationAuthorization> requestAuthorization() async {
    requestCalls++;
    permission = grantedOnRequest ?? permission;
    return permission;
  }

  @override
  Future<LocationFix?> lastKnownFix() async {
    lastKnownCalls++;
    return cached;
  }

  @override
  Future<LocationFix?> currentFix({Duration timeout = const Duration(seconds: 8)}) async {
    currentFixCalls++;
    return current;
  }
}

class _FakePersist {
  int calls = 0;
  double? lastLatitude;
  double? lastLongitude;
  DateTime? lastFixedAt;
  String? lastPermissionStatus;
  bool? lastPermissionGranted;
  bool shouldThrow = false;

  /// Escritura que NUNCA completa: es lo que hace Firestore sin red (la future de
  /// `set()` no se resuelve hasta que el servidor confirma).
  bool neverCompletes = false;

  Future<void> call({
    required double latitude,
    required double longitude,
    required DateTime fixedAt,
    String? permissionStatus,
    bool? permissionGranted,
    ResolvedPlace? place,
  }) async {
    calls++;
    lastLatitude = latitude;
    lastLongitude = longitude;
    lastFixedAt = fixedAt;
    lastPermissionStatus = permissionStatus;
    lastPermissionGranted = permissionGranted;
    if (neverCompletes) return Completer<void>().future;
    if (shouldThrow) {
      throw StateError('permission-denied');
    }
  }
}
