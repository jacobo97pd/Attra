/// Estado REAL de la referencia visual del usuario, tal y como lo ve el BACKEND.
///
/// Antes la pantalla deducía "referencia lista" de que existiera un fichero en
/// Storage, así que enseñaba "Referencia lista ✓" aunque `analyzeReferencePhoto`
/// hubiera devuelto `pending_provider` (sin huella visual): el usuario creía que
/// la búsqueda de parecidos iba a funcionar y no funcionaba.
enum AiReferenceStatus {
  /// No hay foto de referencia.
  none,

  /// Foto subida y análisis en curso (solo mientras dura la llamada).
  processing,

  /// Hay foto Y huella visual en el backend: la búsqueda de parecidos funciona.
  ready,

  /// Hay foto pero el backend NO pudo generar la huella visual (motor caído o
  /// sin habilitar). La búsqueda de parecidos no devolvería nada.
  unavailable,

  /// El backend rechaza la operación: Pro caducado, consentimiento retirado o
  /// IA deshabilitada por configuración.
  denied,

  /// No se pudo comprobar (sin conexión / error de red). No afirmamos nada.
  unknown,
}

/// Foto de referencia + estado real de su huella visual.
class AiReferenceState {
  const AiReferenceState({
    required this.status,
    this.photoUrl,
    this.detail,
  });

  static const AiReferenceState empty =
      AiReferenceState(status: AiReferenceStatus.none);

  final AiReferenceStatus status;

  /// URL de la foto de referencia actual (null si no hay o no se pudo leer).
  final String? photoUrl;

  /// Mensaje del backend cuando el estado es [AiReferenceStatus.denied] o
  /// [AiReferenceStatus.unknown]; se enseña tal cual al usuario.
  final String? detail;

  bool get hasPhoto => photoUrl != null && photoUrl!.isNotEmpty;

  /// Única condición bajo la que tiene sentido ofrecer "Buscar parecidos".
  bool get canSearch => status == AiReferenceStatus.ready;

  /// Etiqueta corta para la fila "Estado" del panel de la IA.
  String get label {
    switch (status) {
      case AiReferenceStatus.none:
        return 'Sin referencia aún';
      case AiReferenceStatus.processing:
        return 'Analizando…';
      case AiReferenceStatus.ready:
        return 'Referencia lista ✓';
      case AiReferenceStatus.unavailable:
        return 'Guardada, sin análisis';
      case AiReferenceStatus.denied:
        return 'No disponible';
      case AiReferenceStatus.unknown:
        return 'Sin comprobar';
    }
  }

  /// Explicación honesta de qué significa el estado para el usuario.
  String get explanation {
    switch (status) {
      case AiReferenceStatus.none:
        return 'Sube una foto de referencia para activar la búsqueda de parecidos.';
      case AiReferenceStatus.processing:
        return 'Estamos analizando tu foto de referencia.';
      case AiReferenceStatus.ready:
        return 'Tu huella visual está lista: ya podemos buscar perfiles parecidos.';
      case AiReferenceStatus.unavailable:
        return 'Tu foto está guardada, pero el motor de IA no pudo analizarla, '
            'así que la búsqueda de parecidos no devolvería resultados. '
            'Inténtalo de nuevo con otra foto o más tarde.';
      case AiReferenceStatus.denied:
        return detail ??
            'La IA visual no está disponible con tu plan o configuración actual.';
      case AiReferenceStatus.unknown:
        return detail ??
            'No hemos podido comprobar el estado de tu referencia. Revisa tu conexión.';
    }
  }

  AiReferenceState copyWith({
    AiReferenceStatus? status,
    String? photoUrl,
    String? detail,
    bool clearPhoto = false,
  }) {
    return AiReferenceState(
      status: status ?? this.status,
      photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
      detail: detail ?? this.detail,
    );
  }
}

/// Resultado del borrado de datos de IA (RGPD). Antes `clearAiData` solo
/// llamaba al backend y las fotos de referencia seguían en Storage, así que el
/// usuario creía haber borrado algo que no se había borrado.
class AiDataDeletion {
  const AiDataDeletion({
    required this.deletedPhotos,
    required this.remainingPhotos,
    required this.verified,
  });

  /// Fotos de referencia efectivamente eliminadas por el cliente.
  final int deletedPhotos;

  /// Fotos que seguían ahí tras el intento de borrado.
  final int remainingPhotos;

  /// false si ni siquiera se pudo listar Storage: no podemos AFIRMAR que no
  /// quede nada, así que tampoco se lo decimos al usuario.
  final bool verified;

  bool get isComplete => verified && remainingPhotos == 0;
}
