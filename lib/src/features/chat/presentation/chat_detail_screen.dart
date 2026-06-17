import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

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
import '../../safety/domain/report.dart';
import '../../spark/data/spark_service.dart';
import '../../spark/presentation/spark_entry_card.dart';
import '../../spark/presentation/spark_game_screen.dart';
import '../../../security/screen_guard.dart';
import '../../../theme/app_colors.dart';
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

  Duration _recordElapsed = Duration.zero;
  Timer? _recordTimer;

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
  MatchJourney _deriveJourney(List<ChatMessage> messages) {
    String? proposalStatus;
    bool hasSystemGame = false;
    DateTime? lastActivity;
    for (final ChatMessage m in messages) {
      if (m.type.isDateProposal && m.dateProposal != null) {
        proposalStatus = m.dateProposal!.status.wireName;
      }
      if (m.type == MessageType.system) hasSystemGame = true;
      final DateTime? c = m.createdAt;
      if (c != null && (lastActivity == null || c.isAfter(lastActivity))) {
        lastActivity = c;
      }
    }
    return MatchJourney.derive(
      realMessageCount: _realMessageCount,
      hasCompletedGame: hasSystemGame,
      dateProposalStatus: proposalStatus,
      lastActivityAt: lastActivity,
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
    );
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

  /// Registra `messageSent` y, si es el primer mensaje real del chat,
  /// `conversationStarted` (una sola vez).
  void _logMessageMetrics() {
    final String me = widget.currentUid;
    widget.metrics
        ?.log(FeedMetricsService.messageSent, uid: me, targetUid: widget.other.uid);
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
      final String id = await widget.chatService
          .sendMessage(chatId: widget.chatId, text: out.text);
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
    final DatePlanSuggestion? plan = await showDateBuilderSheet(context);
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
      case 'report':
        await _report();
        break;
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
                    ? NetworkImage(widget.other.photoUrl)
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
            itemBuilder: (BuildContext context) =>
                const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                  value: 'unread', child: Text('Marcar como no leído')),
              PopupMenuItem<String>(
                  value: 'unmatch', child: Text('Deshacer match')),
              PopupMenuItem<String>(value: 'block', child: Text('Bloquear')),
              PopupMenuItem<String>(value: 'report', child: Text('Reportar')),
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
                          : (widget.icebreakersEnabled
                              ? () => _openIcebreaker(canSend)
                              : null),
                  onProposePlan: canSend ? () => _proposePlanFlow(canSend) : null,
                  onReactivate: widget.icebreakersEnabled
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
              Expanded(child: _messageList()),
              if (_uploadingMedia) const LinearProgressIndicator(minHeight: 2),
              if (!canSend)
                _ClosedBanner(status: chat?.status)
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
                  onPropose: () => _proposeDate(canSend),
                  onPhoto: () => _pickAndSendImage(canSend),
                  onBombPhoto: () => _pickAndSendImage(canSend, bomb: true),
                  onMic: () => _startRecording(canSend),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _messageList() {
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
                m.type.isDateProposal)
            .length;
        _journey = _deriveJourney(messages);

        // Reconciliación: el stream confirma los optimistas por su id real.
        final Set<String> streamIds =
            messages.map((ChatMessage m) => m.id).toSet();
        if (_outgoing.any(
            (_OutgoingMessage o) => o.realId != null && streamIds.contains(o.realId))) {
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
            return _TextBubble(text: m.text, mine: mine);
          },
        );
      },
    );
  }
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
      status = const Padding(
        padding: EdgeInsets.only(right: 4, bottom: 4),
        child: Icon(Icons.schedule_rounded,
            size: 12, color: AppColors.textMuted),
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
              borderRadius: BorderRadius.circular(8),
              child: photoGone
                  ? Container(
                      width: 48,
                      height: 60,
                      color: const Color(0xFFE0E0E0),
                      child: const Icon(Icons.image_not_supported_outlined,
                          size: 22))
                  : Image.network(url,
                      width: 48,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          width: 48,
                          height: 60,
                          color: const Color(0xFFE0E0E0),
                          child: const Icon(Icons.image_not_supported_outlined,
                              size: 22))),
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

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    required this.onPropose,
    required this.onPhoto,
    required this.onBombPhoto,
    required this.onMic,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onPropose;
  final VoidCallback onPhoto;
  final VoidCallback onBombPhoto;
  final VoidCallback onMic;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 6, 10),
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: 'Adjuntar',
              onPressed: onPhoto,
              icon: const Icon(Icons.photo_outlined),
            ),
            IconButton(
              tooltip: 'Foto bomba',
              onPressed: onBombPhoto,
              icon: const Icon(Icons.visibility_off_outlined),
            ),
            IconButton(
              tooltip: 'Proponer cita',
              onPressed: onPropose,
              icon: const Icon(Icons.event),
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
              child: Image.network(
                media.downloadUrl,
                fit: BoxFit.cover,
                loadingBuilder: (BuildContext context, Widget child,
                    ImageChunkEvent? progress) {
                  if (progress == null) return child;
                  return Container(
                    width: maxW,
                    height: 220,
                    color: const Color(0xFFE0E0E0),
                    child: const Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (_, __, ___) => Container(
                  width: maxW,
                  height: 160,
                  color: const Color(0xFFE0E0E0),
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
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
  const _ClosedBanner({required this.status});

  final ChatStatus? status;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Text(
          'Este chat ya no está disponible',
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
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
