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
  ///
  /// PROPAGA el fallo de lectura a propósito. Antes lo tragaba y devolvía false,
  /// que es indistinguible de "apagado": con un bache de red, el token
  /// refrescándose o un `resource-exhausted`, Discover se degradaba en silencio
  /// del muro a ciegas al feed de PERFILES COMPLETOS —bio, trabajo, estudios,
  /// verificación— que es justo lo que el "a ciegas" existe para evitar, y sin
  /// reintento posible porque nadie sabía que había fallado.
  Future<bool> storiesEnabled() async {
    final DocumentSnapshot<Map<String, dynamic>> snap =
        await _firestore.collection('config').doc('featureFlags').get();
    return (snap.data()?['storiesEnabled'] as bool?) ?? false;
  }

  /// RECORTA a UNA story por dueño (la más reciente): NO es "todas las vivas".
  ///
  /// Nació con el límite de una historia por usuario y hoy solo alimenta el aro
  /// de la lista de Chats. Con hasta 5 por persona, cualquier pantalla nueva que
  /// use esto pierde el resto sin que nada avise: para ver el grupo completo hay
  /// que ir por [observeLiveStoriesByOwner].
  ///
  /// Excluye a [excludeUid] y a [excludedOwners] (p. ej. bloqueados).
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
  /// Stories vivas agrupadas por dueño SIN filtrar por visibilidad.
  ///
  /// Es lo que puede ver un MATCH, y por eso no se reutiliza
  /// [observeLiveStoriesByOwner]: aquel descarta las de visibilidad "solo
  /// matches" porque alimenta el muro de Discover, que es descubrimiento. Aquí
  /// esas son precisamente las que hay que enseñar.
  ///
  /// Sustituye a [observeLiveStories] en la ruta de Chats: aquel colapsaba cada
  /// grupo a UNA sola story (la más reciente), herencia de cuando solo se
  /// admitía una por persona. Con el máximo actual de 5, tocar el aro de un
  /// match solo abría la última y las demás eran inalcanzables.
  Stream<Map<String, List<Story>>> observeLiveStoriesForMatches({
    String excludeUid = '',
    Set<String> excludedOwners = const <String>{},
  }) {
    return _stories
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) {
      return groupMatchStories(
        snap.docs.map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
            Story.fromMap(d.id, d.data())),
        excludeUid: excludeUid,
        excludedOwners: excludedOwners,
      );
    });
  }

  /// Agrupa por dueño las stories que puede ver un MATCH.
  ///
  /// Estática y pura para poder fijarla con un test: la regla que importa es
  /// que NO colapse el grupo. La versión anterior se quedaba con la más
  /// reciente de cada persona, herencia de cuando solo se admitía una story por
  /// usuario, y con el máximo actual de 5 eso dejaba las demás inalcanzables.
  ///
  /// A diferencia de [groupWallStories], aquí NO se filtra por visibilidad: las
  /// "solo matches" son precisamente las que este camino debe enseñar.
  static Map<String, List<Story>> groupMatchStories(
    Iterable<Story> stories, {
    String excludeUid = '',
    Set<String> excludedOwners = const <String>{},
  }) {
    final Map<String, List<Story>> byOwner = <String, List<Story>>{};
    for (final Story s in stories) {
      if (!s.isLive) continue;
      if (s.ownerUid == excludeUid) continue;
      if (excludedOwners.contains(s.ownerUid)) continue;
      (byOwner[s.ownerUid] ??= <Story>[]).add(s);
    }
    // De más antigua a más reciente: es el orden en que las cuenta el visor al
    // abrirse por el índice 0.
    for (final List<Story> group in byOwner.values) {
      group.sort((Story a, Story b) =>
          (a.createdAt?.millisecondsSinceEpoch ?? 0)
              .compareTo(b.createdAt?.millisecondsSinceEpoch ?? 0));
    }
    return byOwner;
  }

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
  /// eso. Antes el único filtro por match lo hacía la tira de aros, que
  /// desapareció con el muro; las reglas dejan leer /stories a cualquier usuario
  /// autenticado, así que este filtro es el ÚNICO que hay: sin él la historia
  /// privada se le reproducía a pantalla completa a desconocidos. Las "Solo
  /// matches" siguen viéndose por la ruta de Chats, que sí parte de los matches
  /// (y que hoy, por [observeLiveStories], solo enseña la más reciente de cada
  /// persona).
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

  /// Todas las stories vivas del propio usuario, de más antigua a más reciente
  /// (el orden en que se leen en el visor).
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

  Stream<Story?> observeStoryById(String storyId) {
    return _stories.doc(storyId).snapshots().map(
        (DocumentSnapshot<Map<String, dynamic>> d) =>
            d.exists ? Story.fromMap(d.id, d.data()!) : null);
  }
}
