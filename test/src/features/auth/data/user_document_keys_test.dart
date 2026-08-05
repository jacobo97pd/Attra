import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contrato entre el cliente y `firestore.rules`.
///
/// Las reglas de `users/{uid}` aceptan SOLO una lista cerrada de claves de
/// primer nivel (`allowedTopLevelKeys`). Si el cliente escribe una clave que no
/// esté en esa lista, Firestore rechaza la ESCRITURA ENTERA con
/// `permission-denied` y el login/onboarding se rompe por completo.
///
/// Esta prueba lee las dos fuentes y comprueba que no se han desincronizado.
void main() {
  test('users/{uid}: el cliente no escribe claves que las reglas prohiban', () {
    final Set<String> allowed = _allowedTopLevelKeysFromRules();
    expect(allowed, isNotEmpty,
        reason: 'No se pudo leer allowedTopLevelKeys() de firestore.rules');

    final Set<String> written = _topLevelKeysWrittenBySync();
    expect(written, isNotEmpty,
        reason: 'No se pudo leer el mapa baseData de user_repository.dart');

    final Set<String> forbidden = written.difference(allowed);
    expect(
      forbidden,
      isEmpty,
      reason: 'user_repository escribe claves que firestore.rules no permite: '
          '$forbidden. O las añades a allowedTopLevelKeys() en firestore.rules '
          '(y despliegas las reglas ANTES de publicar la app), o guardas el '
          'dato en una subcolección como users/{uid}/consentRecords.',
    );
  });
}

/// Extrae las claves de `allowedTopLevelKeys()` de firestore.rules.
Set<String> _allowedTopLevelKeysFromRules() {
  final String rules = File('firestore.rules').readAsStringSync();
  final int start = rules.indexOf('function allowedTopLevelKeys()');
  if (start < 0) return <String>{};
  final int open = rules.indexOf('[', start);
  final int close = rules.indexOf(']', open);
  if (open < 0 || close < 0) return <String>{};
  return _quotedStrings(rules.substring(open, close));
}

/// Extrae las claves del mapa `baseData` que `syncUserFromAuth` escribe al
/// crear `users/{uid}`, más las asignadas a `updateData[...]`.
Set<String> _topLevelKeysWrittenBySync() {
  final String source = File('lib/src/features/auth/data/user_repository.dart')
      .readAsStringSync();

  final Set<String> keys = <String>{};

  // Mapa de creación: `final Map<String, dynamic> baseData = <String, dynamic>{ … };`
  final int start = source.indexOf('baseData = <String, dynamic>{');
  if (start >= 0) {
    final int open = source.indexOf('{', start);
    final int close = source.indexOf('\n      };', open);
    if (open >= 0 && close > open) {
      // Solo las claves del propio literal (`'clave':`), no strings sueltas.
      for (final RegExpMatch m in RegExp("'([A-Za-z0-9_]+)'\\s*:")
          .allMatches(source.substring(open, close))) {
        keys.add(m.group(1)!);
      }
    }
  }

  // Actualizaciones sueltas: `updateData['clave'] = …`.
  for (final RegExpMatch m
      in RegExp(r"updateData\['([A-Za-z0-9_]+)'\]").allMatches(source)) {
    keys.add(m.group(1)!);
  }

  // `_setDefaultIfMissing(updateData, currentData, 'clave', …)` y
  // `_setFieldIfChanged(..., key: 'clave', ...)`.
  for (final RegExpMatch m in RegExp(
    r"_setDefaultIfMissing\(\s*updateData,\s*currentData,\s*'([A-Za-z0-9_]+)'",
  ).allMatches(source)) {
    keys.add(m.group(1)!);
  }
  for (final RegExpMatch m
      in RegExp(r"key:\s*'([A-Za-z0-9_]+)'").allMatches(source)) {
    keys.add(m.group(1)!);
  }

  return keys;
}

Set<String> _quotedStrings(String block) {
  return RegExp("'([A-Za-z0-9_]+)'")
      .allMatches(block)
      .map((RegExpMatch m) => m.group(1)!)
      .toSet();
}
