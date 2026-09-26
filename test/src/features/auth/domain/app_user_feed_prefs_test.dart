import 'package:attra/src/features/auth/domain/app_user.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lo que el feed necesita del usuario para sus filtros guardados y la
/// reciprocidad de edad (C09/C23/C42). El rango del onboarding se guardaba y
/// no lo leía nadie más que el directo.
void main() {
  AppUser parse(Map<String, dynamic> data) =>
      AppUser.fromDocument(_FakeDoc(<String, dynamic>{'uid': 'u1', ...data}));

  test('lee el rango de edad, el radio y los filtros guardados', () {
    final AppUser user = parse(<String, dynamic>{
      'profile': <String, dynamic>{'age': 29},
      'preferences': <String, dynamic>{
        'maxDistanceKm': 40,
        'preferredAgeMin': 24,
        'preferredAgeMax': 35,
        'feedFilters': <String, dynamic>{'onlyWithPhoto': true},
      },
    });
    expect(user.age, 29);
    expect(user.maxDistanceKm, 40);
    expect(user.preferredAgeMin, 24);
    expect(user.preferredAgeMax, 35);
    expect(user.savedFeedFilters['onlyWithPhoto'], isTrue);
  });

  test('sin edad declarada, la saca de la fecha de nacimiento', () {
    final DateTime now = DateTime.now();
    final AppUser user = parse(<String, dynamic>{
      'profile': <String, dynamic>{
        'birthDate': Timestamp.fromDate(DateTime(now.year - 40, 1, 1)),
      },
    });
    expect(user.age, anyOf(39, 40));
  });

  test('sin nada guardado: todo vacío (el feed es permisivo)', () {
    final AppUser user = parse(<String, dynamic>{});
    expect(user.age, isNull);
    expect(user.preferredAgeMin, isNull);
    expect(user.preferredAgeMax, isNull);
    expect(user.savedFeedFilters, isEmpty);
  });
}

// ignore_for_file: subtype_of_sealed_class

/// Documento de mentira: `AppUser.fromDocument` solo usa `data()` y `id`.
class _FakeDoc implements DocumentSnapshot<Map<String, dynamic>> {
  _FakeDoc(this._data);

  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  String get id => (_data['uid'] as String?) ?? 'u1';

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Llamada inesperada: ${invocation.memberName}');
  }
}
