import 'dart:async';

import 'package:attra/src/features/match/data/match_repository.dart';
import 'package:attra/src/features/match/domain/user_match.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// C41: la pestaña Matches y su contador salen de MatchRepository.observeMatches.
/// La consulta pide `active`, pero los cerrados con elegancia antes de que el
/// backend marcara el match como `closed` siguen en `active` con el recorrido
/// `archived`. Las pruebas de pantalla usaban un servicio falso que no pasaba
/// por este filtro; aquí se prueba el del repositorio.
class _NoFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestRepository extends MatchRepository {
  _TestRepository(this.source) : super(firestore: _NoFirestore());

  final Stream<List<UserMatch>> source;

  @override
  Stream<List<UserMatch>> activeMatchesSource(String uid) => source;
}

UserMatch _match(
  String other,
  String status, {
  String? journeyStatus,
  required DateTime createdAt,
}) =>
    UserMatch.fromMap('me_$other', <String, dynamic>{
      'users': <String>['me', other],
      'userA': 'me',
      'userB': other,
      'status': status,
      if (journeyStatus != null) 'journeyStatus': journeyStatus,
      'createdAt': createdAt.toIso8601String(),
    });

void main() {
  test('solo matches vivos, más recientes primero', () async {
    final _TestRepository repo =
        _TestRepository(Stream<List<UserMatch>>.value(<UserMatch>[
      _match('ana', 'active', createdAt: DateTime.utc(2026, 9, 1)),
      _match('bea', 'active',
          journeyStatus: 'archived', createdAt: DateTime.utc(2026, 9, 5)),
      _match('carla', 'closed', createdAt: DateTime.utc(2026, 9, 6)),
      _match('dani', 'unmatched', createdAt: DateTime.utc(2026, 9, 7)),
      _match('eva', 'active',
          journeyStatus: 'conversation', createdAt: DateTime.utc(2026, 9, 3)),
    ]));

    final List<UserMatch> open = await repo.observeMatches('me').first;

    expect(open.map((UserMatch m) => m.otherUid('me')), <String>['eva', 'ana']);
  });

  test('isUndone: deshecho, bloqueado o retirado; un cierre con elegancia no',
      () {
    UserMatch m(String status) =>
        _match('x', status, createdAt: DateTime.utc(2026));
    expect(m('unmatched').isUndone, isTrue);
    expect(m('blocked').isUndone, isTrue);
    expect(m('deleted').isUndone, isTrue);
    expect(m('closed').isUndone, isFalse);
    expect(m('active').isUndone, isFalse);
  });
}
