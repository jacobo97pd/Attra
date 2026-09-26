import 'package:attra/src/features/feed/domain/feed_filters.dart';
import 'package:flutter_test/flutter_test.dart';

/// Filtros del feed guardados en `preferences` (C23/C42/C09).
void main() {
  group('guardar y recuperar', () {
    test('lo guardado vuelve igual (sin edad, distancia ni IA dentro)', () {
      const FeedFilters elegidos = FeedFilters(
        minAge: 25,
        maxAge: 35,
        maxDistanceKm: 30,
        showGenders: <String>{'female'},
        onlyWithPhoto: true,
        smoking: 'never',
        relationshipGoal: 'serious_relationship',
        verifiedOnly: true,
        minHeight: 160,
        maxHeight: 190,
        dealbreakers: <String>{FeedFilters.kSmoking, FeedFilters.kGoal},
        sortByVisualReference: true,
        promptQuery: 'alto y moreno',
      );
      final Map<String, dynamic> saved = elegidos.toSavedMap();
      expect(saved.containsKey('minAge'), isFalse,
          reason: 'la edad va en preferences.preferredAgeMin/Max');
      expect(saved.containsKey('maxDistanceKm'), isFalse,
          reason: 'el radio va en preferences.maxDistanceKm');
      expect(saved.containsKey('promptQuery'), isFalse,
          reason: 'una búsqueda IA no es una preferencia');

      final FeedFilters vuelta = FeedFilters.fromPreferences(
        saved: saved,
        maxDistanceKm: 30,
        preferredAgeMin: 25,
        preferredAgeMax: 35,
      );
      expect(vuelta.minAge, 25);
      expect(vuelta.maxAge, 35);
      expect(vuelta.maxDistanceKm, 30);
      expect(vuelta.showGenders, <String>{'female'});
      expect(vuelta.onlyWithPhoto, isTrue);
      expect(vuelta.smoking, 'never');
      expect(vuelta.relationshipGoal, 'serious_relationship');
      expect(vuelta.verifiedOnly, isTrue);
      expect(vuelta.minHeight, 160);
      expect(vuelta.maxHeight, 190);
      expect(vuelta.dealbreakers,
          <String>{FeedFilters.kSmoking, FeedFilters.kGoal});
      expect(vuelta.aiSearchActive, isFalse);
    });

    test('un "no fuma" quitado se guarda como quitado', () {
      // Con `set(merge)` un mapa anidado se fusiona clave a clave y el valor
      // viejo sobrevivía. Por eso las claves van SIEMPRE, también a null.
      final Map<String, dynamic> saved = const FeedFilters().toSavedMap();
      expect(saved.containsKey('smoking'), isTrue);
      expect(saved['smoking'], isNull);
    });

    test('lectura tolerante: tipos raros cuentan como ausentes', () {
      final FeedFilters f = FeedFilters.fromPreferences(
        saved: <String, dynamic>{
          'showGenders': 'female',
          'onlyWithPhoto': 'true',
          'smoking': 7,
          'minHeight': 'alto',
          'maxHeight': 999,
          'dealbreakers': <Object?>['smoking', 3, null],
        },
      );
      expect(f.showGenders, isEmpty);
      expect(f.onlyWithPhoto, isFalse);
      expect(f.smoking, isNull);
      expect(f.minHeight, FeedFilters.heightFloor);
      expect(f.maxHeight, FeedFilters.heightCeil);
      expect(f.dealbreakers, <String>{'smoking'});
    });
  });

  group('rango de edad y radio del onboarding', () {
    test('sin nada guardado, los valores neutros', () {
      final FeedFilters f = FeedFilters.fromPreferences();
      expect(f.minAge, FeedFilters.ageFloor);
      expect(f.maxAge, FeedFilters.ageCeil);
      expect(f.maxDistanceKm, isNull);
    });

    test('el rango nunca baja de 18 ni se da la vuelta', () {
      final FeedFilters f =
          FeedFilters.fromPreferences(preferredAgeMin: 15, preferredAgeMax: 12);
      expect(f.minAge, 18);
      expect(f.maxAge, 18);
    });

    test('el radio respeta el tope del onboarding (500), no el viejo de 200',
        () {
      expect(
          FeedFilters.fromPreferences(maxDistanceKm: 300).maxDistanceKm, 300);
      expect(
          FeedFilters.fromPreferences(maxDistanceKm: 9000).maxDistanceKm, 500);
    });
  });

  group('sin Plus', () {
    const FeedFilters conPlus = FeedFilters(
      minAge: 25,
      maxAge: 35,
      onlyWithPhoto: true,
      smoking: 'never',
      verifiedOnly: true,
      minHeight: 170,
      dealbreakers: <String>{FeedFilters.kSmoking, FeedFilters.kDistance},
    );

    test('quita los avanzados y deja los básicos', () {
      final FeedFilters f = conPlus.withoutPlus();
      expect(f.hasPlusFilters, isFalse);
      expect(f.smoking, isNull);
      expect(f.verifiedOnly, isFalse);
      expect(f.heightActive, isFalse);
      expect(f.dealbreakers, <String>{FeedFilters.kDistance});
      expect(f.minAge, 25);
      expect(f.onlyWithPhoto, isTrue);
    });

    test('sin avanzados, no cambia nada', () {
      const FeedFilters basicos = FeedFilters(minAge: 30);
      expect(identical(basicos.withoutPlus(), basicos), isTrue);
    });
  });
}
