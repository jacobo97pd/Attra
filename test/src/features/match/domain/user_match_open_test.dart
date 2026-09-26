import 'package:attra/src/features/match/domain/user_match.dart';
import 'package:flutter_test/flutter_test.dart';

/// C41: "Cerrar con elegancia" dejaba el match en `active` (solo archivaba el
/// recorrido), así que la pestaña Matches seguía contándolo y ofreciendo
/// "Enviar mensaje" hacia un chat donde ya no se puede escribir.
UserMatch _match(String status, {String? journeyStatus}) =>
    UserMatch.fromMap('a_b', <String, dynamic>{
      'users': <String>['a', 'b'],
      'userA': 'a',
      'userB': 'b',
      'status': status,
      if (journeyStatus != null) 'journeyStatus': journeyStatus,
    });

void main() {
  test('un match activo sale', () {
    expect(_match('active').isOpen, isTrue);
    expect(
        _match('active', journeyStatus: 'conversation_active').isOpen, isTrue);
  });

  test('`closed` se reconoce: no cae en el `active` por defecto', () {
    final UserMatch m = _match('closed');
    expect(m.status, MatchStatus.closed);
    expect(m.status.isActive, isFalse);
    expect(m.isOpen, isFalse);
  });

  test('deshecho o bloqueado: no sale', () {
    expect(_match('unmatched').isOpen, isFalse);
    expect(_match('blocked').isOpen, isFalse);
  });

  test(
      'cerrado con elegancia ANTES del arreglo del backend (active + '
      'recorrido archivado): no sale', () {
    expect(_match('active', journeyStatus: 'archived').isOpen, isFalse);
  });
}
