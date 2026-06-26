import 'package:flutter_test/flutter_test.dart';

import 'package:attra/src/features/auth/domain/app_user.dart';
import 'package:attra/src/features/feed/domain/ranking.dart';
import 'package:attra/src/features/feed/domain/ranking_config.dart';
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
      (int i) =>
          AdditionalPhoto(url: 'u$i', storagePath: '', source: 'x', order: i),
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
        bio:
            'Una bio con bastante contenido para sumar calidad de perfil real.',
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
              bio:
                  'Texto largo y con personalidad para subir la calidad mucho.',
              prompts: 3,
              verified: true),
        ],
        me: me(),
        diversify: false,
      );
      expect(ranked.first.id, 'highq');
    });

    test('cercanía: más cerca puntúa más que lejos', () {
      final SeedProfile near = prof(id: 'near', lat: 40.42, lng: -3.70); // ~1km
      final SeedProfile far =
          prof(id: 'far', lat: 41.39, lng: 2.16); // Barcelona ~500km
      final List<RankedProfile> s =
          RankingScorer.score(profiles: <SeedProfile>[far, near], me: me());
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

  group('RankingScorer v1 (modelo de scores compuestos)', () {
    double scoreOf(List<RankedProfile> s, String id) =>
        s.firstWhere((RankedProfile r) => r.profile.id == id).score;
    RankingBreakdown bd(List<RankedProfile> s, String id) =>
        s.firstWhere((RankedProfile r) => r.profile.id == id).breakdown;

    test('perfil completo > incompleto (profileQuality)', () {
      final SeedProfile full = prof(
          id: 'full', photos: 4, bio: 'a' * 100, prompts: 3, verified: true);
      final SeedProfile empty = prof(id: 'empty', photos: 0);
      final List<RankedProfile> s =
          RankingScorer.score(profiles: <SeedProfile>[full, empty], me: me());
      expect(bd(s, 'full').profileQuality,
          greaterThan(bd(s, 'empty').profileQuality));
      expect(scoreOf(s, 'full'), greaterThan(scoreOf(s, 'empty')));
    });

    test('total siempre normalizado en [0,1]', () {
      final List<RankedProfile> s = RankingScorer.score(
        profiles: <SeedProfile>[
          prof(id: 'a', photos: 4, bio: 'a' * 200, prompts: 3, verified: true),
          prof(id: 'b', photos: 0),
        ],
        me: me(),
        signalsFor: (_) => const RankingSignals(penalty: 1),
      );
      for (final RankedProfile r in s) {
        expect(r.score, inInclusiveRange(0.0, 1.0));
      }
    });

    test('usuario nuevo recibe boost de freshness (cold start)', () {
      final SeedProfile p = prof(id: 'newbie', photos: 1);
      final List<RankedProfile> base =
          RankingScorer.score(profiles: <SeedProfile>[p], me: me());
      final List<RankedProfile> boosted = RankingScorer.score(
        profiles: <SeedProfile>[p],
        me: me(),
        signalsFor: (_) => RankingSignals(
            newUserBoostUntil: DateTime.now().add(const Duration(days: 3))),
      );
      expect(boosted.first.breakdown.freshness,
          greaterThan(base.first.breakdown.freshness));
    });

    test('reportes (penalty) bajan trustSafety y total', () {
      final SeedProfile p = prof(id: 'rep', photos: 2, verified: true);
      final List<RankedProfile> clean =
          RankingScorer.score(profiles: <SeedProfile>[p], me: me());
      final List<RankedProfile> reported = RankingScorer.score(
        profiles: <SeedProfile>[p],
        me: me(),
        signalsFor: (_) => const RankingSignals(penalty: 0.8),
      );
      expect(reported.first.breakdown.trustSafety,
          lessThan(clean.first.breakdown.trustSafety));
      expect(reported.first.score, lessThan(clean.first.score));
    });

    test('reciprocidad alta ordena por encima de popularidad bruta', () {
      // "pop" tiene mejor calidad de perfil; "recip" tiene reciprocidad real
      // alta (override del backend). Reciprocity pesa más => recip gana.
      final SeedProfile pop = prof(id: 'pop', photos: 4, verified: true);
      final SeedProfile recip = prof(id: 'recip', photos: 1);
      final List<RankedProfile> s = RankingScorer.score(
        profiles: <SeedProfile>[pop, recip],
        me: me(),
        signalsFor: (SeedProfile p) => p.id == 'recip'
            ? const RankingSignals(reciprocityOverride: 0.98)
            : const RankingSignals(reciprocityOverride: 0.1),
      );
      expect(scoreOf(s, 'recip'), greaterThan(scoreOf(s, 'pop')));
    });

    test('connectionScore alto sube el total', () {
      final SeedProfile p = prof(id: 'talker', photos: 2);
      final List<RankedProfile> low = RankingScorer.score(
          profiles: <SeedProfile>[p],
          me: me(),
          signalsFor: (_) => const RankingSignals(connectionScore: 0.1));
      final List<RankedProfile> high = RankingScorer.score(
          profiles: <SeedProfile>[p],
          me: me(),
          signalsFor: (_) => const RankingSignals(connectionScore: 0.95));
      expect(high.first.score, greaterThan(low.first.score));
    });

    test('exposure cap baja freshness (anti rich-get-richer)', () {
      final SeedProfile p = prof(id: 'overexposed', photos: 2);
      final List<RankedProfile> normal =
          RankingScorer.score(profiles: <SeedProfile>[p], me: me());
      final List<RankedProfile> capped = RankingScorer.score(
        profiles: <SeedProfile>[p],
        me: me(),
        signalsFor: (_) =>
            const RankingSignals(exposureCount24h: 50, exposureCap: 20),
      );
      expect(capped.first.breakdown.freshness,
          lessThan(normal.first.breakdown.freshness));
    });

    test('pesos configurables desde flags (RankingConfig.fromMap)', () {
      final RankingConfig c = RankingConfig.fromMap(<String, dynamic>{
        'ranking_w_reciprocity': 0.5,
        'ranking_jitter': 0,
        'ranking_enabled': false,
      });
      expect(c.wReciprocity, 0.5);
      expect(c.jitter, 0);
      expect(c.enabled, isFalse);
    });

    test('explainForDebugOnly da reason codes (solo dev)', () {
      final SeedProfile p =
          prof(id: 'x', photos: 4, bio: 'a' * 120, prompts: 3, verified: true);
      final List<RankedProfile> s = RankingScorer.score(
          profiles: <SeedProfile>[p],
          me: me(),
          signalsFor: (_) => const RankingSignals(connectionScore: 0.9));
      final String explain = RankingScorer.explainForDebugOnly(s.first);
      expect(explain, contains('total='));
      expect(explain, contains('codes='));
    });
  });
}
