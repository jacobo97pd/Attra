import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/attra_colors.dart';
import '../../../widgets/attra_backgrounds.dart';
import '../../../widgets/attra_buttons.dart';
import '../../profile/domain/profile_prompt.dart';
import '../data/voice_recording_cleanup.dart';
import '../data/voice_profile_service.dart';
import '../domain/voice_profile_suggestion.dart';

typedef VoiceProfileGenerator = Future<VoiceProfileSuggestion> Function({
  required Uint8List bytes,
  required String contentType,
  required String extension,
  required int durationMs,
  required String intentMode,
});

/// Configuración rápida: explica la finalidad, graba audio limpio, permite
/// escucharlo, genera el borrador y ofrece una revisión editable antes del alta.
class VoiceProfileSetup extends StatefulWidget {
  const VoiceProfileSetup({
    super.key,
    required this.intentMode,
    required this.onGenerate,
    required this.onAccepted,
    required this.onUseManual,
    required this.onBack,
  });

  final String intentMode;
  final VoiceProfileGenerator onGenerate;
  final Future<void> Function(VoiceProfileSuggestion suggestion) onAccepted;
  final VoidCallback onUseManual;
  final VoidCallback onBack;

  @override
  State<VoiceProfileSetup> createState() => _VoiceProfileSetupState();
}

enum _VoicePhase { briefing, recording, recorded, processing, review }

class _VoiceProfileSetupState extends State<VoiceProfileSetup>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const Duration _maxDuration =
      Duration(milliseconds: VoiceProfileService.maxDurationMs);
  static const Duration _minDuration =
      Duration(milliseconds: VoiceProfileService.minDurationMs);

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  late final AnimationController _pulseController;

  _VoicePhase _phase = _VoicePhase.briefing;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  Timer? _processingCopyTimer;
  int _processingCopyIndex = 0;
  String _recordPath = '';
  String _loadedPlaybackPath = '';
  String _recordContentType = 'audio/mp4';
  String _recordExtension = 'm4a';
  String? _error;
  bool _accepting = false;
  bool _playing = false;
  bool _startingRecording = false;
  bool _stoppingRecording = false;
  bool _generating = false;
  bool _disposed = false;

  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _jobController = TextEditingController();
  final TextEditingController _companyController = TextEditingController();
  final List<TextEditingController> _promptQuestionControllers =
      <TextEditingController>[];
  final List<TextEditingController> _promptAnswerControllers =
      <TextEditingController>[];

  VoiceProfileSuggestion? _suggestion;
  String _relationshipIntent = '';
  String _smoking = '';
  String _drinking = '';
  String _fitnessLevel = '';
  String _wantsChildren = '';
  String _socialStyle = '';
  String _travelStyle = '';
  List<String> _fashionStyle = <String>[];
  List<String> _personalityTags = <String>[];

  static const List<String> _processingCopy = <String>[
    'Escuchando lo que te hace ser tú…',
    'Separando hechos de suposiciones…',
    'Dando forma a una bio natural…',
    'Buscando buenos puntos de conversación…',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _player.playerStateStream.listen((PlayerState state) {
      if (!mounted) return;
      final bool playing =
          state.playing && state.processingState != ProcessingState.completed;
      if (_playing != playing) setState(() => _playing = playing);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (_phase == _VoicePhase.recording) {
        unawaited(_cancelRecording(
          message:
              'La grabación se descartó al salir de la app para proteger tu privacidad.',
        ));
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _processingCopyTimer?.cancel();
    _pulseController.dispose();
    final String localRecording = _recordPath;
    _recordPath = '';
    unawaited(_disposeMedia(localRecording));
    _bioController.dispose();
    _jobController.dispose();
    _companyController.dispose();
    _disposePromptControllers();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_startingRecording || _phase != _VoicePhase.briefing) return;
    setState(() {
      _startingRecording = true;
      _error = null;
    });
    try {
      if (!await _recorder.hasPermission()) {
        if (_disposed || !mounted) return;
        setState(() {
          _error =
              'Necesitamos permiso de micrófono. Puedes seguir con la configuración paso a paso.';
        });
        return;
      }

      const List<(AudioEncoder, String, String)> candidates = kIsWeb
          ? <(AudioEncoder, String, String)>[
              (AudioEncoder.opus, 'audio/webm', 'webm'),
              (AudioEncoder.wav, 'audio/wav', 'wav'),
            ]
          : <(AudioEncoder, String, String)>[
              (AudioEncoder.aacLc, 'audio/mp4', 'm4a'),
              (AudioEncoder.opus, 'audio/ogg', 'ogg'),
              (AudioEncoder.wav, 'audio/wav', 'wav'),
            ];
      AudioEncoder? encoder;
      for (final (AudioEncoder, String, String) candidate in candidates) {
        final bool supported = await _recorder.isEncoderSupported(candidate.$1);
        if (_disposed) return;
        if (supported) {
          encoder = candidate.$1;
          _recordContentType = candidate.$2;
          _recordExtension = candidate.$3;
          break;
        }
      }
      if (encoder == null) {
        if (_disposed || !mounted) return;
        setState(() {
          _error =
              'Este dispositivo no ofrece un formato de audio compatible. Puedes continuar paso a paso.';
        });
        return;
      }

      String path = '';
      if (!kIsWeb) {
        final directory = await getTemporaryDirectory();
        if (_disposed) return;
        path =
            '${directory.path}/attra_voice_${DateTime.now().millisecondsSinceEpoch}.$_recordExtension';
      }
      if (_disposed) return;
      _recordPath = path;
      await _recorder.start(
        RecordConfig(
          encoder: encoder,
          // Speech-optimised settings keep the WAV fallback well below the
          // private 10 MB upload ceiling even at the full two minutes.
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: path,
      );
      if (_disposed || !mounted) return;
      setState(() {
        _elapsed = Duration.zero;
        _phase = _VoicePhase.recording;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
        if (!mounted || _phase != _VoicePhase.recording) return;
        final Duration next = _elapsed + const Duration(seconds: 1);
        setState(() => _elapsed = next);
        if (next >= _maxDuration) unawaited(_finishRecording());
      });
    } catch (_) {
      if (_disposed || !mounted) return;
      setState(() {
        _error =
            'No se pudo iniciar la grabación. Revisa el micrófono o usa el modo paso a paso.';
      });
    } finally {
      if (!_disposed && mounted) {
        setState(() => _startingRecording = false);
      }
    }
  }

  Future<void> _finishRecording() async {
    if (_stoppingRecording || _phase != _VoicePhase.recording) return;
    _stoppingRecording = true;
    _timer?.cancel();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = null;
    }
    if ((path == null || path.isEmpty) && _recordPath.isNotEmpty) {
      path = _recordPath;
    }
    if (!mounted) {
      await _deleteLocalRecording(path ?? _recordPath);
      return;
    }
    if (path == null || path.isEmpty) {
      await _deleteLocalRecording(_recordPath);
      _recordPath = '';
      setState(() {
        _phase = _VoicePhase.briefing;
        _error = 'No hemos podido recuperar la grabación. Inténtalo otra vez.';
        _stoppingRecording = false;
      });
      return;
    }
    _recordPath = path;
    setState(() {
      _phase = _VoicePhase.recorded;
      _stoppingRecording = false;
      _error = _elapsed < _minDuration
          ? 'Necesitamos al menos 12 segundos para crear algo fiel a ti.'
          : null;
    });
  }

  Future<void> _cancelRecording({String? message}) async {
    if (_stoppingRecording) return;
    _stoppingRecording = true;
    _timer?.cancel();
    String path = _recordPath;
    try {
      final String? stoppedPath = await _recorder.stop();
      if (stoppedPath != null && stoppedPath.isNotEmpty) path = stoppedPath;
    } catch (_) {}
    try {
      await _player.stop();
    } catch (_) {}
    await _deleteLocalRecording(path);
    if (!mounted) return;
    setState(() {
      _phase = _VoicePhase.briefing;
      _elapsed = Duration.zero;
      _recordPath = '';
      _loadedPlaybackPath = '';
      _suggestion = null;
      _stoppingRecording = false;
      _error = message;
    });
  }

  Future<void> _togglePlayback() async {
    if (_recordPath.isEmpty) return;
    try {
      if (_playing) {
        await _player.pause();
        return;
      }
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      if (_loadedPlaybackPath != _recordPath) {
        if (kIsWeb) {
          await _player.setUrl(_recordPath);
        } else {
          await _player.setFilePath(_recordPath);
        }
        _loadedPlaybackPath = _recordPath;
      }
      await _player.play();
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'No se pudo reproducir el audio, pero puedes repetirlo o enviarlo.');
      }
    }
  }

  Future<void> _generate() async {
    if (_generating ||
        _phase != _VoicePhase.recorded ||
        _recordPath.isEmpty ||
        _elapsed < _minDuration) {
      return;
    }
    setState(() {
      _generating = true;
      _phase = _VoicePhase.processing;
      _error = null;
      _processingCopyIndex = 0;
    });
    _processingCopyTimer?.cancel();
    _processingCopyTimer =
        Timer.periodic(const Duration(milliseconds: 2400), (_) {
      if (!mounted || _phase != _VoicePhase.processing) return;
      setState(() {
        _processingCopyIndex =
            (_processingCopyIndex + 1) % _processingCopy.length;
      });
    });

    try {
      await _player.stop();
      final Uint8List bytes = await XFile(_recordPath).readAsBytes();
      final VoiceProfileSuggestion suggestion = await widget.onGenerate(
        bytes: bytes,
        contentType: _recordContentType,
        extension: _recordExtension,
        durationMs: _elapsed.inMilliseconds,
        intentMode: widget.intentMode,
      );
      if (!mounted) return;
      _prepareReview(suggestion);
      setState(() {
        _suggestion = suggestion;
        _phase = _VoicePhase.review;
      });
    } on VoiceProfileServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _VoicePhase.recorded;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _VoicePhase.recorded;
        _error =
            'No hemos podido crear el borrador. Puedes volver a intentarlo o seguir paso a paso.';
      });
    } finally {
      _processingCopyTimer?.cancel();
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _disposeMedia(String localRecording) async {
    try {
      await _recorder.dispose();
    } catch (_) {}
    try {
      await _player.dispose();
    } catch (_) {}
    await _deleteLocalRecording(localRecording);
  }

  Future<void> _deleteLocalRecording(String path) async {
    try {
      await deleteTemporaryVoiceRecording(path);
    } catch (_) {
      // Best effort: the OS temp directory remains a final fallback.
    }
  }

  Future<void> _showVoicePrivacyDetails() {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Tu voz, bajo tu control',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 18),
                const _PrivacyDetail(
                  icon: Icons.auto_awesome_outlined,
                  title: 'Finalidad única',
                  body:
                      'Google Vertex AI procesa el audio para transcribirlo y '
                      'proponer este borrador. No se usa para clonar tu voz, '
                      'identificarte ni entrenar una voz sintética.',
                ),
                const _PrivacyDetail(
                  icon: Icons.public_outlined,
                  title: 'Procesamiento europeo',
                  body: 'La solicitud del modelo se ejecuta en europe-west4. '
                      'Antes del lanzamiento se verifica también la política '
                      'de ubicación y retención del bucket temporal.',
                ),
                const _PrivacyDetail(
                  icon: Icons.delete_outline_rounded,
                  title: 'Retención mínima',
                  body: 'El backend solicita el borrado tras cada intento. Un '
                      'barrido de seguridad elimina archivos huérfanos; la '
                      'copia local temporal también se descarta.',
                ),
                const _PrivacyDetail(
                  icon: Icons.visibility_outlined,
                  title: 'Nada se publica automáticamente',
                  body: 'La transcripción solo aparece durante esta revisión. '
                      'Guardamos el consentimiento y el borrador que aceptes, '
                      'nunca el audio ni la transcripción en tu perfil.',
                ),
                const SizedBox(height: 4),
                Text(
                  'Puedes consultar el historial de consentimiento y ejercer '
                  'tus derechos desde Ajustes > Datos y privacidad.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _prepareReview(VoiceProfileSuggestion suggestion) {
    _bioController.text = suggestion.bio;
    _jobController.text = suggestion.jobTitle;
    _companyController.text = suggestion.company;
    _relationshipIntent = suggestion.relationshipIntent;
    _smoking = suggestion.smoking;
    _drinking = suggestion.drinking;
    _fitnessLevel = suggestion.fitnessLevel;
    _wantsChildren = suggestion.wantsChildren;
    _socialStyle = suggestion.socialStyle;
    _travelStyle = suggestion.travelStyle;
    _fashionStyle = List<String>.from(suggestion.fashionStyle);
    _personalityTags = List<String>.from(suggestion.personalityTags);
    _disposePromptControllers();
    for (final VoicePromptSuggestion prompt in suggestion.prompts) {
      _promptQuestionControllers
          .add(TextEditingController(text: prompt.question));
      _promptAnswerControllers.add(TextEditingController(text: prompt.answer));
    }
  }

  void _disposePromptControllers() {
    for (final TextEditingController controller in _promptQuestionControllers) {
      controller.dispose();
    }
    for (final TextEditingController controller in _promptAnswerControllers) {
      controller.dispose();
    }
    _promptQuestionControllers.clear();
    _promptAnswerControllers.clear();
  }

  void _addPrompt() {
    if (_promptQuestionControllers.length >= kMaxActivePrompts) return;
    setState(() {
      _promptQuestionControllers.add(TextEditingController());
      _promptAnswerControllers.add(TextEditingController());
    });
  }

  void _removePrompt(int index) {
    setState(() {
      _promptQuestionControllers.removeAt(index).dispose();
      _promptAnswerControllers.removeAt(index).dispose();
    });
  }

  String? _reviewValidationError() {
    final String bio = _bioController.text.trim();
    if (bio.length < 20) {
      return 'La bio necesita al menos 20 caracteres.';
    }
    if (bio.length > 240) return 'La bio no puede superar 240 caracteres.';
    for (int i = 0; i < _promptQuestionControllers.length; i++) {
      final String question = _promptQuestionControllers[i].text;
      final String answer = _promptAnswerControllers[i].text;
      final bool bothEmpty = question.trim().isEmpty && answer.trim().isEmpty;
      if (bothEmpty) continue;
      final String? questionError =
          ProfilePromptValidator.validateCustomQuestion(question);
      if (questionError != null) return 'Pregunta ${i + 1}: $questionError';
      final String? answerError = ProfilePromptValidator.validateAnswer(answer);
      if (answerError != null) return 'Respuesta ${i + 1}: $answerError';
    }
    return null;
  }

  Future<void> _acceptReview() async {
    final VoiceProfileSuggestion? base = _suggestion;
    if (base == null || _accepting) return;
    final String? validationError = _reviewValidationError();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    final List<VoicePromptSuggestion> prompts = <VoicePromptSuggestion>[];
    for (int i = 0; i < _promptQuestionControllers.length; i++) {
      final VoicePromptSuggestion prompt = VoicePromptSuggestion(
        question: _promptQuestionControllers[i].text.trim(),
        answer: _promptAnswerControllers[i].text.trim(),
      );
      if (prompt.isValid) prompts.add(prompt);
    }
    final VoiceProfileSuggestion edited = base.copyWith(
      bio: _bioController.text.trim(),
      jobTitle: _jobController.text.trim(),
      company: _companyController.text.trim(),
      relationshipIntent: _relationshipIntent,
      smoking: _smoking,
      drinking: _drinking,
      fitnessLevel: _fitnessLevel,
      wantsChildren: _wantsChildren,
      socialStyle: _socialStyle,
      travelStyle: _travelStyle,
      fashionStyle: _fashionStyle,
      personalityTags: _personalityTags,
      prompts: prompts,
    );
    setState(() {
      _accepting = true;
      _error = null;
    });
    try {
      await widget.onAccepted(edited);
    } catch (_) {
      if (mounted) {
        setState(() {
          _accepting = false;
          _error =
              'No se pudo guardar el borrador. Tu perfil aún no se ha publicado.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AttraGradientBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: switch (_phase) {
                  _VoicePhase.briefing => _buildBriefing(),
                  _VoicePhase.recording => _buildRecording(),
                  _VoicePhase.recorded => _buildRecorded(),
                  _VoicePhase.processing => _buildProcessing(),
                  _VoicePhase.review => _buildReview(),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBriefing() {
    final ThemeData theme = Theme.of(context);
    return SingleChildScrollView(
      key: const ValueKey<String>('voice-briefing'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _TopBar(
            onBack: widget.onBack,
            trailingLabel: 'Paso a paso',
            onTrailing: widget.onUseManual,
          ),
          const SizedBox(height: 28),
          const _Eyebrow(
            icon: Icons.auto_awesome_rounded,
            label: 'CONFIGURACIÓN RÁPIDA · 2 MIN',
          ),
          const SizedBox(height: 14),
          Text(
            'Cuéntanos quién eres.\nNosotros ordenamos el resto.',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.w800,
              height: 1.08,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Habla entre 60 y 90 segundos. Crearemos un borrador que podrás '
            'editar antes de publicar tu perfil.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: context.colors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),
          AttraCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Puedes contarnos…',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                const _BriefingPoint(
                  icon: Icons.sentiment_satisfied_alt_rounded,
                  text: 'Cómo eres cuando estás a gusto con alguien.',
                ),
                const _BriefingPoint(
                  icon: Icons.local_activity_outlined,
                  text: 'Qué disfrutas y cómo sería un buen fin de semana.',
                ),
                const _BriefingPoint(
                  icon: Icons.favorite_border_rounded,
                  text: 'Qué valoras y qué te gustaría encontrar.',
                ),
                const _BriefingPoint(
                  icon: Icons.work_outline_rounded,
                  text: 'Tu trabajo o estudios, solo si quieres compartirlo.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.colors.accentSoft,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: context.colors.surfaceLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.graphic_eq_rounded,
                        color: context.colors.accent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Para un audio limpio',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Busca un lugar tranquilo, sin música, deja unos 20 cm entre '
                  'el móvil y tu boca y habla con naturalidad. Evita apellidos, '
                  'teléfono, dirección exacta o redes sociales.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.lock_outline_rounded,
                  size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'La IA procesa el audio una sola vez para crear este borrador. '
                  'No clonamos tu voz: el backend solicita su borrado al '
                  'terminar y limpia cualquier archivo huérfano en el '
                  'siguiente barrido de seguridad.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _showVoicePrivacyDetails,
              icon: const Icon(Icons.info_outline_rounded, size: 18),
              label: const Text('Cómo tratamos este audio'),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 14),
            _InlineError(message: _error!),
          ],
          const SizedBox(height: 24),
          AttraPrimaryButton(
            label: 'Grabar mi historia',
            icon: Icons.mic_rounded,
            loading: _startingRecording,
            onPressed: _startRecording,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: widget.onUseManual,
              child: const Text('Prefiero hacerlo paso a paso'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecording() {
    final ThemeData theme = Theme.of(context);
    final bool canFinish = _elapsed >= _minDuration;
    return LayoutBuilder(
      key: const ValueKey<String>('voice-recording'),
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Column(
                  children: <Widget>[
                    _TopBar(
                      onBack: () => _cancelRecording(),
                      trailingLabel: 'Cancelar',
                      onTrailing: () => _cancelRecording(),
                    ),
                    const Spacer(),
                    Text(
                      'Te escuchamos',
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        _recordingPromptFor(_elapsed),
                        key: ValueKey<int>(_elapsed.inSeconds ~/ 15),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: context.colors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                    _VoiceOrb(
                      controller: _pulseController,
                      active: true,
                    ),
                    const SizedBox(height: 26),
                    Text(
                      '${_formatDuration(_elapsed)} / ${_formatDuration(_maxDuration)}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      canFinish
                          ? 'Cuando quieras, ya tenemos suficiente.'
                          : 'Habla al menos 12 segundos.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const Spacer(),
                    AttraPrimaryButton(
                      label: 'Terminar de grabar',
                      icon: Icons.stop_rounded,
                      loading: _stoppingRecording,
                      onPressed: canFinish ? _finishRecording : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecorded() {
    final ThemeData theme = Theme.of(context);
    final bool canGenerate = _elapsed >= _minDuration;
    return SingleChildScrollView(
      key: const ValueKey<String>('voice-recorded'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _TopBar(
            onBack: () => _cancelRecording(),
            trailingLabel: 'Paso a paso',
            onTrailing: widget.onUseManual,
          ),
          const SizedBox(height: 48),
          Center(
            child: _VoiceOrb(
              controller: _pulseController,
              active: _playing,
              icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              onTap: _togglePlayback,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Tu audio está listo',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '${_formatDuration(_elapsed)} · Escúchalo si quieres antes de enviarlo.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 20),
            _InlineError(message: _error!),
          ],
          const SizedBox(height: 32),
          AttraPrimaryButton(
            label: _suggestion == null
                ? 'Crear mi borrador'
                : 'Volver a mi borrador',
            icon: _suggestion == null
                ? Icons.auto_awesome_rounded
                : Icons.edit_note_rounded,
            onPressed: canGenerate
                ? _suggestion == null
                    ? _generate
                    : () => setState(() {
                          _phase = _VoicePhase.review;
                          _error = null;
                        })
                : null,
          ),
          const SizedBox(height: 10),
          AttraGhostButton(
            label: 'Volver a grabar',
            icon: Icons.replay_rounded,
            onPressed: () => _cancelRecording(),
          ),
          const SizedBox(height: 18),
          Text(
            'Al continuar aceptas el procesamiento puntual de este audio para '
            'generar tu borrador. Nada se publicará todavía.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessing() {
    final ThemeData theme = Theme.of(context);
    return LayoutBuilder(
      key: const ValueKey<String>('voice-processing'),
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const SizedBox(
                      width: 58,
                      height: 58,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(height: 30),
                    Text(
                      'Creando algo que suene a ti',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _processingCopy[_processingCopyIndex],
                        key: ValueKey<int>(_processingCopyIndex),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: context.colors.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                        border: Border.all(color: context.colors.surfaceLine),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.visibility_off_outlined,
                            size: 18,
                            color: context.colors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'No inferimos datos sensibles',
                              style: theme.textTheme.bodySmall,
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
      },
    );
  }

  Widget _buildReview() {
    final ThemeData theme = Theme.of(context);
    final VoiceProfileSuggestion suggestion = _suggestion!;
    return SingleChildScrollView(
      key: const ValueKey<String>('voice-review'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _TopBar(
            onBack: () => setState(() => _phase = _VoicePhase.recorded),
            trailingLabel: 'Repetir audio',
            onTrailing: () => _cancelRecording(),
          ),
          const SizedBox(height: 24),
          const _Eyebrow(
            icon: Icons.edit_note_rounded,
            label: 'BORRADOR EDITABLE',
          ),
          const SizedBox(height: 12),
          Text(
            'Esto es lo que hemos entendido de ti',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800, height: 1.15),
          ),
          const SizedBox(height: 8),
          Text(
            'Léelo con calma y cambia lo que quieras. Nada se publica hasta '
            'que termines el alta.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: context.colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          AttraCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.format_quote_rounded,
                        color: context.colors.accent),
                    const SizedBox(width: 8),
                    Text('Tu bio', style: theme.textTheme.titleMedium),
                    const Spacer(),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _bioController,
                      builder: (_, TextEditingValue value, __) => Text(
                        '${value.text.length}/240',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bioController,
                  minLines: 4,
                  maxLines: 7,
                  maxLength: 240,
                  buildCounter: (_,
                          {required int currentLength,
                          required bool isFocused,
                          required int? maxLength}) =>
                      null,
                  decoration: const InputDecoration(
                    hintText: 'Escribe una bio que te represente…',
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AttraCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Tu energía',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  'Toca para añadir o quitar. Solo usamos opciones que hayas mencionado.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: VoiceProfileSuggestion.personalityTagValues
                      .map((String value) => FilterChip(
                            label: Text(_personalityLabels[value] ?? value),
                            selected: _personalityTags.contains(value),
                            onSelected: (bool selected) {
                              setState(() {
                                if (selected) {
                                  _personalityTags.add(value);
                                } else {
                                  _personalityTags.remove(value);
                                }
                              });
                            },
                          ))
                      .toList(growable: false),
                ),
                const SizedBox(height: 18),
                Text('Tu estilo',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: VoiceProfileSuggestion.fashionStyleValues
                      .map((String value) => FilterChip(
                            label: Text(_fashionLabels[value] ?? value),
                            selected: _fashionStyle.contains(value),
                            onSelected: (bool selected) {
                              setState(() {
                                if (selected) {
                                  _fashionStyle.add(value);
                                } else {
                                  _fashionStyle.remove(value);
                                }
                              });
                            },
                          ))
                      .toList(growable: false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AttraCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Detalles que entendimos',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                TextField(
                  controller: _jobController,
                  decoration: const InputDecoration(
                    labelText: 'Trabajo (opcional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _companyController,
                  decoration: const InputDecoration(
                    labelText: 'Empresa (opcional)',
                  ),
                ),
                if (_isRomantic) ...<Widget>[
                  const SizedBox(height: 12),
                  _enumDropdown(
                    label: 'Qué buscas',
                    current: _relationshipIntent,
                    values: _relationshipIntentLabels,
                    onChanged: (String value) =>
                        setState(() => _relationshipIntent = value),
                  ),
                ],
                const SizedBox(height: 12),
                _enumDropdown(
                  label: 'Estilo social',
                  current: _socialStyle,
                  values: _socialLabels,
                  onChanged: (String value) =>
                      setState(() => _socialStyle = value),
                ),
                const SizedBox(height: 12),
                _enumDropdown(
                  label: 'Forma de viajar',
                  current: _travelStyle,
                  values: _travelLabels,
                  onChanged: (String value) =>
                      setState(() => _travelStyle = value),
                ),
                const SizedBox(height: 12),
                _enumDropdown(
                  label: 'Actividad',
                  current: _fitnessLevel,
                  values: _fitnessLabels,
                  onChanged: (String value) =>
                      setState(() => _fitnessLevel = value),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _enumDropdown(
                        label: 'Tabaco',
                        current: _smoking,
                        values: _smokingLabels,
                        onChanged: (String value) =>
                            setState(() => _smoking = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _enumDropdown(
                        label: 'Alcohol',
                        current: _drinking,
                        values: _drinkingLabels,
                        onChanged: (String value) =>
                            setState(() => _drinking = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _enumDropdown(
                  label: 'Hijos en el futuro',
                  current: _wantsChildren,
                  values: _wantsChildrenLabels,
                  onChanged: (String value) =>
                      setState(() => _wantsChildren = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AttraCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Puntos de conversación',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (_promptQuestionControllers.length < kMaxActivePrompts)
                      IconButton(
                        tooltip: 'Añadir pregunta',
                        onPressed: _addPrompt,
                        icon: const Icon(Icons.add_rounded),
                      ),
                  ],
                ),
                if (_promptQuestionControllers.isEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    'No hemos inventado ninguno. Puedes añadirlos aquí o más tarde.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _addPrompt,
                    icon: const Icon(Icons.add_comment_outlined),
                    label: const Text('Añadir una pregunta'),
                  ),
                ] else
                  for (int i = 0;
                      i < _promptQuestionControllers.length;
                      i++) ...<Widget>[
                    if (i > 0) const Divider(height: 28),
                    Row(
                      children: <Widget>[
                        Text('Pregunta ${i + 1}',
                            style: theme.textTheme.labelLarge),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Quitar pregunta ${i + 1}',
                          onPressed: () => _removePrompt(i),
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 20),
                        ),
                      ],
                    ),
                    TextField(
                      controller: _promptQuestionControllers[i],
                      maxLength: kMaxPromptQuestionChars,
                      decoration:
                          const InputDecoration(labelText: 'La pregunta'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _promptAnswerControllers[i],
                      minLines: 2,
                      maxLines: 4,
                      maxLength: kMaxPromptAnswerChars,
                      decoration:
                          const InputDecoration(labelText: 'Tu respuesta'),
                    ),
                  ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          AttraCard(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              leading: const Icon(Icons.subject_rounded),
              title: const Text('Lo que entendimos del audio'),
              subtitle: const Text('Revisa la transcripción si algo no encaja'),
              childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              children: <Widget>[
                SelectableText(
                  suggestion.transcript.isEmpty
                      ? 'No hay transcripción disponible.'
                      : suggestion.transcript,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border:
                  Border.all(color: AppColors.success.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.verified_user_outlined,
                    color: AppColors.success, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No vamos a adivinar tu edad, género, aspecto, ubicación u '
                    'orientación. Te pediremos después solo los datos necesarios.',
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 14),
            _InlineError(message: _error!),
          ],
          const SizedBox(height: 24),
          AttraPrimaryButton(
            label: 'Usar este borrador',
            icon: Icons.arrow_forward_rounded,
            loading: _accepting,
            onPressed: _accepting ? null : _acceptReview,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _accepting ? null : widget.onUseManual,
              child: const Text('Descartar y hacerlo paso a paso'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _enumDropdown({
    required String label,
    required String current,
    required Map<String, String> values,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: current.isEmpty ? null : current,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      hint: const Text('No indicado'),
      items: <DropdownMenuItem<String>>[
        const DropdownMenuItem<String>(
          value: '',
          child: Text('No indicado'),
        ),
        ...values.entries.map(
          (MapEntry<String, String> entry) => DropdownMenuItem<String>(
            value: entry.key,
            child: Text(entry.value),
          ),
        ),
      ],
      onChanged: (String? value) => onChanged(value ?? ''),
    );
  }

  bool get _isRomantic =>
      widget.intentMode == 'dating' || widget.intentMode == 'both';

  static String _formatDuration(Duration duration) {
    final int minutes = duration.inMinutes;
    final int seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static String _recordingPromptFor(Duration elapsed) {
    final int bucket = elapsed.inSeconds ~/ 15;
    const List<String> prompts = <String>[
      'Empieza por cómo te describiría alguien que te conoce bien.',
      '¿Qué te gusta hacer cuando tienes tiempo para ti?',
      '¿Cómo sería un buen fin de semana contigo?',
      '¿Qué valoras cuando conectas con alguien?',
      '¿Qué te gustaría encontrar en esta etapa?',
      'Cierra con algún detalle pequeño que sea muy tuyo.',
    ];
    return prompts[bucket.clamp(0, prompts.length - 1)];
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onBack,
    required this.trailingLabel,
    required this.onTrailing,
  });

  final VoidCallback onBack;
  final String trailingLabel;
  final VoidCallback onTrailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton(
          onPressed: onBack,
          tooltip: 'Atrás',
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const Spacer(),
        Flexible(
          child: TextButton(
            onPressed: onTrailing,
            child: Text(
              trailingLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ),
      ],
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: context.colors.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.colors.accent,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
          ),
        ),
      ],
    );
  }
}

class _BriefingPoint extends StatelessWidget {
  const _BriefingPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: context.colors.accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: context.colors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(height: 1.35)),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceOrb extends StatelessWidget {
  const _VoiceOrb({
    required this.controller,
    required this.active,
    this.icon = Icons.mic_rounded,
    this.onTap,
  });

  final AnimationController controller;
  final bool active;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        final double t = active && !reduceMotion ? controller.value : 0.35;
        final double haloSize = 132 + (t * 18);
        return SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: haloSize,
                height: haloSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      context.colors.accent.withValues(alpha: 0.08 + t * 0.05),
                ),
              ),
              Material(
                color: context.colors.accent,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: onTap,
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 92,
                    height: 92,
                    child: Icon(icon, size: 38, color: context.colors.onAccent),
                  ),
                ),
              ),
              if (active)
                Positioned(
                  bottom: 6,
                  child: Row(
                    children: List<Widget>.generate(9, (int index) {
                      final double wave = reduceMotion
                          ? 0.5
                          : (math.sin((index * 0.8) + t * math.pi * 2) + 1) / 2;
                      return AnimatedContainer(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 100),
                        width: 3,
                        height: 5 + wave * 12,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: context.colors.accent,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PrivacyDetail extends StatelessWidget {
  const _PrivacyDetail({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.colors.accentSoft,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Icon(icon, size: 20, color: context.colors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline_rounded,
              size: 19, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style:
                  Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

const Map<String, String> _relationshipIntentLabels = <String, String>{
  'serious_relationship': 'Una relación seria',
  'meet_people': 'Conocer gente sin prisa',
  'casual': 'Algo casual',
  'open_to_see': 'Abierto/a a ver qué surge',
};
const Map<String, String> _smokingLabels = <String, String>{
  'never': 'Nunca',
  'occasionally': 'A veces',
  'frequently': 'Frecuente',
};
const Map<String, String> _drinkingLabels = <String, String>{
  'never': 'Nunca',
  'socially': 'Socialmente',
  'frequently': 'Frecuente',
};
const Map<String, String> _fitnessLabels = <String, String>{
  'low': 'Tranquila',
  'medium': 'Equilibrada',
  'high': 'Muy activa',
};
const Map<String, String> _wantsChildrenLabels = <String, String>{
  'yes': 'Sí',
  'no': 'No',
  'maybe': 'Quizá',
};
const Map<String, String> _socialLabels = <String, String>{
  'calm': 'Plan tranquilo',
  'balanced': 'Un poco de todo',
  'very_social': 'Muy social',
};
const Map<String, String> _travelLabels = <String, String>{
  'homebody': 'Disfrutar de casa',
  'weekend_getaways': 'Escapadas',
  'adventurous': 'Aventura',
};
const Map<String, String> _fashionLabels = <String, String>{
  'casual': 'Casual',
  'elegant': 'Elegante',
  'urban': 'Urbano',
  'sporty': 'Deportivo',
  'minimalist': 'Minimalista',
};
const Map<String, String> _personalityLabels = <String, String>{
  'ambitious': 'Con iniciativa',
  'empathetic': 'Empático/a',
  'fun': 'Divertido/a',
  'creative': 'Creativo/a',
  'calm': 'Tranquilo/a',
  'intense': 'Intenso/a',
};
