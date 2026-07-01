import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../../../widgets/attra_image.dart';
import '../../chat_game/domain/chat_game.dart';
import '../../match/data/match_service.dart';
import '../../profile/domain/profile_state.dart';
import '../../profile/domain/profile_summary.dart';
import '../../profile/presentation/profile_view_screen.dart';
import '../../feed/data/feed_metrics_service.dart';
import '../../match/domain/date_builder.dart';
import '../../match/domain/match_journey.dart';
import '../../match/presentation/date_builder_sheet.dart';
import '../../match/presentation/icebreaker_sheet.dart';
import '../../match/presentation/match_journey_card.dart';
import '../../anti_ghosting/data/anti_ghosting_analytics.dart';
import '../../anti_ghosting/domain/conversation_turn.dart';
import '../../anti_ghosting/domain/nudge_tier.dart';
import '../../anti_ghosting/presentation/anti_ghosting_nudge_card.dart';
import '../../anti_ghosting/presentation/close_conversation_sheet.dart';
import '../../anti_ghosting/presentation/date_follow_up_sheet.dart';
import '../../safety/domain/report.dart';
import '../../spark/data/spark_service.dart';
import '../../spark/presentation/spark_entry_card.dart';
import '../../spark/presentation/spark_game_screen.dart';
import '../../../security/screen_guard.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../data/chat_service.dart';
import '../domain/chat.dart';
import '../domain/chat_message.dart';
import 'date_proposal_sheet.dart';
import 'voice_note_bubble.dart';

/// Pantalla de conversacion: cabecera con el otro perfil, lista de mensajes
/// (incluida la card de contexto si el match nacio de un comentario a foto),
/// input de texto y menu (ver perfil/silenciar/unmatch/bloquear/reportar).
class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({
    super.key,
    required this.chatId,
    required this.currentUid,
    required this.other,
    required this.chatService,
    required this.matchService,
    this.loadProfile,
    this.sparkService,
    this.sparkEnabled = false,
    this.metrics,
    this.journeyEnabled = false,
    this.icebreakersEnabled = false,
    this.dateBuilderEnabled = false,
    this.dateBuilderFull = false,
    this.thisOrThatEnabled = false,
    this.doubleAnswerEnabled = false,
    this.twoTruthsEnabled = false,
    this.matchReactivationEnabled = false,
    this.chatGameEnabled = false,
    this.closeGracefullyEnabled = false,
    this.nudgesEnabled = false,
    this.dateFollowupEnabled = false,
  });

  final String chatId;
  final String currentUid;
  final ProfileSummary other;
  final ChatService chatService;
  final MatchService matchService;

  /// Carga el perfil del otro usuario para verlo al pinchar la cabecera.
  final Future<SeedProfile?> Function(String uid)? loadProfile;

  /// Attra Spark (opcional). Si `sparkEnabled` es true y hay servicio, se
  /// muestra la card de Spark sobre el chat. Si no, el chat va igual que siempre.
  final SparkService? sparkService;
  final bool sparkEnabled;

  /// Telemetría del embudo (opcional; null = no registra). messageSent,
  /// conversationStarted (primer mensaje), dateProposed.
  final FeedMetricsService? metrics;

  /// Match Journey (Fase 8): card de recorrido guiado sobre el chat. Opt-in por
  /// flag; si off, el chat va igual que siempre.
  final bool journeyEnabled;
  final bool icebreakersEnabled;
  final bool dateBuilderEnabled;
  final bool dateBuilderFull;
  final bool thisOrThatEnabled;
  final bool doubleAnswerEnabled;
  final bool twoTruthsEnabled;
  final bool matchReactivationEnabled;

  /// "Duelo de Química" (reto de 5 min con resultado IA). Opt-in por flag.
  final bool chatGameEnabled;

  /// Attra Clear §3: muestra "Cerrar conversación" en el menú del chat.
  final bool closeGracefullyEnabled;

  /// Attra Clear §5: muestra nudges in-chat cuando llevas tiempo sin responder.
  final bool nudgesEnabled;

  /// Attra Clear §6: muestra el follow-up "¿Cómo fue la cita?" tras una cita.
  final bool dateFollowupEnabled;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  static const int _maxRecordSeconds = 90;

  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();
  final VoiceNotePlayerController _voicePlayer = VoiceNotePlayerController();

  bool _uploadingMedia = false;
  bool _recording = false;

  /// Mensajes de texto salientes mostrados de forma OPTIMISTA: aparecen al
  /// instante (estado "enviando") y se reconcilian cuando el stream confirma su
  /// id real. Esto hace que el chat se sienta inmediato pese al round-trip de la
  /// Cloud Function.
  final List<_OutgoingMessage> _outgoing = <_OutgoingMessage>[];

  /// Nº de mensajes "reales" (texto/media/propuesta) ya en el chat — para
  /// detectar el PRIMER mensaje y registrar `conversationStarted` una vez.
  int _realMessageCount = 0;
  bool _conversationLogged = false;

  /// Journey derivado del chat (Fase 8) + si el usuario ocultó la card.
  MatchJourney? _journey;
  bool _journeyDismissed = false;

  /// Attra Clear §5: nudge in-chat. Se oculta esta sesión al pulsar "luego" y se
  /// registra "shown" una sola vez por nivel.
  bool _nudgeDismissed = false;
  String? _nudgeShownKey;

  /// Attra Clear §6: follow-up post-cita, ocultable esta sesión.
  bool _followUpDismissed = false;

  AntiGhostingAnalytics get _antiGhostingAnalytics =>
      AntiGhostingAnalytics(uid: widget.currentUid, metrics: widget.metrics);

  Duration _recordElapsed = Duration.zero;
  Timer? _recordTimer;

  // Duelo de Química activo: para etiquetar mensajes con su sesión y cerrar el
  // reto cuando vence el tiempo (lo dispara el cliente; el backend es idempotente).
  String? _activeGameSessionId;
  DateTime? _activeGameEndsAt;
  bool _finishingGame = false;

  /// La burbuja del reto reporta su estado activo. Al vencer, cierra el reto.
  void _onGameActive(String? sessionId, DateTime? endsAt) {
    if (_activeGameSessionId == sessionId && _activeGameEndsAt == endsAt) {
      return;
    }
    setState(() {
      _activeGameSessionId = sessionId;
      _activeGameEndsAt = endsAt;
    });
  }

  Future<void> _finishGame(String sessionId) async {
    if (_finishingGame) return;
    _finishingGame = true;
    try {
      await widget.chatService
          .finishChatGame(chatId: widget.chatId, sessionId: sessionId);
    } catch (_) {/* idempotente: reintenta el otro participante */} finally {
      _finishingGame = false;
    }
  }

  // Codec elegido para grabar (depende de soporte de plataforma/navegador).
  String _recordContentType = 'audio/mp4';
  String _recordExt = 'm4a';

  @override
  void initState() {
    super.initState();
    // Marca leidos al abrir (best-effort).
    widget.chatService.markAsRead(widget.chatId).catchError((_) {});
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder.dispose();
    _voicePlayer.dispose();
    _inputFocus.dispose();
    _input.dispose();
    super.dispose();
  }

  String get _uid => widget.currentUid;

  bool get _gamesAvailable =>
      widget.icebreakersEnabled ||
      widget.thisOrThatEnabled ||
      widget.doubleAnswerEnabled ||
      widget.twoTruthsEnabled ||
      widget.chatGameEnabled ||
      (widget.sparkEnabled && widget.sparkService != null);

  void _useSparkQuestion(String question) {
    _input.text = question;
    _input.selection =
        TextSelection.fromPosition(TextPosition(offset: _input.text.length));
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _inputFocus.requestFocus();
    });
  }

  // --- Foto -----------------------------------------------------------------

  Future<void> _pickAndSendImage(bool canSend, {bool bomb = false}) async {
    if (!canSend) {
      _snack('Este chat ya no está disponible.');
      return;
    }
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,
      imageQuality: 90,
    );
    if (file == null || !mounted) return;
    final Uint8List bytes = await file.readAsBytes();
    if (!mounted) return;
    final bool confirmed = await _previewImage(bytes, bomb: bomb);
    if (!confirmed || !mounted) return;

    setState(() => _uploadingMedia = true);
    try {
      if (bomb) {
        await widget.chatService.sendBombImage(
          chatId: widget.chatId,
          senderUid: _uid,
          bytes: bytes,
          fileName: file.name,
        );
      } else {
        await widget.chatService.sendImage(
          chatId: widget.chatId,
          senderUid: _uid,
          bytes: bytes,
          fileName: file.name,
        );
      }
      _logMessageMetrics();
    } on ChatServiceException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack(bomb
          ? 'No se pudo enviar la foto bomba.'
          : 'No se pudo enviar la foto.');
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
    }
  }

  Future<bool> _previewImage(Uint8List bytes, {bool bomb = false}) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: bomb ? const Text('Enviar foto bomba') : null,
        contentPadding: const EdgeInsets.all(12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
            if (bomb) ...<Widget>[
              const SizedBox(height: 12),
              const Text(
                'Solo se podra abrir una vez. Al tocarla, quedara marcada como vista.',
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: Icon(bomb ? Icons.visibility_off_outlined : Icons.send),
            label: Text(bomb ? 'Enviar bomba' : 'Enviar'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  // --- Nota de voz ----------------------------------------------------------

  Future<void> _startRecording(bool canSend) async {
    if (!canSend) {
      _snack('Este chat ya no está disponible.');
      return;
    }
    final bool allowed = await _recorder.hasPermission();
    if (!allowed) {
      _snack('Necesitamos permiso de micrófono para grabar.');
      return;
    }

    // Elige el primer codec soportado por la plataforma/navegador. En web aacLc
    // (m4a) NO suele estar disponible; opus/webm sí. En móvil aacLc va bien.
    final List<(AudioEncoder, String, String)> candidates =
        <(AudioEncoder, String, String)>[
      (AudioEncoder.aacLc, 'audio/mp4', 'm4a'),
      (AudioEncoder.opus, 'audio/webm', 'webm'),
      (AudioEncoder.wav, 'audio/wav', 'wav'),
    ];
    AudioEncoder? encoder;
    for (final (AudioEncoder, String, String) c in candidates) {
      if (await _recorder.isEncoderSupported(c.$1)) {
        encoder = c.$1;
        _recordContentType = c.$2;
        _recordExt = c.$3;
        break;
      }
    }
    if (encoder == null) {
      _snack('Tu dispositivo no soporta la grabación de audio.');
      return;
    }

    try {
      final String path =
          kIsWeb ? '' : '${DateTime.now().millisecondsSinceEpoch}.$_recordExt';
      await _recorder.start(RecordConfig(encoder: encoder), path: path);
    } catch (e) {
      _snack('No se pudo iniciar la grabación.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _recording = true;
      _recordElapsed = Duration.zero;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) return;
      setState(() => _recordElapsed += const Duration(seconds: 1));
      if (_recordElapsed.inSeconds >= _maxRecordSeconds) _stopAndSend();
    });
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {}
    if (mounted) setState(() => _recording = false);
  }

  Future<void> _stopAndSend() async {
    _recordTimer?.cancel();
    final int durationMs = _recordElapsed.inMilliseconds;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _recording = false);
    if (path == null || path.isEmpty || durationMs < 800) {
      if (durationMs < 800) _snack('Nota de voz demasiado corta.');
      return;
    }

    setState(() => _uploadingMedia = true);
    try {
      final Uint8List bytes = await XFile(path).readAsBytes();
      await widget.chatService.sendVoiceNote(
        chatId: widget.chatId,
        senderUid: _uid,
        bytes: bytes,
        durationMs: durationMs,
        contentType: _recordContentType,
        extension: _recordExt,
      );
      _logMessageMetrics();
    } on ChatServiceException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('No se pudo enviar la nota de voz: $e');
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
    }
  }

  Future<void> _send(bool canSend) async {
    final String text = _input.text.trim();
    if (text.isEmpty || !canSend) return;
    _logMessageMetrics();
    // Optimista: pinta el mensaje YA y limpia el input (sin esperar al backend).
    final _OutgoingMessage out = _OutgoingMessage(text: text);
    setState(() {
      _outgoing.add(out);
      _input.clear();
    });
    await _deliver(out);
  }

  /// Deriva el Match Journey (Fase 8) de las señales del chat. PURO read-model:
  /// sin backend. Detecta propuesta de cita, juego completado (mensaje de
  /// sistema de Spark) y última actividad.
  MatchJourney _deriveJourney(
    List<ChatMessage> messages, {
    String? persistedStatus,
  }) {
    String? proposalStatus;
    bool hasSystemGame = false;
    DateTime? lastActivity;
    for (final ChatMessage m in messages) {
      if (m.type.isDateProposal && m.dateProposal != null) {
        proposalStatus = m.dateProposal!.status.wireName;
      }
      if (m.type == MessageType.system ||
          (m.doubleAnswer?.isRevealed ?? false) ||
          (m.twoTruths?.isRevealed ?? false)) {
        hasSystemGame = true;
      }
      final DateTime? c = m.createdAt;
      if (c != null && (lastActivity == null || c.isAfter(lastActivity))) {
        lastActivity = c;
      }
    }
    final MatchJourney derived = MatchJourney.derive(
      realMessageCount: _realMessageCount,
      hasCompletedGame: hasSystemGame,
      dateProposalStatus: proposalStatus,
      lastActivityAt: lastActivity,
    );
    return MatchJourney.fromMap(
      persistedStatus == null
          ? null
          : <String, dynamic>{'journeyStatus': persistedStatus},
      fallback: derived.status,
      coolingDown: derived.coolingDown,
    );
  }

  // --- CTAs del Journey ---

  void _openIcebreaker(bool canSend) {
    showIcebreakerSheet(
      context,
      onPrefill: (String starter) {
        _input.text = starter;
        _input.selection = TextSelection.fromPosition(
            TextPosition(offset: _input.text.length));
        _inputFocus.requestFocus();
      },
      onProposePlan: canSend ? () => _proposePlanFlow(canSend) : null,
      onSpark: (widget.sparkEnabled && widget.sparkService != null)
          ? _inviteSparkFromJourney
          : null,
      onDoubleAnswer: widget.doubleAnswerEnabled
          ? () => _startDoubleAnswerFlow(canSend)
          : null,
      onTwoTruths:
          widget.twoTruthsEnabled ? () => _startTwoTruthsFlow(canSend) : null,
      onChatGame: widget.chatGameEnabled
          ? () => _startChatGameFlow(canSend, mode: 'normal')
          : null,
      onCoffeeChallenge: widget.chatGameEnabled
          ? () => _startChatGameFlow(canSend, mode: 'coffee_challenge')
          : null,
      showQuickQuestion: widget.icebreakersEnabled,
      showThisOrThat: widget.thisOrThatEnabled,
    );
  }

  /// Inicia el "Duelo de Química". El Reto Café pide consentimiento explícito.
  Future<void> _startChatGameFlow(bool canSend, {required String mode}) async {
    if (!canSend) {
      _snack('Este chat ya no está disponible.');
      return;
    }
    if (mode == 'coffee_challenge') {
      final bool ok = await showDialog<bool>(
            context: context,
            builder: (BuildContext ctx) => AlertDialog(
              backgroundColor: context.colors.surface,
              title: const Text('Reto Café ☕'),
              content: const Text(
                'Si hay ganador, el que pierde invita al primer café. Si hay '
                'empate, a medias.\n\nEsto es solo una dinámica divertida. Nadie '
                'está obligado a pagar nada fuera de la app.',
              ),
              actions: <Widget>[
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Acepto y reto')),
              ],
            ),
          ) ??
          false;
      if (!ok || !mounted) return;
    }
    try {
      await widget.chatService.startChatGame(chatId: widget.chatId, mode: mode);
    } on ChatServiceException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo iniciar el reto.');
    }
  }

  Future<void> _inviteSparkFromJourney() async {
    final SparkService? spark = widget.sparkService;
    if (spark == null) return;
    try {
      final String sessionId = await spark.invite(
        matchId: widget.chatId,
        hostUid: widget.currentUid,
        guestUid: widget.other.uid,
      );
      if (!mounted) return;
      // Reutiliza la card de Spark existente abriendo la sala.
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SparkGameScreen(
          service: spark,
          matchId: widget.chatId,
          sessionId: sessionId,
          currentUid: widget.currentUid,
          otherName: widget.other.displayName,
          onReport: () => _report(),
        ),
      ));
    } catch (_) {
      _snack('No se pudo iniciar el juego.');
    }
  }

  Future<void> _startDoubleAnswerFlow(bool canSend) async {
    if (!canSend) {
      _snack('Este chat ya no esta disponible.');
      return;
    }
    final String? question = await _doubleAnswerQuestionDialog();
    if (question == null || question.trim().isEmpty || !mounted) return;
    try {
      await widget.chatService.startDoubleAnswer(
        chatId: widget.chatId,
        question: question.trim(),
      );
      _logMessageMetrics();
    } on ChatServiceException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo iniciar Doble Respuesta.');
    }
  }

  Future<String?> _doubleAnswerQuestionDialog() async {
    final TextEditingController controller = TextEditingController(
      text: IcebreakerCatalog.randomDoubleAnswer(),
    );
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Doble respuesta'),
        content: TextField(
          controller: controller,
          maxLength: 180,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Pregunta',
            hintText: 'Que quereis responder los dos?',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _submitDoubleAnswer(ChatMessage message) async {
    final DoubleAnswer? game = message.doubleAnswer;
    if (game == null || game.hasAnswered(_uid)) return;
    final TextEditingController controller = TextEditingController();
    final String? answer = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Tu respuesta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(game.question),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLength: 240,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Escribe tu respuesta',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (answer == null || answer.trim().isEmpty || !mounted) return;
    try {
      await widget.chatService.submitDoubleAnswer(
        chatId: widget.chatId,
        messageId: message.id,
        answer: answer.trim(),
      );
    } on ChatServiceException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo guardar la respuesta.');
    }
  }

  Future<void> _startTwoTruthsFlow(bool canSend) async {
    if (!canSend) {
      _snack('Este chat ya no esta disponible.');
      return;
    }
    final _TwoTruthsInput? input = await showModalBottomSheet<_TwoTruthsInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _TwoTruthsComposerSheet(),
    );
    if (input == null || !mounted) return;
    try {
      await widget.chatService.startTwoTruths(
        chatId: widget.chatId,
        statements: input.statements,
        lieIndex: input.lieIndex,
      );
      _logMessageMetrics();
    } on ChatServiceException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo iniciar Dos Verdades.');
    }
  }

  Future<void> _guessTwoTruths(ChatMessage message, int guessIndex) async {
    try {
      await widget.chatService.guessTwoTruths(
        chatId: widget.chatId,
        messageId: message.id,
        guessIndex: guessIndex,
      );
    } on ChatServiceException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo responder el juego.');
    }
  }

  /// Registra `messageSent` y, si es el primer mensaje real del chat,
  /// `conversationStarted` (una sola vez).
  void _logMessageMetrics() {
    final String me = widget.currentUid;
    widget.metrics?.log(FeedMetricsService.messageSent,
        uid: me, targetUid: widget.other.uid);
    if (_realMessageCount == 0 && !_conversationLogged) {
      _conversationLogged = true;
      widget.metrics?.log(FeedMetricsService.conversationStarted,
          uid: me, targetUid: widget.other.uid);
    }
  }

  /// Envía (o reintenta) un mensaje optimista y reconcilia su estado.
  Future<void> _deliver(_OutgoingMessage out) async {
    if (mounted) setState(() => out.failed = false);
    try {
      // Si hay un Duelo de Química activo, el mensaje se etiqueta con la sesión
      // (la IA solo analiza esos 5 min). Si no, mensaje normal.
      final String? gameSession = (_activeGameSessionId != null &&
              _activeGameEndsAt != null &&
              _activeGameEndsAt!.isAfter(DateTime.now()))
          ? _activeGameSessionId
          : null;
      final String id = await widget.chatService.sendMessage(
          chatId: widget.chatId, text: out.text, gameSessionId: gameSession);
      // Guarda el id real: el stream lo confirmará y se podará el optimista.
      if (mounted) setState(() => out.realId = id);
    } on ChatServiceException catch (e) {
      if (mounted) setState(() => out.failed = true);
      _snack(e.message);
    } catch (_) {
      if (mounted) setState(() => out.failed = true);
      _snack('No se pudo enviar. Toca para reintentar.');
    }
  }

  Future<void> _openBombImage(ChatMessage message) async {
    try {
      final Uint8List bytes = await widget.chatService.openBombImage(
        chatId: widget.chatId,
        messageId: message.id,
      );
      if (bytes.isEmpty || !mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _BombImageViewer(bytes: bytes),
      ));
    } on ChatServiceException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo abrir la foto bomba.');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openProfile() async {
    final Future<SeedProfile?> Function(String uid)? loader =
        widget.loadProfile;
    if (loader == null) return;
    final NavigatorState nav = Navigator.of(context);
    SeedProfile? profile;
    try {
      profile = await loader(widget.other.uid);
    } catch (_) {
      profile = null;
    }
    if (!mounted) return;
    if (profile == null) {
      _snack('No se pudo cargar el perfil.');
      return;
    }
    nav.push(MaterialPageRoute<void>(
      builder: (_) => ProfileViewScreen(profile: profile!),
    ));
  }

  Future<void> _respondProposal(String messageId, String response) async {
    try {
      await widget.chatService.respondDateProposal(
        chatId: widget.chatId,
        messageId: messageId,
        response: response,
      );
    } on ChatServiceException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo responder la propuesta.');
    }
  }

  /// Flujo de "proponer plan": Date Builder si está habilitado, si no la
  /// propuesta de cita directa.
  Future<void> _proposePlanFlow(bool canSend) {
    return widget.dateBuilderEnabled
        ? _openDateBuilder(canSend)
        : _proposeDate(canSend);
  }

  /// Abre el Date Builder (si está habilitado) para componer un plan y luego
  /// pasa al sheet de propuesta con el lugar/nota ya prefilados.
  Future<void> _openDateBuilder(bool canSend) async {
    if (!canSend) {
      _snack('Este chat ya no está disponible.');
      return;
    }
    final DatePlanSuggestion? plan =
        await showDateBuilderSheet(context, fullMode: widget.dateBuilderFull);
    if (plan == null || !mounted) return;
    await _proposeDate(canSend,
        prefillPlace: plan.placeName, prefillNote: plan.note);
  }

  Future<void> _proposeDate(
    bool canSend, {
    String prefillPlace = '',
    String prefillNote = '',
  }) async {
    if (!canSend) {
      _snack('Este chat ya no está disponible.');
      return;
    }
    final DateProposalInput? input = await DateProposalSheet.show(
      context,
      initialPlaceName: prefillPlace,
      initialNote: prefillNote,
    );
    if (input == null || !mounted) return;
    try {
      await widget.chatService.sendDateProposal(
        chatId: widget.chatId,
        proposedDate: input.dateIso,
        proposedTime: input.timeHm,
        placeName: input.placeName,
        placeAddress: input.placeAddress,
        note: input.note,
      );
      widget.metrics?.log(FeedMetricsService.dateProposed,
          uid: _uid, targetUid: widget.other.uid);
      _logMessageMetrics();
    } on ChatServiceException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo enviar la propuesta.');
    }
  }

  Future<void> _onMenu(String value) async {
    switch (value) {
      case 'unread':
        try {
          await widget.chatService.markAsUnread(widget.chatId);
          if (mounted) Navigator.of(context).pop();
        } catch (_) {
          _snack('No se pudo marcar como no leído.');
        }
        break;
      case 'unmatch':
        if (await _confirm('Deshacer match',
            'Se cerrara el chat con ${widget.other.displayName}.')) {
          await _run(() => widget.matchService.unmatch(widget.chatId),
              'Match deshecho.');
        }
        break;
      case 'block':
        if (await _confirm(
            'Bloquear', 'No podreis volver a veros ni escribiros.')) {
          await _run(() => widget.matchService.blockUser(widget.other.uid),
              'Usuario bloqueado.');
          if (mounted) Navigator.of(context).pop();
        }
        break;
      case 'close':
        await _closeGracefully();
        break;
      case 'report':
        await _report();
        break;
    }
  }

  /// Attra Clear §6: card del follow-up post-cita. Aparece si la cita fue
  /// aceptada, pasaron ≥24h y el follow-up sigue pendiente.
  Widget _buildFollowUp(Chat? chat, bool canSend) {
    if (!widget.dateFollowupEnabled ||
        _followUpDismissed ||
        chat == null ||
        !canSend ||
        !chat.isDateFollowUpDue()) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.celebration_rounded,
              size: 20, color: AppColors.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text('¿Cómo fue tu cita con ${widget.other.displayName}?',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => _openFollowUp(canSend),
            child: const Text('Responder'),
          ),
        ],
      ),
    );
  }

  Future<void> _openFollowUp(bool canSend) async {
    final DateFollowUpAnswer? answer = await DateFollowUpSheet.show(context);
    if (answer == null || !mounted) return;
    setState(() => _followUpDismissed = true);
    _antiGhostingAnalytics.metrics?.log(
      AntiGhostingAnalytics.dateFollowupAnswered,
      uid: widget.currentUid,
      meta: <String, dynamic>{'answer': answer.wire},
    );
    try {
      await widget.chatService
          .answerDateFollowUp(chatId: widget.chatId, answer: answer.wire);
    } catch (_) {/* best-effort: el estado se reintenta en la próxima */}
    if (!mounted) return;
    switch (answer) {
      case DateFollowUpAnswer.keepTalking:
        _snack('¡Genial! Seguid hablando 💬');
        break;
      case DateFollowUpAnswer.noConnection:
      case DateFollowUpAnswer.preferEnd:
        if (widget.closeGracefullyEnabled) {
          await _closeGracefully();
        }
        break;
      case DateFollowUpAnswer.uncomfortable:
      case DateFollowUpAnswer.report:
        await _report();
        break;
    }
  }

  /// Attra Clear §5: tarjeta de nudge in-chat. Solo cuando es TU turno y la
  /// espera supera el primer umbral. Se puede ocultar esta sesión.
  Widget _buildNudge(Chat? chat, bool canSend) {
    if (!widget.nudgesEnabled ||
        _nudgeDismissed ||
        chat == null ||
        !canSend ||
        chat.lastMessageAt == null ||
        !chat.isMyTurn(widget.currentUid)) {
      return const SizedBox.shrink();
    }
    final Duration waited = DateTime.now().difference(chat.lastMessageAt!);
    final NudgeTier tier = nudgeTierForDuration(waited);
    if (!tier.isActive) return const SizedBox.shrink();

    // "Shown" una sola vez por nivel (evita spam de eventos en cada rebuild).
    final String key = '${chat.id}:${tier.name}';
    if (_nudgeShownKey != key) {
      _nudgeShownKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _antiGhostingAnalytics
            .logNudgeShown(tier: tier.name, hoursWaiting: waited.inHours);
      });
    }

    final bool canPropose = canSend;
    return AntiGhostingNudgeCard(
      tier: tier,
      canProposePlan: canPropose,
      canClose: widget.closeGracefullyEnabled,
      onAction: (NudgeAction action) =>
          _onNudgeAction(action, tier, canSend),
    );
  }

  void _onNudgeAction(NudgeAction action, NudgeTier tier, bool canSend) {
    _antiGhostingAnalytics
        .logNudgeAction(tier: tier.name, action: action.name);
    switch (action) {
      case NudgeAction.reply:
        setState(() => _nudgeDismissed = true);
        _inputFocus.requestFocus();
        break;
      case NudgeAction.proposePlan:
        setState(() => _nudgeDismissed = true);
        _proposePlanFlow(canSend);
        break;
      case NudgeAction.closeGracefully:
        _closeGracefully();
        break;
      case NudgeAction.remindLater:
        setState(() => _nudgeDismissed = true);
        break;
    }
  }

  /// Attra Clear §3: abre el sheet de cierre con elegancia y, si el usuario
  /// confirma, envía el mensaje de despedida y cierra el chat (Cloud Function).
  Future<void> _closeGracefully() async {
    final ClosureChoice? choice = await CloseConversationSheet.show(
      context,
      otherName: widget.other.displayName,
    );
    if (choice == null || !mounted) return;
    try {
      await widget.chatService.closeConversation(
        chatId: widget.chatId,
        reason: choice.reason,
        message: choice.message,
      );
      if (mounted) _snack('Conversación cerrada con respeto.');
    } on ChatServiceException catch (e) {
      _snack(e.code == 'failed-precondition'
          ? 'Esta conversación ya no está disponible.'
          : 'No se pudo cerrar la conversación.');
    } catch (_) {
      _snack('No se pudo cerrar la conversación.');
    }
  }

  Future<void> _run(Future<void> Function() action, String okMsg) async {
    try {
      await action();
      _snack(okMsg);
    } catch (e) {
      _snack('No se pudo completar la accion.');
    }
  }

  Future<bool> _confirm(String title, String message) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _report() async {
    final ReportReason? reason = await showModalBottomSheet<ReportReason>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Reportar usuario'),
            ),
            for (final ReportReason r in ReportReason.values)
              ListTile(
                title: Text(r.label),
                onTap: () => Navigator.of(context).pop(r),
              ),
          ],
        ),
      ),
    );
    if (reason == null) return;
    await _run(
      () => widget.matchService
          .reportUser(reportedUid: widget.other.uid, reason: reason.wireName)
          .then((_) {}),
      'Gracias, lo revisaremos.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: widget.loadProfile == null ? null : _openProfile,
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFE0E0E0),
                backgroundImage: widget.other.photoUrl.isNotEmpty
                    ? CachedNetworkImageProvider(widget.other.photoUrl)
                    : null,
                child: widget.other.photoUrl.isEmpty
                    ? Text(widget.other.displayName.isNotEmpty
                        ? widget.other.displayName[0].toUpperCase()
                        : '?')
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.other.displayName,
                    overflow: TextOverflow.ellipsis),
              ),
              if (widget.loadProfile != null)
                const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
        actions: <Widget>[
          PopupMenuButton<String>(
            onSelected: _onMenu,
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                  value: 'unread', child: Text('Marcar como no leído')),
              if (widget.closeGracefullyEnabled)
                const PopupMenuItem<String>(
                    value: 'close', child: Text('Cerrar conversación')),
              const PopupMenuItem<String>(
                  value: 'unmatch', child: Text('Deshacer match')),
              const PopupMenuItem<String>(
                  value: 'block', child: Text('Bloquear')),
              const PopupMenuItem<String>(
                  value: 'report', child: Text('Reportar')),
            ],
          ),
        ],
      ),
      body: StreamBuilder<Chat?>(
        stream: widget.chatService.observeChatById(widget.chatId),
        builder: (BuildContext context, AsyncSnapshot<Chat?> chatSnap) {
          final Chat? chat = chatSnap.data;
          final bool canSend = chat?.status.canSendMessages ?? true;
          return Column(
            children: <Widget>[
              // Match Journey (Fase 8): card de recorrido guiado. Opt-in, cerrable.
              if (widget.journeyEnabled &&
                  canSend &&
                  !_journeyDismissed &&
                  _journey != null)
                MatchJourneyCard(
                  journey: _journey!,
                  otherName: widget.other.displayName,
                  onIcebreaker: widget.icebreakersEnabled
                      ? () => _openIcebreaker(canSend)
                      : null,
                  onQuickGame:
                      (widget.sparkEnabled && widget.sparkService != null)
                          ? _inviteSparkFromJourney
                          : (widget.doubleAnswerEnabled ||
                                  widget.twoTruthsEnabled ||
                                  widget.icebreakersEnabled
                              ? () => _openIcebreaker(canSend)
                              : null),
                  onProposePlan:
                      canSend ? () => _proposePlanFlow(canSend) : null,
                  onReactivate: widget.matchReactivationEnabled &&
                          widget.icebreakersEnabled
                      ? () => _openIcebreaker(canSend)
                      : null,
                  onDismiss: () => setState(() => _journeyDismissed = true),
                ),
              // Attra Spark (opcional, tras la feature flag). No bloquea el chat.
              if (widget.sparkEnabled && widget.sparkService != null && canSend)
                SparkEntryCard(
                  service: widget.sparkService!,
                  matchId: widget.chatId,
                  currentUid: widget.currentUid,
                  otherUid: widget.other.uid,
                  otherName: widget.other.displayName,
                  onReport: () => _report(),
                  onUseQuestion: _useSparkQuestion,
                ),
              // Attra Clear §6: follow-up post-cita "¿Cómo fue la cita?".
              _buildFollowUp(chat, canSend),
              // Attra Clear §5: nudge in-chat si llevas tiempo sin responder.
              _buildNudge(chat, canSend),
              Expanded(
                  child: _messageList(persistedStatus: chat?.journeyStatus)),
              if (_uploadingMedia) const LinearProgressIndicator(minHeight: 2),
              if (!canSend)
                _ClosedBanner(chat: chat, currentUid: widget.currentUid)
              else if (_recording)
                _RecordingBar(
                  elapsed: _recordElapsed,
                  onCancel: _cancelRecording,
                  onSend: _stopAndSend,
                )
              else
                _Composer(
                  controller: _input,
                  focusNode: _inputFocus,
                  sending: false,
                  onSend: () => _send(canSend),
                  onPropose: () => _proposePlanFlow(canSend),
                  onPhoto: () => _pickAndSendImage(canSend),
                  onBombPhoto: () => _pickAndSendImage(canSend, bomb: true),
                  showGames: _gamesAvailable,
                  onGames: () => _openIcebreaker(canSend),
                  onMic: () => _startRecording(canSend),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _messageList({String? persistedStatus}) {
    return StreamBuilder<List<ChatMessage>>(
      stream: widget.chatService.observeMessages(widget.chatId),
      builder:
          (BuildContext context, AsyncSnapshot<List<ChatMessage>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final List<ChatMessage> messages = snapshot.data ?? <ChatMessage>[];

        // Cuenta de mensajes "reales" (texto/media/propuesta), cacheada para
        // detectar el primer mensaje (conversationStarted). No requiere setState.
        _realMessageCount = messages
            .where((ChatMessage m) =>
                m.type == MessageType.text ||
                m.type.isMedia ||
                m.type.isDateProposal ||
                m.type.isDoubleAnswer ||
                m.type.isTwoTruths)
            .length;
        _journey = _deriveJourney(messages, persistedStatus: persistedStatus);

        // Reconciliación: el stream confirma los optimistas por su id real.
        final Set<String> streamIds =
            messages.map((ChatMessage m) => m.id).toSet();
        if (_outgoing.any((_OutgoingMessage o) =>
            o.realId != null && streamIds.contains(o.realId))) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _outgoing.removeWhere((_OutgoingMessage o) =>
                o.realId != null && streamIds.contains(o.realId)));
          });
        }
        // Optimistas aún no confirmados (se pintan al instante).
        final List<_OutgoingMessage> pending = _outgoing
            .where((_OutgoingMessage o) =>
                o.realId == null || !streamIds.contains(o.realId))
            .toList(growable: false);

        if (messages.isEmpty && pending.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('Aún no hay mensajes. Saluda 👋',
                  textAlign: TextAlign.center),
            ),
          );
        }
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.all(12),
          itemCount: messages.length + pending.length,
          itemBuilder: (BuildContext context, int index) {
            // Bloque optimista al fondo (índices 0..pending.length-1).
            if (index < pending.length) {
              final _OutgoingMessage o = pending[pending.length - 1 - index];
              return _TextBubble(
                text: o.text,
                mine: true,
                pending: !o.failed,
                failed: o.failed,
                onRetry: o.failed ? () => _deliver(o) : null,
              );
            }
            final int mIndex = index - pending.length;
            final ChatMessage m = messages[messages.length - 1 - mIndex];
            final bool mine = m.senderId == widget.currentUid;
            if (m.type == MessageType.system) {
              return _SystemLine(text: m.text);
            }
            if (m.type.isContext) {
              return _ContextBubble(message: m, mine: mine);
            }
            if (m.type.isBombImage && m.media != null) {
              return _BombImageBubble(
                message: m,
                mine: mine,
                onOpen: () => _openBombImage(m),
              );
            }
            if (m.type.isImage && m.media != null) {
              return _ImageBubble(media: m.media!, mine: mine);
            }
            if (m.type.isVoiceNote && m.media != null) {
              return VoiceNoteBubble(
                  media: m.media!, mine: mine, controller: _voicePlayer);
            }
            if (m.type.isDateProposal && m.dateProposal != null) {
              return _DateProposalBubble(
                message: m,
                proposal: m.dateProposal!,
                mine: mine,
                onRespond: (String response) =>
                    _respondProposal(m.id, response),
              );
            }
            if (m.type.isDoubleAnswer && m.doubleAnswer != null) {
              return _DoubleAnswerBubble(
                game: m.doubleAnswer!,
                currentUid: widget.currentUid,
                otherName: widget.other.displayName,
                mine: mine,
                onAnswer: () => _submitDoubleAnswer(m),
              );
            }
            if (m.type.isTwoTruths && m.twoTruths != null) {
              return _TwoTruthsBubble(
                game: m.twoTruths!,
                mine: mine,
                onGuess: (int guess) => _guessTwoTruths(m, guess),
              );
            }
            if (m.type.isChatGame && (m.gameSessionId ?? '').isNotEmpty) {
              return _ChatGameBubble(
                chatId: widget.chatId,
                sessionId: m.gameSessionId!,
                currentUid: widget.currentUid,
                chatService: widget.chatService,
                onActive: _onGameActive,
                onTimeUp: _finishGame,
                onAbandon: (String sid) => widget.chatService
                    .abandonChatGame(chatId: widget.chatId, sessionId: sid),
              );
            }
            return _TextBubble(text: m.text, mine: mine);
          },
        );
      },
    );
  }
}

/// Tarjeta del "Duelo de Química" dentro del chat. Observa la sesión en vivo y
/// pinta el estado: invitación (aceptar/rechazar), reto activo (cuenta atrás) y
/// resultado de la IA. Reporta el estado activo al padre (para etiquetar
/// mensajes) y dispara el cierre cuando vence el tiempo.
class _ChatGameBubble extends StatefulWidget {
  const _ChatGameBubble({
    required this.chatId,
    required this.sessionId,
    required this.currentUid,
    required this.chatService,
    required this.onActive,
    required this.onTimeUp,
    required this.onAbandon,
  });

  final String chatId;
  final String sessionId;
  final String currentUid;
  final ChatService chatService;
  final void Function(String? sessionId, DateTime? endsAt) onActive;
  final Future<void> Function(String sessionId) onTimeUp;
  final Future<void> Function(String sessionId) onAbandon;

  @override
  State<_ChatGameBubble> createState() => _ChatGameBubbleState();
}

class _ChatGameBubbleState extends State<_ChatGameBubble> {
  ChatGameSession? _session;
  StreamSubscription<ChatGameSession?>? _sub;
  Timer? _ticker;
  bool _responding = false;
  bool _timeUpSent = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.chatService
        .observeGameSession(widget.chatId, widget.sessionId)
        .listen(_onSession);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final ChatGameSession? s = _session;
      if (s != null && s.status.isActive) {
        setState(() {});
        if (s.secondsLeft() <= 0 && !_timeUpSent) {
          _timeUpSent = true;
          widget.onTimeUp(s.id);
        }
      }
    });
  }

  void _onSession(ChatGameSession? s) {
    if (!mounted) return;
    setState(() => _session = s);
    // Reporta al padre el estado activo (para etiquetar mensajes / cerrar).
    final bool active = s != null && s.status.isActive;
    widget.onActive(active ? s.id : null, active ? s.endsAt : null);
    if (s == null || !s.status.isActive) _timeUpSent = false;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _respond(bool accept) async {
    if (_responding) return;
    setState(() => _responding = true);
    try {
      await widget.chatService.respondChatGame(
          chatId: widget.chatId, sessionId: widget.sessionId, accept: accept);
    } catch (_) {/* el stream reflejará el estado */} finally {
      if (mounted) setState(() => _responding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ChatGameSession? s = _session;
    if (s == null) return const SizedBox.shrink();
    final bool mine = s.creatorUserId == widget.currentUid;
    final ThemeData theme = Theme.of(context);

    Widget shell(List<Widget> children) => Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                AppColors.attraRed.withValues(alpha: 0.18),
                context.colors.surface,
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border:
                Border.all(color: AppColors.attraRed.withValues(alpha: 0.4)),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: children),
        );

    final Widget header = Row(
      children: <Widget>[
        const Icon(Icons.bolt_rounded, color: AppColors.attraRed, size: 20),
        const SizedBox(width: 8),
        Text(
            s.mode.isCoffee
                ? 'Reto Café · Duelo de Química'
                : 'Duelo de Química',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );

    switch (s.status) {
      case ChatGameStatus.pending:
      case ChatGameStatus.accepted:
        final bool iAccepted = s.hasAccepted(widget.currentUid);
        return shell(<Widget>[
          header,
          const SizedBox(height: 8),
          Text(
            mine
                ? 'Has retado a un duelo de 5 min. Esperando que acepte…'
                : '¡Te retan a un duelo de conversación de 5 minutos! La IA '
                    'analizará solo esos 5 min y dictará el resultado.',
            style: theme.textTheme.bodyMedium,
          ),
          if (!mine && !iAccepted) ...<Widget>[
            const SizedBox(height: 12),
            Row(children: <Widget>[
              Expanded(
                child: FilledButton(
                  onPressed: _responding ? null : () => _respond(true),
                  child: const Text('Aceptar reto'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _responding ? null : () => _respond(false),
                child: const Text('Ahora no'),
              ),
            ]),
          ] else if (iAccepted && !mine) ...<Widget>[
            const SizedBox(height: 8),
            Text('Has aceptado. Empezando…',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: context.colors.textSecondary)),
          ],
        ]);

      case ChatGameStatus.active:
        final int secs = s.secondsLeft();
        final String mm = (secs ~/ 60).toString();
        final String ss = (secs % 60).toString().padLeft(2, '0');
        return shell(<Widget>[
          Row(children: <Widget>[
            Expanded(child: header),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.attraRed,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$mm:$ss',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(s.themeTitle.isNotEmpty ? s.themeTitle : 'Hablad sin parar 😄',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('Escribid en el chat. La IA analizará estos 5 minutos.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: context.colors.textSecondary)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => widget.onAbandon(s.id),
              child: const Text('Salir del reto'),
            ),
          ),
        ]);

      case ChatGameStatus.completed:
        return _ChatGameResult(session: s, currentUid: widget.currentUid);

      case ChatGameStatus.cancelled:
      case ChatGameStatus.abandoned:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: context.colors.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            s.status == ChatGameStatus.cancelled
                ? 'Reto no aceptado.'
                : 'Reto cancelado. Sin problema 😊',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: context.colors.textSecondary),
          ),
        );
    }
  }
}

/// Card de resultado de la IA (ganador/empate, química, mejor momento, plan).
class _ChatGameResult extends StatelessWidget {
  const _ChatGameResult({required this.session, required this.currentUid});

  final ChatGameSession session;
  final String currentUid;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ChatGameResult? r = session.result;
    if (r == null) return const SizedBox.shrink();
    final bool iWon = r.winnerUserId != null && r.winnerUserId == currentUid;
    final String headline = r.noWinner
        ? 'Sin ganador esta vez'
        : r.isDraw
            ? '¡Empate de química! 💞'
            : (iWon ? '¡Has ganado! 🎉' : 'Resultado del duelo');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: AppColors.action),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(children: <Widget>[
            const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(headline,
                style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 8),
          if (r.reason.isNotEmpty)
            Text(r.reason,
                style: const TextStyle(color: Colors.white, height: 1.3)),
          const SizedBox(height: 10),
          _chip('💘 Química ${r.chemistryScore}/100'),
          if (r.bestMoment.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            _chip('🌟 "${r.bestMoment}"'),
          ],
          if (r.suggestedDatePlan != null) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Plan sugerido · ${r.suggestedDatePlan!.title}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(r.suggestedDatePlan!.description,
                      style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ],
          if (r.followUpMessage.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(r.followUpMessage,
                style: const TextStyle(
                    color: Colors.white, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 8),
          const Text(
            'Solo una dinámica divertida. Quedad siempre en un lugar público.',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white)),
      );
}

/// Mensaje de texto saliente pintado de forma optimista (antes de que el
/// backend lo confirme). [realId] se rellena cuando la función responde; el
/// stream con ese id permite podar este optimista.
class _OutgoingMessage {
  _OutgoingMessage({required this.text})
      : localId = 'local_${DateTime.now().microsecondsSinceEpoch}',
        createdAt = DateTime.now();

  final String localId;
  final String text;
  final DateTime createdAt;
  String? realId;
  bool failed = false;
}

class _TextBubble extends StatelessWidget {
  const _TextBubble({
    required this.text,
    required this.mine,
    this.pending = false,
    this.failed = false,
    this.onRetry,
  });

  final String text;
  final bool mine;
  final bool pending;
  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget bubble = Container(
      margin: const EdgeInsets.only(top: 4, bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      decoration: BoxDecoration(
        color: mine
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text,
          style: TextStyle(color: mine ? theme.colorScheme.onPrimary : null)),
    );

    // Estado del optimista (reloj = enviando, error = fallido + reintentar).
    Widget? status;
    if (failed) {
      status = GestureDetector(
        onTap: onRetry,
        child: Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline_rounded,
                  size: 13, color: AppColors.danger),
              const SizedBox(width: 3),
              Text('Reintentar',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.danger, fontSize: 11)),
            ],
          ),
        ),
      );
    } else if (pending) {
      status = Padding(
        padding: const EdgeInsets.only(right: 4, bottom: 4),
        child: Icon(Icons.schedule_rounded,
            size: 12, color: context.colors.textMuted),
      );
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Opacity(
        opacity: pending ? 0.85 : 1,
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: <Widget>[bubble, if (status != null) status],
        ),
      ),
    );
  }
}

class _DoubleAnswerBubble extends StatelessWidget {
  const _DoubleAnswerBubble({
    required this.game,
    required this.currentUid,
    required this.otherName,
    required this.mine,
    required this.onAnswer,
  });

  final DoubleAnswer game;
  final String currentUid;
  final String otherName;
  final bool mine;
  final VoidCallback onAnswer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool answered = game.hasAnswered(currentUid);
    final bool revealed = game.isRevealed;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.attraRed.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.question_answer_rounded,
                    size: 18, color: AppColors.attraRed),
                const SizedBox(width: 6),
                Text('Doble respuesta',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 8),
            Text(game.question, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 10),
            if (revealed)
              ...game.answers.entries.map((MapEntry<String, String> entry) {
                final String who = entry.key == currentUid ? 'Tu' : otherName;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _MiniReveal(label: who, value: entry.value),
                );
              })
            else if (answered)
              Row(
                children: <Widget>[
                  Icon(Icons.lock_clock_rounded,
                      size: 16, color: context.colors.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Respuesta guardada. Esperando al reveal.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: context.colors.textMuted)),
                  ),
                ],
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: onAnswer,
                  child: const Text('Responder'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TwoTruthsBubble extends StatelessWidget {
  const _TwoTruthsBubble({
    required this.game,
    required this.mine,
    required this.onGuess,
  });

  final TwoTruths game;
  final bool mine;
  final ValueChanged<int> onGuess;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool canGuess = !mine && !game.isRevealed;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.psychology_alt_rounded,
                    size: 18, color: AppColors.gold),
                const SizedBox(width: 6),
                Text('Dos verdades y una mentira',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < game.statements.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    CircleAvatar(
                      radius: 12,
                      child: Text('${i + 1}',
                          style: const TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(game.statements[i])),
                    if (game.isRevealed && game.lieIndex == i)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.close_rounded,
                            size: 18, color: AppColors.danger),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            if (game.isRevealed)
              Chip(
                label: Text(game.correct == true
                    ? 'Adivinado'
                    : 'La mentira era la ${((game.lieIndex ?? 0) + 1)}'),
              )
            else if (canGuess)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List<Widget>.generate(
                  game.statements.length,
                  (int i) => OutlinedButton(
                    onPressed: () => onGuess(i),
                    child: Text('Mentira ${i + 1}'),
                  ),
                ),
              )
            else
              Text('Esperando a que responda.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: context.colors.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _MiniReveal extends StatelessWidget {
  const _MiniReveal({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.surfaceLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: context.colors.textMuted)),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }
}

class _ContextBubble extends StatelessWidget {
  const _ContextBubble({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isAttra = message.type == MessageType.attraContext;
    final String url = message.relatedPhotoUrlSnapshot ?? '';
    final bool photoGone = message.relatedPhotoDeleted || url.isEmpty;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: photoGone
                  ? Container(
                      width: 64,
                      height: 84,
                      color: const Color(0xFFE0E0E0),
                      child: const Icon(Icons.image_not_supported_outlined,
                          size: 24))
                  : GestureDetector(
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => _FullScreenImage(url: url))),
                      child: AttraImage(url: url, width: 64, height: 84),
                    ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(isAttra ? Icons.star : Icons.favorite,
                          size: 14, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        isAttra ? 'Te envió un Attra' : 'Respondió a tu foto',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                  if (photoGone)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Respondió a una foto que ya no está disponible',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ),
                  if (message.text.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(message.text),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card de propuesta de cita. El receptor (mine==false) puede aceptar/rechazar
/// si sigue pendiente.
class _DateProposalBubble extends StatelessWidget {
  const _DateProposalBubble({
    required this.message,
    required this.proposal,
    required this.mine,
    required this.onRespond,
  });

  final ChatMessage message;
  final DateProposal proposal;
  final bool mine;
  final void Function(String response) onRespond;

  String _statusLabel(DateProposalStatus s) {
    switch (s) {
      case DateProposalStatus.pending:
        return 'Pendiente';
      case DateProposalStatus.accepted:
        return 'Aceptada';
      case DateProposalStatus.declined:
        return 'Rechazada';
      case DateProposalStatus.countered:
        return 'Contrapropuesta';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool canRespond = !mine && proposal.isPending;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.primary),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.event, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('Propuesta de cita',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: theme.colorScheme.primary)),
              ],
            ),
            const SizedBox(height: 8),
            _row(Icons.calendar_today, proposal.proposedDate),
            _row(Icons.schedule, proposal.proposedTime),
            _row(
                Icons.place_outlined,
                <String>[
                  proposal.placeName,
                  proposal.placeAddress,
                ].where((String s) => s.isNotEmpty).join(' · ')),
            if (proposal.note.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(proposal.note, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 8),
            Chip(
              label: Text(_statusLabel(proposal.status)),
              visualDensity: VisualDensity.compact,
            ),
            if (canRespond) ...<Widget>[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                      onPressed: () => onRespond('declined'),
                      child: const Text('Rechazar')),
                  const SizedBox(width: 6),
                  FilledButton(
                      onPressed: () => onRespond('accepted'),
                      child: const Text('Aceptar')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _TwoTruthsInput {
  const _TwoTruthsInput({required this.statements, required this.lieIndex});

  final List<String> statements;
  final int lieIndex;
}

class _TwoTruthsComposerSheet extends StatefulWidget {
  const _TwoTruthsComposerSheet();

  @override
  State<_TwoTruthsComposerSheet> createState() =>
      _TwoTruthsComposerSheetState();
}

class _TwoTruthsComposerSheetState extends State<_TwoTruthsComposerSheet> {
  final List<TextEditingController> _controllers = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  int _lieIndex = 0;

  @override
  void dispose() {
    for (final TextEditingController controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _ready =>
      _controllers.every((TextEditingController c) => c.text.trim().isNotEmpty);

  void _submit() {
    if (!_ready) return;
    Navigator.of(context).pop(_TwoTruthsInput(
      statements: _controllers
          .map((TextEditingController c) => c.text.trim())
          .toList(growable: false),
      lieIndex: _lieIndex,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.surfaceLine,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Dos verdades y una mentira',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Escribe tres frases y marca cual es la mentira.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: context.colors.textSecondary)),
            const SizedBox(height: 14),
            for (int i = 0; i < _controllers.length; i++) ...<Widget>[
              TextField(
                controller: _controllers[i],
                maxLength: 140,
                decoration: InputDecoration(
                  labelText: 'Frase ${i + 1}',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 4),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List<Widget>.generate(
                _controllers.length,
                (int i) => ChoiceChip(
                  label: Text('Mentira ${i + 1}'),
                  selected: _lieIndex == i,
                  onSelected: (_) => setState(() => _lieIndex = i),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('La frase marcada sera la mentira.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: context.colors.textMuted)),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _ready ? _submit : null,
                icon: const Icon(Icons.psychology_alt_rounded),
                label: const Text('Crear juego'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    required this.onPropose,
    required this.onPhoto,
    required this.onBombPhoto,
    required this.showGames,
    required this.onGames,
    required this.onMic,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onPropose;
  final VoidCallback onPhoto;
  final VoidCallback onBombPhoto;
  final bool showGames;
  final VoidCallback onGames;
  final VoidCallback onMic;

  /// Abre la hoja con TODAS las acciones del chat (antes apretadas en la barra).
  void _openActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext sheetCtx) {
        Widget tile(IconData icon, String title, VoidCallback onTap) {
          return ListTile(
            leading: Icon(icon, color: AppColors.attraRed),
            title: Text(title),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              onTap();
            },
          );
        }

        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.surfaceLine,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              tile(Icons.photo_outlined, 'Enviar foto', onPhoto),
              tile(Icons.visibility_off_outlined, 'Foto bomba', onBombPhoto),
              tile(Icons.event, 'Proponer cita', onPropose),
              if (showGames) tile(Icons.casino_outlined, 'Juegos', onGames),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            // Todas las acciones colapsadas en un "+".
            IconButton(
              tooltip: 'Más',
              onPressed: () => _openActions(context),
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Escribe un mensaje…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Grabar nota de voz',
              onPressed: onMic,
              icon: const Icon(Icons.mic_none),
            ),
            IconButton.filled(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barra mostrada mientras se graba una nota de voz: punto rojo + contador +
/// cancelar/enviar.
class _RecordingBar extends StatelessWidget {
  const _RecordingBar({
    required this.elapsed,
    required this.onCancel,
    required this.onSend,
  });

  final Duration elapsed;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String mm = (elapsed.inSeconds ~/ 60).toString();
    final String ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 10),
        child: Row(
          children: <Widget>[
            Icon(Icons.fiber_manual_record,
                color: theme.colorScheme.error, size: 16),
            const SizedBox(width: 8),
            Text('Grabando…  $mm:$ss'),
            const Spacer(),
            TextButton(onPressed: onCancel, child: const Text('Cancelar')),
            const SizedBox(width: 4),
            IconButton.filled(
              tooltip: 'Enviar',
              onPressed: onSend,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _BombImageBubble extends StatefulWidget {
  const _BombImageBubble({
    required this.message,
    required this.mine,
    required this.onOpen,
  });

  final ChatMessage message;
  final bool mine;
  final Future<void> Function() onOpen;

  @override
  State<_BombImageBubble> createState() => _BombImageBubbleState();
}

class _BombImageBubbleState extends State<_BombImageBubble> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening || widget.mine || (widget.message.bomb?.isViewed ?? false)) {
      return;
    }
    setState(() => _opening = true);
    try {
      await widget.onOpen();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool viewed = widget.message.bomb?.isViewed ?? false;
    final String subtitle = widget.mine
        ? (viewed ? 'Vista' : 'Enviada - sin abrir')
        : (viewed ? 'Ya fue vista' : 'Tocar para abrir una vez');

    return Align(
      alignment: widget.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: viewed || widget.mine ? null : _open,
          child: Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: widget.mine
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: viewed
                    ? theme.colorScheme.outline
                    : theme.colorScheme.primary,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_opening)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    viewed
                        ? Icons.visibility_off_outlined
                        : Icons.timer_outlined,
                    color: widget.mine ? theme.colorScheme.onPrimary : null,
                  ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'Foto bomba',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: widget.mine
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: widget.mine
                              ? theme.colorScheme.onPrimary
                                  .withValues(alpha: 0.8)
                              : theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Burbuja de imagen: miniatura con loader; al tocar abre el visor a pantalla
/// completa.
class _ImageBubble extends StatelessWidget {
  const _ImageBubble({required this.media, required this.mine});

  final MediaInfo media;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final double maxW = MediaQuery.of(context).size.width * 0.62;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => _FullScreenImage(url: media.downloadUrl),
          )),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW, maxHeight: 320),
              child: AttraImage(url: media.downloadUrl, width: maxW),
            ),
          ),
        ),
      ),
    );
  }
}

/// Visor de imagen a pantalla completa con zoom.
class _FullScreenImage extends StatelessWidget {
  const _FullScreenImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Image.network(url,
              errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white,
                  size: 64)),
        ),
      ),
    );
  }
}

class _BombImageViewer extends StatefulWidget {
  const _BombImageViewer({required this.bytes});

  final Uint8List bytes;

  @override
  State<_BombImageViewer> createState() => _BombImageViewerState();
}

class _BombImageViewerState extends State<_BombImageViewer> {
  bool _captured = false;

  @override
  void initState() {
    super.initState();
    // Protege la foto bomba mientras está abierta (Android la bloquea; iOS la
    // oculta/detecta; web es no-op). Se desactiva al cerrar.
    ScreenGuard.enable();
    ScreenGuard.addCaptureListeners(
      onScreenshot: _onCapture,
      onScreenRecord: _onCapture,
    );
  }

  @override
  void dispose() {
    ScreenGuard.removeCaptureListeners();
    ScreenGuard.disable();
    super.dispose();
  }

  void _onCapture() {
    if (!mounted) return;
    setState(() => _captured = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Foto bomba'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              _captured
                  ? 'Se detectó una captura de pantalla. El contenido es privado.'
                  : 'Esta vista ya fue consumida. Al salir no podras abrirla de nuevo.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _captured ? const Color(0xFFFFB4A2) : Colors.white70),
            ),
          ),
          Expanded(
            child: Center(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.memory(
                  widget.bytes,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white,
                    size: 64,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClosedBanner extends StatelessWidget {
  const _ClosedBanner({required this.chat, required this.currentUid});

  final Chat? chat;
  final String currentUid;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Attra Clear §3: si fue un cierre con elegancia, etiqueta respetuosa.
    final bool graceful = chat?.isGracefullyClosed ?? false;
    final String label;
    if (graceful) {
      label = (chat!.closedByMe(currentUid))
          ? 'Cerraste esta conversación con respeto'
          : 'Conversación cerrada con respeto';
    } else {
      label = 'Este chat ya no está disponible';
    }
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        color: theme.colorScheme.surfaceContainerHighest,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (graceful) ...<Widget>[
              Icon(Icons.verified_outlined,
                  size: 16, color: theme.colorScheme.outline),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Línea de sistema centrada (p. ej. el resumen automático de Attra Spark).
class _SystemLine extends StatelessWidget {
  const _SystemLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
      child: Row(
        children: <Widget>[
          const Expanded(child: Divider()),
          Flexible(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}
