/// Resolucion del NOMBRE PUBLICO canonico de un usuario.
///
/// Regla de privacidad: el usuario muestra el nombre que ELIGIO en la app, no
/// el nombre legal/titular de Google/Auth. El nombre de Auth solo es un
/// fallback inicial y NUNCA debe sobreescribir el elegido.
///
/// Prioridad (de mas a menos fiable como "nombre elegido"):
///   1. profile.displayName        (edicion explicita de nombre publico)
///   2. profile.visibleName        (nombre elegido en onboarding)
///   3. firstName + lastName        (si no hay displayName explicito)
///   4. displayName de primer nivel (puede venir de Auth: ultimo recurso)
String resolvePublicDisplayName(Map<String, dynamic> userData) {
  final Map<String, dynamic> profile = _asMap(userData['profile']);

  final String profileDisplay = _str(profile['displayName']);
  if (profileDisplay.isNotEmpty) return profileDisplay;

  final String visible = _str(profile['visibleName']);
  if (visible.isNotEmpty) return visible;

  final String first = _str(profile['firstName']);
  final String last = _str(profile['lastName']);
  final String full = <String>[first, last]
      .where((String s) => s.isNotEmpty)
      .join(' ')
      .trim();
  if (full.isNotEmpty) return full;

  return _str(userData['displayName']);
}

String _str(dynamic v) => v is String ? v.trim() : '';

Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    return v.map((dynamic k, dynamic val) => MapEntry(k.toString(), val));
  }
  return <String, dynamic>{};
}
