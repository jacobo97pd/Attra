import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/like.dart';
import '../domain/received_like_priority.dart';
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

  /// Uids con los que el usuario ya interactuo (like, pass, match) o bloqueo,
  /// para excluirlos del feed. Lecturas puntuales permitidas por las reglas
  /// (fromUid==me / blockerUid==me / participante). Los que ME bloquearon NO se
  /// pueden leer (reglas), pero el backend igualmente impide interactuar.
  Future<Set<String>> fetchExcludedUids(String uid) async {
    final List<QuerySnapshot<Map<String, dynamic>>> results = await Future.wait(
      <Future<QuerySnapshot<Map<String, dynamic>>>>[
        _likes.where('fromUid', isEqualTo: uid).get(),
        _dislikes.where('fromUid', isEqualTo: uid).get(),
        _matches.where('users', arrayContains: uid).get(),
        _blocks.where('blockerUid', isEqualTo: uid).get(),
      ],
    );

    final Set<String> excluded = <String>{};
    for (final QueryDocumentSnapshot<Map<String, dynamic>> d
        in results[0].docs) {
      final String? to = d.data()['toUid'] as String?;
      if (to != null) excluded.add(to);
    }
    for (final QueryDocumentSnapshot<Map<String, dynamic>> d
        in results[1].docs) {
      final String? to = d.data()['toUid'] as String?;
      if (to != null) excluded.add(to);
    }
    for (final QueryDocumentSnapshot<Map<String, dynamic>> d
        in results[2].docs) {
      final List<dynamic> users =
          (d.data()['users'] as List<dynamic>?) ?? const <dynamic>[];
      for (final dynamic u in users) {
        if (u is String && u != uid) excluded.add(u);
      }
    }
    for (final QueryDocumentSnapshot<Map<String, dynamic>> d
        in results[3].docs) {
      final String? blocked = d.data()['blockedUid'] as String?;
      if (blocked != null) excluded.add(blocked);
    }
    return excluded;
  }

  /// Matches activos del usuario, mas recientes primero.
  Stream<List<UserMatch>> observeMatches(String uid) {
    return _matches
        .where('users', arrayContains: uid)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) {
      final List<UserMatch> items = snap.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              UserMatch.fromMap(d.id, d.data()))
          .toList(growable: true)
        ..sort((UserMatch a, UserMatch b) =>
            _millis(b.createdAt).compareTo(_millis(a.createdAt)));
      return items;
    });
  }

  Stream<UserMatch?> observeMatchById(String matchId) {
    return _matches.doc(matchId).snapshots().map(
        (DocumentSnapshot<Map<String, dynamic>> d) =>
            d.exists ? UserMatch.fromMap(d.id, d.data()!) : null);
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
