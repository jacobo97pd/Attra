import 'dart:math' as math;

/// Decide CUÁNDO hay que volver a mirar dónde está el usuario y cuándo hay que
/// guardarlo. Es lógica PURA a propósito: Geolocator es canal nativo y no se
/// puede probar en `flutter test`, así que la decisión vive aquí (testeable) y
/// el acceso al GPS en [DeviceLocationSource].
///
/// El fallo que arregla: la ubicación se capturaba UNA sola vez en la vida de
/// la cuenta (`if (user.latitude != null) return;`). Quien se registró en
/// Madrid y se mudó a Valencia seguía siendo de Madrid para siempre, y solo
/// veía gente de Valencia activando el modo viaje a mano.

/// Estado del permiso, independiente del plugin. Se traduce en la capa de datos
/// para que esta política no dependa de Geolocator (ni de Flutter).
enum LocationAuthorization {
  /// Todavía no se ha preguntado (o el sistema no lo sabe).
  unknown,

  /// Concedido (whileInUse o always: para nosotros es lo mismo, solo pedimos
  /// ubicación con la app en primer plano).
  granted,

  /// Denegado, pero el sistema PERMITE volver a preguntar.
  denied,

  /// Denegado para siempre: pedirlo otra vez no abre ningún diálogo. La única
  /// salida es Ajustes del sistema.
  deniedForever,

  /// Localización apagada en el dispositivo (el permiso da igual).
  serviceDisabled;

  /// Vocabulario que se persiste en `users/{uid}.location.permissionStatus`.
  /// Es el MISMO que ya escribe el onboarding ('granted', 'denied',
  /// 'denied_forever', 'service_disabled'): antes el feed guardaba aquí el
  /// nombre del enum de Geolocator ('whileInUse', 'always'…), así que el mismo
  /// campo tenía dos vocabularios según quién lo hubiera escrito.
  String get wireName {
    switch (this) {
      case LocationAuthorization.granted:
        return 'granted';
      case LocationAuthorization.denied:
        return 'denied';
      case LocationAuthorization.deniedForever:
        return 'denied_forever';
      case LocationAuthorization.serviceDisabled:
        return 'service_disabled';
      case LocationAuthorization.unknown:
        return 'unknown';
    }
  }

  bool get isGranted => this == LocationAuthorization.granted;
}

/// Qué ha disparado el intento. Importa porque NO todos pueden abrir el diálogo
/// del sistema ni gastar GPS: iOS penaliza en revisión que se pida el permiso
/// sin que el usuario entienda por qué, así que solo [manual] (un gesto
/// explícito sobre un aviso que lo explica) puede pedirlo.
enum LocationRefreshTrigger {
  /// Arranque del feed.
  appStart,

  /// La app vuelve del fondo (alguien que viaja abre la app al llegar).
  appResume,

  /// Gesto explícito sobre el aviso de ubicación. Es el ÚNICO que puede abrir el
  /// diálogo del sistema.
  manual,

  /// El usuario recarga el feed a mano ("Recargar" del estado vacío). Un feed
  /// vacío en la ciudad equivocada es indistinguible de un feed vacío de verdad,
  /// así que vale la pena volver a mirar dónde está. No pide permiso (el botón no
  /// habla de ubicación y un diálogo del sistema ahí no se entendería) y RESPETA
  /// el cooldown del fix: es el botón del síntoma, se pulsa en ráfagas.
  feedReload,

  /// Se acaba de desactivar el modo viaje: las coordenadas guardadas pueden ser
  /// de antes del viaje y ahora SÍ se publican.
  travelEnded,
}

/// Ubicación tal como está guardada en `users/{uid}.location`.
class StoredLocation {
  const StoredLocation({
    this.latitude,
    this.longitude,
    this.updatedAt,
    this.measuredAt,
  });

  final double? latitude;
  final double? longitude;

  /// `users/{uid}.location.updatedAt`. En producción hay documentos SIN esta
  /// marca (se escribía, pero nadie la leía), así que "sin marca" no puede
  /// significar "reciente": ver [LocationRefreshReason.unknownAge].
  final DateTime? updatedAt;

  /// `users/{uid}.location.fixedAt`: cuándo se MIDIÓ la posición.
  ///
  /// No es lo mismo que [updatedAt], que es cuándo se ESCRIBIÓ (serverTimestamp,
  /// lo pone el servidor al confirmar). Sin cobertura, la escritura queda
  /// pendiente y se confirma al recuperar red: una posición del kilómetro 300
  /// quedaba sellada como "medida ahora mismo" al llegar a destino, y la política
  /// la daba por fresquísima durante 4 h justo cuando había cambiado de ciudad.
  final DateTime? measuredAt;

  /// Marca con la que se decide la frescura: la de la MEDICIÓN si la hay y, si
  /// no, la de la escritura (documentos anteriores a `fixedAt`).
  DateTime? get freshAt => measuredAt ?? updatedAt;

  bool get hasCoordinates => latitude != null && longitude != null;

  static const StoredLocation empty = StoredLocation();
}

/// Una lectura del dispositivo. `fromCache` distingue la lectura BARATA (última
/// posición conocida que ya tiene el sistema operativo: no despierta el GPS ni
/// enciende el indicador de localización de iOS) del fix ACTIVO.
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    this.timestamp,
    this.fromCache = false,
  });

  final double latitude;
  final double longitude;

  /// Momento en que el SISTEMA tomó la posición (no cuando la leímos). Un fix
  /// cacheado puede ser de hace días.
  final DateTime? timestamp;
  final bool fromCache;
}

/// Por qué se hace (o no) el intento.
enum LocationRefreshReason {
  /// No hay coordenadas guardadas.
  missing,

  /// Hay coordenadas, pero viejas.
  stale,

  /// Hay coordenadas sin marca de tiempo: no se puede saber si son de hoy o de
  /// hace tres meses, así que se tratan como viejas.
  unknownAge,

  /// El usuario lo ha pedido (o acaba de apagar el modo viaje).
  forced,

  /// Recientes: solo lectura barata de la caché, sin GPS.
  fresh,

  /// Haría falta un fix activo, pero se pidió uno hace muy poco: esta ronda se
  /// queda en la lectura barata (el ciclo de vida "resumed" salta cada vez que el
  /// usuario vuelve de otra app).
  cooldown,

  /// Hay otro intento en curso.
  inFlight,

  /// Falta el permiso y este disparador no puede pedirlo.
  permissionNeeded,

  /// No se ha podido averiguar el estado del permiso (canal nativo que falla al
  /// arrancar, plugin todavía sin registrar). NO es una negativa: se intenta la
  /// vía barata y se vuelve a mirar en la siguiente vuelta, sin acusar al usuario
  /// de no haber dado un permiso que puede tener concedido.
  permissionUnknown,

  /// Permiso denegado para siempre o localización apagada: no hay nada que
  /// intentar, solo avisar.
  permissionBlocked,

  /// Modo viaje activo: se mantiene la ubicación real al día por la vía barata,
  /// pero no se gasta GPS (el feed está anclado al destino de todas formas).
  traveling,
}

/// Qué hay que hacer en este intento.
class LocationRefreshPlan {
  const LocationRefreshPlan({
    required this.reason,
    this.askPermission = false,
    this.readCache = false,
    this.requestFix = false,
  });

  /// Abrir el diálogo del sistema.
  final bool askPermission;

  /// Leer la última posición conocida (gratis).
  final bool readCache;

  /// Pedir un fix activo (cuesta batería y enciende el indicador de iOS).
  final bool requestFix;

  final LocationRefreshReason reason;

  bool get touchesDevice => askPermission || readCache || requestFix;
}

/// Por qué se guarda (o no) una lectura.
enum LocationPersistReason {
  /// No había coordenadas: cualquier lectura es mejor que nada.
  noCoordinates,

  /// Se ha movido lo suficiente para cambiar de zona.
  moved,

  /// Mismo sitio, pero la marca de tiempo está vieja: hay que refrescarla o el
  /// siguiente arranque volvería a pedir GPS.
  staleStamp,

  /// Mismo sitio y marca reciente: no se escribe (evita una escritura y una
  /// republicación de `discovery` para nada).
  unchanged,

  /// La lectura cacheada es MÁS VIEJA que lo guardado: guardarla sería retroceder
  /// y encima mentir con una marca nueva.
  cacheOlderThanStored,
}

class LocationPersistDecision {
  const LocationPersistDecision(this.persist, this.reason);

  final bool persist;
  final LocationPersistReason reason;
}

/// Qué se le cuenta al usuario. Sin esto el fallo era invisible:
/// `_ensureDeviceLocation` se tragaba cualquier error y el feed enseñaba gente
/// de otra ciudad sin explicar nada.
enum LocationNotice {
  none,

  /// Se puede pedir el permiso con un gesto (aún no está bloqueado).
  permissionAskable,

  /// Denegado para siempre: hay que ir a Ajustes del sistema.
  permissionBlocked,

  /// Localización apagada en el dispositivo.
  serviceDisabled,

  /// Permiso concedido pero la ubicación sigue vieja (o no hay): los intentos
  /// están fallando y el usuario merece saberlo.
  stale,
}

/// Política de refresco. Los umbrales están aquí (y no repartidos por la UI)
/// para poder justificarlos y probarlos.
class LocationRefreshPolicy {
  const LocationRefreshPolicy._();

  /// A partir de aquí la ubicación se considera VIEJA y se permite un fix
  /// activo.
  ///
  /// 4 h es el punto de equilibrio para una app de citas: acertar la ciudad es
  /// el núcleo del producto, pero el fix cuesta batería y en iOS enciende el
  /// indicador de localización. Con 4 h, una mudanza o un viaje se detecta como
  /// muy tarde en la primera apertura 4 h después de llegar, y un usuario que
  /// abre la app veinte veces al día gasta como máximo 6 fixes (siempre en
  /// primer plano, nunca en segundo plano, y de precisión baja).
  ///
  /// En la práctica casi nunca se llega a esperar 4 h: en cada vuelta del fondo
  /// se lee la última posición conocida del sistema, que es GRATIS, y con eso ya
  /// se detecta la llegada a otra ciudad (ver [cacheUsableFor]).
  static const Duration staleAfter = Duration(hours: 4);

  /// Ventana de frescura cuando la app NO ha estado delante: arranque en frío o
  /// vuelta del fondo tras un buen rato.
  ///
  /// Con las 4 h de [staleAfter] a secas había un agujero garantizado: Valencia →
  /// Madrid en AVE son 1 h 50 min, así que al llegar la ubicación seguía siendo
  /// "fresca", no se pedía fix, y si la última posición conocida del sistema no
  /// servía (en iOS, tras arranque en frío, suele no servir) el usuario se
  /// quedaba viendo gente de Valencia sin ninguna forma de arreglarlo.
  ///
  /// Que la app no haya estado en primer plano durante media hora es una señal de
  /// viaje MUCHO más fuerte que el reloj: es justo el rato en el que uno se mueve.
  /// El precio es como mucho un fix (primer plano, precisión baja) por arranque
  /// separado más de media hora del anterior.
  static const Duration awayStaleAfter = Duration(minutes: 30);

  /// Mínimo entre dos FIXES ACTIVOS. `resumed` llega cada vez que el usuario
  /// vuelve de otra app (mirar WhatsApp y volver ya son dos), y cuando el fix
  /// falla —interiores, GPS sin señal— el plan sigue pidiéndolo: sin esta guarda,
  /// un rato de multitarea era una ráfaga de peticiones de GPS.
  ///
  /// NO limita la lectura de la última posición conocida: esa es gratis y es lo
  /// que detecta la llegada a otra ciudad en la primera apertura. Limitarla
  /// también retrasaba la detección sin ahorrar nada.
  static const Duration fixCooldown = Duration(minutes: 10);

  /// Antigüedad máxima para creer que la última posición conocida del sistema es
  /// "donde estoy AHORA". Más vieja que esto, no se guarda como si fuera actual
  /// (sería mentir con la marca de tiempo) y se deja pasar al fix activo.
  static const Duration cacheUsableFor = Duration(minutes: 30);

  /// Antigüedad máxima de la caché para que SUSTITUYA a un fix activo cuando el
  /// plan pedía fix.
  ///
  /// Es mucho más estricta que [cacheUsableFor] a propósito: en coche
  /// Valencia → Madrid, al llegar, la última posición conocida es de hace 20-25
  /// min y está en la A-3, a 60-100 km. Aceptarla como si fuera el fix la
  /// guardaba con marca nueva, dejaba al usuario publicado a 60 km y bloqueaba
  /// cualquier intento durante horas. Con 2 min, "cacheado" solo gana cuando el
  /// sistema acaba de medir (y entonces el fix daría lo mismo gastando batería).
  static const Duration cacheTrustedForFix = Duration(minutes: 2);

  /// Margen que se tolera si la marca de la caché está en el FUTURO (reloj del
  /// dispositivo desajustado). Sin tope, una marca adelantada días se aceptaba
  /// como "donde estoy ahora" y quedaba sellada como fresca.
  static const Duration clockSkewTolerance = Duration(minutes: 5);

  /// Movimiento que merece una escritura, salvo que quien llama pida un umbral
  /// menor (ver [shouldPersist]).
  ///
  /// Es un TOPE, no una constante universal: el radio del feed por defecto son
  /// 100 km ([FeedFilter.defaultRadiusKm]) pero el usuario puede bajarlo a 1 km,
  /// y con un radio pequeño publicar una posición 9 km desplazada te hace dar
  /// likes a vecinos que no te ven. Por eso el feed pasa la mitad de su radio
  /// efectivo y esto solo lo limita por arriba (para no escribir —y republicar
  /// `discovery`— por cada paseo).
  static const double significantMoveKm = 10;

  /// Suelo del umbral de escritura: las coordenadas publicadas se redondean a
  /// ~1,1 km, así que por debajo de 1 km la escritura no cambiaría nada de lo que
  /// ven los demás.
  static const double minMoveKm = 1;

  /// Con permiso concedido, si la ubicación sigue más vieja que esto es que los
  /// refrescos están fallando (GPS sin señal, timeout, escritura rechazada): se
  /// avisa en el feed en vez de dejarlo en silencio.
  static const Duration noticeAfter = Duration(days: 1);

  /// Tope del fix activo. Sin timeout, en interiores se queda colgado.
  static const Duration fixTimeout = Duration(seconds: 8);

  /// Tope de la ESCRITURA. Las futures de escritura de Firestore no completan
  /// hasta que el servidor confirma: sin red (túnel, avión) se quedan pendientes
  /// indefinidamente y el intento en curso no se soltaba nunca, así que todo
  /// refresco posterior de la sesión moría con `inFlight`. Justo el trayecto en
  /// el que más importa detectar el cambio de ciudad.
  static const Duration persistTimeout = Duration(seconds: 15);

  /// Tope de las llamadas al canal nativo que no lo traen de serie. Un canal que
  /// no contesta no puede dejar el refresco bloqueado para el resto de la sesión.
  static const Duration deviceCallTimeout = Duration(seconds: 5);

  /// ¿Toca refrescar y con qué medios?
  static LocationRefreshPlan decide({
    required StoredLocation stored,
    required DateTime now,
    required LocationAuthorization permission,
    required LocationRefreshTrigger trigger,
    bool travelActive = false,
    DateTime? lastFixAt,
    Duration? awayFor,
  }) {
    // Bloqueado por el sistema: pedirlo otra vez no abre ningún diálogo, así que
    // el único resultado posible es el aviso.
    if (permission == LocationAuthorization.serviceDisabled ||
        permission == LocationAuthorization.deniedForever) {
      return const LocationRefreshPlan(
          reason: LocationRefreshReason.permissionBlocked);
    }

    // No se ha podido leer el estado del permiso (canal nativo que falla en el
    // arranque). NO se trata como una negativa: se intenta la vía barata (que es
    // gratis y, si de verdad falta el permiso, devuelve null) y se vuelve a mirar
    // en la siguiente vuelta. Antes esto se traducía en un aviso rojo diciéndole
    // al usuario que no había dado un permiso que sí había dado.
    if (permission == LocationAuthorization.unknown) {
      return LocationRefreshPlan(
        askPermission: trigger == LocationRefreshTrigger.manual,
        readCache: true,
        reason: LocationRefreshReason.permissionUnknown,
      );
    }

    // Sin permiso: el diálogo del sistema SOLO tras un gesto explícito del
    // usuario sobre un aviso que explica para qué. Pedirlo al abrir el feed es
    // justo lo que iOS penaliza en revisión.
    if (!permission.isGranted) {
      return LocationRefreshPlan(
        askPermission: trigger == LocationRefreshTrigger.manual,
        reason: LocationRefreshReason.permissionNeeded,
      );
    }

    // Un gesto explícito (o apagar el viaje) salta el cooldown: detrás hay una
    // intención del usuario o un cambio de estado que lo justifica.
    //
    // "Recargar" del feed vacío NO lo salta: dice "Recargar", no "actualizar mi
    // ubicación", y al ser el botón del síntoma se pulsa en ráfagas. Sí cuenta
    // como motivo para mirar la ubicación (un feed vacío en la ciudad de la que
    // te mudaste se ve igual que un feed vacío de verdad), pero respetando el
    // cooldown: N pulsaciones ya no son N encendidos del GPS.
    final bool skipsCooldown = trigger == LocationRefreshTrigger.manual ||
        trigger == LocationRefreshTrigger.travelEnded;
    final bool asksForItself =
        skipsCooldown || trigger == LocationRefreshTrigger.feedReload;

    // La app no ha estado delante: en un arranque en frío es seguro (el proceso
    // no existía) y al volver del fondo lo dice [awayFor]. En ese caso la
    // ubicación caduca en [awayStaleAfter], no en [staleAfter].
    final bool wasAway = trigger == LocationRefreshTrigger.appStart ||
        (awayFor != null && awayFor >= awayStaleAfter);
    final Duration window = wasAway ? awayStaleAfter : staleAfter;

    final DateTime? freshAt = stored.freshAt;
    // Sin coordenadas no hay "yo" con el que calcular el radio del feed.
    final LocationRefreshReason reason = !stored.hasCoordinates
        ? LocationRefreshReason.missing
        : (freshAt == null
            ? LocationRefreshReason.unknownAge
            : (now.difference(freshAt) >= window
                ? LocationRefreshReason.stale
                : (asksForItself
                    ? LocationRefreshReason.forced
                    : LocationRefreshReason.fresh)));

    final bool wantsFix = reason != LocationRefreshReason.fresh;

    // Modo viaje: el feed está anclado al destino y las coordenadas reales NO se
    // publican, así que un fix activo no cambiaría nada de lo que ve el usuario:
    // solo gastaría batería. La vía barata sí se mantiene para que
    // `users/{uid}` conserve la ubicación real (al apagar el viaje se publica
    // ella). Un gesto explícito manda igual.
    //
    // Sin coordenadas se pide fix incluso viajando: al apagar el viaje hacen
    // falta, y mientras tanto el feed no tiene con qué medir distancias.
    if (travelActive &&
        stored.hasCoordinates &&
        trigger != LocationRefreshTrigger.manual) {
      return const LocationRefreshPlan(
        readCache: true,
        reason: LocationRefreshReason.traveling,
      );
    }

    // El cooldown frena SOLO el fix activo: la lectura de la última posición
    // conocida sigue haciéndose porque es gratis y es la que detecta una llegada.
    if (wantsFix &&
        !skipsCooldown &&
        lastFixAt != null &&
        now.difference(lastFixAt) < fixCooldown) {
      return const LocationRefreshPlan(
        readCache: true,
        reason: LocationRefreshReason.cooldown,
      );
    }

    return LocationRefreshPlan(
      readCache: true,
      requestFix: wantsFix,
      reason: reason,
    );
  }

  /// ¿Se puede creer que esta lectura cacheada es "donde estoy ahora"?
  static bool isCacheUsable({
    required LocationFix fix,
    required DateTime now,
  }) {
    if (!fix.fromCache) return true;
    final Duration? age = cacheAge(fix: fix, now: now);
    // Sin marca no se puede fechar: no se guarda como actual.
    if (age == null) return false;
    return age <= cacheUsableFor;
  }

  /// Antigüedad de una lectura cacheada, o null si no se puede fechar.
  ///
  /// Una marca en el futuro se tolera solo por [clockSkewTolerance] (reloj del
  /// dispositivo desajustado): más allá, la marca no es creíble y no se puede
  /// tratar la lectura como "donde estoy ahora".
  static Duration? cacheAge({
    required LocationFix fix,
    required DateTime now,
  }) {
    final DateTime? at = fix.timestamp;
    if (at == null) return null;
    final Duration age = now.difference(at);
    if (age.isNegative) {
      return age.abs() <= clockSkewTolerance ? Duration.zero : null;
    }
    return age;
  }

  /// ¿Merece la pena escribir esta lectura?
  ///
  /// [moveThresholdKm] permite bajar el umbral cuando el radio del feed es
  /// pequeño (se limita a [significantMoveKm] por arriba y a [minMoveKm] por
  /// abajo): con un radio de 2 km, no escribir un movimiento de 9 km dejaba al
  /// usuario likeando a vecinos que no le veían.
  static LocationPersistDecision shouldPersist({
    required StoredLocation stored,
    required LocationFix fix,
    required DateTime now,
    double? moveThresholdKm,
  }) {
    if (!stored.hasCoordinates) {
      return const LocationPersistDecision(
          true, LocationPersistReason.noCoordinates);
    }

    final DateTime? fixAt = fix.timestamp;
    final DateTime? storedAt = stored.freshAt;
    if (fix.fromCache &&
        fixAt != null &&
        storedAt != null &&
        fixAt.isBefore(storedAt)) {
      return const LocationPersistDecision(
          false, LocationPersistReason.cacheOlderThanStored);
    }

    final double threshold = moveThresholdKm == null
        ? significantMoveKm
        : moveThresholdKm.clamp(minMoveKm, significantMoveKm);
    final double moved = distanceKm(
      stored.latitude!,
      stored.longitude!,
      fix.latitude,
      fix.longitude,
    );
    if (moved >= threshold) {
      return const LocationPersistDecision(true, LocationPersistReason.moved);
    }
    if (storedAt == null || now.difference(storedAt) >= staleAfter) {
      return const LocationPersistDecision(
          true, LocationPersistReason.staleStamp);
    }
    return const LocationPersistDecision(
        false, LocationPersistReason.unchanged);
  }

  /// Qué aviso corresponde con lo que sabemos AHORA.
  ///
  /// [permissionAskFailed] = ya se pidió el permiso con un gesto y NO se
  /// consiguió. En iOS `restricted` (Screen Time/MDM) el diálogo no se abre
  /// nunca, así que insistir con "Activar" es un botón que no puede funcionar:
  /// se degrada a la variante de Ajustes.
  static LocationNotice notice({
    required StoredLocation stored,
    required DateTime now,
    required LocationAuthorization permission,
    bool travelActive = false,
    bool permissionAskFailed = false,
  }) {
    // Viajando el usuario ya tiene el aviso de "de viaje en X" y su feed es el
    // del destino a propósito: un segundo aviso de ubicación solo confundiría (y
    // sin permiso tampoco hace falta ubicación para ese feed).
    if (travelActive) return LocationNotice.none;
    switch (permission) {
      case LocationAuthorization.serviceDisabled:
        return LocationNotice.serviceDisabled;
      case LocationAuthorization.deniedForever:
        return LocationNotice.permissionBlocked;
      case LocationAuthorization.denied:
      case LocationAuthorization.unknown:
        // Con una ubicación creíble guardada el feed SÍ está filtrando por zona:
        // el aviso de permiso afirmaba lo contrario. Es el estado de "Permitir
        // una vez" en iOS, que en el arranque siguiente vuelve como notDetermined
        // (y el plugin lo mapea a denegado): un banner rojo permanente pidiendo
        // un permiso que no cambia nada de lo que el usuario ve.
        if (_isCredible(stored, now)) return LocationNotice.none;
        if (permissionAskFailed) return LocationNotice.permissionBlocked;
        // `unknown` no es una negativa (puede ser un fallo del canal nativo): se
        // cuenta lo que sí es verdad, que la ubicación no está al día.
        return permission == LocationAuthorization.unknown
            ? LocationNotice.stale
            : LocationNotice.permissionAskable;
      case LocationAuthorization.granted:
        if (!stored.hasCoordinates) return LocationNotice.stale;
        final DateTime? at = stored.freshAt;
        // Sin marca de tiempo no se puede afirmar que esté vieja: el refresco ya
        // la va a intentar y, si funciona, el aviso no habría aportado nada.
        if (at == null) return LocationNotice.none;
        return now.difference(at) >= noticeAfter
            ? LocationNotice.stale
            : LocationNotice.none;
    }
  }

  /// ¿Hay una ubicación guardada que se pueda seguir usando como "yo"?
  static bool _isCredible(StoredLocation stored, DateTime now) {
    if (!stored.hasCoordinates) return false;
    final DateTime? at = stored.freshAt;
    if (at == null) return false;
    return now.difference(at) < noticeAfter;
  }

  /// Distancia haversine en km. Duplica la de `FeedFilter._distanceKm` porque
  /// allí es privada y este módulo no debe depender del feed (lo usa también la
  /// capa de datos).
  static double distanceKm(
      double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371;
    final double dLat = _rad(lat2 - lat1);
    final double dLon = _rad(lon2 - lon1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(a)));
  }

  static double _rad(double deg) => deg * math.pi / 180;
}
