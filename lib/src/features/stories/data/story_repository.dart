import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/story.dart';

/// Lecturas en vivo de stories. SOLO lectura: crear/ver/responder/borrar pasa
/// por Cloud Functions (StoryService). Se consulta por `status==active` (campo
/// unico, sin indice compuesto) y se filtran las caducadas en cliente.
class StoryRepository {
  StoryRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _stories =>
      _firestore.collection('stories');

  /// Kill switch desde `config/featureFlags.storiesEnabled` (default false).
  Future<bool> storiesEnabled() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await _firestore.collection('config').doc('featureFlags').get();
      return (snap.data()?['storiesEnabled'] as bool?) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Stories vivas (active + no caducadas), una por dueño (la mas reciente),
  /// excluyendo a [excludeUid] y a [excludedOwners] (p.ej. bloqueados).
  Stream<List<Story>> observeLiveStories({
    String excludeUid = '',
    Set<String> excludedOwners = const <String>{},
  }) {
    return _stories
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) {
      final Map<String, Story> byOwner = <String, Story>{};
      for (final QueryDocumentSnapshot<Map<String, dynamic>> d in snap.docs) {
        final Story s = Story.fromMap(d.id, d.data());
        if (!s.isLive) continue;
        if (s.ownerUid == excludeUid) continue;
        if (excludedOwners.contains(s.ownerUid)) continue;
        final Story? prev = byOwner[s.ownerUid];
        if (prev == null ||
            (s.createdAt?.millisecondsSinceEpoch ?? 0) >
                (prev.createdAt?.millisecondsSinceEpoch ?? 0)) {
          byOwner[s.ownerUid] = s;
        }
      }
      final List<Story> list = byOwner.values.toList(growable: true)
        ..sort((Story a, Story b) => (b.createdAt?.millisecondsSinceEpoch ?? 0)
            .compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0));
      return list;
    });
  }

  /// La story viva del propio usuario (o null).
  Stream<Story?> observeMyLiveStory(String uid) {
    return _stories
        .where('ownerUid', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) {
      final List<Story> live = snap.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              Story.fromMap(d.id, d.data()))
          .where((Story s) => s.isLive)
          .toList(growable: true)
        ..sort((Story a, Story b) => (b.createdAt?.millisecondsSinceEpoch ?? 0)
            .compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0));
      return live.isEmpty ? null : live.first;
    });
  }

  Stream<Story?> observeStoryById(String storyId) {
    return _stories.doc(storyId).snapshots().map(
        (DocumentSnapshot<Map<String, dynamic>> d) =>
            d.exists ? Story.fromMap(d.id, d.data()!) : null);
  }
}
