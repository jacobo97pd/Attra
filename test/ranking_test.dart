import 'package:flutter_test/flutter_test.dart';

import 'package:attra/src/features/auth/domain/app_user.dart';
import 'package:attra/src/features/feed/domain/ranking.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';

AppUser me({
  String intent = 'serious',
  List<String> interests = const <String>['montaña', 'cafe', 'cine'],
  double? lat = 40.41,
  double? lng = -3.70,
}) {
  return AppUser(
    uid: 'me',
    email: null,
    displayName: 'Yo',
    photoUrl: null,
    onboardingCompleted: true,
    profileCompleted: true,
    profileCompletionPercent: 100,
    isBot: false,
    relationshipIntent: intent,
    interests: interests,
    latitude: lat,
    longitude: lng,
  );
}

SeedProfile prof({
  required String id,
  String relationshipGoal = 'serious',
  List<String> interests = const <String>[],
  int photos = 1,
  String bio = '',
  int prompts = 0,
  bool verified = false,
  double? lat,
  double? lng,
  String city = '',
}) {
  return SeedProfile(
    id: id,
    displayName: id,
    city: city,
    country: '',
    bio: bio,
    gender: 'female',
    interestedIn: const <String>['male'],
    orientation: const <String>[],
    relationshipGoal: relationshipGoal,
    verified: verified,
    lat: lat,
    lng: lng,
    age: 28,
    jobTitle: '',
    company: '',
    interests: interests,
    photoUrl: photos > 0 ? 'u' : '',
    isBot: true,
    botProfileVersion: 1,
    botScenario: 'test',
    seedQualityScore: 0,
    photos: List<AdditionalPhoto>.generate(
      photos,
      (int i) => AdditionalPhoto(
          url: 'u$i', storagePath: '', source: 'x', order: i),
    ),
    profilePrompts: List<PublicPrompt>.generate(
      prompts,
      (int i) => PublicPrompt(id: 'p$i', question: 'q', answer: 'a'),
    ),
  );
}

void main() {
  group('RankingScorer', () {
    test('no rompe con 0/1 candidatos', () {
      expect(RankingScorer.rank(profiles: const <SeedProfile>[], me: me()),
          isEmpty);
      final List<SeedProfile> one = <SeedProfile>[prof(id: 'a')];
      expect(RankingScorer.rank(profiles: one, me: me()).length, 1);
    });

    test('misma intención + intereses compartidos puntúa más que opuesto', () {
      final SeedProfile good = prof(
        id: 'good',
        relationshipGoal: 'serious',
        interests: const <String>['montaña', 'cafe'],
        photos: 4,
        bio: 'Una bio con bastante contenido para sumar calidad de perfil real.',
        prompts: 3,
        verified: true,
      );
      final SeedProfile bad = prof(
        id: 'bad',
        relationshipGoal: 'casual',
        interests: const <String>['fiesta'],
        photos: 1,
      );
      final List<RankedProfile> s =
          RankingScorer.score(profiles: <SeedProfile>[bad, good], me: me());
      final double goodScore =
          s.firstWhere((RankedProfile r) => r.profile.id == 'good').score;
      final double badScore =
          s.firstWhere((RankedProfile r) => r.profile.id == 'bad').score;
      expect(goodScore, greaterThan(badScore));
    });

    test('rank ordena de mayor a menor afinidad', () {
      final List<SeedProfile> ranked = RankingScorer.rank(
        profiles: <SeedProfile>[
          prof(id: 'lowq', relationshipGoal: 'casual', photos: 1),
          prof(
              id: 'highq',
              relationshipGoal: 'serious',
              interests: const <String>['montaña', 'cine'],
              photos: 4,
              bio: 'Texto largo y con personalidad para subir la calidad mucho.',
              prompts: 3,
              verified: true),
        ],
        me: me(),
        diversify: false,
      );
      expect(ranked.first.id, 'highq');
    });

    test('cercanía: más cerca puntúa más que lejos', () {
      final SeedProfile near =
          prof(id: 'near', lat: 40.42, lng: -3.70); // ~1km
      final SeedProfile far =
          prof(id: 'far', lat: 41.39, lng: 2.16); // Barcelona ~500km
      final List<RankedProfile> s = RankingScorer.score(
          profiles: <SeedProfile>[far, near], me: me());
      final double nearScore =
          s.firstWhere((RankedProfile r) => r.profile.id == 'near').score;
      final double farScore =
          s.firstWhere((RankedProfile r) => r.profile.id == 'far').score;
      expect(nearScore, greaterThan(farScore));
    });

    test('penalización (señales negativas) baja el score', () {
      final SeedProfile p = prof(id: 'p', interests: const <String>['cafe']);
      final List<RankedProfile> clean =
          RankingScorer.score(profiles: <SeedProfile>[p], me: me());
      final List<RankedProfile> penalized = RankingScorer.score(
        profiles: <SeedProfile>[p],
        me: me(),
        signalsFor: (_) => const RankingSignals(penalty: 0.8),
      );
      expect(penalized.first.score, lessThan(clean.first.score));
    });

    test('diversidad: no deja 3+ de la misma ciudad seguidos', () {
      final List<SeedProfile> same = <SeedProfile>[
        for (int i = 0; i < 5; i++)
          prof(id: 'm$i', city: 'Madrid', interests: const <String>['cafe']),
        prof(id: 'bcn', city: 'Barcelona', interests: const <String>['cafe']),
      ];
      final List<SeedProfile> ranked =
          RankingScorer.rank(profiles: same, me: me());
      // En los primeros 3 no deben estar los 5 de Madrid juntos: el de BCN
      // debe haberse colado antes del 4º Madrid.
      final int bcnPos = ranked.indexWhere((SeedProfile p) => p.id == 'bcn');
      expect(bcnPos, lessThan(5));
    });
  });
}
