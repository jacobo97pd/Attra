import 'package:attra/src/features/feed/domain/feed_exclusions.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exclusiones del feed separadas por motivo (C06/C15/C16/D09).
///
/// Antes eran un solo `Set` y la segunda vuelta le restaba los pases: quien
/// estaba fuera por un pase Y un bloqueo (o un match) volvía al feed.
void main() {
  Map<String, dynamic> like(String to) =>
      <String, dynamic>{'fromUid': 'me', 'toUid': to};
  Map<String, dynamic> dislike(String to, [String? source]) =>
      <String, dynamic>{
        'fromUid': 'me',
        'toUid': to,
        if (source != null) 'source': source,
      };
  Map<String, dynamic> match(String other, String status) => <String, dynamic>{
        'users': <String>['me', other],
        'status': status,
      };
  Map<String, dynamic> block(String blocked) =>
      <String, dynamic>{'blockerUid': 'me', 'blockedUid': blocked};

  group('fromDocs', () {
    test('clasifica cada documento en su categoría', () {
      final FeedExclusions ex = FeedExclusions.fromDocs(
        uid: 'me',
        likes: <Map<String, dynamic>>[like('liked')],
        dislikes: <Map<String, dynamic>>[
          dislike('pasado'),
          dislike('pasado_en_directo', 'live'),
          dislike('reportado', 'live_report'),
          dislike('moderado', 'live_moderation'),
          dislike('motivo_nuevo', 'safety_whatever'),
        ],
        matches: <Map<String, dynamic>>[
          match('activo', 'active'),
          match('me_bloqueo', 'blocked'),
          match('cerrado', 'unmatched'),
        ],
        blocks: <Map<String, dynamic>>[block('bloqueado')],
      );
      expect(ex.complete, isTrue);
      expect(ex.liked, <String>{'liked'});
      expect(ex.passed, <String>{'pasado', 'pasado_en_directo'});
      expect(ex.permanentlyPassed,
          <String>{'reportado', 'moderado', 'motivo_nuevo'},
          reason: 'ante un motivo desconocido, no se vuelve a enseñar a nadie');
      expect(ex.matched, <String>{'activo', 'me_bloqueo', 'cerrado'},
          reason: 'cualquier estado: el match en "blocked" es la única señal '
              'de que alguien TE bloqueó');
      expect(ex.blocked, <String>{'bloqueado'});
    });

    test('una lectura que falla no se lleva por delante a las demás', () {
      final FeedExclusions ex = FeedExclusions.fromDocs(
        uid: 'me',
        likes: null, // falló
        dislikes: <Map<String, dynamic>>[dislike('pasado')],
        matches: <Map<String, dynamic>>[match('m', 'active')],
        blocks: <Map<String, dynamic>>[block('b')],
      );
      expect(ex.complete, isFalse);
      expect(ex.failed, <ExclusionSource>{ExclusionSource.likes});
      expect(ex.matched, <String>{'m'});
      expect(ex.blocked, <String>{'b'});
    });

    test('documentos con tipos raros no rompen nada', () {
      final FeedExclusions ex = FeedExclusions.fromDocs(
        uid: 'me',
        likes: <Map<String, dynamic>>[
          <String, dynamic>{'toUid': 42},
        ],
        dislikes: const <Map<String, dynamic>>[],
        matches: <Map<String, dynamic>>[
          <String, dynamic>{'users': 'no-es-lista'},
        ],
        blocks: <Map<String, dynamic>>[
          <String, dynamic>{'blockedUid': ''},
        ],
      );
      expect(ex.hard, isEmpty);
      expect(ex.complete, isTrue);
    });
  });

  group('segunda vuelta', () {
    final FeedExclusions ex = FeedExclusions.fromDocs(
      uid: 'me',
      likes: <Map<String, dynamic>>[like('attra')],
      dislikes: <Map<String, dynamic>>[
        dislike('pasado'),
        // Pasé y LUEGO bloqueé (caso 1 del informe).
        dislike('bloqueado'),
        // Pasé y luego ÉL me bloqueó (caso 2): solo lo sé por el match.
        dislike('me_bloqueo'),
        // Pasé y luego le mandé un Attra desde otro sitio.
        dislike('attra'),
        dislike('reportado', 'live_report'),
      ],
      matches: <Map<String, dynamic>>[match('me_bloqueo', 'blocked')],
      blocks: <Map<String, dynamic>>[block('bloqueado')],
    );

    test('solo repone pases normales sin nada duro detrás', () {
      expect(ex.secondRoundCandidates, <String>{'pasado'});
    });

    test('lo duro sigue excluido en la segunda vuelta', () {
      final Set<String> excluded = ex.excludedFor(secondRound: true);
      expect(
          excluded,
          containsAll(
              <String>['bloqueado', 'me_bloqueo', 'attra', 'reportado']));
      expect(excluded, isNot(contains('pasado')));
    });

    test('en el feed normal se excluye todo', () {
      expect(
        ex.excludedFor(secondRound: false),
        <String>{'pasado', 'bloqueado', 'me_bloqueo', 'attra', 'reportado'},
      );
    });
  });

  group('fallar cerrado (D09)', () {
    final FeedExclusions buena = FeedExclusions.fromDocs(
      uid: 'me',
      likes: <Map<String, dynamic>>[like('l')],
      dislikes: <Map<String, dynamic>>[dislike('p')],
      matches: <Map<String, dynamic>>[match('m', 'active')],
      blocks: <Map<String, dynamic>>[block('b')],
    );

    test('completa: se usa tal cual', () {
      expect(identical(buena.coveredBy(null), buena), isTrue);
    });

    test('sin lectura anterior, un fallo NO se convierte en "nadie"', () {
      expect(FeedExclusions.unavailable.coveredBy(null), isNull);
      final FeedExclusions soloBloqueosCaidos = FeedExclusions.fromDocs(
        uid: 'me',
        likes: const <Map<String, dynamic>>[],
        dislikes: const <Map<String, dynamic>>[],
        matches: const <Map<String, dynamic>>[],
        blocks: null,
      );
      expect(soloBloqueosCaidos.coveredBy(null), isNull);
    });

    test('con lectura anterior, lo que falla se cubre con ella', () {
      final FeedExclusions nueva = FeedExclusions.fromDocs(
        uid: 'me',
        likes: <Map<String, dynamic>>[like('l'), like('l2')],
        dislikes: null,
        matches: <Map<String, dynamic>>[match('m', 'active')],
        blocks: null,
      );
      final FeedExclusions? cubierta = nueva.coveredBy(buena);
      expect(cubierta, isNotNull);
      expect(cubierta!.complete, isTrue);
      expect(cubierta.liked, <String>{'l', 'l2'}, reason: 'lo leído, manda');
      expect(cubierta.passed, <String>{'p'}, reason: 'lo caído, de antes');
      expect(cubierta.blocked, <String>{'b'});
    });

    test('un bloqueo de esta sesión viaja en la lectura de respaldo', () {
      final FeedExclusions conBloqueo = buena.withBlocked('nuevo');
      final FeedExclusions? cubierta = FeedExclusions.fromDocs(
        uid: 'me',
        likes: const <Map<String, dynamic>>[],
        dislikes: const <Map<String, dynamic>>[],
        matches: const <Map<String, dynamic>>[],
        blocks: null,
      ).coveredBy(conBloqueo);
      expect(cubierta!.hard, contains('nuevo'));
    });

    test('deshacer un gesto no levanta nada duro', () {
      final FeedExclusions ex = buena.withBlocked('l').withoutGesture('l');
      expect(ex.liked, isEmpty);
      expect(ex.hard, contains('l'), reason: 'el bloqueo no se deshace');
    });
  });
}
