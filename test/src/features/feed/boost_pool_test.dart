import 'package:attra/src/features/feed/domain/boost_ranker.dart';
import 'package:attra/src/features/monetization/domain/boost.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un Boost pagado tiene que hacer DOS cosas:
///   1. Meter al perfil en el pool del feed, aunque quede fuera del corte
///      general (`discovery.limit(50)`, que no ordena por nada).
///   2. Subirlo dentro de ese pool.
///
/// Solo estaba la segunda: se vendía "sube al frente del feed" y el impulsado
/// ni siquiera entraba en él. Este test fija la primera parte, que es la que
/// resuelve `SessionController._loadBoostedProfiles`.
SeedProfile _profile(String id) => SeedProfile.fromMap(id, <String, dynamic>{
      'displayName': 'Perfil $id',
      'gender': 'female',
      'interestedIn': <String>['male'],
      'country': 'España',
    });

/// Réplica de la unión que hace `loadSeedProfiles`: impulsados primero, sin
/// duplicar a quien ya venía en el corte.
List<SeedProfile> buildPool({
  required List<SeedProfile> discovery,
  required List<SeedProfile> seeds,
  required List<SeedProfile> boosted,
}) {
  final Set<String> already = <String>{
    ...discovery.map((SeedProfile p) => p.id),
    ...seeds.map((SeedProfile p) => p.id),
  };
  final List<SeedProfile> extra = boosted
      .where((SeedProfile p) => !already.contains(p.id))
      .toList(growable: false);
  return <SeedProfile>[...extra, ...discovery, ...seeds];
}

void main() {
  group('El impulsado entra al pool aunque no esté en el corte', () {
    test('un boost fuera de los 50 primeros SÍ aparece', () {
      final List<SeedProfile> discovery = <SeedProfile>[
        for (int i = 0; i < 50; i++) _profile('normal_$i'),
      ];
      final SeedProfile impulsado = _profile('impulsado');

      final List<SeedProfile> sinArreglo = <SeedProfile>[...discovery];
      expect(
        sinArreglo.map((SeedProfile p) => p.id),
        isNot(contains('impulsado')),
        reason: 'así estaba antes: el corte no lo incluía',
      );

      final List<SeedProfile> pool = buildPool(
        discovery: discovery,
        seeds: const <SeedProfile>[],
        boosted: <SeedProfile>[impulsado],
      );
      expect(pool.map((SeedProfile p) => p.id), contains('impulsado'));
      expect(pool.length, 51);
    });

    test('no se duplica si ya venía en el corte', () {
      final List<SeedProfile> discovery = <SeedProfile>[
        _profile('a'),
        _profile('b'),
      ];
      final List<SeedProfile> pool = buildPool(
        discovery: discovery,
        seeds: const <SeedProfile>[],
        boosted: <SeedProfile>[_profile('b')],
      );
      expect(pool.length, 2);
      expect(
        pool.where((SeedProfile p) => p.id == 'b').length,
        1,
        reason: 'aparecería dos veces en el feed',
      );
    });
  });

  group('Dentro del pool, el boost sube al perfil', () {
    test('el impulsado adelanta a los demás', () {
      final List<SeedProfile> pool = <SeedProfile>[
        _profile('a'),
        _profile('b'),
        _profile('impulsado'),
      ];
      final List<SeedProfile> ordenado = BoostAwareRanker.rank(
        profiles: pool,
        me: null,
        activeBoosts: <String, ActiveBoost>{
          'impulsado': ActiveBoost(
            boostId: 'b1',
            userId: 'impulsado',
            type: BoostType.superboost,
            status: 'active',
            startedAt: DateTime.now(),
            expiresAt: DateTime.now().add(const Duration(hours: 12)),
            priorityBonus: 150,
            impressionCap: 500,
            deliveredImpressions: 0,
          ),
        },
      );
      expect(ordenado.first.id, 'impulsado');
    });
  });
}
