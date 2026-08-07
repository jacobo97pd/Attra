import 'package:attra/src/features/stories/presentation/story_stack_card.dart';
import 'package:flutter_test/flutter_test.dart';

/// El grosor de la pila del muro depende del NÚMERO de historias vivas de esa
/// persona y de nada más.
///
/// Es solo visual: no reordena el muro. El orden lo pone el pipeline del feed
/// (ver story_wall_test.dart). Si el grosor llegara a influir en el orden, quien
/// ha PAGADO un Boost lo perdería frente a quien simplemente publica más.
void main() {
  group('Grosor de la pila', () {
    test('una historia se ve plana (sin hojas detrás)', () {
      expect(storyStackSheets(1), 0);
    });

    test('cada historia extra añade una hoja', () {
      expect(storyStackSheets(2), 1);
      expect(storyStackSheets(3), 2);
      expect(storyStackSheets(4), 3);
    });

    test('cinco historias es la pila más gruesa', () {
      // El backend no deja pasar de 5 vivas por usuario (MAX_ACTIVE_STORIES en
      // functions/src/stories.ts).
      expect(storyStackSheets(5), StoryStackCard.maxSheets);
      expect(StoryStackCard.maxSheets, 4);
    });

    test('un dato corrupto no dibuja una escalera infinita', () {
      expect(storyStackSheets(9), StoryStackCard.maxSheets);
      expect(storyStackSheets(500), StoryStackCard.maxSheets);
    });

    test('cero o negativo no rompe (no hay hojas)', () {
      expect(storyStackSheets(0), 0);
      expect(storyStackSheets(-3), 0);
    });
  });
}
