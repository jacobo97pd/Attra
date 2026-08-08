import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/location_refresh_policy.dart';
import '../domain/resolved_place.dart';
import 'device_location_source.dart';

/// Guarda la ubicación en `users/{uid}` (y republica `discovery/{uid}`). Es la
/// misma firma en toda la cadena feed → HomeShell → SessionGate →
/// SessionController → UserRepository.
///
/// [fixedAt] es cuándo se MIDIÓ la posición, que no es cuándo se escribe:
/// `location.updatedAt` lo pone el servidor al confirmar y sin cobertura eso
/// puede ser horas después, en otra ciudad.
///
/// [permissionStatus]/[permissionGranted] son opcionales porque "no lo sabemos"
/// (canal nativo que falla) NO es "denegado": escribir `unknown`/false pisaría un
/// `granted` bueno y Ajustes volvería a decir que no hay permiso.
typedef PersistDeviceLocation = Future<void> Function({
  required double latitude,
  required double longitude,
  required DateTime fixedAt,
  String? permissionStatus,
  bool? permissionGranted,
  /// Ciudad y pais resueltos de esas coordenadas. `null` = no se pudo, y
  /// entonces se CONSERVAN los que ya habia: media verdad (coordenadas nuevas,
  /// pais viejo) es peor que el dato entero viejo.
  ResolvedPlace? place,
});

/// Resultado de un intento de refresco. El feed lo usa para dos cosas: tener un
/// "yo" con el que calcular distancias y saber qué aviso enseñar.
class LocationRefreshOutcome {
  const LocationRefreshOutcome({
    required this.reason,
    required this.notice,
    required this.permission,
    this.fix,
    this.persisted = false,
    this.persistReason,
    this.persistFailed = false,
  });

  /// Qué se decidió hacer.
  final LocationRefreshReason reason;

  /// Qué contarle al usuario ([LocationNotice.none] = nada).
  final LocationNotice notice;

  final LocationAuthorization permission;

  /// Lectura utilizable de esta ronda (persistida o no). null = no hay.
  final LocationFix? fix;

  /// True si se escribió en `users/{uid}` (lo que arrastra la republicación de
  /// `discovery/{uid}`).
  final bool persisted;

  final LocationPersistReason? persistReason;

  /// La escritura falló (reglas, red…). La ubicación guardada sigue siendo la
  /// vieja, así que el siguiente intento volverá a probar.
  final bool persistFailed;
}

/// Orquesta el refresco: pregunta a [LocationRefreshPolicy] qué toca, habla con
/// el dispositivo a través de [DeviceLocationSource] y persiste si merece la
/// pena. No tiene UI ni conoce Firestore: recibe la ubicación guardada y un
/// callback de escritura.
///
/// El estado que guarda (último intento / intento en curso) es lo que evita que
/// el gancho de ciclo de vida se convierta en una tormenta de peticiones: el
/// evento `resumed` llega cada vez que el usuario vuelve de otra app.
class LocationRefreshService {
  LocationRefreshService({
    required PersistDeviceLocation persist,
    PlaceResolver? placeResolver,
    DeviceLocationSource source = const GeolocatorLocationSource(),
    DateTime Function()? clock,
    Duration persistTimeout = LocationRefreshPolicy.persistTimeout,
  })  : _persist = persist,
        _placeResolver = placeResolver,
        _source = source,
        _clock = clock ?? DateTime.now,
        _persistTimeout = persistTimeout;

  final PersistDeviceLocation _persist;

  /// Traduce coordenadas a ciudad/pais. Opcional: sin el, todo lo demas sigue
  /// funcionando y el sitio se queda como estaba.
  final PlaceResolver? _placeResolver;
  final DeviceLocationSource _source;
  final DateTime Function() _clock;

  /// Tope de espera de la escritura. Se inyecta SOLO para poder probar el caso
  /// "sin red la escritura no vuelve" sin esperar los 15 s de verdad.
  final Duration _persistTimeout;

  /// Cuándo se pidió el último fix ACTIVO (lo caro). No se apunta la lectura de
  /// caché: es gratis y limitarla solo retrasaría detectar una mudanza.
  DateTime? _lastFixAt;

  /// Lo último que este proceso ha guardado con éxito.
  ///
  /// `location.updatedAt` se escribe con `serverTimestamp()`: el valor lo pone
  /// el servidor, así que una relectura inmediata puede devolver todavía la marca
  /// vieja (o ninguna). Sin esta memoria, el usuario recargado parecía "sin marca"
  /// y la política volvía a pedir GPS y a reescribir lo mismo.
  StoredLocation? _lastPersisted;

  bool _inFlight = false;

  /// Ya se pidió el permiso con un gesto del usuario y no se consiguió. En iOS
  /// `restricted` (Screen Time/MDM) el diálogo no se abre NUNCA, así que seguir
  /// ofreciendo "Activar" es un botón que no puede funcionar.
  bool _permissionAskFailed = false;

  @visibleForTesting
  DateTime? get lastFixAt => _lastFixAt;

  Future<LocationRefreshOutcome> refresh({
    required StoredLocation stored,
    required LocationRefreshTrigger trigger,
    bool travelActive = false,
    Duration? awayFor,
    double? moveThresholdKm,
  }) async {
    if (_inFlight) {
      return const LocationRefreshOutcome(
        reason: LocationRefreshReason.inFlight,
        notice: LocationNotice.none,
        permission: LocationAuthorization.unknown,
      );
    }
    _inFlight = true;
    try {
      final StoredLocation known = _known(stored);
      LocationAuthorization permission = await _authorization();
      LocationRefreshPlan plan = LocationRefreshPolicy.decide(
        stored: known,
        now: _clock(),
        permission: permission,
        trigger: trigger,
        travelActive: travelActive,
        lastFixAt: _lastFixAt,
        awayFor: awayFor,
      );

      if (plan.askPermission) {
        permission = await _source
            .requestAuthorization()
            .timeout(LocationRefreshPolicy.deviceCallTimeout,
                onTimeout: () => LocationAuthorization.unknown);
        // El gesto ya se gastó y el sistema ha contestado que no: el aviso tiene
        // que dejar de ofrecer un botón que vuelve a no abrir nada (iOS
        // `restricted`, Screen Time/MDM). Si la respuesta es `unknown` no se
        // concluye nada: puede haber fallado el canal, no el usuario.
        if (permission != LocationAuthorization.unknown &&
            !permission.isGranted) {
          _permissionAskFailed = true;
        }
        // Con el permiso ya resuelto se vuelve a decidir: si lo ha concedido hay
        // que refrescar en el mismo gesto (el usuario acaba de pedirlo), y si lo
        // ha denegado no se toca el GPS.
        plan = LocationRefreshPolicy.decide(
          stored: known,
          now: _clock(),
          permission: permission,
          trigger: trigger,
          travelActive: travelActive,
          lastFixAt: _lastFixAt,
          awayFor: awayFor,
        );
      }

      if (!plan.touchesDevice) {
        return LocationRefreshOutcome(
          reason: plan.reason,
          notice: _notice(known, permission, travelActive),
          permission: permission,
        );
      }

      // Lectura barata primero (es gratis), pero NO manda sobre el fix.
      LocationFix? cached;
      if (plan.readCache) {
        final LocationFix? last = await _lastKnownFix();
        if (last != null &&
            LocationRefreshPolicy.isCacheUsable(fix: last, now: _clock())) {
          cached = last;
        }
      }

      LocationFix? fix;
      if (plan.requestFix) {
        // La caché solo sustituye al fix si el sistema acaba de medir. Con el
        // criterio ancho (30 min) la caché SIEMPRE ganaba: al llegar a Madrid en
        // coche, la última posición conocida era de la A-3 hace 20 min, se
        // guardaba con marca nueva y bloqueaba cualquier intento durante horas,
        // así que ni "Actualizar" ni "Recargar" servían de nada. El fix activo es
        // justo lo que el plan había pedido.
        final Duration? age = cached == null
            ? null
            : LocationRefreshPolicy.cacheAge(fix: cached, now: _clock());
        final bool cacheIsAsGoodAsAFix = age != null &&
            age <= LocationRefreshPolicy.cacheTrustedForFix;
        if (cacheIsAsGoodAsAFix) {
          fix = cached;
        } else {
          // El cooldown se apunta AQUÍ y no antes: lo que hay que limitar es el
          // fix, no la lectura barata, y hay que apuntarlo aunque el fix falle
          // (si no, un GPS sin señal se reintentaría en cada vuelta).
          _lastFixAt = _clock();
          // Doble tope: el de dentro lo aplica la fuente y este es la red de
          // seguridad por si el canal nativo no contesta nunca. Ningún camino
          // puede dejar `_inFlight` en true para el resto de la sesión.
          fix = await _source
              .currentFix(timeout: LocationRefreshPolicy.fixTimeout)
              .timeout(LocationRefreshPolicy.fixTimeout * 2,
                  onTimeout: () => null);
          // Sin fix (interiores, GPS sin señal) la caché sigue siendo mejor que
          // nada para que el feed tenga un "yo".
          fix ??= cached;
        }
      } else {
        fix = cached;
      }

      if (fix == null) {
        return LocationRefreshOutcome(
          reason: plan.reason,
          notice: _notice(known, permission, travelActive),
          permission: permission,
        );
      }

      final LocationPersistDecision decision =
          LocationRefreshPolicy.shouldPersist(
        stored: known,
        fix: fix,
        now: _clock(),
        moveThresholdKm: moveThresholdKm,
      );
      if (!decision.persist) {
        return LocationRefreshOutcome(
          reason: plan.reason,
          notice: _notice(known, permission, travelActive),
          permission: permission,
          fix: fix,
          persistReason: decision.reason,
        );
      }

      // Momento de la MEDICIÓN: es lo que decide la frescura. `updatedAt` lo pone
      // el servidor al confirmar la escritura y, sin cobertura, eso puede ser
      // horas después y en otra ciudad.
      final DateTime fixedAt = fix.timestamp ?? _clock();

      bool failed = false;
      try {
        // Con timeout: la future de una escritura de Firestore no completa hasta
        // que el servidor la confirma, así que sin red se quedaba esperando
        // indefinidamente, el intento nunca se soltaba y cualquier refresco
        // posterior de la sesión moría con `inFlight`. Un timeout no cancela la escritura
        // (Firestore la confirmará al recuperar red), solo deja de esperarla: se
        // trata como fallo para que la ronda siguiente vuelva a intentarlo en vez
        // de dar por fresca una ubicación que quizá no llegó.
        // La ciudad y el pais se resuelven ANTES de escribir, para que vayan en
        // la MISMA escritura que las coordenadas. En dos escrituras habria un
        // intervalo con coordenadas nuevas y pais viejo, y el trigger de
        // backend republicaria `discovery` en ese estado incoherente.
        //
        // Solo se pide si la persona se ha movido de verdad: el geocodificador
        // de iOS esta limitado por tasa y esto no vale una peticion por
        // arranque.
        ResolvedPlace? place;
        if (_placeResolver != null &&
            (decision.reason == LocationPersistReason.moved ||
                decision.reason == LocationPersistReason.noCoordinates)) {
          try {
            place = await _placeResolver
                .resolve(latitude: fix.latitude, longitude: fix.longitude);
          } catch (error) {
            // Blindaje del CONTRATO, no del PlatformPlaceResolver (ese ya
            // captura por dentro). No poder nombrar la ciudad jamas puede
            // impedir guardar unas coordenadas buenas: se perderia el arreglo
            // entero por un fallo de red. Lo caza un test.
            if (kDebugMode) {
              debugPrint('[Attra][Ubicación] sitio sin resolver: $error');
            }
          }
        }
        await _persist(
          latitude: fix.latitude,
          longitude: fix.longitude,
          fixedAt: fixedAt,
          // "No lo sabemos" NO es "denegado": escribir `unknown`/false pisaría un
          // `granted` bueno y Ajustes volvería a decir que no hay permiso.
          permissionStatus: permission == LocationAuthorization.unknown
              ? null
              : permission.wireName,
          permissionGranted: permission == LocationAuthorization.unknown
              ? null
              : permission.isGranted,
          place: place,
        ).timeout(_persistTimeout);
      } catch (error) {
        failed = true;
        if (kDebugMode) {
          debugPrint('[Attra][Ubicación] no se pudo guardar: $error');
        }
      }

      // Si se guardó, la ubicación efectiva ya es la nueva: el aviso se calcula
      // con ella (si no, avisaría de "vieja" justo después de refrescarla).
      final StoredLocation effective = failed
          ? known
          : StoredLocation(
              latitude: fix.latitude,
              longitude: fix.longitude,
              updatedAt: _clock(),
              measuredAt: fixedAt,
            );
      if (!failed) _lastPersisted = effective;

      return LocationRefreshOutcome(
        reason: plan.reason,
        notice: _notice(effective, permission, travelActive),
        permission: permission,
        fix: fix,
        persisted: !failed,
        persistReason: decision.reason,
        persistFailed: failed,
      );
    } finally {
      _inFlight = false;
    }
  }

  /// Lo que de verdad sabemos de la ubicación guardada: el documento, salvo que
  /// lo que este proceso escribió sea más nuevo (ver [_lastPersisted]).
  StoredLocation _known(StoredLocation stored) {
    final StoredLocation? mine = _lastPersisted;
    final DateTime? mineAt = mine?.freshAt;
    if (mine == null || mineAt == null) return stored;
    final DateTime? theirs = stored.freshAt;
    if (theirs != null && theirs.isAfter(mineAt)) {
      // El documento es más nuevo que lo nuestro: lo habrá escrito otra sesión
      // (otro dispositivo). Manda el documento.
      return stored;
    }
    return mine;
  }

  /// Estado del permiso, con tope de tiempo: un canal nativo que no contesta no
  /// puede dejar el refresco colgado (y con él `_inFlight`) el resto de la sesión.
  Future<LocationAuthorization> _authorization() => _source
      .authorization()
      .timeout(LocationRefreshPolicy.deviceCallTimeout,
          onTimeout: () => LocationAuthorization.unknown);

  Future<LocationFix?> _lastKnownFix() => _source.lastKnownFix().timeout(
      LocationRefreshPolicy.deviceCallTimeout,
      onTimeout: () => null);

  LocationNotice _notice(
    StoredLocation stored,
    LocationAuthorization permission,
    bool travelActive,
  ) =>
      LocationRefreshPolicy.notice(
        stored: stored,
        now: _clock(),
        permission: permission,
        travelActive: travelActive,
        permissionAskFailed: _permissionAskFailed,
      );
}
