/// Prompts de perfil (Attra Prompts): el usuario elige una pregunta (del
/// catálogo o propia), la responde y la respuesta aparece en su perfil público.
///
/// Persistencia: `users/{uid}.profilePrompts` (array de mapas). Se espeja un
/// resumen en `profile.prompts` (strings) para no romper el cálculo de
/// completitud legacy.
library;

/// Límite de prompts ACTIVOS visibles en el perfil (free). Plus/Pro podrán
/// ampliar en el futuro (dejar el parámetro, no activar premium aquí).
const int kMaxActivePrompts = 3;

/// Límites de caracteres.
const int kMaxPromptQuestionChars = 90; // pregunta personalizada
const int kMaxPromptAnswerChars = 180;

class ProfilePrompt {
  const ProfilePrompt({
    required this.id,
    required this.question,
    required this.answer,
    this.promptId,
    this.category = 'custom',
    this.isCustom = false,
    this.order = 0,
    this.isActive = true,
    this.createdAtIso,
    this.updatedAtIso,
  });

  final String id;

  /// Id del catálogo (null si es pregunta personalizada).
  final String? promptId;
  final String question;
  final String answer;
  final String category;
  final bool isCustom;
  final int order;
  final bool isActive;
  final String? createdAtIso;
  final String? updatedAtIso;

  factory ProfilePrompt.fromMap(Map<String, dynamic> map) {
    return ProfilePrompt(
      id: (map['id'] as String?) ?? '',
      promptId: map['promptId'] as String?,
      question: (map['question'] as String?) ?? '',
      answer: (map['answer'] as String?) ?? '',
      category: (map['category'] as String?) ?? 'custom',
      isCustom: (map['isCustom'] as bool?) ?? false,
      order: (map['order'] as num?)?.toInt() ?? 0,
      isActive: (map['isActive'] as bool?) ?? true,
      createdAtIso: map['createdAt']?.toString(),
      updatedAtIso: map['updatedAt']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'promptId': promptId,
      'question': question,
      'answer': answer,
      'category': category,
      'isCustom': isCustom,
      'order': order,
      'isActive': isActive,
      'createdAt': createdAtIso,
      'updatedAt': updatedAtIso,
    };
  }

  ProfilePrompt copyWith({
    String? id,
    String? promptId,
    String? question,
    String? answer,
    String? category,
    bool? isCustom,
    int? order,
    bool? isActive,
    String? createdAtIso,
    String? updatedAtIso,
  }) {
    return ProfilePrompt(
      id: id ?? this.id,
      promptId: promptId ?? this.promptId,
      question: question ?? this.question,
      answer: answer ?? this.answer,
      category: category ?? this.category,
      isCustom: isCustom ?? this.isCustom,
      order: order ?? this.order,
      isActive: isActive ?? this.isActive,
      createdAtIso: createdAtIso ?? this.createdAtIso,
      updatedAtIso: updatedAtIso ?? this.updatedAtIso,
    );
  }
}

/// Validación de prompts (pura, testeable). Devuelve null si es válido o el
/// mensaje de error a mostrar.
class ProfilePromptValidator {
  const ProfilePromptValidator._();

  static final RegExp _contactInfo = RegExp(
    r'(https?://|www\.)|([\w.+-]+@[\w-]+\.[a-z]{2,})|(\+?\d[\d\s.-]{7,})',
    caseSensitive: false,
  );

  // Filtro básico; la moderación fuerte vive en backend (moderation.ts).
  static final RegExp _offensive = RegExp(
    r'\b(puta|puto|gilipollas|cabr[oó]n|mierda|nazi)\b',
    caseSensitive: false,
  );

  /// Normaliza: trim + colapsa espacios múltiples.
  static String normalize(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String? validateAnswer(String raw) {
    final String text = normalize(raw);
    if (text.isEmpty) return 'La respuesta no puede estar vacía.';
    if (text.length > kMaxPromptAnswerChars) {
      return 'Máximo $kMaxPromptAnswerChars caracteres.';
    }
    if (_contactInfo.hasMatch(text)) {
      return 'Evita compartir datos personales o enlaces.';
    }
    if (_offensive.hasMatch(text)) {
      return 'Esa respuesta no cumple nuestras normas.';
    }
    return null;
  }

  static String? validateCustomQuestion(String raw) {
    final String text = normalize(raw);
    if (text.isEmpty) return 'La pregunta no puede estar vacía.';
    if (text.length > kMaxPromptQuestionChars) {
      return 'Máximo $kMaxPromptQuestionChars caracteres.';
    }
    if (_contactInfo.hasMatch(text)) {
      return 'Evita compartir datos personales o enlaces.';
    }
    if (_offensive.hasMatch(text)) {
      return 'Esa pregunta no cumple nuestras normas.';
    }
    return null;
  }

  /// Valida la lista completa antes de guardar: máximo activos y sin preguntas
  /// duplicadas.
  static String? validateList(List<ProfilePrompt> prompts) {
    final int active = prompts.where((ProfilePrompt p) => p.isActive).length;
    if (active > kMaxActivePrompts) {
      return 'Máximo $kMaxActivePrompts preguntas activas.';
    }
    final Set<String> seen = <String>{};
    for (final ProfilePrompt p in prompts) {
      final String key = normalize(p.question).toLowerCase();
      if (!seen.add(key)) return 'No puedes repetir esta pregunta.';
    }
    return null;
  }
}
