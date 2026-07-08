import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/friend_group.dart';
import '../domain/social_affinity.dart';

class _Scored {
  const _Scored(this.group, this.affinity, this.rank);
  final FriendGroup group;
  final double affinity;
  final double rank;
}

/// Grupo recomendado + su score de afinidad social (para mostrar "%" y ordenar).
class RecommendedGroup {
  const RecommendedGroup({required this.group, required this.affinity});
  final FriendGroup group;
  final double affinity;

  int get affinityPercent => (affinity * 100).round();
}

/// Descubrimiento social: recomienda grupos abiertos por ciudad + intereses.
/// Solo LECTURA (Firestore). Ranking por afinidad de intereses (puro/testeable).
/// La IA futura puede sustituir el ranking detrás de la misma forma
/// (ver SocialAiRecommender).
class SocialDiscoveryService {
  SocialDiscoveryService({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _groups =>
      _firestore.collection('friendGroups');

  /// Grupos abiertos recomendados. Filtra por ciudad si se da (nunca ubicación
  /// exacta) y ordena por afinidad con [myInterests], excluyendo aquellos donde
  /// ya soy miembro o tengo solicitud pendiente.
  Future<List<RecommendedGroup>> recommendedGroups({
    required String uid,
    String city = '',
    List<String> myInterests = const <String>[],
    int limit = 30,
  }) async {
    // Trae grupos ABIERTOS y ordena por ciudad (match = boost) + afinidad de
    // intereses. No filtra duro por ciudad para no vaciar el listado cuando aún
    // hay pocos grupos por zona.
    final QuerySnapshot<Map<String, dynamic>> snap =
        await _groups.where('status', isEqualTo: 'open').limit(limit).get();
    final String myCity = city.trim().toLowerCase();

    final List<_Scored> scored = <_Scored>[];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> d in snap.docs) {
      final FriendGroup g = FriendGroup.fromMap(d.id, d.data());
      if (g.isMember(uid) || g.isPending(uid) || g.isFull) continue;
      final double affinity = SocialAffinity.score(myInterests, g.interests);
      final bool sameCity =
          myCity.isNotEmpty && g.city.trim().toLowerCase() == myCity;
      // Ranking: la ciudad pesa más que la afinidad de intereses.
      final double rank = (sameCity ? 1.0 : 0.0) + affinity * 0.5;
      scored.add(_Scored(g, affinity, rank));
    }
    scored.sort((_Scored a, _Scored b) => b.rank.compareTo(a.rank));
    return scored
        .map((_Scored s) =>
            RecommendedGroup(group: s.group, affinity: s.affinity))
        .toList(growable: false);
  }
}
