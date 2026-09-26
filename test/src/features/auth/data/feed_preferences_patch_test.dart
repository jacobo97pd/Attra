import 'package:attra/src/features/auth/data/user_repository.dart';
import 'package:attra/src/features/feed/domain/feed_filters.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lo que se guarda al aplicar filtros en el feed (C23/C42/C09): el radio y la
/// edad en sus claves de siempre de `preferences` (las del onboarding, que
/// también lee el directo) y el resto en `preferences.feedFilters`.
void main() {
  test('rutas punteadas: no pisa el resto de `preferences`', () {
    final Map<String, Object?> patch = UserRepository.buildFeedPreferencesPatch(
      maxDistanceKm: 30,
      preferredAgeMin: 25,
      preferredAgeMax: 35,
      feedFilters: const FeedFilters(smoking: 'never').toSavedMap(),
    );

    expect(patch['preferences.maxDistanceKm'], 30);
    expect(patch['preferences.preferredAgeMin'], 25);
    expect(patch['preferences.preferredAgeMax'], 35);
    expect(
        (patch['preferences.feedFilters']! as Map<String, dynamic>)['smoking'],
        'never');
    expect(patch['updatedAt'], isA<FieldValue>());
    // Nada que reemplace `preferences` entero (se perdería `interestedIn`).
    expect(patch.containsKey('preferences'), isFalse);
  });

  test('sin radio NO se borra el guardado (lo exige la completitud)', () {
    final Map<String, Object?> patch = UserRepository.buildFeedPreferencesPatch(
      preferredAgeMin: 18,
      preferredAgeMax: 80,
      feedFilters: const <String, dynamic>{},
    );
    expect(patch.containsKey('preferences.maxDistanceKm'), isFalse);
  });
}
