import 'package:attra/src/features/auth/domain/app_user.dart';
import 'package:attra/src/features/feed/domain/boost_ranker.dart';
import 'package:attra/src/features/feed/domain/ranking.dart';
import 'package:attra/src/features/feed/domain/ranking_config.dart';
import 'package:attra/src/features/monetization/domain/boost.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Desde dónde mide la CERCANÍA el ranking.
///
/// Se medía siempre desde `me.latitude/longitude`, que son las coordenadas
/// REALES (se siguen guardando mientras se viaja): viajando de Madrid a Cádiz,
/// la gente de Madrid tenía cercanía 1 y la de Cádiz 0, y Madrid subía arriba.
void main() {
  // Coordenadas REALES de quien ordena: Madrid.
  const AppUser me = AppUser(
    uid: 'yo',
    email: null,
    displayName: 'Yo',
    photoUrl: null,
    onboardingCompleted: true,
    profileCompleted: true,
    profileCompletionPercent: 100,
    isBot: false,
    latitude: 40.4168,
    longitude: -3.7038,
  );
  const RankingOrigin cadiz = RankingOrigin(lat: 36.53, lng: -6.29);

  SeedProfile perfil(String id, String city, double lat, double lng) =>
      SeedProfile.fromMap(id, <String, dynamic>{
        'displayName': id,
        'currentCity': city,
        'geo': <String, dynamic>{'lat': lat, 'lng': lng},
      });

  final SeedProfile madrid = perfil('madrid', 'Madrid', 40.42, -3.70);
  final SeedProfile lucia = perfil('lucia', 'Cádiz', 36.53, -6.29);

  double proximidad(List<RankedProfile> scored, String id) => scored
      .firstWhere((RankedProfile r) => r.profile.id == id)
      .breakdown
      .proximity;

  test('con origen en Cádiz, Cádiz está cerca y Madrid lejos', () {
    final List<RankedProfile> scored = RankingScorer.score(
      profiles: <SeedProfile>[madrid, lucia],
      me: me,
      origin: cadiz,
    );
    expect(proximidad(scored, 'lucia'), greaterThan(0.9));
    expect(proximidad(scored, 'madrid'), 0);
  });

  test('sin origen se sigue midiendo desde "me" (compatibilidad)', () {
    final List<RankedProfile> scored = RankingScorer.score(
      profiles: <SeedProfile>[madrid, lucia],
      me: me,
    );
    expect(proximidad(scored, 'madrid'), greaterThan(0.9));
    expect(proximidad(scored, 'lucia'), 0);
  });

  test('origen sin coordenadas = cercanía NEUTRA, nunca la de casa', () {
    final List<RankedProfile> scored = RankingScorer.score(
      profiles: <SeedProfile>[madrid, lucia],
      me: me,
      origin: RankingOrigin.none,
    );
    expect(proximidad(scored, 'madrid'), 0.5);
    expect(proximidad(scored, 'lucia'), 0.5);
  });

  test('el Boost mide desde el mismo origen', () {
    // Madrid con Boost, Cádiz sin él y todo lo demás igual: desde el destino,
    // la cercanía de Cádiz (+0,07) pesa más que un Boost pequeño.
    final List<SeedProfile> ranked = BoostAwareRanker.rank(
      profiles: <SeedProfile>[madrid, lucia],
      me: me,
      activeBoosts: <String, ActiveBoost>{
        'madrid': ActiveBoost(
          boostId: 'b',
          userId: 'madrid',
          type: BoostType.boostNormal,
          status: 'active',
          startedAt: DateTime(2026, 1, 1),
          expiresAt: DateTime.now().add(const Duration(minutes: 30)),
          priorityBonus: 30,
          impressionCap: 500,
          deliveredImpressions: 0,
        ),
      },
      config: const RankingConfig(jitter: 0),
      origin: cadiz,
    );
    expect(ranked.first.id, 'lucia');
  });

  test('sin diversificar, 3+ de la misma ciudad siguen seguidos', () {
    // Viajando no se diversifica por ciudad: mandaría al final a la tercera
    // persona seguida de la ciudad de destino.
    final List<SeedProfile> pool = <SeedProfile>[
      perfil('c1', 'Cádiz', 36.53, -6.29),
      perfil('c2', 'Cádiz', 36.53, -6.29),
      perfil('c3', 'Cádiz', 36.53, -6.29),
      perfil('jerez', 'Jerez de la Frontera', 36.69, -6.14),
    ];
    final List<String> diversificado = RankingScorer.rank(
      profiles: pool,
      me: me,
      config: const RankingConfig(jitter: 0),
      origin: cadiz,
    ).map((SeedProfile p) => p.id).toList();
    final List<String> seguido = RankingScorer.rank(
      profiles: pool,
      me: me,
      config: const RankingConfig(jitter: 0),
      origin: cadiz,
      diversify: false,
    ).map((SeedProfile p) => p.id).toList();
    expect(diversificado.last, isNot('jerez'),
        reason: 'con diversificación la tercera de Cádiz se va al final');
    expect(seguido.take(3), unorderedEquals(<String>['c1', 'c2', 'c3']));
    expect(seguido.last, 'jerez');
  });
}
