import 'package:attra/src/features/auth/domain/app_user.dart';
import 'package:attra/src/features/feed/domain/boost_ranker.dart';
import 'package:attra/src/features/feed/domain/feed_filter.dart';
import 'package:attra/src/features/monetization/domain/boost.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser _me() {
  return const AppUser(
    uid: 'me',
    email: null,
    displayName: 'Yo',
    photoUrl: null,
    onboardingCompleted: true,
    profileCompleted: true,
    profileCompletionPercent: 100,
    isBot: false,
    gender: 'male',
    interestedIn: <String>['female'],
    relationshipIntent: 'serious',
    interests: <String>['cafe', 'cine', 'montana'],
    latitude: 40.42,
    longitude: -3.70,
  );
}

SeedProfile _profile({
  required String id,
  String gender = 'female',
  List<String> interestedIn = const <String>['male'],
  String relationshipGoal = 'serious',
  List<String> interests = const <String>[],
  int photos = 1,
  String bio = '',
  int prompts = 0,
  bool verified = false,
}) {
  return SeedProfile(
    id: id,
    displayName: id,
    city: '',
    country: '',
    bio: bio,
    gender: gender,
    interestedIn: interestedIn,
    orientation: const <String>[],
    relationshipGoal: relationshipGoal,
    age: 28,
    jobTitle: '',
    company: '',
    interests: interests,
    photoUrl: photos > 0 ? 'https://x/$id.jpg' : '',
    isBot: true,
    botProfileVersion: 1,
    botScenario: 'test',
    seedQualityScore: 0,
    photos: List<AdditionalPhoto>.generate(
      photos,
      (int i) => AdditionalPhoto(
        url: 'https://x/$id/$i.jpg',
        storagePath: '',
        source: 'test',
        order: i,
      ),
    ),
    profilePrompts: List<PublicPrompt>.generate(
      prompts,
      (int i) => PublicPrompt(id: 'p$i', question: 'q', answer: 'a'),
    ),
  );
}

ActiveBoost _boost({
  required String userId,
  int priorityBonus = 150,
  int deliveredImpressions = 0,
  int impressionCap = 500,
  DateTime? expiresAt,
}) {
  return ActiveBoost(
    boostId: 'boost_$userId',
    userId: userId,
    type: BoostType.boostNormal,
    status: 'active',
    startedAt: DateTime(2026, 1, 1),
    expiresAt: expiresAt ?? DateTime.now().add(const Duration(minutes: 30)),
    priorityBonus: priorityBonus,
    impressionCap: impressionCap,
    deliveredImpressions: deliveredImpressions,
  );
}

void main() {
  group('BoostAwareRanker', () {
    test('capa el bonus y lo ignora si expiro o alcanzo cap', () {
      expect(
        BoostAwareRanker.boostContribution(_boost(userId: 'a', priorityBonus: 999)),
        closeTo(BoostAwareRanker.maxBoostScore, 0.0001),
      );
      expect(
        BoostAwareRanker.boostContribution(
          _boost(
            userId: 'a',
            expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
          ),
        ),
        0,
      );
      expect(
        BoostAwareRanker.boostContribution(
          _boost(userId: 'a', deliveredImpressions: 500, impressionCap: 500),
        ),
        0,
      );
    });

    test('un boost no tapa una diferencia organica grande', () {
      final SeedProfile strong = _profile(
        id: 'strong',
        interests: const <String>['cafe', 'cine', 'montana'],
        photos: 4,
        bio: 'Bio completa con suficiente detalle para subir calidad real.',
        prompts: 3,
        verified: true,
      );
      final SeedProfile weak = _profile(
        id: 'weak',
        relationshipGoal: 'casual',
        interests: const <String>['fiesta'],
        photos: 0,
      );

      final List<SeedProfile> ranked = BoostAwareRanker.rank(
        profiles: <SeedProfile>[weak, strong],
        me: _me(),
        activeBoosts: <String, ActiveBoost>{'weak': _boost(userId: 'weak')},
      );

      expect(ranked.first.id, 'strong');
    });

    test('se aplica despues de filtros duros y no reintroduce excluidos', () {
      final SeedProfile compatible = _profile(id: 'compatible');
      final SeedProfile incompatible =
          _profile(id: 'incompatible', gender: 'male');
      final List<SeedProfile> filtered = FeedFilter.apply(
        profiles: <SeedProfile>[compatible, incompatible],
        myUid: 'me',
        myGender: _me().gender,
        myInterestedIn: _me().interestedIn,
        excludedUids: const <String>{},
      );

      final List<SeedProfile> ranked = BoostAwareRanker.rank(
        profiles: filtered,
        me: _me(),
        activeBoosts: <String, ActiveBoost>{
          'incompatible': _boost(userId: 'incompatible'),
        },
      );

      expect(ranked.map((SeedProfile p) => p.id), <String>['compatible']);
    });
  });
}
