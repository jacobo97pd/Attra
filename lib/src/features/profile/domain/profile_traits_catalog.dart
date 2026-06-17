import 'profile_trait.dart';

/// Catalogo de rasgos completables del perfil (previo a filtros avanzados).
/// Define QUE se puede completar, donde se guarda y si es sensible. NO valida
/// tipos: la app guarda en `users/{uid}.[group].[field]`.
class ProfileTraitsCatalog {
  const ProfileTraitsCatalog._();

  static const List<ProfileSection> sections = <ProfileSection>[
    _identity,
    _vitals,
    _appearance,
    _relationship,
    _lifestyle,
    _work,
    _interests,
    _origin,
  ];

  /// Todas las definiciones aplanadas.
  static List<ProfileTraitDefinition> get all => <ProfileTraitDefinition>[
        for (final ProfileSection s in sections) ...s.definitions,
      ];

  static ProfileTraitDefinition? byKey(String key) {
    for (final ProfileTraitDefinition d in all) {
      if (d.key == key) return d;
    }
    return null;
  }

  /// Claves de rasgos SENSIBLES (opcionales, opt-in, fuera del strength).
  static Set<String> get sensitiveKeys =>
      all.where((ProfileTraitDefinition d) => d.sensitive).map((ProfileTraitDefinition d) => d.key).toSet();

  // --- Secciones ------------------------------------------------------------

  static const ProfileSection _identity = ProfileSection(
    key: 'identity',
    title: 'Identidad',
    definitions: <ProfileTraitDefinition>[
      ProfileTraitDefinition(
          key: 'pronouns',
          sectionKey: 'identity',
          label: 'Pronombres',
          type: TraitType.text,
          group: 'profile',
          field: 'pronouns'),
      ProfileTraitDefinition(
        key: 'sexualOrientation',
        sectionKey: 'identity',
        label: 'Orientación sexual',
        type: TraitType.multiSelect,
        group: 'profile',
        field: 'orientation',
        sensitive: true,
        options: <TraitOption>[
          TraitOption('straight', 'Hetero'),
          TraitOption('gay', 'Gay'),
          TraitOption('lesbian', 'Lesbiana'),
          TraitOption('bisexual', 'Bisexual'),
          TraitOption('pansexual', 'Pansexual'),
          TraitOption('asexual', 'Asexual'),
          TraitOption('queer', 'Queer'),
          TraitOption('questioning', 'Cuestionándose'),
          TraitOption('prefer_not_to_say', 'Prefiero no decirlo'),
        ],
      ),
      ProfileTraitDefinition(
          key: 'languages',
          sectionKey: 'identity',
          label: 'Idiomas',
          type: TraitType.multiSelect,
          group: 'profile',
          field: 'languages'),
    ],
  );

  static const ProfileSection _vitals = ProfileSection(
    key: 'vitals',
    title: 'Datos',
    definitions: <ProfileTraitDefinition>[
      ProfileTraitDefinition(
          key: 'hometown',
          sectionKey: 'vitals',
          label: 'Ciudad de origen',
          type: TraitType.text,
          group: 'profile',
          field: 'birthCity'),
      ProfileTraitDefinition(
          key: 'height',
          sectionKey: 'vitals',
          label: 'Altura (cm)',
          type: TraitType.number,
          group: 'appearance',
          field: 'heightCm'),
      ProfileTraitDefinition(
        key: 'zodiac',
        sectionKey: 'vitals',
        label: 'Signo del zodiaco',
        type: TraitType.singleSelect,
        group: 'profile',
        field: 'zodiac',
        options: <TraitOption>[
          TraitOption('aries', 'Aries'),
          TraitOption('taurus', 'Tauro'),
          TraitOption('gemini', 'Géminis'),
          TraitOption('cancer', 'Cáncer'),
          TraitOption('leo', 'Leo'),
          TraitOption('virgo', 'Virgo'),
          TraitOption('libra', 'Libra'),
          TraitOption('scorpio', 'Escorpio'),
          TraitOption('sagittarius', 'Sagitario'),
          TraitOption('capricorn', 'Capricornio'),
          TraitOption('aquarius', 'Acuario'),
          TraitOption('pisces', 'Piscis'),
        ],
      ),
    ],
  );

  static const ProfileSection _appearance = ProfileSection(
    key: 'appearance',
    title: 'Apariencia',
    definitions: <ProfileTraitDefinition>[
      ProfileTraitDefinition(
          key: 'eyes',
          sectionKey: 'appearance',
          label: 'Color de ojos',
          type: TraitType.singleSelect,
          group: 'appearance',
          field: 'eyeColor',
          options: <TraitOption>[
            TraitOption('brown', 'Marrones'),
            TraitOption('blue', 'Azules'),
            TraitOption('green', 'Verdes'),
            TraitOption('hazel', 'Avellana'),
            TraitOption('gray', 'Grises'),
            TraitOption('black', 'Negros'),
          ]),
      ProfileTraitDefinition(
          key: 'bodyType',
          sectionKey: 'appearance',
          label: 'Complexión',
          type: TraitType.singleSelect,
          group: 'appearance',
          field: 'bodyType',
          options: <TraitOption>[
            TraitOption('slim', 'Delgada'),
            TraitOption('athletic', 'Atlética'),
            TraitOption('average', 'Media'),
            TraitOption('curvy', 'Con curvas'),
            TraitOption('muscular', 'Musculada'),
            TraitOption('plus', 'Grande'),
          ]),
      ProfileTraitDefinition(
          key: 'tattoos',
          sectionKey: 'appearance',
          label: 'Tatuajes',
          type: TraitType.singleSelect,
          group: 'appearance',
          field: 'tattoos',
          options: <TraitOption>[
            TraitOption('none', 'Ninguno'),
            TraitOption('some', 'Algunos'),
            TraitOption('many', 'Muchos'),
          ]),
      ProfileTraitDefinition(
          key: 'glasses',
          sectionKey: 'appearance',
          label: 'Gafas',
          type: TraitType.singleSelect,
          group: 'appearance',
          field: 'glasses',
          options: <TraitOption>[
            TraitOption('yes', 'Sí'),
            TraitOption('no', 'No'),
            TraitOption('sometimes', 'A veces'),
          ]),
    ],
  );

  static const ProfileSection _relationship = ProfileSection(
    key: 'relationship',
    title: 'Relación',
    definitions: <ProfileTraitDefinition>[
      ProfileTraitDefinition(
          key: 'relationshipGoal',
          sectionKey: 'relationship',
          label: 'Qué buscas',
          type: TraitType.singleSelect,
          group: 'profile',
          field: 'relationshipIntent',
          options: <TraitOption>[
            TraitOption('serious_relationship', 'Relación seria'),
            TraitOption('meet_people', 'Conocer gente'),
            TraitOption('casual', 'Algo casual'),
            TraitOption('open_to_see', 'Abierto a ver qué surge'),
          ]),
      ProfileTraitDefinition(
          key: 'children',
          sectionKey: 'relationship',
          label: 'Hijos',
          type: TraitType.singleSelect,
          group: 'lifestyle',
          field: 'hasChildren',
          options: <TraitOption>[
            TraitOption('none', 'No tengo'),
            TraitOption('have', 'Tengo'),
            TraitOption('prefer_not_to_say', 'Prefiero no decirlo'),
          ]),
      ProfileTraitDefinition(
          key: 'familyPlans',
          sectionKey: 'relationship',
          label: 'Planes de familia',
          type: TraitType.singleSelect,
          group: 'lifestyle',
          field: 'wantsChildren',
          options: <TraitOption>[
            TraitOption('want', 'Quiero'),
            TraitOption('dont_want', 'No quiero'),
            TraitOption('open', 'Abierto/a'),
            TraitOption('prefer_not_to_say', 'Prefiero no decirlo'),
          ]),
    ],
  );

  static const ProfileSection _lifestyle = ProfileSection(
    key: 'lifestyle',
    title: 'Estilo de vida',
    definitions: <ProfileTraitDefinition>[
      ProfileTraitDefinition(
          key: 'smoking',
          sectionKey: 'lifestyle',
          label: 'Tabaco',
          type: TraitType.singleSelect,
          group: 'lifestyle',
          field: 'smoking',
          options: <TraitOption>[
            TraitOption('never', 'Nunca'),
            TraitOption('occasionally', 'Ocasional'),
            TraitOption('regularly', 'Habitual'),
          ]),
      ProfileTraitDefinition(
          key: 'drinking',
          sectionKey: 'lifestyle',
          label: 'Alcohol',
          type: TraitType.singleSelect,
          group: 'lifestyle',
          field: 'drinking',
          options: <TraitOption>[
            TraitOption('never', 'Nunca'),
            TraitOption('socially', 'Socialmente'),
            TraitOption('regularly', 'Habitual'),
          ]),
      ProfileTraitDefinition(
        key: 'cannabis',
        sectionKey: 'lifestyle',
        label: 'Cannabis',
        type: TraitType.singleSelect,
        group: 'lifestyle',
        field: 'cannabis',
        sensitive: true,
        options: <TraitOption>[
          TraitOption('never', 'Nunca'),
          TraitOption('sometimes', 'A veces'),
          TraitOption('regularly', 'Habitual'),
          TraitOption('prefer_not_to_say', 'Prefiero no decirlo'),
        ],
      ),
      ProfileTraitDefinition(
        key: 'drugs',
        sectionKey: 'lifestyle',
        label: 'Otras sustancias',
        type: TraitType.singleSelect,
        group: 'lifestyle',
        field: 'drugs',
        sensitive: true,
        options: <TraitOption>[
          TraitOption('never', 'Nunca'),
          TraitOption('sometimes', 'A veces'),
          TraitOption('prefer_not_to_say', 'Prefiero no decirlo'),
        ],
      ),
      ProfileTraitDefinition(
          key: 'diet',
          sectionKey: 'lifestyle',
          label: 'Dieta',
          type: TraitType.singleSelect,
          group: 'lifestyle',
          field: 'diet',
          options: <TraitOption>[
            TraitOption('omnivore', 'De todo'),
            TraitOption('vegetarian', 'Vegetariana'),
            TraitOption('vegan', 'Vegana'),
            TraitOption('pescatarian', 'Pescetariana'),
            TraitOption('other', 'Otra'),
          ]),
      ProfileTraitDefinition(
          key: 'pets',
          sectionKey: 'lifestyle',
          label: 'Mascotas',
          type: TraitType.multiSelect,
          group: 'lifestyle',
          field: 'pets'),
    ],
  );

  static const ProfileSection _work = ProfileSection(
    key: 'work',
    title: 'Trabajo y estudios',
    definitions: <ProfileTraitDefinition>[
      ProfileTraitDefinition(
          key: 'jobTitle',
          sectionKey: 'work',
          label: 'Puesto',
          type: TraitType.text,
          group: 'profile',
          field: 'jobTitle'),
      ProfileTraitDefinition(
          key: 'company',
          sectionKey: 'work',
          label: 'Empresa',
          type: TraitType.text,
          group: 'profile',
          field: 'company'),
      ProfileTraitDefinition(
          key: 'educationLevel',
          sectionKey: 'work',
          label: 'Nivel de estudios',
          type: TraitType.singleSelect,
          group: 'profile',
          field: 'educationLevel',
          options: <TraitOption>[
            TraitOption('high_school', 'Bachillerato'),
            TraitOption('vocational', 'FP'),
            TraitOption('bachelor', 'Grado'),
            TraitOption('master', 'Máster'),
            TraitOption('phd', 'Doctorado'),
          ]),
      ProfileTraitDefinition(
          key: 'university',
          sectionKey: 'work',
          label: 'Universidad / centro',
          type: TraitType.text,
          group: 'profile',
          field: 'university'),
    ],
  );

  static const ProfileSection _interests = ProfileSection(
    key: 'interests',
    title: 'Intereses y personalidad',
    definitions: <ProfileTraitDefinition>[
      ProfileTraitDefinition(
          key: 'interestTags',
          sectionKey: 'interests',
          label: 'Intereses',
          type: TraitType.multiSelect,
          group: 'profile',
          field: 'interests'),
      ProfileTraitDefinition(
          key: 'personalityTags',
          sectionKey: 'interests',
          label: 'Personalidad',
          type: TraitType.multiSelect,
          group: 'style',
          field: 'personalityTags'),
    ],
  );

  static const ProfileSection _origin = ProfileSection(
    key: 'origin',
    title: 'Origen (opcional)',
    definitions: <ProfileTraitDefinition>[
      ProfileTraitDefinition(
        key: 'ethnicity',
        sectionKey: 'origin',
        label: 'Origen / etnia',
        type: TraitType.singleSelect,
        group: 'origin',
        field: 'ethnicity',
        sensitive: true,
        options: <TraitOption>[
          TraitOption('white_caucasian', 'Blanco / caucásico'),
          TraitOption('hispanic_latino', 'Hispano / latino'),
          TraitOption('black_afro', 'Negro / afro'),
          TraitOption('east_asian', 'Asiático oriental'),
          TraitOption('south_asian', 'Asiático del sur'),
          TraitOption('middle_eastern_north_african', 'MENA'),
          TraitOption('indigenous', 'Indígena'),
          TraitOption('multiracial', 'Multirracial'),
          TraitOption('other', 'Otro'),
          TraitOption('prefer_not_to_say', 'Prefiero no decirlo'),
        ],
      ),
      ProfileTraitDefinition(
        key: 'religion',
        sectionKey: 'origin',
        label: 'Religión',
        type: TraitType.singleSelect,
        group: 'profile',
        field: 'religion',
        sensitive: true,
        options: <TraitOption>[
          TraitOption('none', 'Ninguna'),
          TraitOption('christian', 'Cristiana'),
          TraitOption('catholic', 'Católica'),
          TraitOption('muslim', 'Musulmana'),
          TraitOption('jewish', 'Judía'),
          TraitOption('hindu', 'Hindú'),
          TraitOption('buddhist', 'Budista'),
          TraitOption('spiritual', 'Espiritual'),
          TraitOption('other', 'Otra'),
          TraitOption('prefer_not_to_say', 'Prefiero no decirlo'),
        ],
      ),
      ProfileTraitDefinition(
        key: 'politics',
        sectionKey: 'origin',
        label: 'Política',
        type: TraitType.singleSelect,
        group: 'profile',
        field: 'politics',
        sensitive: true,
        options: <TraitOption>[
          TraitOption('apolitical', 'Apolítico/a'),
          TraitOption('left', 'Izquierda'),
          TraitOption('center', 'Centro'),
          TraitOption('right', 'Derecha'),
          TraitOption('other', 'Otra'),
          TraitOption('prefer_not_to_say', 'Prefiero no decirlo'),
        ],
      ),
    ],
  );
}
