import 'setting_definition.dart';

/// Catalogo declarativo de las 8 secciones de ajustes, derivado del informe
/// analitico de apps de citas (Tinder, Bumble, Hinge, OkCupid, Grindr, POF).
///
/// Este es el "seed de definiciones" del que habla el prompt: la unica fuente
/// de verdad de que ajustes existen, su tipo, scope y base juridica. La UI se
/// genera a partir de aqui.
class SettingsCatalog {
  const SettingsCatalog._();

  /// Version del esquema de definiciones. Subir al renombrar/deprecar settings.
  static const int schemaVersion = 1;

  static const String secAccount = 'account';
  static const String secPrivacy = 'privacy';
  static const String secNotifications = 'notifications';
  static const String secLocation = 'location';
  static const String secSecurity = 'security';
  static const String secDataConsent = 'data_consent';
  static const String secIntegrations = 'integrations';
  static const String secLifecycle = 'lifecycle';

  /// Claves de accion (botones, no toggles).
  static const String actionExportData = 'export_data';
  static const String actionConsentHistory = 'consent_history';
  static const String actionChangeHistory = 'change_history';
  static const String actionDisableAccount = 'disable_account';
  static const String actionDeleteAccount = 'delete_account';

  static final List<SettingsSection> sections = <SettingsSection>[
    _accountSection,
    _privacySection,
    _notificationsSection,
    _locationSection,
    _securitySection,
    _dataConsentSection,
    _integrationsSection,
    _lifecycleSection,
  ];

  static SettingsSection? sectionByKey(String key) {
    for (final SettingsSection s in sections) {
      if (s.key == key) return s;
    }
    return null;
  }

  /// Todas las definiciones aplanadas (util para defaults / migraciones).
  static List<SettingDefinition> get allDefinitions => sections
      .expand((SettingsSection s) => s.definitions)
      .toList(growable: false);

  static SettingDefinition? definitionByKey(String key) {
    for (final SettingDefinition d in allDefinitions) {
      if (d.key == key) return d;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // 1. CUENTA
  // ---------------------------------------------------------------------------
  static const SettingsSection _accountSection = SettingsSection(
    key: secAccount,
    title: 'Cuenta',
    icon: 'manage_accounts',
    description: 'Identidad, credenciales y preferencias basicas.',
    definitions: <SettingDefinition>[
      SettingDefinition(
        key: 'account.unitSystem',
        sectionKey: secAccount,
        type: SettingType.enumeration,
        label: 'Sistema de unidades',
        description: 'Como se muestran distancias y medidas.',
        defaultValue: 'metric',
        options: <SettingOption>[
          SettingOption(value: 'metric', label: 'Metrico (km)'),
          SettingOption(value: 'imperial', label: 'Imperial (mi)'),
        ],
        auditLevel: AuditLevel.low,
      ),
      SettingDefinition(
        key: 'account.language',
        sectionKey: secAccount,
        type: SettingType.enumeration,
        label: 'Idioma de la app',
        description: 'Idioma de la interfaz.',
        defaultValue: 'es',
        options: <SettingOption>[
          SettingOption(value: 'es', label: 'Espanol'),
          SettingOption(value: 'en', label: 'English'),
        ],
        auditLevel: AuditLevel.low,
      ),
    ],
  );

  // ---------------------------------------------------------------------------
  // 2. PRIVACIDAD
  // ---------------------------------------------------------------------------
  static const SettingsSection _privacySection = SettingsSection(
    key: secPrivacy,
    title: 'Privacidad',
    icon: 'visibility',
    description: 'Quien te ve y cuanta informacion de actividad compartes.',
    definitions: <SettingDefinition>[
      SettingDefinition(
        key: 'privacy.hideProfile',
        sectionKey: secPrivacy,
        type: SettingType.boolean,
        label: 'Ocultar mi perfil',
        description:
            'Deja de aparecer en el feed de descubrimiento. Tus matches '
            'actuales podran seguir escribiendote.',
        defaultValue: false,
        legalBasis: LegalBasis.contract,
        auditLevel: AuditLevel.high,
      ),
      SettingDefinition(
        key: 'privacy.incognito',
        sectionKey: secPrivacy,
        type: SettingType.boolean,
        label: 'Modo incognito',
        description:
            'Solo te ven las personas a las que tu has dado like. Oculta tu '
            'ubicacion y tu estado de actividad.',
        defaultValue: false,
        requiresSubscription: true,
        legalBasis: LegalBasis.contract,
        auditLevel: AuditLevel.high,
      ),
      SettingDefinition(
        key: 'privacy.slowDating',
        sectionKey: secPrivacy,
        type: SettingType.boolean,
        label: 'Slow Dating',
        description: 'Citas con calma: ves menos perfiles pero mas afines a ti '
            '(intereses y lo que buscais). Prioriza conexiones intencionales '
            'sobre el deslizar masivo. Puedes desactivarlo cuando quieras.',
        defaultValue: false,
        legalBasis: LegalBasis.contract,
        auditLevel: AuditLevel.standard,
      ),
      SettingDefinition(
        key: 'privacy.showDistance',
        sectionKey: secPrivacy,
        type: SettingType.boolean,
        label: 'Mostrar mi distancia',
        description: 'Muestra a otros la distancia aproximada hasta ti.',
        defaultValue: true,
        auditLevel: AuditLevel.standard,
      ),
      SettingDefinition(
        key: 'privacy.showActiveStatus',
        sectionKey: secPrivacy,
        type: SettingType.boolean,
        label: 'Mostrar estado activo',
        description:
            'Muestra cuando estuviste activo por ultima vez. Si lo desactivas, '
            'tampoco veras el de los demas.',
        defaultValue: true,
        auditLevel: AuditLevel.standard,
      ),
      SettingDefinition(
        key: 'privacy.showInRecommendations',
        sectionKey: secPrivacy,
        type: SettingType.boolean,
        label: 'Aparecer en recomendaciones',
        description: 'Permite que te sugiramos a otras personas compatibles.',
        defaultValue: true,
        auditLevel: AuditLevel.standard,
      ),
      SettingDefinition(
        key: 'privacy.readReceipts',
        sectionKey: secPrivacy,
        type: SettingType.boolean,
        label: 'Confirmaciones de lectura',
        description: 'Muestra a tus matches cuando has leido sus mensajes.',
        defaultValue: true,
        auditLevel: AuditLevel.low,
      ),
      SettingDefinition(
        key: 'privacy.messageFilter',
        sectionKey: secPrivacy,
        type: SettingType.enumeration,
        label: 'Quien puede escribirme',
        description: 'Filtra quien puede iniciar una conversacion contigo.',
        defaultValue: 'matches',
        options: <SettingOption>[
          SettingOption(value: 'everyone', label: 'Todos'),
          SettingOption(value: 'matches', label: 'Solo mis matches'),
          SettingOption(value: 'verified', label: 'Solo perfiles verificados'),
        ],
        auditLevel: AuditLevel.standard,
      ),
    ],
  );

  // ---------------------------------------------------------------------------
  // 3. NOTIFICACIONES
  // ---------------------------------------------------------------------------
  static const SettingsSection _notificationsSection = SettingsSection(
    key: secNotifications,
    title: 'Notificaciones',
    icon: 'notifications',
    description: 'Que te avisamos y por que canal.',
    definitions: <SettingDefinition>[
      SettingDefinition(
        key: 'notifications.matchesPush',
        sectionKey: secNotifications,
        type: SettingType.boolean,
        label: 'Nuevos matches (push)',
        description: 'Avisos en el dispositivo cuando tienes un match.',
        defaultValue: true,
        auditLevel: AuditLevel.low,
      ),
      SettingDefinition(
        key: 'notifications.matchesEmail',
        sectionKey: secNotifications,
        type: SettingType.boolean,
        label: 'Nuevos matches (email)',
        description: 'Resumen de matches por correo.',
        defaultValue: false,
        auditLevel: AuditLevel.low,
      ),
      SettingDefinition(
        key: 'notifications.messagesPush',
        sectionKey: secNotifications,
        type: SettingType.boolean,
        label: 'Mensajes (push)',
        description: 'Avisos cuando recibes un mensaje.',
        defaultValue: true,
        auditLevel: AuditLevel.low,
      ),
      SettingDefinition(
        key: 'notifications.messagesEmail',
        sectionKey: secNotifications,
        type: SettingType.boolean,
        label: 'Mensajes (email)',
        description: 'Avisos de mensajes por correo.',
        defaultValue: false,
        auditLevel: AuditLevel.low,
      ),
      SettingDefinition(
        key: 'notifications.likesPush',
        sectionKey: secNotifications,
        type: SettingType.boolean,
        label: 'Likes recibidos (push)',
        description: 'Avisos cuando alguien te da like.',
        defaultValue: true,
        auditLevel: AuditLevel.low,
      ),
      SettingDefinition(
        key: 'notifications.marketingPush',
        sectionKey: secNotifications,
        type: SettingType.boolean,
        label: 'Novedades y ofertas (push)',
        description: 'Comunicaciones promocionales en el dispositivo.',
        defaultValue: false,
        legalBasis: LegalBasis.consent,
        consentPurpose: 'marketing_push',
        auditLevel: AuditLevel.standard,
      ),
      SettingDefinition(
        key: 'notifications.marketingEmail',
        sectionKey: secNotifications,
        type: SettingType.boolean,
        label: 'Novedades y ofertas (email)',
        description: 'Comunicaciones promocionales por correo.',
        defaultValue: false,
        legalBasis: LegalBasis.consent,
        consentPurpose: 'marketing_email',
        auditLevel: AuditLevel.standard,
      ),
      SettingDefinition(
        key: 'notifications.quietHours',
        sectionKey: secNotifications,
        type: SettingType.boolean,
        label: 'Horas de silencio',
        description: 'No enviar notificaciones push por la noche.',
        defaultValue: false,
        auditLevel: AuditLevel.low,
      ),
    ],
  );

  // ---------------------------------------------------------------------------
  // 4. UBICACION
  // ---------------------------------------------------------------------------
  static const SettingsSection _locationSection = SettingsSection(
    key: secLocation,
    title: 'Ubicacion',
    icon: 'location_on',
    description: 'Precision, visibilidad y uso de tu ubicacion.',
    definitions: <SettingDefinition>[
      SettingDefinition(
        key: 'location.precision',
        sectionKey: secLocation,
        type: SettingType.enumeration,
        label: 'Precision de ubicacion',
        description:
            'Aproximada difumina tu posicion real. Requiere permiso de '
            'ubicacion del dispositivo.',
        defaultValue: 'precise',
        scope: SettingScope.device,
        requiresOsPermission: 'location',
        options: <SettingOption>[
          SettingOption(value: 'precise', label: 'Precisa'),
          SettingOption(value: 'approximate', label: 'Aproximada (~1 km)'),
        ],
        legalBasis: LegalBasis.consent,
        consentPurpose: 'location_use',
        auditLevel: AuditLevel.high,
      ),
      SettingDefinition(
        key: 'location.showOnProfile',
        sectionKey: secLocation,
        type: SettingType.boolean,
        label: 'Mostrar ciudad en mi perfil',
        description: 'Muestra tu ciudad a otras personas.',
        defaultValue: true,
        auditLevel: AuditLevel.standard,
      ),
      SettingDefinition(
        key: 'location.travelMode',
        sectionKey: secLocation,
        type: SettingType.boolean,
        label: 'Modo viaje',
        description:
            'Fija tu ubicacion en otra ciudad para hacer match antes de '
            'llegar.',
        defaultValue: false,
        requiresSubscription: true,
        auditLevel: AuditLevel.standard,
      ),
      SettingDefinition(
        key: 'location.useForMatching',
        sectionKey: secLocation,
        type: SettingType.boolean,
        label: 'Usar ubicacion para recomendar',
        description: 'Tener en cuenta la cercania al sugerirte perfiles.',
        defaultValue: true,
        legalBasis: LegalBasis.legitimateInterest,
        auditLevel: AuditLevel.standard,
      ),
    ],
  );

  // ---------------------------------------------------------------------------
  // 5. SEGURIDAD
  // ---------------------------------------------------------------------------
  static const SettingsSection _securitySection = SettingsSection(
    key: secSecurity,
    title: 'Seguridad',
    icon: 'shield',
    description: 'Bloqueo de la app, biometria y proteccion de contenido.',
    definitions: <SettingDefinition>[
      SettingDefinition(
        key: 'security.appLock',
        sectionKey: secSecurity,
        type: SettingType.boolean,
        label: 'Bloqueo con PIN',
        description: 'Pide un codigo para abrir la app.',
        defaultValue: false,
        auditLevel: AuditLevel.high,
      ),
      SettingDefinition(
        key: 'security.biometricUnlock',
        sectionKey: secSecurity,
        type: SettingType.boolean,
        label: 'Desbloqueo biometrico',
        description: 'Usa huella o cara para abrir la app.',
        defaultValue: false,
        scope: SettingScope.device,
        requiresOsPermission: 'biometric',
        auditLevel: AuditLevel.high,
      ),
      SettingDefinition(
        key: 'security.screenshotProtection',
        sectionKey: secSecurity,
        type: SettingType.boolean,
        label: 'Proteger capturas de pantalla',
        description: 'Evita capturas en chats y fotos privadas.',
        defaultValue: false,
        scope: SettingScope.device,
        auditLevel: AuditLevel.standard,
      ),
      SettingDefinition(
        key: 'security.discreetIcon',
        sectionKey: secSecurity,
        type: SettingType.boolean,
        label: 'Icono discreto',
        description: 'Muestra un icono neutro en la pantalla de inicio.',
        defaultValue: false,
        requiresSubscription: true,
        scope: SettingScope.device,
        auditLevel: AuditLevel.standard,
      ),
    ],
  );

  // ---------------------------------------------------------------------------
  // 6. DATOS Y CONSENTIMIENTO
  // ---------------------------------------------------------------------------
  static const SettingsSection _dataConsentSection = SettingsSection(
    key: secDataConsent,
    title: 'Datos y consentimiento',
    icon: 'privacy_tip',
    description: 'Control sobre publicidad, IA y uso de tus datos.',
    definitions: <SettingDefinition>[
      SettingDefinition(
        key: 'data.targetedAdsOptOut',
        sectionKey: secDataConsent,
        type: SettingType.boolean,
        label: 'No usar mis datos para anuncios personalizados',
        description: 'Excluye tus datos de la publicidad segmentada.',
        defaultValue: false,
        optOutSemantics: true,
        legalBasis: LegalBasis.consent,
        consentPurpose: 'targeted_ads',
        auditLevel: AuditLevel.high,
      ),
      SettingDefinition(
        key: 'data.saleShareOptOut',
        sectionKey: secDataConsent,
        type: SettingType.boolean,
        label: 'No vender ni compartir mi informacion',
        description:
            'Exclusion de "sale/share" de datos personales (derechos de '
            'EE. UU.).',
        defaultValue: false,
        optOutSemantics: true,
        requiresRegion: 'US',
        legalBasis: LegalBasis.consent,
        consentPurpose: 'sale_share',
        auditLevel: AuditLevel.high,
      ),
      SettingDefinition(
        key: 'data.aiPersonalization',
        sectionKey: secDataConsent,
        type: SettingType.boolean,
        label: 'Personalizacion con IA',
        description: 'Usar IA para mejorar tus recomendaciones.',
        defaultValue: true,
        legalBasis: LegalBasis.consent,
        consentPurpose: 'ai_personalization',
        auditLevel: AuditLevel.standard,
      ),
      SettingDefinition(
        key: 'data.aiTrainingConsent',
        sectionKey: secDataConsent,
        type: SettingType.boolean,
        label: 'Usar mis datos para entrenar IA',
        description: 'Permitir que datos no sensibles entrenen modelos.',
        defaultValue: false,
        legalBasis: LegalBasis.consent,
        consentPurpose: 'ai_training',
        auditLevel: AuditLevel.high,
      ),
      SettingDefinition(
        key: 'data.analyticsConsent',
        sectionKey: secDataConsent,
        type: SettingType.boolean,
        label: 'Analitica de uso',
        description: 'Permitir metricas para mejorar la app.',
        defaultValue: true,
        legalBasis: LegalBasis.consent,
        consentPurpose: 'analytics',
        auditLevel: AuditLevel.standard,
      ),
    ],
    actions: <SettingsAction>[
      SettingsAction(
        key: actionExportData,
        label: 'Exportar mis datos',
        description: 'Solicita una copia de tus datos (RGPD).',
        requiresReauth: true,
        icon: 'download',
      ),
      SettingsAction(
        key: actionConsentHistory,
        label: 'Historial de consentimientos',
        description: 'Que aceptaste y cuando.',
        icon: 'history',
      ),
      SettingsAction(
        key: actionChangeHistory,
        label: 'Historial de cambios',
        description: 'Cambios recientes en tus ajustes.',
        icon: 'manage_history',
      ),
    ],
  );

  // ---------------------------------------------------------------------------
  // 7. INTEGRACIONES / TERCEROS
  // ---------------------------------------------------------------------------
  static const SettingsSection _integrationsSection = SettingsSection(
    key: secIntegrations,
    title: 'Integraciones',
    icon: 'extension',
    description: 'Conexiones con servicios externos.',
    definitions: <SettingDefinition>[
      SettingDefinition(
        key: 'integrations.instagram',
        sectionKey: secIntegrations,
        type: SettingType.boolean,
        label: 'Instagram',
        description: 'Muestra tus fotos de Instagram en el perfil.',
        defaultValue: false,
        legalBasis: LegalBasis.consent,
        consentPurpose: 'integration_instagram',
        auditLevel: AuditLevel.standard,
      ),
      SettingDefinition(
        key: 'integrations.spotify',
        sectionKey: secIntegrations,
        type: SettingType.boolean,
        label: 'Spotify',
        description: 'Muestra tus artistas favoritos.',
        defaultValue: false,
        legalBasis: LegalBasis.consent,
        consentPurpose: 'integration_spotify',
        auditLevel: AuditLevel.standard,
      ),
      SettingDefinition(
        key: 'integrations.contactSync',
        sectionKey: secIntegrations,
        type: SettingType.boolean,
        label: 'Sincronizar contactos',
        description: 'Usar tu agenda para no mostrarte a personas que conoces.',
        defaultValue: false,
        requiresOsPermission: 'contacts',
        legalBasis: LegalBasis.consent,
        consentPurpose: 'contact_sync',
        auditLevel: AuditLevel.high,
      ),
    ],
  );

  // ---------------------------------------------------------------------------
  // 8. ELIMINACION / EXPORTACION
  // ---------------------------------------------------------------------------
  static const SettingsSection _lifecycleSection = SettingsSection(
    key: secLifecycle,
    title: 'Eliminar cuenta',
    icon: 'no_accounts',
    description: 'Pausar, exportar o eliminar tu cuenta de forma definitiva.',
    actions: <SettingsAction>[
      SettingsAction(
        key: actionExportData,
        label: 'Exportar mis datos',
        description: 'Solicita una copia antes de borrar nada.',
        requiresReauth: true,
        icon: 'download',
      ),
      SettingsAction(
        key: actionDisableAccount,
        label: 'Pausar mi cuenta',
        description:
            'Oculta tu perfil temporalmente. Puedes reactivarla cuando '
            'quieras volviendo a iniciar sesion.',
        icon: 'pause_circle',
      ),
      SettingsAction(
        key: actionDeleteAccount,
        label: 'Eliminar cuenta',
        description:
            'Borra tu cuenta y tus datos. Accion irreversible tras la ventana '
            'de seguridad. No cancela suscripciones de Apple/Google.',
        destructive: true,
        requiresReauth: true,
        icon: 'delete_forever',
      ),
    ],
  );
}
