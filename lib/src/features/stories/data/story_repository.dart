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

  /// Stories vivas AGRUPADAS por dueño, de más reciente a más antigua dentro de
  /// cada grupo.
  ///
  /// [observeLiveStories] colapsa a UNA story por dueño porque nació con el
  /// límite de una historia por usuario. Con hasta 5 por persona eso perdía el
  /// resto: el muro no podría apilarlas ni el visor pasarlas una a una.
  ///
  /// El orden DENTRO del grupo es cronológico ASCENDENTE (la más antigua
  /// primero), que es como se leen las historias; el orden ENTRE grupos lo
  /// decide quien pinta el muro (el ranking del feed), no este repositorio.
  Stream<Map<String, List<Story>>> observeLiveStoriesByOwner({
    String excludeUid = '',
    Set<String> excludedOwners = const <String>{},
  }) {
    return _stories
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) => groupWallStories(
              snap.docs.map(
                  (QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                      Story.fromMap(d.id, d.data())),
              excludeUid: excludeUid,
              excludedOwners: excludedOwners,
            ));
  }

  /// Agrupa por dueño las stories que pueden alimentar el MURO de Discover.
  ///
  /// Aquí NO entra `visibility: matches`: el muro es descubrimiento por
  /// definición y quien elige "Solo matches" en el editor espera exactamente
  /// eso. Antes el único filtro por match lo hacía la tira de aros
  /// (`StoriesBar`), que desapareció con el muro; las reglas dejan leer
  /// /stories a cualquier usuario autenticado, así que este filtro es el ÚNICO
  /// que hay: sin él la historia privada se le reproducía a pantalla completa a
  /// desconocidos. Las "Solo matches" siguen viéndose por la ruta de Chats, que
  /// sí parte de los matches.
  ///
  /// Estática y pura para poder fijarla con un test: es una regla de
  /// privacidad, no un detalle de la consulta.
  static Map<String, List<Story>> groupWallStories(
    Iterable<Story> stories, {
    String excludeUid = '',
    Set<String> excludedOwners = const <String>{},
  }) {
    final Map<String, List<Story>> byOwner = <String, List<Story>>{};
    for (final Story s in stories) {
      if (!s.isLive) continue;
      if (s.visibility != StoryVisibility.discovery) continue;
      if (s.ownerUid == excludeUid) continue;
      if (excludedOwners.contains(s.ownerUid)) continue;
      (byOwner[s.ownerUid] ??= <Story>[]).add(s);
    }
    for (final List<Story> group in byOwner.values) {
      group.sort((Story a, Story b) => (a.createdAt?.millisecondsSinceEpoch ?? 0)
          .compareTo(b.createdAt?.millisecondsSinceEpoch ?? 0));
    }
    return byOwner;
  }

  /// Todas las stories vivas del propio usuario, de más antigua a más reciente.
  /// Sustituye a [observeMyLiveStory] ahora que se admiten varias.
  Stream<List<Story>> observeMyLiveStories(String uid) {
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
        ..sort((Story a, Story b) => (a.createdAt?.millisecondsSinceEpoch ?? 0)
            .compareTo(b.createdAt?.millisecondsSinceEpoch ?? 0));
      return live;
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
