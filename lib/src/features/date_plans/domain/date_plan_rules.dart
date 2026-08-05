// Attra Plans — reglas PURAS de generación (sin IA ni red). Deciden qué TIPO de
// plan encaja a partir de intereses de perfil + señales del chat, y qué lugares
// son aceptables. La Cloud Function `generateDatePlanSuggestions` refleja esta
// misma lógica en TS (patrón "espejo Dart↔TS", como las plantillas de
// notificaciones). Al vivir aquí también, es testeable y reutilizable por el
// cliente (p. ej. fallback local si el backend no está disponible).
//
// La IA (Fase 3) sustituirá/afinará `extractCommonInterests` y
// `recommendedPlanTypes`, pero el contrato se mantiene.

/// Umbral mínimo de mensajes "reales" para sugerir un plan (espejo de
/// CONVERSATION_THRESHOLD en el backend). Menos que esto = aún no proponer.
const int kMinConversationForPlan = 6;

/// Rating mínimo aceptable de un lugar cuando el dato está disponible.
const double kMinPlaceRating = 4.1;

/// Nº mínimo de reseñas para fiarnos del rating (evita sitios con 1-2 reseñas).
const int kMinPlaceReviews = 30;

/// Categorías de plan que entiende el motor. `safe`/`social`/`differential`
/// marcan a qué "carril" de propuesta pertenece cada una (plan seguro, social,
/// diferencial) para poder ofrecer siempre 3 opciones variadas.
enum PlanCategory {
  cafe('cafe', PlanTier.safe),
  paseo('paseo', PlanTier.safe),
  helado('helado', PlanTier.safe),
  comida('comida', PlanTier.social),
  copas('copas', PlanTier.social),
  cultura('cultura', PlanTier.differential),
  musica('musica', PlanTier.differential);

  const PlanCategory(this.key, this.tier);
  final String key;
  final PlanTier tier;
}

enum PlanTier { safe, social, differential }

/// Palabras clave (minúsculas, sin tildes) que delatan interés por cada
/// categoría, en perfil o conversación. ES + algo de EN.
const Map<PlanCategory, List<String>> _keywords = <PlanCategory, List<String>>{
  PlanCategory.cafe: <String>[
    'cafe',
    'cafeteria',
    'coffee',
    'te',
    'chocolate',
    'tomar algo',
    'merendar'
  ],
  PlanCategory.paseo: <String>[
    'pasear',
    'paseo',
    'andar',
    'caminar',
    'parque',
    'naturaleza',
    'walk',
    'senderismo',
    'aire libre',
    'playa',
    'monte'
  ],
  PlanCategory.helado: <String>['helado', 'heladeria', 'ice cream'],
  PlanCategory.comida: <String>[
    'comer',
    'comida',
    'cena',
    'cenar',
    'restaurante',
    'tapas',
    'food',
    'dinner',
    'lunch',
    'brunch',
    'sushi',
    'pizza',
    'hamburguesa'
  ],
  PlanCategory.copas: <String>[
    'copa',
    'copas',
    'bar',
    'cerveza',
    'vino',
    'cocktail',
    'coctel',
    'terraza',
    'fiesta',
    'drink',
    'vermut'
  ],
  PlanCategory.cultura: <String>[
    'museo',
    'expo',
    'exposicion',
    'arte',
    'cultura',
    'teatro',
    'cine',
    'libro',
    'lectura',
    'museum',
    'galeria',
    'historia'
  ],
  PlanCategory.musica: <String>[
    'musica',
    'concierto',
    'directo',
    'banda',
    'dj',
    'festival',
    'vinilo',
    'guitarra',
    'cantar',
    'karaoke',
    'music',
    'gig'
  ],
};

/// Normaliza texto para el matching: minúsculas + sin tildes.
String _norm(String s) {
  final String lower = s.toLowerCase();
  const Map<String, String> map = <String, String>{
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
  };
  final StringBuffer b = StringBuffer();
  for (final int r in lower.runes) {
    final String ch = String.fromCharCode(r);
    b.write(map[ch] ?? ch);
  }
  return b.toString();
}

/// Motor de reglas de Attra Plans (todo estático/puro).
class DatePlanRules {
  const DatePlanRules._();

  /// ¿Hay conversación suficiente para proponer un plan?
  static bool hasEnoughConversation(int realMessageCount) =>
      realMessageCount >= kMinConversationForPlan;

  /// Una zona es válida si es texto no vacío y razonable (no coordenadas ni
  /// basura). No valida contra un catálogo: solo forma.
  static bool isValidZone(String? zone) {
    final String z = (zone ?? '').trim();
    if (z.length < 2 || z.length > 80) return false;
    // Rechaza algo que parezca "lat,lng" (no queremos ubicación exacta).
    if (RegExp(r'^-?\d+\.\d+\s*,\s*-?\d+\.\d+$').hasMatch(z)) return false;
    return true;
  }

  /// Extrae categorías de interés COMÚN a partir de los intereses declarados de
  /// ambos + fragmentos del chat. Una categoría cuenta si aparece en ambos
  /// perfiles, o en un perfil + el chat, o solo en el chat (señal fuerte).
  /// Devuelve las categorías ordenadas por relevancia (más señales primero).
  static List<PlanCategory> commonCategories({
    required List<String> aInterests,
    required List<String> bInterests,
    required List<String> chatMessages,
  }) {
    final String aText = aInterests.map(_norm).join(' ');
    final String bText = bInterests.map(_norm).join(' ');
    final String chatText = chatMessages.map(_norm).join(' ');

    final Map<PlanCategory, int> score = <PlanCategory, int>{};
    for (final PlanCategory cat in PlanCategory.values) {
      final List<String> kws = _keywords[cat] ?? const <String>[];
      final bool inA = kws.any((String k) => aText.contains(k));
      final bool inB = kws.any((String k) => bText.contains(k));
      final bool inChat = kws.any((String k) => chatText.contains(k));
      int s = 0;
      if (inA && inB) s += 3; // interés compartido explícito
      if (inChat) s += 2; // se ha hablado de ello
      if ((inA || inB) && inChat) s += 1;
      if (s > 0) score[cat] = s;
    }
    final List<PlanCategory> ordered = score.keys.toList()
      ..sort(
          (PlanCategory a, PlanCategory b) => score[b]!.compareTo(score[a]!));
    return ordered;
  }

  /// A partir de las categorías comunes, elige hasta 3 tipos de plan cubriendo
  /// carriles distintos (seguro → social → diferencial) para variedad. Si no hay
  /// señales, cae a un default seguro (café + paseo + cultura).
  static List<PlanCategory> recommendedPlanTypes(List<PlanCategory> common) {
    final List<PlanCategory> out = <PlanCategory>[];
    final Set<PlanTier> usedTiers = <PlanTier>{};
    for (final PlanCategory cat in common) {
      if (usedTiers.contains(cat.tier)) continue;
      out.add(cat);
      usedTiers.add(cat.tier);
      if (out.length == 3) break;
    }
    // Rellena carriles que falten con defaults seguros y variados.
    const List<PlanCategory> fillers = <PlanCategory>[
      PlanCategory.cafe,
      PlanCategory.comida,
      PlanCategory.cultura,
      PlanCategory.paseo,
    ];
    for (final PlanCategory f in fillers) {
      if (out.length == 3) break;
      if (out.contains(f)) continue;
      if (usedTiers.contains(f.tier)) continue;
      out.add(f);
      usedTiers.add(f.tier);
    }
    // Si aún faltan (poco probable), añade sin mirar carril.
    for (final PlanCategory f in fillers) {
      if (out.length == 3) break;
      if (!out.contains(f)) out.add(f);
    }
    return out;
  }

  /// ¿Un lugar tiene calidad suficiente para una primera cita? Filtra ratings
  /// bajos y sitios con muy pocas reseñas (cuando el dato existe).
  static bool passesPlaceQuality({double? rating, int? reviewCount}) {
    if (rating != null && rating < kMinPlaceRating) return false;
    if (reviewCount != null && reviewCount < kMinPlaceReviews) return false;
    return true;
  }
}
