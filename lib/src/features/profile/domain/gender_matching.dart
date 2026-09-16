/// Compatibilidad entre la identidad de género de alguien (`profile.gender`) y
/// a quién dice buscar la otra persona (`preferences.interestedIn`).
///
/// POR QUÉ EXISTE: el onboarding deja elegir OCHO identidades de género
/// (`female`, `male`, `non_binary`, `trans_woman`, `trans_man`, `genderfluid`,
/// `agender`, `other`), pero "a quién buscas" solo tiene TRES casillas
/// (`female`, `male`, `non_binary`). Al comparar los dos campos en crudo con
/// `interestedIn.contains(gender)`, las cinco identidades que no son una de
/// esas tres casillas no coincidían con NADIE que hubiera dicho a quién busca:
/// una mujer trans quedaba fuera del feed de todo el mundo, sin error, sin
/// aviso y sin forma de arreglarlo desde la app. Es un fallo de emparejamiento,
/// no una preferencia: nadie había pedido excluirla.
///
/// CÓMO SE RESUELVE: cada identidad se traduce a la casilla o casillas que la
/// representan. Una mujer trans es una mujer, así que entra en `female`; un
/// hombre trans, en `male`. Las identidades no binarias (`genderfluid`,
/// `agender`) entran en `non_binary`. `other` no dice qué es, así que entra en
/// las tres: siguiendo el criterio del resto de [FeedFilter], cuando el dato no
/// permite decidir NO se excluye.
///
/// La traducción es solo para el emparejamiento. El valor original es el que se
/// guarda y el que se enseña: aquí no se reescribe la identidad de nadie.
library;

class GenderMatching {
  const GenderMatching._();

  /// Las tres casillas que `interestedIn` sabe expresar.
  static const List<String> interestBuckets = <String>[
    'female',
    'male',
    'non_binary',
  ];

  /// Casillas de `interestedIn` que representan a [gender].
  ///
  /// Un género vacío o desconocido devuelve todas: sin dato no se excluye.
  static List<String> bucketsFor(String gender) {
    switch (gender) {
      case 'female':
      case 'trans_woman':
        return const <String>['female'];
      case 'male':
      case 'trans_man':
        return const <String>['male'];
      case 'non_binary':
      case 'genderfluid':
      case 'agender':
        return const <String>['non_binary'];
      default:
        // '', 'other' y cualquier valor futuro que aún no esté contemplado.
        return interestBuckets;
    }
  }

  /// ¿Alguien que busca [interestedIn] podría ver a alguien de género [gender]?
  ///
  /// Permisivo a propósito: sin preferencia declarada o sin género declarado,
  /// no hay motivo para excluir.
  static bool wants(Iterable<String> interestedIn, String gender) {
    if (interestedIn.isEmpty) return true;
    if (gender.isEmpty) return true;
    if (interestedIn.contains(gender)) return true;
    for (final String bucket in bucketsFor(gender)) {
      if (interestedIn.contains(bucket)) return true;
    }
    return false;
  }
}
