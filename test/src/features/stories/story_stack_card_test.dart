import 'package:attra/src/features/stories/domain/story.dart';
import 'package:attra/src/features/stories/presentation/story_stack_card.dart';
import 'package:attra/src/widgets/attra_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// El grosor de la pila del muro depende del NÚMERO de historias vivas de esa
/// persona y de nada más.
///
/// Es solo visual: no reordena el muro. El orden lo pone el pipeline del feed
/// (ver story_wall_test.dart). Si el grosor llegara a influir en el orden, quien
/// ha PAGADO un Boost lo perdería frente a quien simplemente publica más.

/// Historia de foto viva, con su URL.
Story _photo(String id, {String url = '', DateTime? at}) =>
    Story.fromMap(id, <String, dynamic>{
      'ownerUid': 'a',
      'displayName': 'Fer',
      'mediaType': 'image',
      'imageUrl': url.isEmpty ? 'https://example.test/$id.jpg' : url,
      'status': 'active',
      'createdAt': (at ?? DateTime(2026, 8, 10, 8, 43)).toIso8601String(),
      'expiresAt':
          DateTime.now().add(const Duration(hours: 12)).toIso8601String(),
    });

/// Historia de vídeo. Sin [thumbnail] reproduce el caso real: la miniatura es
/// best-effort (`VideoCompress.getByteThumbnail` va en su propio try, y en web
/// no se genera nunca), así que se publica sin ella.
Story _video(String id, {String thumbnail = '', DateTime? at}) =>
    Story.fromMap(id, <String, dynamic>{
      'ownerUid': 'a',
      'displayName': 'Fer',
      'mediaType': 'video',
      'videoUrl': 'https://example.test/$id.mp4',
      'thumbnailUrl': thumbnail,
      'status': 'active',
      'createdAt': (at ?? DateTime(2026, 8, 10, 8, 43)).toIso8601String(),
      'expiresAt':
          DateTime.now().add(const Duration(hours: 12)).toIso8601String(),
    });

Widget _card(List<Story> stories) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 480,
          child: StoryStackCard(
            stories: stories,
            displayName: 'Fer',
            age: 33,
            onTap: () {},
          ),
        ),
      ),
    );

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

  group('Las hojas se ven TODAS', () {
    // Con todas las hojas pegadas al fondo, cada una quedaba íntegramente
    // dentro de la de delante —que se pinta después y es opaca— y solo asomaba
    // UNA banda: 3 y 5 historias se veían exactamente igual.
    test('cada hoja asoma por debajo de la siguiente', () {
      const int sheets = 4;
      final List<double> bottoms = <double>[
        for (int i = 1; i <= sheets; i++)
          storyStackSheetInsets(index: i, sheets: sheets).bottom,
      ];
      // Estrictamente decreciente: ninguna hoja acaba donde acaba la de delante.
      for (int i = 1; i < bottoms.length; i++) {
        expect(bottoms[i], lessThan(bottoms[i - 1]));
      }
      expect(bottoms.toSet().length, sheets, reason: 'ninguna se solapa');
    });

    test('la hoja del fondo llega al borde inferior de la tarjeta', () {
      expect(storyStackSheetInsets(index: 3, sheets: 3).bottom, 0);
    });
  });

  group('Qué historia pone la cara de la pila', () {
    // Tres historias vivas reales: un vídeo (la más antigua) y dos fotos. El
    // grupo llega ordenado de más antigua a más reciente.
    List<Story> tres({String thumbnail = 'https://example.test/thumb.jpg'}) =>
        <Story>[
          _video('v', thumbnail: thumbnail, at: DateTime(2026, 8, 10, 8, 43, 0)),
          _photo('f1', at: DateTime(2026, 8, 10, 8, 43, 28)),
          _photo('f2', at: DateTime(2026, 8, 10, 8, 43, 48)),
        ];

    test('la portada es la MÁS RECIENTE, no la más antigua', () {
      expect(storyStackCover(tres()).storyId, 'f2');
    });

    test('un vídeo sin miniatura no puede secuestrar la portada', () {
      // Era el caso real: la más antigua era un vídeo, su miniatura no se
      // generó, y la tarjeta pintaba el recuadro con la inicial del nombre
      // teniendo dos fotos válidas en el mismo grupo sin usar.
      final List<Story> conVideoAlFinal = <Story>[
        _photo('f1', at: DateTime(2026, 8, 10, 8, 43, 0)),
        _photo('f2', at: DateTime(2026, 8, 10, 8, 43, 28)),
        _video('v', at: DateTime(2026, 8, 10, 8, 43, 48)),
      ];
      final Story cover = storyStackCover(conVideoAlFinal);
      expect(cover.storyId, 'f2');
      expect(storyCoverUrl(cover), isNotEmpty);
    });

    test('si el vídeo SÍ tiene miniatura y es el último, es la portada', () {
      final List<Story> conVideoAlFinal = <Story>[
        _photo('f1', at: DateTime(2026, 8, 10, 8, 43, 0)),
        _video('v',
            thumbnail: 'https://example.test/thumb.jpg',
            at: DateTime(2026, 8, 10, 8, 43, 48)),
      ];
      expect(storyStackCover(conVideoAlFinal).storyId, 'v');
    });

    test('sin ninguna vista previa utilizable no revienta', () {
      final List<Story> soloVideosSinMiniatura = <Story>[
        _video('v1', at: DateTime(2026, 8, 10, 8, 43, 0)),
        _video('v2', at: DateTime(2026, 8, 10, 8, 43, 48)),
      ];
      expect(storyStackCover(soloVideosSinMiniatura).storyId, 'v2');
      expect(storyCoverUrl(storyStackCover(soloVideosSinMiniatura)), isEmpty);
    });
  });

  group('La tarjeta pintada de verdad', () {
    testWidgets('con tres historias enseña la más reciente y lo dice', (
      WidgetTester tester,
    ) async {
      final List<Story> stories = <Story>[
        _video('v', at: DateTime(2026, 8, 10, 8, 43, 0)),
        _photo('f1', at: DateTime(2026, 8, 10, 8, 43, 28)),
        _photo('f2', at: DateTime(2026, 8, 10, 8, 43, 48)),
      ];
      await tester.pumpWidget(_card(stories));

      final AttraImage cover = tester.widget<AttraImage>(
        find.byType(AttraImage),
      );
      expect(
        cover.url,
        'https://example.test/f2.jpg',
        reason: 'la cara de la pila era el vídeo más antiguo y, sin miniatura, '
            'ni siquiera eso: salía el recuadro con la inicial teniendo dos '
            'fotos válidas en el mismo grupo',
      );
      expect(find.text('3 historias'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('la pila de tres dibuja dos hojas, ambas visibles', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_card(<Story>[
        _photo('f1', at: DateTime(2026, 8, 10, 8, 43, 0)),
        _photo('f2', at: DateTime(2026, 8, 10, 8, 43, 28)),
        _photo('f3', at: DateTime(2026, 8, 10, 8, 43, 48)),
      ]));

      // Solo las capas de la pila: los hijos directos del Stack exterior (las
      // hojas y la portada). Dentro de la portada hay más Positioned (pastilla,
      // nombre) que no pintan pila.
      final Stack pila = tester.widget<Stack>(find
          .descendant(
            of: find.byType(StoryStackCard),
            matching: find.byType(Stack),
          )
          .first);
      final List<Positioned> capas =
          pila.children.whereType<Positioned>().toList(growable: false);
      // Dos hojas + la portada.
      expect(capas.length, 3);
      final Set<double?> bordesInferiores =
          capas.map((Positioned p) => p.bottom).toSet();
      expect(
        bordesInferiores.length,
        3,
        reason: 'si dos capas acaban a la misma altura, la de detrás queda '
            'tapada entera y la pila miente sobre cuántas historias hay',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
