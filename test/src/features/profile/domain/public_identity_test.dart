import 'package:attra/src/features/profile/domain/public_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolvePublicDisplayName', () {
    test(
        'el nombre elegido en onboarding (profile.visibleName) gana al de '
        'Google en displayName de primer nivel', () {
      final name = resolvePublicDisplayName(<String, dynamic>{
        'displayName': 'Javier Rodriguez Montero', // Auth/Google
        'profile': <String, dynamic>{'visibleName': 'Bella Hadid'},
      });
      expect(name, 'Bella Hadid');
    });

    test('profile.displayName tiene prioridad sobre visibleName', () {
      final name = resolvePublicDisplayName(<String, dynamic>{
        'displayName': 'Javier Rodriguez Montero',
        'profile': <String, dynamic>{
          'displayName': 'Bella H.',
          'visibleName': 'Bella Hadid',
        },
      });
      expect(name, 'Bella H.');
    });

    test('firstName + lastName si no hay displayName/visibleName', () {
      final name = resolvePublicDisplayName(<String, dynamic>{
        'displayName': 'Auth Name',
        'profile': <String, dynamic>{
          'firstName': 'Jacobo',
          'lastName': 'Pedrero',
        },
      });
      expect(name, 'Jacobo Pedrero');
    });

    test('cae al displayName de primer nivel solo como ultimo recurso', () {
      final name = resolvePublicDisplayName(<String, dynamic>{
        'displayName': 'Auth Name',
        'profile': <String, dynamic>{},
      });
      expect(name, 'Auth Name');
    });

    test('FirebaseAuth.displayName NO sobrescribe un nombre elegido', () {
      // Simula login posterior: aunque cambie el nombre de Auth, el publico
      // sigue siendo el elegido.
      final data = <String, dynamic>{
        'displayName': 'Nombre Legal Distinto',
        'profile': <String, dynamic>{'visibleName': 'Bella Hadid'},
      };
      expect(resolvePublicDisplayName(data), 'Bella Hadid');
    });

    test('vacio si no hay ningun nombre', () {
      expect(resolvePublicDisplayName(<String, dynamic>{}), '');
    });
  });
}
