import 'dart:async';

import 'package:attra/src/features/anti_ghosting/data/pending_conversations_controller.dart';
import 'package:attra/src/features/anti_ghosting/domain/anti_ghosting_config.dart';
import 'package:attra/src/features/chat/data/chat_service.dart';
import 'package:attra/src/features/chat/domain/chat.dart';
import 'package:attra/src/features/feed/presentation/feed_screen.dart';
import 'package:attra/src/features/match/data/match_service.dart';
import 'package:attra/src/features/match/domain/match_flow_result.dart';
import 'package:attra/src/features/profile/domain/profile_state.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// La marcha atrás de verdad, con el feed montado.
///
/// Esto es lo que faltaba: la lógica existía, pero NO había botón. Lo único que
/// ofrecía deshacer era un SnackBar de 4 segundos después de cada gesto, así que
/// si no lo cazabas no había forma de volver.
///
/// Aquí se pinta la pantalla REAL (su `State`, su `_excluded`, su `_consumed`) y
/// se comprueba con gestos que la persona vuelve. NO se da por hecho el orden de
/// las tarjetas: lo pone el pipeline del feed (ranking orgánico, Boost, "te dio
/// like"…) y fijarlo en el test sería inventarse un contrato que no existe.
///
/// Lo que no se cubre aquí es el muro a ciegas, que necesita `StoryService`
/// (red): ese lado va en `blind_story_viewer_test.dart`, contra el mismo puente.
void main() {
  final Finder boton = find.byKey(const ValueKey<String>('feed-rewind-button'));

  testWidgets('Plus deshace su último pase y la persona vuelve', (
    WidgetTester tester,
  ) async {
    _usePhoneViewport(tester);
    final _MatchServiceStub service = _MatchServiceStub();
    await tester.pumpWidget(_FeedHost(
      matchService: service,
      profiles: <SeedProfile>[_profile('zoe', 'Zoe'), _profile('ada', 'Ada')],
      canRewind: true,
    ));
    await tester.pumpAndSettle();
    final String primera = _quien(tester);
    expect(primera, isNotEmpty);

    await _pasar(tester);
    expect(service.passed, <String>[primera.toLowerCase()]);
    expect(_quien(tester), isNot(primera));

    await tester.tap(boton);
    await tester.pumpAndSettle();

    expect(service.rewinds, <String>['${primera.toLowerCase()}:pass']);
    expect(_quien(tester), primera,
        reason: 'si no se limpian `_excluded` y `_consumed`, el perfil no '
            'reaparece y la marcha atrás se ha gastado para nada');
    expect(tester.takeException(), isNull);
  });

  testWidgets('agotada, Plus lo DICE en vez de quedarse mudo', (
    WidgetTester tester,
  ) async {
    _usePhoneViewport(tester);
    final _MatchServiceStub service = _MatchServiceStub();
    await tester.pumpWidget(_FeedHost(
      matchService: service,
      profiles: <SeedProfile>[_profile('zoe', 'Zoe'), _profile('ada', 'Ada')],
      canRewind: true,
    ));
    await tester.pumpAndSettle();

    await _pasar(tester);
    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(service.rewinds.length, 1);

    // Segundo toque: ya no queda nada. Ni se llama al backend ni se calla.
    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(service.rewinds.length, 1);
    expect(find.textContaining('Ya has deshecho'), findsOneWidget);
  });

  testWidgets('Free ve el botón y va al paywall, no al backend', (
    WidgetTester tester,
  ) async {
    _usePhoneViewport(tester);
    final _MatchServiceStub service = _MatchServiceStub();
    int paywalls = 0;
    await tester.pumpWidget(_FeedHost(
      matchService: service,
      profiles: <SeedProfile>[_profile('zoe', 'Zoe'), _profile('ada', 'Ada')],
      onOpenUpgrade: () => paywalls++,
    ));
    await tester.pumpAndSettle();

    await _pasar(tester);
    final String actual = _quien(tester);
    // El botón se ve aunque no pueda usarlo: es el gancho.
    expect(boton, findsOneWidget);

    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(service.rewinds, isEmpty);
    expect(paywalls, 1);
    expect(find.textContaining('Attra Plus y Pro'), findsOneWidget);
    // Y no ha movido el feed: sigue donde estaba.
    expect(_quien(tester), actual);
  });

  testWidgets('Pro deshace varias seguidas y lleva la cuenta', (
    WidgetTester tester,
  ) async {
    _usePhoneViewport(tester);
    final _MatchServiceStub service = _MatchServiceStub();
    await tester.pumpWidget(_FeedHost(
      matchService: service,
      profiles: <SeedProfile>[
        _profile('zoe', 'Zoe'),
        _profile('ada', 'Ada'),
        _profile('eva', 'Eva'),
      ],
      canRewind: true,
      rewindUnlimited: true,
    ));
    await tester.pumpAndSettle();

    final String primera = _quien(tester);
    await _pasar(tester);
    final String segunda = _quien(tester);
    await _pasar(tester);
    expect(
        service.passed, <String>[primera.toLowerCase(), segunda.toLowerCase()]);
    // Dos gestos guardados: el contador lo dice sin tener que adivinarlo.
    expect(find.text('2'), findsOneWidget);

    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(_quien(tester), segunda);

    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(service.rewinds, <String>[
      '${segunda.toLowerCase()}:pass',
      '${primera.toLowerCase()}:pass',
    ]);
    expect(_quien(tester), primera);
  });

  testWidgets('con el feed agotado la marcha atrás sigue a mano', (
    WidgetTester tester,
  ) async {
    // El feed se acaba justo después de un gesto: si el botón viviera solo en la
    // tarjeta, ahí ya no habría ninguna y la última marcha atrás se perdería
    // (además "Recargar" borra el historial).
    _usePhoneViewport(tester);
    final _MatchServiceStub service = _MatchServiceStub();
    await tester.pumpWidget(_FeedHost(
      matchService: service,
      profiles: <SeedProfile>[_profile('zoe', 'Zoe')],
      canRewind: true,
    ));
    await tester.pumpAndSettle();

    await _pasar(tester);
    expect(find.text('No hay más personas por el momento'), findsOneWidget);

    final Finder franja =
        find.byKey(const ValueKey<String>('feed-rewind-strip'));
    expect(franja, findsOneWidget);
    await tester.tap(franja);
    await tester.pumpAndSettle();

    expect(service.rewinds, <String>['zoe:pass']);
    expect(_quien(tester), 'Zoe');
    expect(franja, findsNothing, reason: 'ya no queda nada que deshacer');
  });

  testWidgets('un gesto que nunca se registró no gasta la marcha atrás', (
    WidgetTester tester,
  ) async {
    // El backend contesta `rewound: false` cuando no hay nada que deshacer (el
    // like se quedó en el tope diario, el pase falló y se tragó su error...).
    // Antes ese bool se tiraba: la app decía "Hecho" y se comía la ÚNICA marcha
    // atrás de un Plus por un no-op.
    _usePhoneViewport(tester);
    final _MatchServiceStub service = _MatchServiceStub(rewound: false);
    await tester.pumpWidget(_FeedHost(
      matchService: service,
      profiles: <SeedProfile>[_profile('zoe', 'Zoe'), _profile('ada', 'Ada')],
      canRewind: true,
    ));
    await tester.pumpAndSettle();
    final String primera = _quien(tester);

    await _pasar(tester);
    await tester.tap(boton);
    await tester.pumpAndSettle();

    expect(service.rewinds.length, 1);
    expect(find.textContaining('no llegó a registrarse'), findsOneWidget);
    expect(_quien(tester), primera,
        reason: 'si en el servidor no había nada, esa persona no estaba '
            'decidida: tiene que volver');

    // Y NO se ha cobrado: el mensaje sigue siendo el de "aún no has hecho
    // nada", no el de "ya lo has gastado".
    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(service.rewinds.length, 1);
    expect(find.textContaining('Todavía no has dado'), findsOneWidget);
  });

  testWidgets('un bache de red NO se come el gesto guardado', (
    WidgetTester tester,
  ) async {
    // `MatchService._call` envuelve TODAS las FirebaseFunctionsException por
    // igual: tratar 'unavailable' como definitivo borraba el gesto del historial
    // dejando el dislike vivo en el servidor, y el botón pasaba a decir "ya no
    // queda nada", que era mentira.
    _usePhoneViewport(tester);
    final _MatchServiceStub service = _MatchServiceStub()
      ..rewindError =
          const MatchServiceException('Sin conexión', code: 'unavailable');
    await tester.pumpWidget(_FeedHost(
      matchService: service,
      profiles: <SeedProfile>[_profile('zoe', 'Zoe'), _profile('ada', 'Ada')],
      canRewind: true,
    ));
    await tester.pumpAndSettle();
    final String primera = _quien(tester);

    await _pasar(tester);
    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(find.textContaining('Sin conexión'), findsOneWidget);

    // Vuelve la cobertura: el gesto sigue ahí y se puede reintentar.
    service.rewindError = null;
    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(service.rewinds.length, 2);
    expect(_quien(tester), primera);
  });

  testWidgets('un "no" definitivo del backend sí retira el gesto', (
    WidgetTester tester,
  ) async {
    _usePhoneViewport(tester);
    final _MatchServiceStub service = _MatchServiceStub()
      ..rewindError = const MatchServiceException(
          'No se puede deshacer un match ya creado.',
          code: 'failed-precondition');
    await tester.pumpWidget(_FeedHost(
      matchService: service,
      profiles: <SeedProfile>[_profile('zoe', 'Zoe'), _profile('ada', 'Ada')],
      canRewind: true,
    ));
    await tester.pumpAndSettle();

    await _pasar(tester);
    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(find.textContaining('match ya creado'), findsOneWidget);

    // No se vuelve a intentar: sería una promesa que falla siempre.
    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(service.rewinds.length, 1);
  });

  testWidgets('con el like todavía en vuelo el botón espera', (
    WidgetTester tester,
  ) async {
    // Arrepentirse en el segundo siguiente es LA razón de ser del botón, y ahí
    // es donde estaba la carrera: `rewindFeedAction` leía el documento antes de
    // que la transacción de `sendLike` lo escribiera, contestaba "no había nada"
    // y el like se enviaba igualmente, para siempre.
    _usePhoneViewport(tester);
    final Completer<MatchFlowResult> enVuelo = Completer<MatchFlowResult>();
    final _MatchServiceStub service = _MatchServiceStub(likeGate: enVuelo);
    await tester.pumpWidget(_FeedHost(
      matchService: service,
      profiles: <SeedProfile>[_profile('zoe', 'Zoe'), _profile('ada', 'Ada')],
      canRewind: true,
      rewindUnlimited: true,
    ));
    await tester.pumpAndSettle();

    await _dar(tester);
    expect(service.liked.length, 1);
    expect(tester.widget<IconButton>(boton).onPressed, isNull,
        reason: 'el like todavía no está escrito: deshacerlo sería un no-op '
            'que además lo dejaría enviado');

    enVuelo.complete(const MatchFlowResult.liked());
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(boton).onPressed, isNotNull);
  });

  testWidgets('con el feed agotado Free también ve el gancho', (
    WidgetTester tester,
  ) async {
    // Free guarda el gesto aunque no pueda usarlo, y esta es la pantalla donde
    // más tiempo pasa: esconder aquí la franja quitaba el gancho justo donde el
    // usuario está más receptivo a pagar.
    _usePhoneViewport(tester);
    final _MatchServiceStub service = _MatchServiceStub();
    int paywalls = 0;
    await tester.pumpWidget(_FeedHost(
      matchService: service,
      profiles: <SeedProfile>[_profile('zoe', 'Zoe')],
      onOpenUpgrade: () => paywalls++,
    ));
    await tester.pumpAndSettle();

    await _pasar(tester);
    expect(find.text('No hay más personas por el momento'), findsOneWidget);

    final Finder franja =
        find.byKey(const ValueKey<String>('feed-rewind-strip'));
    expect(franja, findsOneWidget);
    await tester.tap(franja);
    await tester.pumpAndSettle();
    expect(service.rewinds, isEmpty);
    expect(paywalls, 1);
  });

  testWidgets('un like que hace match deja de ser deshacible', (
    WidgetTester tester,
  ) async {
    // El backend contesta `failed-precondition` a un rewind con match ya creado.
    // Si el botón siguiera ofreciéndolo, sería una promesa que falla siempre.
    _usePhoneViewport(tester);
    final _MatchServiceStub service = _MatchServiceStub(matchOnLike: true);
    await tester.pumpWidget(_FeedHost(
      matchService: service,
      profiles: <SeedProfile>[_profile('zoe', 'Zoe'), _profile('ada', 'Ada')],
      canRewind: true,
    ));
    await tester.pumpAndSettle();

    await _dar(tester);
    // El diálogo de match se lleva el foco; se cierra para volver al feed.
    await tester.tap(find.text('Seguir viendo'));
    await tester.pumpAndSettle();

    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(service.rewinds, isEmpty);
    expect(find.textContaining('Todavía no has dado'), findsOneWidget);
  });

  testWidgets(
      'tras volver atrás, el siguiente gesto NO cae en alguien ya decidido '
      '(C44)', (WidgetTester tester) async {
    // Pro: pasa P, like a M (match: sale del historial), pasa Q, dos marchas
    // atrás hasta P. Pasar P hacía `_index += 1` y volvía a enseñar a M, con
    // quien ya hay match (y un like reabría el diálogo).
    _usePhoneViewport(tester);
    final _MatchServiceStub service = _MatchServiceStub(matchOnLike: true);
    await tester.pumpWidget(_FeedHost(
      matchService: service,
      profiles: <SeedProfile>[
        _profile('zoe', 'Zoe'),
        _profile('ada', 'Ada'),
        _profile('eva', 'Eva'),
        _profile('ana', 'Ana'),
      ],
      canRewind: true,
      rewindUnlimited: true,
    ));
    await tester.pumpAndSettle();

    final String p = _quien(tester);
    await _pasar(tester);
    final String m = _quien(tester);
    await _dar(tester);
    await tester.tap(find.text('Seguir viendo'));
    await tester.pumpAndSettle();
    final String q = _quien(tester);
    await _pasar(tester);

    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(_quien(tester), q);
    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(_quien(tester), p);

    await _pasar(tester);
    expect(_quien(tester), isNot(m),
        reason: 'con M ya hay match: no puede volver a salir');
    expect(_quien(tester), q, reason: 'la siguiente SIN decidir es Q');
  });

  testWidgets(
      'al tope diario de likes la carta NO se pierde: vuelve, sin gesto que '
      'deshacer, y se ofrece el plan una vez (D08)',
      (WidgetTester tester) async {
    _usePhoneViewport(tester);
    final _MatchServiceStub service =
        _MatchServiceStub(likeOutcome: MatchOutcome.limitReached);
    int paywalls = 0;
    await tester.pumpWidget(_FeedHost(
      matchService: service,
      profiles: <SeedProfile>[_profile('zoe', 'Zoe'), _profile('ada', 'Ada')],
      canRewind: true,
      onOpenUpgrade: () => paywalls++,
    ));
    await tester.pumpAndSettle();
    final String primera = _quien(tester);

    await _dar(tester);
    expect(service.liked, <String>[primera.toLowerCase()]);
    expect(_quien(tester), primera,
        reason: 'el like no se escribió: la persona sigue sin decidir');
    expect(find.textContaining('límite de likes'), findsOneWidget);
    expect(paywalls, 1);

    // Otro intento: sigue ahí y el paywall no salta en cada toque.
    await _dar(tester);
    expect(_quien(tester), primera);
    expect(paywalls, 1);

    // Y no hay un "like" fantasma que deshacer.
    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(service.rewinds, isEmpty);
    expect(find.textContaining('Todavía no has dado'), findsOneWidget);
  });

  testWidgets(
      'responder a un prompt avanza la carta y se puede deshacer, como la foto '
      '(C30)', (WidgetTester tester) async {
    _usePhoneViewport(tester);
    final _MatchServiceStub service = _MatchServiceStub();
    await tester.pumpWidget(_FeedHost(
      matchService: service,
      profiles: <SeedProfile>[
        _profile('zoe', 'Zoe', withPrompt: true),
        _profile('ada', 'Ada', withPrompt: true),
      ],
      canRewind: true,
    ));
    await tester.pumpAndSettle();
    final String primera = _quien(tester);

    await _responderPrompt(tester, primera);
    await tester.tap(find.text('Enviar Like'));
    await tester.pumpAndSettle();

    expect(service.liked, <String>[primera.toLowerCase()]);
    expect(_quien(tester), isNot(primera),
        reason: 'antes la carta se quedaba delante y parecía que no había ido');

    await tester.tap(boton);
    await tester.pumpAndSettle();
    expect(service.rewinds, <String>['${primera.toLowerCase()}:like']);
    expect(_quien(tester), primera);
  });

  testWidgets(
      'responder a un prompt pasa por el límite de conversaciones pendientes '
      '(C30)', (WidgetTester tester) async {
    _usePhoneViewport(tester);
    final _MatchServiceStub service = _MatchServiceStub();
    final _PendientesFijos pendientes = _PendientesFijos(9);
    addTearDown(pendientes.dispose);
    await tester.pumpWidget(_FeedHost(
      matchService: service,
      profiles: <SeedProfile>[
        _profile('zoe', 'Zoe', withPrompt: true),
        _profile('ada', 'Ada', withPrompt: true),
      ],
      antiGhostingConfig: const AntiGhostingConfig(
        pendingLimitEnabled: true,
        pendingLimitFree: 3,
      ),
      pendingController: pendientes,
    ));
    await tester.pumpAndSettle();
    final String primera = _quien(tester);

    await _responderPrompt(tester, primera);
    await tester.tap(find.text('Enviar Like'));
    await tester.pumpAndSettle();

    // Sale el aviso de pendientes y NO se envía nada.
    expect(find.text('Ahora no'), findsOneWidget);
    await tester.tap(find.text('Ahora no'));
    await tester.pumpAndSettle();
    expect(service.liked, isEmpty,
        reason: 'por los prompts se saltaba el bloqueo suave anti-ghosting');
    expect(_quien(tester), primera);
  });
}

/// Abre la hoja de respuesta al prompt de [nombre] (baja por la ficha hasta
/// el botón).
Future<void> _responderPrompt(WidgetTester tester, String nombre) async {
  final Finder responder = find
      .byKey(ValueKey<String>('feed-prompt-respond-p_${nombre.toLowerCase()}'));
  await tester.ensureVisible(responder);
  await tester.pumpAndSettle();
  await tester.tap(responder);
  await tester.pumpAndSettle();
}

/// Conversaciones pendientes fijas (sin chats de verdad).
class _PendientesFijos extends PendingConversationsController {
  _PendientesFijos(this._n) : super(chatService: _ChatsVacios(), uid: 'yo');

  final int _n;

  @override
  int pendingCount(int maxAgeHours) => _n;
}

class _ChatsVacios implements ChatService {
  @override
  Stream<List<Chat>> observeChats(String uid) =>
      Stream<List<Chat>>.value(const <Chat>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Llamada inesperada: ${invocation.memberName}');
  }
}

/// Nombre de quien está en la tarjeta (la ficha lo pinta como «Zoe, 30»). Vacío
/// si no hay tarjeta (feed agotado).
String _quien(WidgetTester tester) {
  for (final Text texto in tester.widgetList<Text>(find.byType(Text))) {
    final String data = texto.data ?? '';
    if (data.endsWith(', 30')) return data.substring(0, data.length - 4);
  }
  return '';
}

/// Pasa (deslizar a la izquierda) a quien esté en la tarjeta.
Future<void> _pasar(WidgetTester tester) async {
  await tester.drag(
    find.byKey(const ValueKey<String>('feed-swipe-card')),
    const Offset(-260, 0),
  );
  await tester.pumpAndSettle();
}

/// Like (deslizar a la derecha).
Future<void> _dar(WidgetTester tester) async {
  await tester.drag(
    find.byKey(const ValueKey<String>('feed-swipe-card')),
    const Offset(260, 0),
  );
  await tester.pumpAndSettle();
}

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _FeedHost extends StatelessWidget {
  const _FeedHost({
    required this.profiles,
    required this.matchService,
    this.canRewind = false,
    this.rewindUnlimited = false,
    this.onOpenUpgrade,
    this.antiGhostingConfig,
    this.pendingController,
  });

  final List<SeedProfile> profiles;
  final MatchService matchService;
  final bool canRewind;
  final bool rewindUnlimited;
  final VoidCallback? onOpenUpgrade;
  final AntiGhostingConfig? antiGhostingConfig;
  final PendingConversationsController? pendingController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: FeedScreen(
          user: null,
          onLoadSeedProfiles: () async => profiles,
          matchService: matchService,
          chatService: _ChatServiceStub(),
          canRewind: canRewind,
          rewindUnlimited: rewindUnlimited,
          onOpenUpgrade: onOpenUpgrade,
          antiGhostingConfig: antiGhostingConfig,
          pendingController: pendingController,
        ),
      ),
    );
  }
}

SeedProfile _profile(String id, String name, {bool withPrompt = false}) {
  return SeedProfile(
    profilePrompts: withPrompt
        ? <PublicPrompt>[
            PublicPrompt(
                id: 'p_$id', question: '¿Plan ideal?', answer: 'Playa y libro'),
          ]
        : const <PublicPrompt>[],
    id: id,
    displayName: name,
    city: 'Madrid',
    country: 'Espana',
    bio: 'Una bio de prueba.',
    gender: 'female',
    interestedIn: const <String>[],
    orientation: const <String>['heterosexual'],
    age: 30,
    jobTitle: 'Disenadora',
    company: 'Atelier',
    interests: const <String>['Arte'],
    photoUrl: '',
    isBot: false,
    botProfileVersion: 0,
    botScenario: '',
    seedQualityScore: 100,
    photos: const <AdditionalPhoto>[],
  );
}

class _MatchServiceStub implements MatchService {
  _MatchServiceStub({
    this.matchOnLike = false,
    this.rewound = true,
    this.likeGate,
    this.likeOutcome,
  });

  final bool matchOnLike;

  /// Respuesta fija del backend a un like (p.ej. `limitReached`).
  final MatchOutcome? likeOutcome;

  /// Lo que contesta el backend: `false` = "no había nada que deshacer".
  final bool rewound;

  /// Deja el like EN VUELO hasta que el test lo complete (carrera con el botón).
  final Completer<MatchFlowResult>? likeGate;

  /// Error de la llamada de rewind. Mutable para poder simular que la cobertura
  /// vuelve entre dos pulsaciones.
  MatchServiceException? rewindError;

  final List<String> passed = <String>[];
  final List<String> liked = <String>[];

  /// `uid:accion`, en el orden en que se pidieron.
  final List<String> rewinds = <String>[];

  @override
  Future<void> passProfile(String toUid) async => passed.add(toUid);

  @override
  Future<MatchFlowResult> sendLike(
    String toUid, {
    String? targetPhotoId,
    String? comment,
    String? promptId,
    String? promptQuestion,
    String? promptAnswer,
  }) async {
    liked.add(toUid);
    final Completer<MatchFlowResult>? gate = likeGate;
    if (gate != null) return gate.future;
    final MatchOutcome? fixed = likeOutcome;
    if (fixed != null) return MatchFlowResult(outcome: fixed);
    return matchOnLike
        ? const MatchFlowResult(
            outcome: MatchOutcome.matched,
            matchId: 'match_1',
            chatId: 'chat_1',
          )
        : const MatchFlowResult.liked();
  }

  @override
  Future<bool> rewindFeedAction({
    required String targetUid,
    required String action,
  }) async {
    rewinds.add('$targetUid:$action');
    final MatchServiceException? error = rewindError;
    if (error != null) throw error;
    return rewound;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Llamada inesperada: ${invocation.memberName}');
  }
}

class _ChatServiceStub implements ChatService {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Llamada inesperada: ${invocation.memberName}');
  }
}
