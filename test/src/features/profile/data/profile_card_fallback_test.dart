import 'package:attra/src/features/auth/data/user_repository.dart';
import 'package:attra/src/features/profile/data/profile_summary_repository.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:attra/src/features/profile/domain/profile_summary.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// C02 / C10: ocultar el perfil, pausar la cuenta, no salir en recomendaciones
/// o el incógnito de pago borraban `discovery/{uid}`, la única ficha legible
/// de un usuario real. Sus matches y a quien había dado like veían "Alguien"
/// sin foto y "No se pudo cargar el perfil.". Ahora el backend publica además
/// `profileCards/{uid}` (legible solo por su match activo y por quien recibió
/// su like) y el cliente la usa cuando no está en discovery.

/// Firestore de mentira: `colección/uid` -> datos, o una excepción a lanzar.
class _FakeStore {
  _FakeStore(this.docs, {this.errors = const <String, Object>{}});

  final Map<String, Map<String, dynamic>> docs;
  final Map<String, Object> errors;
  final List<String> reads = <String>[];

  Future<Map<String, dynamic>?> read(String collection, String uid) async {
    final String path = '$collection/$uid';
    reads.add(path);
    final Object? error = errors[path];
    if (error != null) throw error;
    return docs[path];
  }
}

FirebaseException _denied() => FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );

Map<String, dynamic> _card(String name) => <String, dynamic>{
      'uid': 'ana',
      'displayName': name,
      'photoUrl': 'https://example.test/ana.jpg',
      'age': 31,
      'gender': 'female',
      'currentCity': 'Madrid',
      'currentCountryName': 'España',
      'isBot': false,
    };

void main() {
  group('ProfileSummaryRepository', () {
    test('un match con el perfil oculto se ve con nombre y foto', () async {
      // discovery/ana no existe (se ocultó); su ficha sí.
      final _FakeStore store = _FakeStore(<String, Map<String, dynamic>>{
        'profileCards/ana': _card('Ana'),
      });
      final ProfileSummaryRepository repo =
          ProfileSummaryRepository.withReader(store.read);

      final ProfileSummary s = await repo.fetch('ana');

      expect(s.displayName, 'Ana');
      expect(s.photoUrl, 'https://example.test/ana.jpg');
      expect(s.city, 'Madrid');
      expect(store.reads, <String>[
        'discovery/ana',
        'seed_profiles/ana',
        'profileCards/ana',
      ]);
      // Resuelto: se cachea como cualquier otro.
      expect(repo.peek('ana')?.displayName, 'Ana');
    });

    test('quien sale en el feed se sigue resolviendo por discovery', () async {
      final _FakeStore store = _FakeStore(<String, Map<String, dynamic>>{
        'discovery/ana': _card('Ana feed'),
        'profileCards/ana': _card('Ana ficha'),
      });
      final ProfileSummary s =
          await ProfileSummaryRepository.withReader(store.read).fetch('ana');

      expect(s.displayName, 'Ana feed');
      expect(store.reads, <String>['discovery/ana']);
    });

    test('sin relación (reglas lo deniegan) es "Alguien", sin romper',
        () async {
      final _FakeStore store = _FakeStore(
        <String, Map<String, dynamic>>{},
        errors: <String, Object>{'profileCards/ana': _denied()},
      );
      final ProfileSummaryRepository repo =
          ProfileSummaryRepository.withReader(store.read);

      final ProfileSummary s = await repo.fetch('ana');

      expect(s.displayName, 'Alguien');
      expect(s.photoUrl, '');
      expect(s.uid, 'ana');
      // No se fija "Alguien" en caché: si luego hay relación, se relee.
      expect(repo.peek('ana'), isNull);
    });

    test('un permission-denied fuera de profileCards no se oculta', () async {
      final _FakeStore store = _FakeStore(
        <String, Map<String, dynamic>>{},
        errors: <String, Object>{'discovery/ana': _denied()},
      );
      await expectLater(
        ProfileSummaryRepository.withReader(store.read).fetch('ana'),
        throwsA(isA<FirebaseException>()),
      );
    });
  });

  group('UserRepository.profileByUid (fetchProfileByUid)', () {
    test('abre el perfil de un like incógnito desde su ficha', () async {
      final _FakeStore store = _FakeStore(<String, Map<String, dynamic>>{
        'profileCards/ana': _card('Ana'),
      });

      final SeedProfile? p =
          await UserRepository.profileByUid('ana', store.read);

      expect(p, isNotNull);
      expect(p!.id, 'ana');
      expect(p.displayName, 'Ana');
      expect(p.age, 31);
    });

    test('sin ficha para quien pregunta devuelve null, no lanza', () async {
      final _FakeStore store = _FakeStore(
        <String, Map<String, dynamic>>{},
        errors: <String, Object>{'profileCards/ana': _denied()},
      );
      expect(await UserRepository.profileByUid('ana', store.read), isNull);
      expect(await UserRepository.profileByUid('', store.read), isNull);
    });

    test('los mocks siguen saliendo de seed_profiles', () async {
      final _FakeStore store = _FakeStore(<String, Map<String, dynamic>>{
        'seed_profiles/mock_1': <String, dynamic>{
          'displayName': 'Mock',
          'isBot': true,
          'city': 'Cádiz',
        },
      });
      final SeedProfile? p =
          await UserRepository.profileByUid('mock_1', store.read);
      expect(p?.displayName, 'Mock');
      expect(store.reads, <String>['discovery/mock_1', 'seed_profiles/mock_1']);
    });
  });
}
