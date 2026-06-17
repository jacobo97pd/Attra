import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_backgrounds.dart';
import '../../../widgets/attra_buttons.dart';
import '../../../widgets/attra_states.dart';
import '../domain/profile_prompt.dart';
import '../domain/profile_prompt_catalog.dart';

/// Flag para la futura mejora de respuestas con IA (Pro). Oculto hasta que el
/// servicio exista; al activarse mostrará el botón "Mejorar con IA".
const bool kPromptsAiImproveEnabled = false;

/// Editor de "Preguntas de perfil" (Attra Prompts): elegir pregunta del
/// catálogo o crear una propia, responder, editar, eliminar y reordenar.
/// Máximo [kMaxActivePrompts] activas en el perfil.
class ProfilePromptsEditorScreen extends StatefulWidget {
  const ProfilePromptsEditorScreen({
    super.key,
    required this.loadPrompts,
    required this.savePrompts,
  });

  final Future<List<ProfilePrompt>> Function() loadPrompts;
  final Future<void> Function(List<ProfilePrompt> prompts) savePrompts;

  @override
  State<ProfilePromptsEditorScreen> createState() =>
      _ProfilePromptsEditorScreenState();
}

class _ProfilePromptsEditorScreenState
    extends State<ProfilePromptsEditorScreen> {
  List<ProfilePrompt> _prompts = <ProfilePrompt>[];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<ProfilePrompt> prompts = await widget.loadPrompts();
    if (!mounted) return;
    setState(() {
      _prompts = prompts;
      _loading = false;
    });
  }

  Future<void> _persist(List<ProfilePrompt> updated) async {
    final String? error = ProfilePromptValidator.validateList(updated);
    if (error != null) {
      _snack(error);
      return;
    }
    setState(() {
      _prompts = updated;
      _saving = true;
    });
    try {
      await widget.savePrompts(updated);
    } catch (_) {
      _snack('No se pudo guardar. Inténtalo de nuevo.');
      await _reload();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  bool get _canAddMore =>
      _prompts.where((ProfilePrompt p) => p.isActive).length <
      kMaxActivePrompts;

  // --- Flujos ---------------------------------------------------------------

  Future<void> _addFromCatalog() async {
    final CatalogPrompt? picked = await _PromptPickerSheet.show(
      context,
      usedQuestions: _prompts
          .map((ProfilePrompt p) =>
              ProfilePromptValidator.normalize(p.question).toLowerCase())
          .toSet(),
    );
    if (picked == null || !mounted) return;
    final String? answer = await _AnswerEditorSheet.show(
      context,
      question: picked.question,
    );
    if (answer == null || !mounted) return;
    final String now = DateTime.now().toIso8601String();
    await _persist(<ProfilePrompt>[
      ..._prompts,
      ProfilePrompt(
        id: 'p_${DateTime.now().millisecondsSinceEpoch}',
        promptId: picked.id,
        question: picked.question,
        answer: answer,
        category: picked.category,
        order: _prompts.length,
        createdAtIso: now,
        updatedAtIso: now,
      ),
    ]);
  }

  Future<void> _addCustom() async {
    final ({String question, String answer})? result =
        await _CustomPromptSheet.show(context);
    if (result == null || !mounted) return;
    final String now = DateTime.now().toIso8601String();
    await _persist(<ProfilePrompt>[
      ..._prompts,
      ProfilePrompt(
        id: 'p_${DateTime.now().millisecondsSinceEpoch}',
        question: result.question,
        answer: result.answer,
        category: 'custom',
        isCustom: true,
        order: _prompts.length,
        createdAtIso: now,
        updatedAtIso: now,
      ),
    ]);
  }

  Future<void> _edit(ProfilePrompt prompt) async {
    final String? answer = await _AnswerEditorSheet.show(
      context,
      question: prompt.question,
      initialAnswer: prompt.answer,
    );
    if (answer == null || !mounted) return;
    await _persist(_prompts
        .map((ProfilePrompt p) => p.id == prompt.id
            ? p.copyWith(
                answer: answer,
                updatedAtIso: DateTime.now().toIso8601String())
            : p)
        .toList(growable: false));
  }

  Future<void> _delete(ProfilePrompt prompt) async {
    await _persist(_prompts
        .where((ProfilePrompt p) => p.id != prompt.id)
        .toList(growable: false));
  }

  Future<void> _move(int index, int delta) async {
    final int target = index + delta;
    if (target < 0 || target >= _prompts.length) return;
    final List<ProfilePrompt> updated = <ProfilePrompt>[..._prompts];
    final ProfilePrompt moved = updated.removeAt(index);
    updated.insert(target, moved);
    await _persist(updated);
  }

  // --- UI ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preguntas de perfil'),
        actions: <Widget>[
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.lg),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: AppSpacing.screen,
              children: <Widget>[
                Text(
                  'Añade respuestas que ayuden a empezar una conversación.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Máximo $kMaxActivePrompts preguntas activas. Aparecerán en tu perfil.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_prompts.isEmpty)
                  const AttraEmptyState(
                    icon: Icons.chat_bubble_outline,
                    title: 'Tu perfil habla poco',
                    message:
                        'Añade una respuesta para que tu perfil no parezca un contrato de alquiler.',
                  )
                else
                  for (int i = 0; i < _prompts.length; i++) ...<Widget>[
                    _PromptEditCard(
                      prompt: _prompts[i],
                      onEdit: () => _edit(_prompts[i]),
                      onDelete: () => _delete(_prompts[i]),
                      onUp: i > 0 ? () => _move(i, -1) : null,
                      onDown:
                          i < _prompts.length - 1 ? () => _move(i, 1) : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                const SizedBox(height: AppSpacing.sm),
                AttraPrimaryButton(
                  label: 'Añadir pregunta',
                  icon: Icons.add,
                  onPressed: _canAddMore && !_saving ? _addFromCatalog : null,
                ),
                const SizedBox(height: AppSpacing.md),
                AttraGhostButton(
                  label: 'Crear mi propia pregunta',
                  icon: Icons.edit_outlined,
                  onPressed: _canAddMore && !_saving ? _addCustom : null,
                ),
                if (!_canAddMore)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Text(
                      'Has llegado al máximo de $kMaxActivePrompts. Elimina una para añadir otra.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Card de un prompt en el editor: pregunta pequeña, respuesta protagonista,
/// acciones de editar/eliminar/reordenar.
class _PromptEditCard extends StatelessWidget {
  const _PromptEditCard({
    required this.prompt,
    required this.onEdit,
    required this.onDelete,
    this.onUp,
    this.onDown,
  });

  final ProfilePrompt prompt;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AttraCard(
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  prompt.question,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(letterSpacing: 0.3),
                ),
              ),
              if (prompt.isCustom)
                const Icon(Icons.draw_outlined,
                    size: 14, color: AppColors.textMuted),
            ],
          ),
          const SizedBox(height: 6),
          Text(prompt.answer,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700, height: 1.3)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Subir',
                icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                onPressed: onUp,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Bajar',
                icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                onPressed: onDown,
              ),
              const Spacer(),
              TextButton(onPressed: onEdit, child: const Text('Editar')),
              TextButton(
                onPressed: onDelete,
                child: const Text('Eliminar',
                    style: TextStyle(color: AppColors.danger)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Selector de preguntas del catálogo: chips de categoría + buscador + lista.
class _PromptPickerSheet extends StatefulWidget {
  const _PromptPickerSheet({required this.usedQuestions});

  final Set<String> usedQuestions;

  static Future<CatalogPrompt?> show(BuildContext context,
      {required Set<String> usedQuestions}) {
    return showModalBottomSheet<CatalogPrompt>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PromptPickerSheet(usedQuestions: usedQuestions),
    );
  }

  @override
  State<_PromptPickerSheet> createState() => _PromptPickerSheetState();
}

class _PromptPickerSheetState extends State<_PromptPickerSheet> {
  String _category = ProfilePromptCatalog.categories.first.key;
  String _query = '';

  List<CatalogPrompt> get _visible {
    final List<CatalogPrompt> base = _query.trim().isNotEmpty
        ? ProfilePromptCatalog.search(_query)
        : ProfilePromptCatalog.byCategory(_category);
    return base
        .where((CatalogPrompt p) => !widget.usedQuestions
            .contains(ProfilePromptValidator.normalize(p.question).toLowerCase()))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<CatalogPrompt> visible = _visible;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.82,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding:
                const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 0),
            child: Text('Elige una pregunta',
                style: theme.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar pregunta…',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
              ),
              onChanged: (String v) => setState(() => _query = v),
            ),
          ),
          if (_query.trim().isEmpty)
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: ProfilePromptCatalog.categories.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (BuildContext context, int i) {
                  final PromptCategory c =
                      ProfilePromptCatalog.categories[i];
                  return ChoiceChip(
                    label: Text(c.label),
                    selected: _category == c.key,
                    onSelected: (_) => setState(() => _category = c.key),
                  );
                },
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text('No hay preguntas disponibles aquí.',
                        style: theme.textTheme.bodyMedium))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
                    itemCount: visible.length,
                    itemBuilder: (BuildContext context, int i) {
                      final CatalogPrompt p = visible[i];
                      return Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: AttraCard(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.md),
                          onTap: () => Navigator.of(context).pop(p),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                  child: Text(p.question,
                                      style: theme.textTheme.bodyLarge)),
                              const Icon(Icons.chevron_right,
                                  size: 20, color: AppColors.textMuted),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Editor de respuesta: pregunta fija arriba, respuesta con contador y vista
/// previa en tiempo real de cómo quedará la card en el perfil.
class _AnswerEditorSheet extends StatefulWidget {
  const _AnswerEditorSheet({required this.question, this.initialAnswer});

  final String question;
  final String? initialAnswer;

  static Future<String?> show(BuildContext context,
      {required String question, String? initialAnswer}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _AnswerEditorSheet(question: question, initialAnswer: initialAnswer),
    );
  }

  @override
  State<_AnswerEditorSheet> createState() => _AnswerEditorSheetState();
}

class _AnswerEditorSheetState extends State<_AnswerEditorSheet> {
  late final TextEditingController _answer =
      TextEditingController(text: widget.initialAnswer ?? '');
  String? _error;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  void _save() {
    final String? error = ProfilePromptValidator.validateAnswer(_answer.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(ProfilePromptValidator.normalize(_answer.text));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int remaining = kMaxPromptAnswerChars - _answer.text.length;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Escribe tu respuesta', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Esta respuesta aparecerá en tu perfil.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.lg),
          // Vista previa en tiempo real.
          AttraCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(widget.question, style: theme.textTheme.bodySmall),
                const SizedBox(height: 6),
                Text(
                  _answer.text.trim().isEmpty
                      ? 'Tu respuesta…'
                      : _answer.text.trim(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _answer.text.trim().isEmpty
                        ? AppColors.textMuted
                        : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _answer,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            maxLength: kMaxPromptAnswerChars,
            buildCounter: (_,
                    {required int currentLength,
                    required bool isFocused,
                    int? maxLength}) =>
                Text('$remaining',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: remaining < 0
                            ? AppColors.danger
                            : AppColors.textMuted)),
            decoration: InputDecoration(
              hintText: 'Escribe tu respuesta',
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: AppSpacing.md),
          if (kPromptsAiImproveEnabled)
            AttraGhostButton(
              label: 'Mejorar con IA',
              icon: Icons.auto_awesome,
              onPressed: () {}, // futura llamada al servicio de IA (Pro)
            ),
          AttraPrimaryButton(label: 'Guardar', onPressed: _save),
        ],
      ),
    );
  }
}

/// Creación de pregunta personalizada: pregunta + respuesta en un solo flujo.
class _CustomPromptSheet extends StatefulWidget {
  const _CustomPromptSheet();

  static Future<({String question, String answer})?> show(
      BuildContext context) {
    return showModalBottomSheet<({String question, String answer})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CustomPromptSheet(),
    );
  }

  @override
  State<_CustomPromptSheet> createState() => _CustomPromptSheetState();
}

class _CustomPromptSheetState extends State<_CustomPromptSheet> {
  final TextEditingController _question = TextEditingController();
  final TextEditingController _answer = TextEditingController();
  String? _questionError;
  String? _answerError;

  @override
  void dispose() {
    _question.dispose();
    _answer.dispose();
    super.dispose();
  }

  void _save() {
    final String? qError =
        ProfilePromptValidator.validateCustomQuestion(_question.text);
    final String? aError = ProfilePromptValidator.validateAnswer(_answer.text);
    if (qError != null || aError != null) {
      setState(() {
        _questionError = qError;
        _answerError = aError;
      });
      return;
    }
    Navigator.of(context).pop((
      question: ProfilePromptValidator.normalize(_question.text),
      answer: ProfilePromptValidator.normalize(_answer.text),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Crea tu propia pregunta', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Hazla tuya: corta, con personalidad y fácil de responder.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _question,
            autofocus: true,
            maxLength: kMaxPromptQuestionChars,
            decoration: InputDecoration(
              labelText: 'Tu pregunta',
              hintText: 'Ej: Mi tradición favorita es…',
              errorText: _questionError,
            ),
            onChanged: (_) => setState(() => _questionError = null),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _answer,
            minLines: 2,
            maxLines: 4,
            maxLength: kMaxPromptAnswerChars,
            decoration: InputDecoration(
              labelText: 'Escribe tu respuesta',
              errorText: _answerError,
            ),
            onChanged: (_) => setState(() => _answerError = null),
          ),
          const SizedBox(height: AppSpacing.md),
          AttraPrimaryButton(label: 'Guardar', onPressed: _save),
        ],
      ),
    );
  }
}
