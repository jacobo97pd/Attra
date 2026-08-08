import 'package:attra/src/features/auth/domain/location_refresh_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lógica de DECISIÓN del refresco de ubicación.
///
/// El fallo que cubre: la ubicación se capturaba una única vez en la vida de la
/// cuenta, así que quien se registró en Madrid y se mudó a Valencia seguía
/// apareciendo en Madrid para siempre (y solo veía gente de Valencia activando
/// el modo viaje a mano).
///
/// Geolocator es canal nativo y no se puede probar: por eso toda la decisión
/// vive en esta clase pura y aquí se prueba entera.
void main() {
  final DateTime now = DateTime.utc(2026, 8, 5, 12, 0);

  // Madrid y Valencia (a ~300 km): "mudarse" de verdad.
  const double madridLat = 40.4168;
  const double madridLng = -3.7038;
  const double valenciaLat = 39.4699;
  const double valenciaLng = -0.3763;

  StoredLocation madrid({Duration? age}) => StoredLocation(
        latitude: madridLat,
        longitude: madridLng,
        updatedAt: age == null ? null : now.subtract(age),
      );

  LocationRefreshPlan plan({
    StoredLocation? stored,
    LocationAuthorization permission = LocationAuthorization.granted,
    // Por defecto `appResume` sin ausencia: es el disparador que NO acorta la
    // ventana de frescura, así que deja ver el comportamiento de cada caso.
    LocationRefreshTrigger trigger = LocationRefreshTrigger.appResume,
    bool travelActive = false,
    DateTime? lastFixAt,
    Duration? awayFor,
  }) =>
      LocationRefreshPolicy.decide(
        stored: stored ?? madrid(age: const Duration(minutes: 30)),
        now: now,
        permission: permission,
        trigger: trigger,
        travelActive: travelActive,
        lastFixAt: lastFixAt,
        awayFor: awayFor,
      );

  group('¿toca refrescar?', () {
    test('sin coordenadas guardadas: se intenta todo', () {
      final LocationRefreshPlan p = plan(stored: StoredLocation.empty);

      expect(p.reason, LocationRefreshReason.missing);
      expect(p.readCache, isTrue);
      expect(p.requestFix, isTrue);
    });

    test('ubicación reciente: solo la lectura barata, NADA de GPS', () {
      final LocationRefreshPlan p =
          plan(stored: madrid(age: const Duration(hours: 1)));

      expect(p.reason, LocationRefreshReason.fresh);
      expect(p.readCache, isTrue,
          reason: 'la última posición conocida es gratis y detecta la llegada '
              'a otra ciudad sin despertar el GPS');
      expect(p.requestFix, isFalse);
    });

    test('ubicación rancia (más de 4 h): se pide fix', () {
      final LocationRefreshPlan p =
          plan(stored: madrid(age: const Duration(hours: 5)));

      expect(p.reason, LocationRefreshReason.stale);
      expect(p.requestFix, isTrue);
    });

    test('justo en el umbral (4 h exactas) ya cuenta como rancia', () {
      final LocationRefreshPlan p =
          plan(stored: madrid(age: LocationRefreshPolicy.staleAfter));

      expect(p.reason, LocationRefreshReason.stale);
      expect(p.requestFix, isTrue);
    });

    test('coordenadas SIN marca de tiempo: se tratan como rancias', () {
      // Es el estado real de producción: los perfiles publicados no tenían
      // ninguna marca de frescura, así que no había forma de saber si la
      // ubicación era de hoy o de hace tres meses.
      final LocationRefreshPlan p = plan(stored: madrid());

      expect(p.reason, LocationRefreshReason.unknownAge);
      expect(p.requestFix, isTrue);
    });

    test('la app vuelve del fondo: mismas reglas que al arrancar', () {
      final LocationRefreshPlan p = plan(
        stored: madrid(age: const Duration(hours: 6)),
        trigger: LocationRefreshTrigger.appResume,
      );

      expect(p.requestFix, isTrue);
    });

    test('la marca que cuenta es la de la MEDICIÓN, no la de la escritura', () {
      // Sin cobertura, la escritura se confirma horas después: una posición del
      // kilómetro 300 quedaba sellada con `updatedAt` de la llegada y la política
      // la daba por fresquísima justo cuando el usuario había cambiado de ciudad.
      final LocationRefreshPlan p = plan(
        stored: StoredLocation(
          latitude: madridLat,
          longitude: madridLng,
          updatedAt: now.subtract(const Duration(minutes: 1)),
          measuredAt: now.subtract(const Duration(hours: 5)),
        ),
      );

      expect(p.reason, LocationRefreshReason.stale);
      expect(p.requestFix, isTrue);
    });
  });

  group('la app no ha estado delante', () {
    test('arranque en frío: una ubicación de 2 h ya no vale', () {
      // Valencia→Madrid en AVE son 1 h 50 min: con las 4 h a secas, al llegar la
      // ubicación seguía siendo "fresca", no se pedía fix y el usuario se quedaba
      // viendo gente de Valencia sin ninguna forma de arreglarlo.
      final LocationRefreshPlan p = plan(
        stored: madrid(age: const Duration(hours: 2)),
        trigger: LocationRefreshTrigger.appStart,
      );

      expect(p.reason, LocationRefreshReason.stale);
      expect(p.requestFix, isTrue);
    });

    test('arranque en frío recién hecho: no se repite el fix', () {
      // El precio de lo anterior está acotado: si se acaba de medir, no se pide.
      final LocationRefreshPlan p = plan(
        stored: madrid(age: const Duration(minutes: 10)),
        trigger: LocationRefreshTrigger.appStart,
      );

      expect(p.reason, LocationRefreshReason.fresh);
      expect(p.requestFix, isFalse);
    });

    test('vuelta del fondo tras media hora: se mira de verdad', () {
      final LocationRefreshPlan p = plan(
        stored: madrid(age: const Duration(hours: 2)),
        trigger: LocationRefreshTrigger.appResume,
        awayFor: const Duration(minutes: 45),
      );

      expect(p.requestFix, isTrue);
    });

    test('mirar WhatsApp y volver no cuenta como ausencia', () {
      final LocationRefreshPlan p = plan(
        stored: madrid(age: const Duration(hours: 2)),
        trigger: LocationRefreshTrigger.appResume,
        awayFor: const Duration(seconds: 40),
      );

      expect(p.reason, LocationRefreshReason.fresh);
      expect(p.requestFix, isFalse);
    });
  });

  group('cooldown', () {
    test('dos vueltas del fondo seguidas: la segunda no vuelve a gastar GPS',
        () {
      final LocationRefreshPlan p = plan(
        stored: madrid(age: const Duration(hours: 6)),
        trigger: LocationRefreshTrigger.appResume,
        lastFixAt: now.subtract(const Duration(minutes: 2)),
      );

      expect(p.reason, LocationRefreshReason.cooldown);
      expect(p.requestFix, isFalse);
      expect(p.readCache, isTrue,
          reason: 'la lectura barata NO se limita: es gratis y es la que detecta '
              'que has llegado a otra ciudad');
    });

    test('pasado el cooldown vuelve a intentarlo', () {
      final LocationRefreshPlan p = plan(
        stored: madrid(age: const Duration(hours: 6)),
        trigger: LocationRefreshTrigger.appResume,
        lastFixAt: now.subtract(LocationRefreshPolicy.fixCooldown * 1.5),
      );

      expect(p.requestFix, isTrue);
    });

    test('un gesto del usuario salta el cooldown Y la frescura', () {
      final LocationRefreshPlan p = plan(
        stored: madrid(age: const Duration(minutes: 1)),
        trigger: LocationRefreshTrigger.manual,
        lastFixAt: now.subtract(const Duration(seconds: 5)),
      );

      expect(p.reason, LocationRefreshReason.forced);
      expect(p.requestFix, isTrue);
    });

    test('recargar el feed mira la ubicación aunque parezca fresca', () {
      // Un feed vacío en la ciudad de la que te mudaste se ve igual que un feed
      // vacío de verdad, así que vale la pena volver a mirar.
      final LocationRefreshPlan p = plan(
        stored: madrid(age: const Duration(minutes: 1)),
        trigger: LocationRefreshTrigger.feedReload,
      );

      expect(p.reason, LocationRefreshReason.forced);
      expect(p.requestFix, isTrue);
      expect(p.askPermission, isFalse,
          reason: '"Recargar" no habla de ubicación: un diálogo del sistema ahí '
              'no se entendería y iOS lo penaliza');
    });

    test('pero "Recargar" NO salta el cooldown: es el botón del síntoma', () {
      // El feed vacío es justo el síntoma de la ubicación equivocada, así que se
      // pulsa en ráfagas: N pulsaciones no pueden ser N encendidos del GPS.
      final LocationRefreshPlan p = plan(
        stored: madrid(age: const Duration(minutes: 1)),
        trigger: LocationRefreshTrigger.feedReload,
        lastFixAt: now.subtract(const Duration(seconds: 5)),
      );

      expect(p.reason, LocationRefreshReason.cooldown);
      expect(p.requestFix, isFalse);
      expect(p.readCache, isTrue);
    });

    test('apagar el modo viaje fuerza un refresco', () {
      final LocationRefreshPlan p = plan(
        stored: madrid(age: const Duration(minutes: 1)),
        trigger: LocationRefreshTrigger.travelEnded,
      );

      expect(p.requestFix, isTrue);
    });
  });

  group('permisos', () {
    test('denegado: al arrancar NO se abre el diálogo del sistema', () {
      final LocationRefreshPlan p =
          plan(permission: LocationAuthorization.denied);

      expect(p.reason, LocationRefreshReason.permissionNeeded);
      expect(p.askPermission, isFalse);
      expect(p.touchesDevice, isFalse);
    });

    test('denegado: un gesto explícito SÍ puede pedirlo', () {
      final LocationRefreshPlan p = plan(
        permission: LocationAuthorization.denied,
        trigger: LocationRefreshTrigger.manual,
      );

      expect(p.askPermission, isTrue);
    });

    test('sin preguntar todavía: tampoco se pide sin gesto', () {
      expect(plan(permission: LocationAuthorization.unknown).askPermission,
          isFalse);
      expect(
        plan(
          permission: LocationAuthorization.unknown,
          trigger: LocationRefreshTrigger.manual,
        ).askPermission,
        isTrue,
      );
    });

    test('estado del permiso ilegible: se intenta la vía barata, no se aborta',
        () {
      // `authorization()` devuelve `unknown` ante cualquier excepción del canal
      // nativo (plugin todavía sin registrar al arrancar). Tratarlo como una
      // negativa cancelaba hasta la lectura GRATIS y encima acusaba al usuario de
      // no haber dado un permiso que sí había dado.
      final LocationRefreshPlan p =
          plan(permission: LocationAuthorization.unknown);

      expect(p.reason, LocationRefreshReason.permissionUnknown);
      expect(p.readCache, isTrue);
      expect(p.requestFix, isFalse, reason: 'sin permiso confirmado, sin GPS');
    });

    test('denegado para siempre: no se pide ni con gesto (no abre nada)', () {
      final LocationRefreshPlan p = plan(
        permission: LocationAuthorization.deniedForever,
        trigger: LocationRefreshTrigger.manual,
      );

      expect(p.reason, LocationRefreshReason.permissionBlocked);
      expect(p.touchesDevice, isFalse);
    });

    test('localización del dispositivo apagada: no se intenta nada', () {
      final LocationRefreshPlan p =
          plan(permission: LocationAuthorization.serviceDisabled);

      expect(p.reason, LocationRefreshReason.permissionBlocked);
      expect(p.touchesDevice, isFalse);
    });

    test('el vocabulario persistido es el del onboarding', () {
      // El feed guardaba aquí el nombre del enum de Geolocator ('whileInUse'),
      // así que el mismo campo tenía dos vocabularios según quién lo escribiera.
      expect(LocationAuthorization.granted.wireName, 'granted');
      expect(LocationAuthorization.denied.wireName, 'denied');
      expect(LocationAuthorization.deniedForever.wireName, 'denied_forever');
      expect(
          LocationAuthorization.serviceDisabled.wireName, 'service_disabled');
      expect(LocationAuthorization.unknown.wireName, 'unknown');
    });
  });

  group('modo viaje (no se puede pisar)', () {
    test('viajando no se gasta GPS, pero sí se lee la caché', () {
      final LocationRefreshPlan p = plan(
        stored: madrid(age: const Duration(days: 3)),
        travelActive: true,
      );

      expect(p.reason, LocationRefreshReason.traveling);
      expect(p.requestFix, isFalse,
          reason: 'el feed está anclado al destino: un fix activo solo gastaría '
              'batería sin cambiar nada de lo que ve el usuario');
      expect(p.readCache, isTrue,
          reason: 'la ubicación REAL tiene que seguir guardándose en '
              'users/{uid} aunque no se publique');
    });

    test('viajando SIN coordenadas sí se pide fix (hace falta un "yo")', () {
      final LocationRefreshPlan p = plan(
        stored: StoredLocation.empty,
        travelActive: true,
      );

      expect(p.requestFix, isTrue);
    });

    test('viajando, un gesto explícito manda', () {
      final LocationRefreshPlan p = plan(
        stored: madrid(age: const Duration(days: 3)),
        travelActive: true,
        trigger: LocationRefreshTrigger.manual,
      );

      expect(p.requestFix, isTrue);
    });
  });

  group('¿se guarda la lectura?', () {
    LocationFix fix({
      double lat = madridLat,
      double lng = madridLng,
      Duration? age,
      bool fromCache = false,
    }) =>
        LocationFix(
          latitude: lat,
          longitude: lng,
          timestamp: age == null ? null : now.subtract(age),
          fromCache: fromCache,
        );

    test('sin nada guardado, cualquier lectura vale', () {
      final LocationPersistDecision d = LocationRefreshPolicy.shouldPersist(
        stored: StoredLocation.empty,
        fix: fix(),
        now: now,
      );

      expect(d.persist, isTrue);
      expect(d.reason, LocationPersistReason.noCoordinates);
    });

    test('mudanza a otra ciudad: se guarda aunque la marca sea reciente', () {
      final LocationPersistDecision d = LocationRefreshPolicy.shouldPersist(
        stored: madrid(age: const Duration(minutes: 5)),
        fix: fix(lat: valenciaLat, lng: valenciaLng),
        now: now,
      );

      expect(d.persist, isTrue);
      expect(d.reason, LocationPersistReason.moved);
    });

    test('mismo sitio y marca reciente: no se escribe', () {
      final LocationPersistDecision d = LocationRefreshPolicy.shouldPersist(
        stored: madrid(age: const Duration(minutes: 5)),
        // Un par de calles más allá.
        fix: fix(lat: madridLat + 0.01, lng: madridLng + 0.01),
        now: now,
      );

      expect(d.persist, isFalse);
      expect(d.reason, LocationPersistReason.unchanged);
    });

    test('mismo sitio pero marca rancia: se escribe para refrescar la marca',
        () {
      // Si no, el siguiente arranque volvería a pedir GPS eternamente.
      final LocationPersistDecision d = LocationRefreshPolicy.shouldPersist(
        stored: madrid(age: const Duration(hours: 9)),
        fix: fix(),
        now: now,
      );

      expect(d.persist, isTrue);
      expect(d.reason, LocationPersistReason.staleStamp);
    });

    test('coordenadas sin marca: se escribe (para ponerle marca)', () {
      final LocationPersistDecision d = LocationRefreshPolicy.shouldPersist(
        stored: madrid(),
        fix: fix(),
        now: now,
      );

      expect(d.persist, isTrue);
      expect(d.reason, LocationPersistReason.staleStamp);
    });

    test('con radio pequeño se escribe antes (el umbral lo pone el feed)', () {
      // El slider de "Distancia máxima" baja hasta 1 km: con un radio de 2 km, no
      // guardar un movimiento de 9 km actualizaba TU feed y no el que ven los
      // demás, así que dabas likes a vecinos que no te podían ver.
      final LocationPersistDecision d = LocationRefreshPolicy.shouldPersist(
        stored: madrid(age: const Duration(minutes: 5)),
        // ~9 km al norte.
        fix: fix(lat: madridLat + 0.081),
        now: now,
        moveThresholdKm: 1,
      );

      expect(d.persist, isTrue);
      expect(d.reason, LocationPersistReason.moved);
    });

    test('el umbral que pida el feed nunca sube del tope ni baja del suelo', () {
      // Por debajo de 1 km la escritura no cambiaría nada: las coordenadas
      // públicas se redondean a ~1,1 km.
      expect(
        LocationRefreshPolicy.shouldPersist(
          stored: madrid(age: const Duration(minutes: 5)),
          fix: fix(lat: madridLat + 0.002),
          now: now,
          moveThresholdKm: 0.05,
        ).persist,
        isFalse,
      );
      // Y por encima del tope tampoco: un radio de 200 km no puede dejar de
      // publicar una mudanza de 30 km.
      expect(
        LocationRefreshPolicy.shouldPersist(
          stored: madrid(age: const Duration(minutes: 5)),
          fix: fix(lat: madridLat + 0.27),
          now: now,
          moveThresholdKm: 100,
        ).persist,
        isTrue,
      );
    });

    test('una lectura cacheada más vieja que lo guardado no retrocede', () {
      final LocationPersistDecision d = LocationRefreshPolicy.shouldPersist(
        stored: madrid(age: const Duration(hours: 1)),
        fix: fix(
          lat: valenciaLat,
          lng: valenciaLng,
          age: const Duration(hours: 6),
          fromCache: true,
        ),
        now: now,
      );

      expect(d.persist, isFalse);
      expect(d.reason, LocationPersistReason.cacheOlderThanStored);
    });
  });

  group('¿es creíble la lectura cacheada?', () {
    test('reciente: sí (es la vía barata que detecta la llegada)', () {
      expect(
        LocationRefreshPolicy.isCacheUsable(
          fix: LocationFix(
            latitude: valenciaLat,
            longitude: valenciaLng,
            timestamp: now.subtract(const Duration(minutes: 5)),
            fromCache: true,
          ),
          now: now,
        ),
        isTrue,
      );
    });

    test('vieja: no se guarda como "donde estoy ahora"', () {
      expect(
        LocationRefreshPolicy.isCacheUsable(
          fix: LocationFix(
            latitude: valenciaLat,
            longitude: valenciaLng,
            timestamp: now.subtract(const Duration(hours: 3)),
            fromCache: true,
          ),
          now: now,
        ),
        isFalse,
      );
    });

    test('sin marca de tiempo: no se puede fechar, no se cree', () {
      expect(
        LocationRefreshPolicy.isCacheUsable(
          fix: const LocationFix(
              latitude: madridLat, longitude: madridLng, fromCache: true),
          now: now,
        ),
        isFalse,
      );
    });

    test('un fix activo siempre vale (lo acabamos de pedir)', () {
      expect(
        LocationRefreshPolicy.isCacheUsable(
          fix: const LocationFix(latitude: madridLat, longitude: madridLng),
          now: now,
        ),
        isTrue,
      );
    });

    test('marca en el futuro: se tolera un desajuste de reloj, no días', () {
      LocationFix ahead(Duration by) => LocationFix(
            latitude: madridLat,
            longitude: madridLng,
            timestamp: now.add(by),
            fromCache: true,
          );

      expect(
        LocationRefreshPolicy.isCacheUsable(
            fix: ahead(const Duration(minutes: 1)), now: now),
        isTrue,
      );
      expect(
        LocationRefreshPolicy.isCacheUsable(
            fix: ahead(const Duration(days: 3)), now: now),
        isFalse,
        reason: 'una marca adelantada días no es "donde estoy ahora", y se '
            'quedaba sellada como fresca',
      );
    });
  });

  group('qué se le cuenta al usuario', () {
    LocationNotice notice({
      StoredLocation? stored,
      LocationAuthorization permission = LocationAuthorization.granted,
      bool travelActive = false,
      bool permissionAskFailed = false,
    }) =>
        LocationRefreshPolicy.notice(
          stored: stored ?? madrid(age: const Duration(minutes: 10)),
          now: now,
          permission: permission,
          travelActive: travelActive,
          permissionAskFailed: permissionAskFailed,
        );

    test('permiso denegado y SIN ubicación: se ofrece activarlo', () {
      expect(
        notice(
          stored: StoredLocation.empty,
          permission: LocationAuthorization.denied,
        ),
        LocationNotice.permissionAskable,
      );
    });

    test('permiso denegado pero con ubicación buena: no se miente ni se mendiga',
        () {
      // Es el estado de "Permitir una vez" en iOS: la sesión guardó coordenadas
      // buenas y en el arranque siguiente el sistema devuelve notDetermined, que
      // el plugin mapea a denegado. El feed SIGUE filtrando por radio con esas
      // coordenadas, así que un banner rojo diciendo "te enseñamos gente de tu
      // país, no de tu zona" era falso, permanente y no cambiaba nada.
      expect(notice(permission: LocationAuthorization.denied),
          LocationNotice.none);
    });

    test('estado del permiso ilegible: no se acusa al usuario', () {
      // `unknown` puede ser un fallo pasajero del canal nativo.
      expect(
        notice(
          stored: StoredLocation.empty,
          permission: LocationAuthorization.unknown,
        ),
        LocationNotice.stale,
      );
      expect(notice(permission: LocationAuthorization.unknown),
          LocationNotice.none);
    });

    test('gesto que no consiguió el permiso: se manda a Ajustes', () {
      // iOS `restricted` (Screen Time/MDM): pedirlo otra vez no abre nada, así
      // que "Activar" sería un botón que no puede funcionar.
      expect(
        notice(
          stored: StoredLocation.empty,
          permission: LocationAuthorization.denied,
          permissionAskFailed: true,
        ),
        LocationNotice.permissionBlocked,
      );
    });

    test('denegado para siempre: hay que ir a Ajustes del sistema', () {
      expect(notice(permission: LocationAuthorization.deniedForever),
          LocationNotice.permissionBlocked);
    });

    test('localización apagada: se dice tal cual', () {
      expect(notice(permission: LocationAuthorization.serviceDisabled),
          LocationNotice.serviceDisabled);
    });

    test('todo en orden: no se molesta al usuario', () {
      expect(notice(), LocationNotice.none);
    });

    test('con permiso pero la ubicación sigue vieja: se avisa', () {
      // Con permiso concedido el refresco debería mantenerla en menos de 4 h: si
      // lleva más de un día es que está fallando, y antes eso era invisible.
      expect(notice(stored: madrid(age: const Duration(days: 2))),
          LocationNotice.stale);
    });

    test('con permiso y sin coordenadas: se avisa', () {
      expect(notice(stored: StoredLocation.empty), LocationNotice.stale);
    });

    test('coordenadas sin marca: no se afirma que estén viejas', () {
      // El refresco ya las va a intentar; si funciona, el aviso no habría
      // aportado nada.
      expect(notice(stored: madrid()), LocationNotice.none);
    });

    test('viajando no hay aviso de ubicación (el feed del destino es a propósito)',
        () {
      expect(
        notice(stored: madrid(age: const Duration(days: 30)),
            travelActive: true),
        LocationNotice.none,
      );
    });
  });

  test('la distancia usada para decidir es real (Madrid-Valencia ~300 km)', () {
    final double km = LocationRefreshPolicy.distanceKm(
        madridLat, madridLng, valenciaLat, valenciaLng);

    expect(km, greaterThan(280));
    expect(km, lessThan(320));
    expect(km, greaterThan(LocationRefreshPolicy.significantMoveKm));
  });
}
