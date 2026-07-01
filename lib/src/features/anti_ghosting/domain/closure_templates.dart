/// Plantillas de "Cerrar con elegancia" (Attra Clear §3). Los `reason` son la
/// clave de cable (deben coincidir con `CLOSURE_REASONS` del backend en
/// `functions/src/chat.ts`).
class ClosureTemplate {
  const ClosureTemplate({
    required this.reason,
    required this.label,
    required this.message,
  });

  /// Clave estable enviada al backend (closedReason).
  final String reason;

  /// Etiqueta corta para el tile de selección.
  final String label;

  /// Texto completo que se enviará como mensaje de cierre.
  final String message;

  bool get isCustom => reason == 'custom';
}

/// Motivos válidos (espejo del backend). Sirve para validación defensiva.
const Set<String> kClosureReasons = <String>{
  'no_connection',
  'different_goals',
  'not_now',
  'save_time',
  'custom',
};

const List<ClosureTemplate> kClosureTemplates = <ClosureTemplate>[
  ClosureTemplate(
    reason: 'no_connection',
    label: 'No siento conexión romántica',
    message:
        'Me ha gustado hablar contigo, pero no siento conexión romántica. '
        'Te deseo lo mejor.',
  ),
  ClosureTemplate(
    reason: 'different_goals',
    label: 'Buscamos cosas distintas',
    message: 'Creo que buscamos cosas distintas, pero gracias por el rato.',
  ),
  ClosureTemplate(
    reason: 'not_now',
    label: 'No es mi momento',
    message:
        'Ahora mismo no estoy en el momento adecuado para seguir conociendo '
        'gente.',
  ),
  ClosureTemplate(
    reason: 'save_time',
    label: 'Prefiero ser sincero/a',
    message: 'Prefiero dejarlo aquí antes de hacerte perder tiempo.',
  ),
  ClosureTemplate(
    reason: 'custom',
    label: 'Escribir mi propio mensaje',
    message: '',
  ),
];
