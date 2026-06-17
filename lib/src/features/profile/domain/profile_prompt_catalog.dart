/// Catálogo de preguntas predefinidas para los prompts de perfil.
///
/// Primera implementación LOCAL (en Dart) para iterar rápido; el shape
/// (id/question/category/locale) está pensado para migrar a Firestore o
/// Remote Config sin tocar la UI.
library;

class PromptCategory {
  const PromptCategory({required this.key, required this.label});
  final String key;
  final String label;
}

class CatalogPrompt {
  const CatalogPrompt(this.id, this.category, this.question);
  final String id;
  final String category;
  final String question;
}

class ProfilePromptCatalog {
  const ProfilePromptCatalog._();

  static const List<PromptCategory> categories = <PromptCategory>[
    PromptCategory(key: 'ice', label: 'Romper el hielo'),
    PromptCategory(key: 'dates', label: 'Citas y planes'),
    PromptCategory(key: 'everyday', label: 'Vida cotidiana'),
    PromptCategory(key: 'lifestyle', label: 'Estilo de vida'),
    PromptCategory(key: 'personality', label: 'Personalidad'),
    PromptCategory(key: 'humor', label: 'Humor'),
    PromptCategory(key: 'tastes', label: 'Gustos'),
    PromptCategory(key: 'flirty', label: 'Coqueteo suave'),
    PromptCategory(key: 'romantic', label: 'Romántico'),
    PromptCategory(key: 'values', label: 'Valores y relación'),
    PromptCategory(key: 'vulnerability', label: 'Vulnerabilidad ligera'),
    PromptCategory(key: 'deep', label: 'Profundo pero ligero'),
  ];

  static String categoryLabel(String key) {
    for (final PromptCategory c in categories) {
      if (c.key == key) return c.label;
    }
    return key == 'custom' ? 'Mi pregunta' : key;
  }

  static const List<CatalogPrompt> all = <CatalogPrompt>[
    // --- Romper el hielo ---
    CatalogPrompt('ice_01', 'ice', 'Dos verdades y una mentira…'),
    CatalogPrompt('ice_02', 'ice', 'Una opinión impopular que tengo es…'),
    CatalogPrompt('ice_03', 'ice', 'Me ganas si…'),
    CatalogPrompt('ice_04', 'ice', 'Mi plan perfecto improvisado sería…'),
    CatalogPrompt('ice_05', 'ice', 'Si solo pudieras preguntarme una cosa, pregunta…'),
    CatalogPrompt('ice_06', 'ice', 'El mejor cumplido que me pueden hacer es…'),
    CatalogPrompt('ice_07', 'ice', 'Mi señal verde más clara es…'),
    CatalogPrompt('ice_08', 'ice', 'Mi red flag graciosa es…'),
    CatalogPrompt('ice_09', 'ice', 'Una cosa que siempre me hace reír es…'),
    CatalogPrompt('ice_10', 'ice', 'Algo que parece pequeño pero me conquista es…'),
    // --- Citas y planes ---
    CatalogPrompt('dates_01', 'dates', 'Mi cita ideal sería…'),
    CatalogPrompt('dates_02', 'dates', 'El primer plan perfecto para mí es…'),
    CatalogPrompt('dates_03', 'dates', 'Primera ronda invito yo si…'),
    CatalogPrompt('dates_04', 'dates', 'Un domingo perfecto incluye…'),
    CatalogPrompt('dates_05', 'dates', 'El mejor sitio para conocernos sería…'),
    CatalogPrompt('dates_06', 'dates', 'Me apunto sin pensarlo a…'),
    CatalogPrompt('dates_07', 'dates', 'La cita más simple pero efectiva es…'),
    CatalogPrompt('dates_08', 'dates', 'Si hacemos match, deberíamos…'),
    CatalogPrompt('dates_09', 'dates', 'Nuestro primer plan no puede ser…'),
    CatalogPrompt('dates_10', 'dates', 'Prefiero una cita que sea…'),
    // --- Personalidad ---
    CatalogPrompt('pers_01', 'personality', 'La mejor forma de describirme sería…'),
    CatalogPrompt('pers_02', 'personality', 'Soy demasiado bueno/a en…'),
    CatalogPrompt('pers_03', 'personality', 'Soy pésimo/a en…'),
    CatalogPrompt('pers_04', 'personality', 'Mi superpoder secreto es…'),
    CatalogPrompt('pers_05', 'personality', 'Mi lado más competitivo sale cuando…'),
    CatalogPrompt('pers_06', 'personality', 'La gente se sorprende cuando descubre que…'),
    CatalogPrompt('pers_07', 'personality', 'Algo muy mío es…'),
    CatalogPrompt('pers_08', 'personality', 'Me tomo muy en serio…'),
    CatalogPrompt('pers_09', 'personality', 'No puedo vivir sin…'),
    CatalogPrompt('pers_10', 'personality', 'Mi energía es más de…'),
    // --- Humor ---
    CatalogPrompt('humor_01', 'humor', 'Mi talento inútil es…'),
    CatalogPrompt('humor_02', 'humor', 'Mi biografía honesta sería…'),
    CatalogPrompt('humor_03', 'humor', 'Una frase que digo demasiado es…'),
    CatalogPrompt('humor_04', 'humor', 'Mi momento más vergonzoso fue…'),
    CatalogPrompt('humor_05', 'humor', 'Si mi vida fuera una película se llamaría…'),
    CatalogPrompt('humor_06', 'humor', 'Mi playlist me delata porque…'),
    CatalogPrompt('humor_07', 'humor', 'Mi excusa favorita para salir de casa es…'),
    CatalogPrompt('humor_08', 'humor', 'Mi mayor drama semanal es…'),
    CatalogPrompt('humor_09', 'humor', 'Sobreviviría a un apocalipsis porque…'),
    CatalogPrompt('humor_10', 'humor', 'Mi defecto premium es…'),
    // --- Gustos ---
    CatalogPrompt('taste_01', 'tastes', 'Mi comida de confianza es…'),
    CatalogPrompt('taste_02', 'tastes', 'Una canción que nunca salto es…'),
    CatalogPrompt('taste_03', 'tastes', 'Una película que puedo ver mil veces es…'),
    CatalogPrompt('taste_04', 'tastes', 'Mi sitio feliz es…'),
    CatalogPrompt('taste_05', 'tastes', 'Mi viaje pendiente es…'),
    CatalogPrompt('taste_06', 'tastes', 'Mi hobby más inesperado es…'),
    CatalogPrompt('taste_07', 'tastes', 'Mi plan de viernes noche suele ser…'),
    CatalogPrompt('taste_08', 'tastes', 'Mi café, bar o restaurante ideal es…'),
    CatalogPrompt('taste_09', 'tastes', 'Mi guilty pleasure es…'),
    CatalogPrompt('taste_10', 'tastes', 'Si me recomiendas algo, que sea…'),
    // --- Valores y relación ---
    CatalogPrompt('values_01', 'values', 'Busco a alguien que…'),
    CatalogPrompt('values_02', 'values', 'Para mí una relación sana es…'),
    CatalogPrompt('values_03', 'values', 'Valoro mucho que alguien…'),
    CatalogPrompt('values_04', 'values', 'Mi lenguaje del amor es…'),
    CatalogPrompt('values_05', 'values', 'Me siento atraído/a por personas que…'),
    CatalogPrompt('values_06', 'values', 'Una green flag para mí es…'),
    CatalogPrompt('values_07', 'values', 'Una buena conversación empieza con…'),
    CatalogPrompt('values_08', 'values', 'Lo que más cuido en una relación es…'),
    CatalogPrompt('values_09', 'values', 'Me ilusiona alguien que…'),
    CatalogPrompt('values_10', 'values', 'Quiero construir algo que…'),
    // --- Estilo de vida ---
    CatalogPrompt('life_01', 'lifestyle', 'Entre semana normalmente estoy…'),
    CatalogPrompt('life_02', 'lifestyle', 'Los fines de semana soy de…'),
    CatalogPrompt('life_03', 'lifestyle', 'Mi rutina ideal empieza con…'),
    CatalogPrompt('life_04', 'lifestyle', 'Mi equilibrio perfecto es…'),
    CatalogPrompt('life_05', 'lifestyle', 'Soy más de ciudad, playa o montaña porque…'),
    CatalogPrompt('life_06', 'lifestyle', 'Mi plan tranquilo favorito es…'),
    CatalogPrompt('life_07', 'lifestyle', 'Mi plan activo favorito es…'),
    CatalogPrompt('life_08', 'lifestyle', 'El deporte que más practico o probaría es…'),
    CatalogPrompt('life_09', 'lifestyle', 'Mi forma de desconectar es…'),
    CatalogPrompt('life_10', 'lifestyle', 'Mi casa ideal tendría…'),
    // --- Coqueteo suave ---
    CatalogPrompt('flirt_01', 'flirty', 'Me derrito cuando alguien…'),
    CatalogPrompt('flirt_02', 'flirty', 'Me cuesta decir que no a…'),
    CatalogPrompt('flirt_03', 'flirty', 'Mi debilidad es…'),
    CatalogPrompt('flirt_04', 'flirty', 'Si hay química, se nota cuando…'),
    CatalogPrompt('flirt_05', 'flirty', 'Me parece atractivo que alguien…'),
    CatalogPrompt('flirt_06', 'flirty', 'Un mensaje que sí respondería es…'),
    CatalogPrompt('flirt_07', 'flirty', 'Mi tipo de tontería favorita es…'),
    CatalogPrompt('flirt_08', 'flirty', 'Me conquistas más con…'),
    CatalogPrompt('flirt_09', 'flirty', 'Un detalle que suma puntos es…'),
    CatalogPrompt('flirt_10', 'flirty', 'Lo que me engancha de alguien es…'),
    // --- Profundo pero ligero ---
    CatalogPrompt('deep_01', 'deep', 'Algo que he aprendido últimamente es…'),
    CatalogPrompt('deep_02', 'deep', 'Una etapa que me cambió fue…'),
    CatalogPrompt('deep_03', 'deep', 'Me siento orgulloso/a de…'),
    CatalogPrompt('deep_04', 'deep', 'Estoy trabajando en…'),
    CatalogPrompt('deep_05', 'deep', 'Algo que quiero hacer más este año es…'),
    CatalogPrompt('deep_06', 'deep', 'Una conversación que me encanta tener es…'),
    CatalogPrompt('deep_07', 'deep', 'Me inspira la gente que…'),
    CatalogPrompt('deep_08', 'deep', 'Mi versión ideal dentro de unos años…'),
    CatalogPrompt('deep_09', 'deep', 'Una cosa que intento mejorar es…'),
    CatalogPrompt('deep_10', 'deep', 'Me gustaría compartir con alguien…'),
    CatalogPrompt('deep_11', 'deep', 'Lo que de verdad me hace feliz es…'),
    CatalogPrompt('deep_12', 'deep', 'Una creencia que guía mi vida es…'),

    // --- Vida cotidiana (lo pequeño del día a día, en pareja) ---
    CatalogPrompt('day_01', 'everyday', 'Mi mañana ideal contigo sería…'),
    CatalogPrompt('day_02', 'everyday', 'En casa soy de…'),
    CatalogPrompt('day_03', 'everyday', 'Mi pequeño placer diario es…'),
    CatalogPrompt('day_04', 'everyday', 'La rutina en pareja que me encantaría es…'),
    CatalogPrompt('day_05', 'everyday', 'Sé que hay confianza cuando podemos…'),
    CatalogPrompt('day_06', 'everyday', 'Mi forma de cuidar a alguien en el día a día es…'),
    CatalogPrompt('day_07', 'everyday', 'Lo que hace especial un día normal es…'),
    CatalogPrompt('day_08', 'everyday', 'Discutiríamos en broma por…'),
    CatalogPrompt('day_09', 'everyday', 'Mi domingo perfecto en pareja es…'),
    CatalogPrompt('day_10', 'everyday', 'Un detalle cotidiano que me derrite es…'),
    CatalogPrompt('day_11', 'everyday', 'Compartiría sin pensarlo mi…'),
    CatalogPrompt('day_12', 'everyday', 'La canción que pondría mientras cocinamos sería…'),

    // --- Romántico (intención de pareja, ternura, futuro) ---
    CatalogPrompt('rom_01', 'romantic', 'Lo que más ilusión me hace de enamorarme es…'),
    CatalogPrompt('rom_02', 'romantic', 'Sé que me gusta alguien de verdad cuando…'),
    CatalogPrompt('rom_03', 'romantic', 'Mi gesto romántico favorito es…'),
    CatalogPrompt('rom_04', 'romantic', 'La forma en que me gusta querer es…'),
    CatalogPrompt('rom_05', 'romantic', 'Quiero a alguien con quien pueda…'),
    CatalogPrompt('rom_06', 'romantic', 'Un “para siempre” conmigo se parece a…'),
    CatalogPrompt('rom_07', 'romantic', 'Me enamoro despacio cuando…'),
    CatalogPrompt('rom_08', 'romantic', 'Contigo me gustaría aprender a…'),
    CatalogPrompt('rom_09', 'romantic', 'El amor, para mí, empieza cuando…'),
    CatalogPrompt('rom_10', 'romantic', 'Lo que me derrite sin remedio es…'),
    CatalogPrompt('rom_11', 'romantic', 'Mi idea de una noche perfecta juntos es…'),
    CatalogPrompt('rom_12', 'romantic', 'Lo primero que querría hacer contigo es…'),

    // --- Vulnerabilidad ligera (apertura emocional sin pesar) ---
    CatalogPrompt('vuln_01', 'vulnerability', 'Me siento querido/a cuando…'),
    CatalogPrompt('vuln_02', 'vulnerability', 'Algo que me cuesta admitir es…'),
    CatalogPrompt('vuln_03', 'vulnerability', 'Mi corazón se ablanda con…'),
    CatalogPrompt('vuln_04', 'vulnerability', 'Una cosa que necesito en una relación es…'),
    CatalogPrompt('vuln_05', 'vulnerability', 'Me da un poco de respeto, pero quiero…'),
    CatalogPrompt('vuln_06', 'vulnerability', 'Cuando confío en alguien, yo…'),
    CatalogPrompt('vuln_07', 'vulnerability', 'Lo que me gustaría que entendieran de mí es…'),
    CatalogPrompt('vuln_08', 'vulnerability', 'Un día difícil mejora muchísimo si alguien…'),
    CatalogPrompt('vuln_09', 'vulnerability', 'Me siento yo mismo/a cuando…'),
    CatalogPrompt('vuln_10', 'vulnerability', 'Me cuesta pedirlo, pero agradezco mucho…'),
    CatalogPrompt('vuln_11', 'vulnerability', 'Lo que de verdad estoy buscando es…'),
    CatalogPrompt('vuln_12', 'vulnerability', 'Estoy aprendiendo a abrirme sobre…'),

    // --- Valores y relación (refuerzo romántico) ---
    CatalogPrompt('values_11', 'values', 'La base de una buena relación para mí es…'),
    CatalogPrompt('values_12', 'values', 'Quiero a mi lado a alguien que también…'),
    CatalogPrompt('values_13', 'values', 'Discrepar bien para mí significa…'),
    CatalogPrompt('values_14', 'values', 'El equipo perfecto en pareja sería el que…'),

    // --- Citas y planes (más planes a futuro) ---
    CatalogPrompt('dates_11', 'dates', 'El viaje que me encantaría hacer en pareja es…'),
    CatalogPrompt('dates_12', 'dates', 'Una tradición de pareja que crearía es…'),
  ];

  static List<CatalogPrompt> byCategory(String key) =>
      all.where((CatalogPrompt p) => p.category == key).toList(growable: false);

  static List<CatalogPrompt> search(String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((CatalogPrompt p) => p.question.toLowerCase().contains(q))
        .toList(growable: false);
  }
}
