import 'dart:io';

import 'package:attra/src/features/profile/domain/profile_trait.dart';
import 'package:attra/src/features/profile/domain/profile_traits_catalog.dart';
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

    final Set<String> written = _topLevelKeysWrittenByRepository();
    expect(written, isNotEmpty,
        reason: 'No se pudo leer el mapa baseData de user_repository.dart');
    // Guarda de la propia extracción: si dejara de encontrar los mapas de
    // `_withRequiredUserFields`, la prueba pasaría en verde sin comprobar nada.
    // `location` lo escribe `setDeviceLocation` por esa vía.
    expect(written, contains('location'),
        reason: 'la extracción ya no ve los mapas de _withRequiredUserFields: '
            'la prueba estaría pasando sin comprobar nada');

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

  test('los grupos del catálogo de rasgos también son claves permitidas', () {
    // `setProfileTrait` escribe en `users/{uid}.[def.group].[def.field]`, así que
    // el grupo ES una clave de primer nivel. Al venir del catálogo no se puede
    // leer del código fuente: se comprueba con el catálogo en la mano.
    final Set<String> allowed = _allowedTopLevelKeysFromRules();
    final Set<String> groups = ProfileTraitsCatalog.all
        .map((ProfileTraitDefinition d) => d.group)
        .toSet();

    expect(groups, isNotEmpty);
    expect(groups.difference(allowed), isEmpty,
        reason: 'un rasgo escribe en un grupo que firestore.rules no permite: '
            'la escritura ENTERA se rechazaría');
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

/// Extrae TODAS las claves de primer nivel que el repositorio escribe en
/// `users/{uid}`.
///
/// Antes solo miraba `syncUserFromAuth` (el mapa `baseData` y las asignaciones a
/// `updateData[...]`), así que dejaba fuera las ~20 escrituras que pasan por
/// `_withRequiredUserFields(uid, {...})` — entre ellas la de la ubicación. Una
/// clave nueva ahí seguía dando verde y en producción el `permission-denied`
/// tumbaba la escritura ENTERA, que es justo lo que esta prueba existe para
/// evitar.
Set<String> _topLevelKeysWrittenByRepository() {
  final String source = File('lib/src/features/auth/data/user_repository.dart')
      .readAsStringSync();

  final Set<String> keys = <String>{};

  // Mapas literales pasados a `_withRequiredUserFields(uid, <String, dynamic>{…})`
  // (la vía de casi todos los métodos del repositorio).
  for (final RegExpMatch m in RegExp(
    r'_withRequiredUserFields\(\s*\w+,\s*<String,\s*dynamic>\{',
  ).allMatches(source)) {
    keys.addAll(_topLevelKeysOfMapLiteral(source, m.end - 1));
  }

  // `ref.update({'grupo.campo': …})`: en una ruta con punto, lo que las reglas
  // ven es el PRIMER segmento.
  for (final RegExpMatch m in RegExp(
    r'\.update\(<String,\s*(?:dynamic|Object\?)>\{',
  ).allMatches(source)) {
    for (final String key in _topLevelKeysOfMapLiteral(source, m.end - 1)) {
      keys.add(key.split('.').first);
    }
  }

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

/// Claves del PRIMER nivel de un mapa literal de Dart que empieza en [openIndex]
/// (la posición de su `{`). Los mapas anidados se saltan: sus claves no son
/// claves de primer nivel del documento.
Set<String> _topLevelKeysOfMapLiteral(String source, int openIndex) {
  final Set<String> keys = <String>{};
  int depth = 0;
  for (int i = openIndex; i < source.length; i++) {
    final String ch = source[i];
    if (ch == '{' || ch == '[' || ch == '(') {
      depth++;
      continue;
    }
    if (ch == '}' || ch == ']' || ch == ')') {
      depth--;
      if (depth == 0) break;
      continue;
    }
    if (depth != 1 || ch != "'") continue;
    final int end = source.indexOf("'", i + 1);
    if (end < 0) break;
    final String literal = source.substring(i + 1, end);
    i = end;
    // Solo cuenta si es una CLAVE: lo siguiente (ignorando espacios) es ':'.
    int j = end + 1;
    while (j < source.length && (source[j] == ' ' || source[j] == '\n')) {
      j++;
    }
    if (j >= source.length || source[j] != ':') continue;
    // Claves interpoladas (`'${def.group}.${def.field}'`): el valor no está en el
    // código, así que estáticamente no se pueden comprobar. Las cubre la prueba
    // de los grupos del catálogo de rasgos, más abajo.
    if (literal.contains(r'$')) continue;
    keys.add(literal);
  }
  return keys;
}

Set<String> _quotedStrings(String block) {
  return RegExp("'([A-Za-z0-9_]+)'")
      .allMatches(block)
      .map((RegExpMatch m) => m.group(1)!)
      .toSet();
}
