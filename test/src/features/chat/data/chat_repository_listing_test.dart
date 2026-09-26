import 'dart:async';

import 'package:attra/src/features/chat/data/chat_repository.dart';
import 'package:attra/src/features/chat/domain/chat.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// El filtro de la lista vive en ChatRepository.observeChats (también alimenta
/// "Tu turno"), y las pruebas de pantalla usaban servicios falsos que no
/// pasaban por él. Aquí se prueba el stream real, con las dos consultas
/// sustituidas por controladores.
///
/// Caso nuevo: "Cerrar con elegancia" y después "Deshacer match". El chat se
/// queda `closed` y firmado (igual que un archivo) y los dos seguían viéndose
/// en "Conversaciones"; solo el match sabe que está `unmatched`.
class _NoFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestRepository extends ChatRepository {
  _TestRepository() : super(firestore: _NoFirestore());

  final StreamController<List<Chat>> chats =
      StreamController<List<Chat>>.broadcast();
  final StreamController<Set<String>> unmatched =
      StreamController<Set<String>>.broadcast();
  int chatsOpened = 0;
  int unmatchedOpened = 0;

  @override
  Stream<List<Chat>> chatsSource(String uid) {
    chatsOpened++;
    return chats.stream;
  }

  @override
  Stream<Set<String>> unmatchedPairsSource(String uid) {
    unmatchedOpened++;
    return unmatched.stream;
  }
}

Chat _chat(
  String other,
  String status, {
  String? closedBy,
  DateTime? lastAt,
}) =>
    Chat.fromMap('me_$other', <String, dynamic>{
      'matchId': 'me_$other',
      'users': <String>['me', other],
      'status': status,
      if (closedBy != null) 'closedByUserId': closedBy,
      if (closedBy != null) 'lastMessageType': 'closure',
      if (lastAt != null) 'lastMessageAt': lastAt.toIso8601String(),
    });

List<String> _others(List<Chat> chats) =>
    chats.map((Chat c) => c.otherUid('me')).toList();

void main() {
  late _TestRepository repo;

  setUp(() => repo = _TestRepository());
  tearDown(() async {
    await repo.chats.close();
    await repo.unmatched.close();
  });

  test(
      'quita bloqueados, deshechos y el cierre con elegancia cuyo match se '
      'deshizo después; deja activos y archivos, por último mensaje', () async {
    final List<List<Chat>> out = <List<Chat>>[];
    final StreamSubscription<List<Chat>> sub =
        repo.observeChats('me').listen(out.add);
    await pumpEventQueue();

    repo.chats.add(<Chat>[
      _chat('ana', 'active', lastAt: DateTime.utc(2026, 9, 1)),
      _chat('bea', 'blocked'),
      _chat('dani', 'closed'), // unmatch "normal": closed sin firmar
      _chat('fran', 'closed',
          closedBy: 'fran', lastAt: DateTime.utc(2026, 9, 3)), // archivo
      _chat('gala', 'closed', closedBy: 'me'), // archivo... y luego unmatch
      _chat('hugo', 'deleted'),
      _chat('ines', 'active', lastAt: DateTime.utc(2026, 9, 2)),
    ]);
    await pumpEventQueue();
    expect(out, isEmpty, reason: 'aún no se sabe qué matches se deshicieron');

    repo.unmatched.add(<String>{'me_gala', 'me_dani'});
    await pumpEventQueue();

    expect(_others(out.single), <String>['fran', 'ines', 'ana']);
    await sub.cancel();
  });

  test('si la consulta de matches falla, sigue con lo que dice el chat',
      () async {
    final List<List<Chat>> out = <List<Chat>>[];
    final StreamSubscription<List<Chat>> sub =
        repo.observeChats('me').listen(out.add);
    await pumpEventQueue();

    repo.chats.add(<Chat>[
      _chat('ana', 'active'),
      _chat('bea', 'blocked'),
      _chat('gala', 'closed', closedBy: 'me'),
    ]);
    repo.unmatched.addError(StateError('permission-denied'));
    await pumpEventQueue();

    expect(_others(out.single), <String>['ana', 'gala']);
    await sub.cancel();
  });

  test('un error de los chats llega a la lista', () async {
    final List<Object> errors = <Object>[];
    final StreamSubscription<List<Chat>> sub =
        repo.observeChats('me').listen((_) {}, onError: errors.add);
    await pumpEventQueue();

    repo.chats.addError(StateError('sin red'));
    await pumpEventQueue();

    expect(errors, hasLength(1));
    await sub.cancel();
  });

  test(
      'la lista y "Tu turno" comparten las dos escuchas; pedirlo otra vez '
      'devuelve el mismo stream', () async {
    expect(identical(repo.observeChats('me'), repo.observeChats('me')), isTrue);

    final List<List<Chat>> lista = <List<Chat>>[];
    final StreamSubscription<List<Chat>> a =
        repo.observeChats('me').listen(lista.add);
    final StreamSubscription<List<Chat>> b =
        repo.observeChats('me').listen((_) {});
    await pumpEventQueue();
    repo.chats.add(<Chat>[_chat('ana', 'active')]);
    repo.unmatched.add(const <String>{});
    await pumpEventQueue();

    // Quien llega después (una lista recién montada) no se queda cargando.
    final List<List<Chat>> tarde = <List<Chat>>[];
    final StreamSubscription<List<Chat>> c =
        repo.observeChats('me').listen(tarde.add);
    await pumpEventQueue();

    expect(repo.chatsOpened, 1);
    expect(repo.unmatchedOpened, 1);
    expect(_others(tarde.single), <String>['ana']);
    await a.cancel();
    await b.cancel();
    await c.cancel();
  });

  group('Chat.listable (puro)', () {
    test('sin matches deshechos es lo mismo que isListed', () {
      expect(
        _others(Chat.listable(<Chat>[
          _chat('ana', 'active'),
          _chat('bea', 'blocked'),
          _chat('fran', 'closed', closedBy: 'fran'),
        ])),
        <String>['ana', 'fran'],
      );
    });

    test('un archivo cuyo match se deshizo sale fuera', () {
      expect(
        Chat.listable(<Chat>[_chat('gala', 'closed', closedBy: 'me')],
            undoneMatchIds: <String>{'me_gala'}),
        isEmpty,
      );
    });
  });
}
