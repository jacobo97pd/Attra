import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../feed/domain/feed_exclusions.dart';
import '../domain/like.dart';
import '../domain/received_like_priority.dart';
import '../domain/sent_like_ordering.dart';
import '../domain/user_match.dart';

/// Lecturas en vivo de matches y likes recibidos. SOLO lectura: las escrituras
/// pasan por Cloud Functions (MatchService). Evitamos `orderBy` combinado con
/// `arrayContains`/igualdad para no requerir indices compuestos; ordenamos en
/// cliente (volumen por usuario bajo).
class MatchRepository {
  MatchRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _matches =>
      _firestore.collection('matches');
  CollectionReference<Map<String, dynamic>> get _likes =>
      _firestore.collection('likes');
  CollectionReference<Map<String, dynamic>> get _dislikes =>
      _firestore.collection('dislikes');
  CollectionReference<Map<String, dynamic>> get _blocks =>
      _firestore.collection('blocks');

  /// A quién excluir del feed, SEPARADO POR MOTIVO (ver [FeedExclusions]):
  /// likes enviados, pases (normales y permanentes), matches de cualquier
  /// estado y bloqueos hechos. Lecturas puntuales permitidas por las reglas
  /// (fromUid==me / blockerUid==me / participante). Los bloqueos que ME hicieron
  /// no se pueden leer (reglas): de esos solo queda el match en 'blocked'.
  ///
  /// Cada lectura va por su cuenta: antes iban en un solo `Future.wait` y el
  /// fallo de UNA (un token que se refresca, un `unavailable`) tiraba las
  /// cuatro, y el feed seguía con NADIE excluido. Ahora la que falla se apunta
  /// en [FeedExclusions.failed] y el feed decide qué hacer sin perder las demás.
  /// Esta llamada ya no lanza.
  Future<FeedExclusions> fetchExcludedUids(String uid) async {
    Future<List<Map<String, dynamic>>?> read(
        Query<Map<String, dynamic>> query) async {
      try {
        final QuerySnapshot<Map<String, dynamic>> snap = await query.get();
        return snap.docs
            .map((QueryDocumentSnapshot<Map<String, dynamic>> d) => d.data())
            .toList(growable: false);
      } catch (_) {
        return null;
      }
    }

    final List<List<Map<String, dynamic>>?> results = await Future.wait(
      <Future<List<Map<String, dynamic>>?>>[
        read(_likes.where('fromUid', isEqualTo: uid)),
        read(_dislikes.where('fromUid', isEqualTo: uid)),
        read(_matches.where('users', arrayContains: uid)),
        read(_blocks.where('blockerUid', isEqualTo: uid)),
      ],
    );
    return FeedExclusions.fromDocs(
      uid: uid,
      likes: results[0],
      dislikes: results[1],
      matches: results[2],
      blocks: results[3],
    );
  }

  /// Matches activos del usuario, mas recientes primero. La consulta ya pide
  /// `active`; [UserMatch.isOpen] quita además los cerrados con elegancia que
  /// quedaron en `active` con el recorrido archivado.
  Stream<List<UserMatch>> observeMatches(String uid) {
    return activeMatchesSource(uid).map((List<UserMatch> all) {
      final List<UserMatch> items = all
          .where((UserMatch m) => m.isOpen)
          .toList(growable: true)
        ..sort((UserMatch a, UserMatch b) =>
            _millis(b.createdAt).compareTo(_millis(a.createdAt)));
      return items;
    });
  }

  /// La consulta de [observeMatches] (`active`), sin el filtro de cliente.
  /// Separada para probar ese filtro sin Firestore.
  @visibleForTesting
  Stream<List<UserMatch>> activeMatchesSource(String uid) => _matches
      .where('users', arrayContains: uid)
      .where('status', isEqualTo: 'active')
      .snapshots()
      .map((QuerySnapshot<Map<String, dynamic>> snap) => snap.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              UserMatch.fromMap(d.id, d.data()))
          .toList(growable: false));

  Stream<UserMatch?> observeMatchById(String matchId) {
    return _matches.doc(matchId).snapshots().map(
        (DocumentSnapshot<Map<String, dynamic>> d) =>
            d.exists ? UserMatch.fromMap(d.id, d.data()!) : null);
  }

  /// Likes enviados que siguen pendientes de respuesta, más recientes primero.
  ///
  /// Los likes que ya produjeron match pasan a `matched`, por lo que no se
  /// duplican aquí y en la pestaña de matches.
  Stream<List<Like>> observeSentLikes(String uid) {
    return _likes
        .where('fromUid', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) {
      return SentLikeOrdering.newestPending(
        snap.docs.map(
          (QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              Like.fromMap(d.data()),
        ),
      );
    });
  }

  /// Likes recibidos activos (bandeja "Te han dado like"). Los de tipo attra se
  /// destacan en la UI. Sin match todavia.
  Stream<List<Like>> observeReceivedLikes(String uid) {
    late final StreamController<List<Like>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? likesSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? blocksSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? matchesSub;

    List<Like> likes = const <Like>[];
    Set<String> blockedUids = const <String>{};
    Set<String> matchedUids = const <String>{};
    bool hasLikes = false;
    bool hasBlocks = false;
    bool hasMatches = false;

    void emitIfReady() {
      if (!hasLikes || !hasBlocks || !hasMatches || controller.isClosed) {
        return;
      }
      controller.add(ReceivedLikePriority.sortAndFilter(
        likes: likes,
        blockedUids: blockedUids,
        matchedUids: matchedUids,
      ));
    }

    controller = StreamController<List<Like>>(
      onListen: () {
        likesSub = _likes
            .where('toUid', isEqualTo: uid)
            .where('status', isEqualTo: 'active')
            .snapshots()
            .listen(
          (QuerySnapshot<Map<String, dynamic>> snap) {
            likes = snap.docs
                .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                    Like.fromMap(d.data()))
                .toList(growable: false);
            hasLikes = true;
            emitIfReady();
          },
          onError: controller.addError,
        );

        blocksSub =
            _blocks.where('blockerUid', isEqualTo: uid).snapshots().listen(
          (QuerySnapshot<Map<String, dynamic>> snap) {
            blockedUids = snap.docs
                .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                    d.data()['blockedUid'])
                .whereType<String>()
                .toSet();
            hasBlocks = true;
            emitIfReady();
          },
          onError: controller.addError,
        );

        matchesSub = _matches
            .where('users', arrayContains: uid)
            .where('status', isEqualTo: 'active')
            .snapshots()
            .listen(
          (QuerySnapshot<Map<String, dynamic>> snap) {
            final Set<String> matched = <String>{};
            for (final QueryDocumentSnapshot<Map<String, dynamic>> d
                in snap.docs) {
              final List<dynamic> users =
                  (d.data()['users'] as List<dynamic>?) ?? const <dynamic>[];
              for (final dynamic other in users) {
                if (other is String && other != uid) matched.add(other);
              }
            }
            matchedUids = matched;
            hasMatches = true;
            emitIfReady();
          },
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await likesSub?.cancel();
        await blocksSub?.cancel();
        await matchesSub?.cancel();
      },
    );
    return controller.stream;
  }

  static int _millis(DateTime? d) => d?.millisecondsSinceEpoch ?? 0;
}
