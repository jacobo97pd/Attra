import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../../../../l10n/app_localizations.dart';
import '../../../security/screen_guard.dart';
import '../../../theme/attra_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_backgrounds.dart';

import '../../ai_visual/data/ai_visual_service.dart';
import '../../ai_visual/presentation/ai_visual_screen.dart';
import '../../anti_ghosting/data/pending_conversations_controller.dart';
import '../../anti_ghosting/domain/anti_ghosting_config.dart';
import '../../auth/data/location_refresh_service.dart';
import '../../auth/domain/app_user.dart';
import '../../chat/data/chat_service.dart';
import '../../date_plans/data/date_plan_service.dart';
import '../../safedate/data/safedate_service.dart';
import '../../safedate/domain/safedate_flags.dart';
import '../../safedate/presentation/safedate_home_screen.dart';
import '../../social/data/friend_group_service.dart';
import '../../social/data/friend_mode_service.dart';
import '../../social/data/social_discovery_service.dart';
import '../../social/presentation/groups_screen.dart';
import '../../social/presentation/intent_mode_selector.dart';
import '../../social/domain/intent_mode.dart';
import '../../chat/presentation/chats_screen.dart';
import '../../feed/data/feed_metrics_service.dart';
import '../../feed/data/ranking_signals_repository.dart';
import '../../feed/domain/ranking_config.dart';
import '../../feed/presentation/feed_screen.dart';
import '../../feed/presentation/travel_sheet.dart';
import '../../live/domain/live_flags.dart';
import '../../live/presentation/live_entry.dart';
import '../../notifications/data/notification_router.dart';
import '../../notifications/data/notification_service.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../integrations/domain/integration_connector.dart';
import '../../match/data/match_service.dart';
import '../../match/presentation/likes_received_screen.dart';
import '../../stories/data/story_service.dart';
import '../../monetization/data/boost_service.dart';
import '../../monetization/data/purchase_delivery_router.dart';
import '../../monetization/presentation/boost_store_sheet.dart';
import '../../monetization/data/entitlement_service.dart';
import '../../monetization/data/feature_flag_service.dart';
import '../../monetization/domain/monetization_feature_flags.dart';
import '../../monetization/domain/premium_feature.dart';
import '../../monetization/domain/subscription_tier.dart';
import '../../monetization/presentation/entitlement_controller.dart';
import '../../monetization/presentation/paywall_screen.dart';
import '../../profile/data/profile_summary_repository.dart';
import '../../profile/domain/intro_media.dart';
import '../../profile/domain/profile_prompt.dart';
import '../../spark/data/spark_service.dart';
import '../../profile/domain/profile_state.dart';
import '../../profile/domain/profile_trait.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/presentation/settings_controller.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../tutorial/presentation/tutorial_screen.dart';
import 'home_screen.dart';

/// Contenedor principal tras el onboarding: bottom-nav con Feed (por defecto)
/// y Perfil. El perfil se sigue pudiendo completar desde su pestaña (Bumble).
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.onLogout,
    required this.onLoadProfileState,
    required this.onUploadAdditionalPhoto,
    required this.onDeleteAdditionalPhoto,
    this.onReorderPhotos,
    required this.onAddPrompt,
    required this.onClaimReward,
    required this.onLoadSeedProfiles,
    required this.onDeleteAccount,
    required this.onLoadProfileRaw,
    required this.onSetTrait,
    required this.onSetTraitVisibility,
    required this.onLoadProfilePrompts,
    required this.onSaveProfilePrompts,
    required this.onLoadIntroMedia,
    required this.onUploadIntroAudio,
    required this.onDeleteIntroAudio,
    required this.onUploadIntroVideo,
    required this.onDeleteIntroVideo,
    required this.settingsRepository,
    required this.entitlementService,
    required this.featureFlagService,
    required this.matchService,
    required this.chatService,
    this.datePlanService,
    this.friendModeService,
    this.friendGroupService,
    this.socialDiscoveryService,
    this.safeDateService,
    this.onSetIntentMode,
    this.onSaveDeviceLocation,
    this.boostService,
    this.sparkService,
    this.feedMetricsService,
    this.notificationService,
    required this.profileSummaryRepository,
    required this.rankingSignalsRepository,
    required this.storyService,
    required this.aiVisualService,
    required this.onSetAiConsent,
    required this.onSetSlowDating,
    this.onSetBusyMode,
    required this.onSetThemeMode,
    this.onRefreshUser,
    required this.onRepublishDiscovery,
    required this.onSetTravelLocation,
    required this.onLoadProfileByUid,
    this.integrationConnector,
    this.user,
    this.errorMessage,
    this.showTutorial = false,
    this.onCompleteTutorial,
  });

  final AppUser? user;
  final String? errorMessage;

  /// True cuando el usuario acaba de completar el onboarding (nuevo): muestra el
  /// tutorial de bienvenida una sola vez. Los usuarios existentes lo reciben en
  /// false (y pueden reverlo desde Ajustes).
  final bool showTutorial;

  /// Persiste que el tutorial (obligatorio) se completó, para no repetirlo.
  final VoidCallback? onCompleteTutorial;
  final VoidCallback onLogout;
  final Future<ProfileCompletionState> Function() onLoadProfileState;
  final Future<void> Function({
    required Uint8List photoBytes,
    required String fileExtension,
    required String source,
  }) onUploadAdditionalPhoto;
  final Future<void> Function(String storagePath) onDeleteAdditionalPhoto;

  /// Reordena las fotos adicionales (arrastrar para colocar). Null = deshabilita
  /// el reordenar.
  final Future<void> Function(List<String> orderedStoragePaths)?
      onReorderPhotos;
  final Future<void> Function(String prompt) onAddPrompt;
  final Future<void> Function(String rewardId) onClaimReward;
  final Future<List<SeedProfile>> Function() onLoadSeedProfiles;
  final Future<void> Function() onDeleteAccount;
  final Future<Map<String, dynamic>> Function() onLoadProfileRaw;
  final Future<void> Function(ProfileTraitDefinition def, Object? value)
      onSetTrait;
  final Future<void> Function(
    String traitKey, {
    required bool visibleInProfile,
    required bool useForMatching,
    required bool useForFilters,
  }) onSetTraitVisibility;
  final Future<List<ProfilePrompt>> Function() onLoadProfilePrompts;
  final Future<void> Function(List<ProfilePrompt> prompts) onSaveProfilePrompts;
  final Future<({IntroAudio? audio, IntroVideo? video})> Function()
      onLoadIntroMedia;
  final Future<void> Function({
    required Uint8List bytes,
    required String contentType,
    required String extension,
    required int durationMs,
  }) onUploadIntroAudio;
  final Future<void> Function() onDeleteIntroAudio;
  final Future<void> Function({
    required Uint8List bytes,
    required String contentType,
    required String extension,
    required int durationMs,
  }) onUploadIntroVideo;
  final Future<void> Function() onDeleteIntroVideo;
  final SettingsRepository settingsRepository;
  final EntitlementService entitlementService;
  final FeatureFlagService featureFlagService;
  final MatchService matchService;
  final ChatService chatService;
  final DatePlanService? datePlanService;
  final FriendModeService? friendModeService;
  final FriendGroupService? friendGroupService;
  final SocialDiscoveryService? socialDiscoveryService;
  final SafeDateService? safeDateService;

  /// Modo Amigos: cambia la intención y recarga el usuario (vía SessionController).
  final Future<void> Function(IntentMode mode)? onSetIntentMode;

  /// Persiste la ubicación del dispositivo (lat/lng + permiso) cuando el feed la
  /// obtiene o la refresca: escribe `users/{uid}.location` (con la marca de
  /// frescura) y republica `discovery/{uid}`.
  final PersistDeviceLocation? onSaveDeviceLocation;
  final BoostService? boostService;
  final SparkService? sparkService;
  final FeedMetricsService? feedMetricsService;
  final NotificationService? notificationService;
  final ProfileSummaryRepository profileSummaryRepository;
  final RankingSignalsRepository rankingSignalsRepository;
  final StoryService storyService;
  final AiVisualService aiVisualService;
  final Future<void> Function(bool granted) onSetAiConsent;
  final Future<void> Function(bool value) onSetSlowDating;

  /// Attra Clear §4: activa/desactiva el modo ocupado. Opcional.
  final Future<void> Function({
    required bool enabled,
    DateTime? until,
    String reason,
    bool visibleToMatches,
  })? onSetBusyMode;

  /// Cambia el modo de tema (claro/oscuro/sistema) desde Ajustes.
  final Future<void> Function(ThemeMode mode) onSetThemeMode;

  /// Re-publica el doc público de discovery (efecto inmediato de los ajustes de
  /// visibilidad/ubicación en el feed).
  /// Recarga el documento del usuario (saldos incluidos). Se llama tras
  /// entregar una compra: el backend abona el saldo pero `AppUser` no es
  /// reactivo, así que sin esto la app seguía diciendo "Tienes 0 boosts".
  final Future<void> Function()? onRefreshUser;
  final Future<void> Function() onRepublishDiscovery;

  /// Modo viajes (Plus/Pro): fija/desactiva el destino del feed.
  final Future<void> Function({
    required bool active,
    String iso2,
    String city,
    String country,
  }) onSetTravelLocation;
  final Future<SeedProfile?> Function(String uid) onLoadProfileByUid;
  final IntegrationConnector? integrationConnector;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

enum _HomeDestination {
  discover,
  connections,
  chats,
  profile,
}

class _HomeShellState extends State<HomeShell> {
  _HomeDestination _destination = _HomeDestination.discover;
  int _feedReloadToken = 0;
  int _visualSearchToken = 0;

  /// Paso actual del tour guiado (-1 = inactivo). Cada paso resalta una pestaña.
  int _tourStep = -1;

  static const List<_TourStep> _tourSteps = <_TourStep>[
    _TourStep(
      _HomeDestination.discover,
      Icons.explore_rounded,
      'Descubrir',
      'Personas seleccionadas según tus preferencias, con contexto para '
          'decidir con calma.',
    ),
    _TourStep(
      _HomeDestination.connections,
      Icons.favorite_rounded,
      'Conexiones',
      'Tus likes y matches viven juntos para que siempre sepas qué está '
          'pasando.',
    ),
    _TourStep(
      _HomeDestination.chats,
      Icons.forum_rounded,
      'Chats',
      'Continúa las conversaciones y propón un plan cuando tenga sentido.',
    ),
    _TourStep(
      _HomeDestination.profile,
      Icons.person_rounded,
      'Perfil',
      'Ajusta cómo te presentas, qué buscas y tus preferencias de seguridad.',
    ),
  ];
  SettingsController? _settingsController;
  EntitlementController? _entitlementController;
  PurchaseDeliveryRouter? _purchases;
  PendingConversationsController? _pendingController;

  /// Attra Clear: config remota (flags `anti_ghosting_*`) con fallback seguro.
  AntiGhostingConfig get _antiGhosting =>
      AntiGhostingConfig.fromMap(_entitlementController?.flags.rawConfig);

  @override
  void initState() {
    super.initState();
    _maybeBuildSessionControllers();
    // Protección anti-captura global según el ajuste del usuario (Seguridad).
    ScreenGuard.setGlobal(widget.user?.screenshotProtectionEnabled ?? false);
    // Consentimiento de analítica (Datos): opt-out detiene la telemetría.
    widget.feedMetricsService?.analyticsEnabled =
        widget.user?.analyticsConsent ?? true;
    // Routing de notificaciones push: consume una ruta pendiente (tap con la
    // app cerrada) y escucha futuros taps (background).
    NotificationRouter.instance.pendingRoute.addListener(_onPushRoute);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPushRoute());
    // Tutorial de bienvenida OBLIGATORIO para nuevos usuarios: carrusel a
    // pantalla completa (no se puede saltar) + tour guiado por las pestañas.
    if (widget.showTutorial) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runIntroFlow());
    }
  }

  /// Slideshow no-saltable → tour guiado por las pestañas → persiste completado.
  Future<void> _runIntroFlow() async {
    if (!mounted) return;
    await TutorialScreen.show(context);
    if (!mounted) return;
    setState(() {
      _destination = _HomeDestination.discover;
      _tourStep = 0;
    });
  }

  /// Avanza el tour guiado: cambia a la pestaña del paso y, al terminar, cierra
  /// el tour y persiste que el tutorial se completó (no se repite).
  void _tourNext() {
    if (_tourStep < 0) return;
    if (_tourStep >= _tourSteps.length - 1) {
      setState(() => _tourStep = -1);
      widget.onCompleteTutorial?.call();
      return;
    }
    setState(() {
      _tourStep++;
      _destination = _tourSteps[_tourStep].destination;
    });
  }

  void _onPushRoute() {
    final String? route = NotificationRouter.instance.consume();
    if (route == null) return;
    final _HomeDestination? destination = _destinationForRoute(route);
    if (destination != null && mounted) {
      setState(() => _destination = destination);
    }
  }

  @override
  void didUpdateWidget(HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user?.uid != widget.user?.uid) {
      _disposeSessionControllers();
      _maybeBuildSessionControllers();
    } else if (oldWidget.user != widget.user) {
      // Mismo uid, datos espejo (consent/saldo) actualizados.
      _entitlementController?.updateUser(widget.user);
    }
    if (oldWidget.user?.screenshotProtectionEnabled !=
        widget.user?.screenshotProtectionEnabled) {
      ScreenGuard.setGlobal(widget.user?.screenshotProtectionEnabled ?? false);
    }
    widget.feedMetricsService?.analyticsEnabled =
        widget.user?.analyticsConsent ?? true;
  }

  void _maybeBuildSessionControllers() {
    final String? uid = widget.user?.uid;
    if (uid == null) return;

    final EntitlementController entitlements = EntitlementController(
      entitlementService: widget.entitlementService,
      featureFlagService: widget.featureFlagService,
      uid: uid,
      user: widget.user,
    );
    _entitlementController = entitlements;
    // Refresca etiquetas/locks cuando llegan entitlements/flags.
    entitlements.addListener(_onEntitlementsChanged);
    entitlements.load();

    _settingsController = SettingsController(
      repository: widget.settingsRepository,
      uid: uid,
      onDeleteAccount: () async => widget.onDeleteAccount(),
      premiumResolver: () => entitlements.isPremiumActive,
      integrationConnector: widget.integrationConnector,
      onVisibilityChanged: widget.onRepublishDiscovery,
    );

    // Attra Clear §2: observa los chats para contar conversaciones pendientes.
    _pendingController = PendingConversationsController(
      chatService: widget.chatService,
      uid: uid,
    )..addListener(_onEntitlementsChanged);

    // Entrega de compras a nivel de SESIÓN. Antes la escucha del purchaseStream
    // solo existía mientras el paywall estaba abierto, así que una compra que se
    // resolvía después (pago diferido, red lenta, app reabierta) no se entregaba
    // ni se completaba: el usuario pagaba y no recibía nada.
    final BoostService? boosts = widget.boostService;
    if (boosts != null) {
      final PurchaseDeliveryRouter router =
          PurchaseDeliveryRouter(boostService: boosts);
      router.onSubscriptionDelivered = () {
        _entitlementController?.load();
        widget.onRefreshUser?.call();
      };
      // El saldo de consumibles vive en el documento del usuario, no en los
      // entitlements: hay que recargarlo o la compra no se ve ni se puede usar.
      router.onConsumableDelivered = (_, __) {
        _onEntitlementsChanged();
        widget.onRefreshUser?.call();
      };
      _purchases = router;
      router.start(subscriptionIds: _subscriptionProductIds);
    }
  }

  /// IDs de suscripción que la sesión vigila. Deben coincidir con los que usa
  /// PaywallScreen y con PRODUCT_TIER del backend.
  static const Set<String> _subscriptionProductIds = <String>{
    'attra_plus',
    'attra_plus_monthly',
    'attra_plus_yearly',
    'attra_pro',
    'attra_pro_monthly',
    'attra_pro_yearly',
  };

  void _onEntitlementsChanged() {
    if (mounted) setState(() {});
  }

  void _disposeSessionControllers() {
    _entitlementController?.removeListener(_onEntitlementsChanged);
    _entitlementController?.dispose();
    _entitlementController = null;
    _settingsController?.dispose();
    _settingsController = null;
    _pendingController?.removeListener(_onEntitlementsChanged);
    _pendingController?.dispose();
    _pendingController = null;
    _purchases?.dispose();
    _purchases = null;
  }

  @override
  void dispose() {
    NotificationRouter.instance.pendingRoute.removeListener(_onPushRoute);
    _disposeSessionControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String uid = widget.user?.uid ?? '';

    void goTo(_HomeDestination destination) {
      // Durante el tour guiado, la navegación la controla el tour (obligatorio).
      if (_tourStep >= 0) return;
      setState(() {
        if (destination == _HomeDestination.discover &&
            _destination != _HomeDestination.discover) {
          _feedReloadToken++;
        }
        _destination = destination;
      });
    }

    final int attrasBalance = _entitlementController?.attrasBalance ?? 0;

    final bool isPro = _entitlementController?.isProActive ?? false;
    final bool slowDating = widget.user?.slowDatingEnabled ?? false;
    final Widget feedTab = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
              color: Colors.white,
            ),
        title: slowDating
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _AttraTitleLogo(),
                  SizedBox(width: 10),
                  _SlowDatingBadge(),
                ],
              )
            : const _AttraTitleLogo(),
        actions: <Widget>[
          // FEED EN VIVO: único punto de entrada de la app. Detrás de
          // `feature_live_enabled` (OFF por defecto, como se hizo con
          // SafeDate): con la flag apagada este widget no se construye y el
          // directo es literalmente inalcanzable.
          if (_liveFlags.active && uid.isNotEmpty)
            LiveEntryButton(onTap: _openLive),
          if (widget.notificationService != null && uid.isNotEmpty)
            NotificationBell(
              service: widget.notificationService!,
              uid: uid,
              onTap: _openNotifications,
            ),
        ],
      ),
      body: FeedScreen(
        user: widget.user,
        onLoadSeedProfiles: widget.onLoadSeedProfiles,
        matchService: widget.matchService,
        chatService: widget.chatService,
        sparkService: widget.sparkService,
        sparkEnabled: _entitlementController?.sparkEnabled ?? false,
        attrasBalance: attrasBalance,
        canComment: _entitlementController?.isPlusActive ?? false,
        reloadToken: _feedReloadToken,
        visualSearchToken: _visualSearchToken,
        storyService: widget.storyService,
        isPlus: _entitlementController?.isPlusActive ?? false,
        canRewind:
            _entitlementController?.hasFeature(PremiumFeature.rewind) ?? false,
        rewindUnlimited: _entitlementController?.isProActive ?? false,
        onOpenUpgrade: _openPaywall,
        aiVisualService: widget.aiVisualService,
        canUseVisualMatch:
            (_entitlementController?.canUseAiVisualMatching ?? false) &&
                (widget.user?.aiVisualConsent ?? false),
        canSeeLikedMe: _entitlementController?.canSeeAllLikes ?? false,
        metrics: widget.feedMetricsService,
        boostService: widget.boostService,
        // Anuncios: flag activo Y el usuario NO es Plus/Pro (premium sin ads).
        adsEnabled: (_entitlementController?.flags.adsEnabled ?? false) &&
            !(_entitlementController?.isPlusActive ?? false),
        canUseTravelMode: _entitlementController?.canUseTravelMode ?? false,
        onOpenTravel: _openTravelSheet,
        // Ranking inteligente: señales server-side + config remota. Detrás del
        // flag `ranking_enabled` (default off hasta desplegar el backend).
        rankingSignals: widget.rankingSignalsRepository,
        rankingConfig: RankingConfig.fromMap(
            _entitlementController?.flags.rawConfig ??
                const <String, dynamic>{}),
        // Attra Clear §2: límite suave de conversaciones pendientes.
        antiGhostingConfig: _antiGhosting,
        pendingController: _pendingController,
        isBusy: widget.user?.busyModeActive ?? false,
        isPro: _entitlementController?.isProActive ?? false,
        onOpenChats: () => goTo(_HomeDestination.chats),
        // Modo Amigos: acceso a grupos desde el feed cuando estás en modo social.
        onOpenGroups: (widget.friendGroupService == null ||
                widget.socialDiscoveryService == null)
            ? null
            : _openGroups,
        // Persiste la ubicación del dispositivo (completitud del perfil + feed).
        onDeviceLocation: widget.onSaveDeviceLocation,
      ),
    );

    final Widget likesTab = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
              color: Colors.white,
            ),
        title: Text(l10n.likesTitle),
      ),
      body: uid.isEmpty
          ? const SizedBox.shrink()
          : LikesReceivedScreen(
              currentUid: uid,
              matchService: widget.matchService,
              chatService: widget.chatService,
              summaries: widget.profileSummaryRepository,
              showCompatibility: _entitlementController?.isProActive ?? false,
              // Ventaja nº1 que vende el paywall de Plus. Estaba prometida y
              // cobrada, pero no se aplicaba: la tenía todo el mundo gratis.
              canSeeAllLikes: _entitlementController?.canSeeAllLikes ?? false,
              onUpgrade: _openPaywall,
              currentUserInterests: widget.user?.interests ?? const <String>[],
              onImproveProfile: () =>
                  setState(() => _destination = _HomeDestination.profile),
              // El perfil de cada conexión forma parte del flujo principal.
              loadProfile: widget.onLoadProfileByUid,
              sparkService: widget.sparkService,
              sparkEnabled: _entitlementController?.sparkEnabled ?? false,
              currentUserPhotoUrl: widget.user?.photoUrl,
            ),
    );

    final Widget chatsTab = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
              color: Colors.white,
            ),
        title: Text(l10n.chatsTitle),
      ),
      body: uid.isEmpty
          ? const SizedBox.shrink()
          : ChatsScreen(
              currentUid: uid,
              chatService: widget.chatService,
              datePlanService: widget.datePlanService,
              datePlansEnabled:
                  _entitlementController?.flags.datePlansActive ?? false,
              safeDateService: widget.safeDateService,
              safeDatePlanEnabled: _safeDateFlags.datePlanActive,
              safeDateAiRiskEnabled: _safeDateFlags.aiRiskActive,
              safeDateSafePlacesEnabled: _safeDateFlags.safePlacesActive,
              friendGroupService: widget.friendGroupService,
              currentUserName: widget.user?.displayName ?? '',
              matchService: widget.matchService,
              summaries: widget.profileSummaryRepository,
              storyService: widget.storyService,
              loadProfile: widget.onLoadProfileByUid,
              sparkService: widget.sparkService,
              sparkEnabled: _entitlementController?.sparkEnabled ?? false,
              metrics: widget.feedMetricsService,
              journeyEnabled:
                  _entitlementController?.flags.matchJourneyEnabled ?? false,
              icebreakersEnabled:
                  _entitlementController?.flags.icebreakersEnabled ?? false,
              dateBuilderEnabled:
                  _entitlementController?.flags.dateBuilderEnabled ?? false,
              dateBuilderFull:
                  _entitlementController?.journeyLimits.dateBuilderFull ??
                      false,
              thisOrThatEnabled:
                  _entitlementController?.flags.thisOrThatEnabled ?? false,
              doubleAnswerEnabled:
                  (_entitlementController?.flags.miniGamesEnabled ?? false) &&
                      (_entitlementController?.flags.doubleAnswerEnabled ??
                          false),
              twoTruthsEnabled:
                  (_entitlementController?.flags.miniGamesEnabled ?? false) &&
                      (_entitlementController?.flags.twoTruthsEnabled ?? false),
              chatGameEnabled:
                  (_entitlementController?.flags.miniGamesEnabled ?? false) &&
                      (_entitlementController?.flags.chatGameEnabled ?? false),
              matchReactivationEnabled:
                  (_entitlementController?.flags.matchReactivationEnabled ??
                          false) &&
                      (_entitlementController?.journeyLimits.canReactivate ??
                          false),
              antiGhostingEnabled: _antiGhosting.enabled,
              closeGracefullyEnabled:
                  _antiGhosting.enabled && _antiGhosting.closeGracefullyEnabled,
              nudgesEnabled:
                  _antiGhosting.enabled && _antiGhosting.nudgesEnabled,
              dateFollowupEnabled:
                  _antiGhosting.enabled && _antiGhosting.dateFollowupEnabled,
              onDiscover: () => goTo(_HomeDestination.discover),
            ),
    );

    final Widget profileTab = HomeScreen(
      user: widget.user,
      errorMessage: widget.errorMessage,
      onLogout: widget.onLogout,
      onLoadProfileState: widget.onLoadProfileState,
      onUploadAdditionalPhoto: widget.onUploadAdditionalPhoto,
      onDeleteAdditionalPhoto: widget.onDeleteAdditionalPhoto,
      onReorderPhotos: widget.onReorderPhotos,
      onAddPrompt: widget.onAddPrompt,
      onClaimReward: widget.onClaimReward,
      onLoadSeedProfiles: widget.onLoadSeedProfiles,
      onDeleteAccount: widget.onDeleteAccount,
      onLoadProfileRaw: widget.onLoadProfileRaw,
      onSetTrait: widget.onSetTrait,
      onSetTraitVisibility: widget.onSetTraitVisibility,
      onLoadProfilePrompts: widget.onLoadProfilePrompts,
      onSaveProfilePrompts: widget.onSaveProfilePrompts,
      onLoadIntroMedia: widget.onLoadIntroMedia,
      onUploadIntroAudio: widget.onUploadIntroAudio,
      onDeleteIntroAudio: widget.onDeleteIntroAudio,
      onUploadIntroVideo: widget.onUploadIntroVideo,
      onDeleteIntroVideo: widget.onDeleteIntroVideo,
      onOpenSettings: _settingsController == null ? null : _openSettings,
      onOpenUpgrade: _openPaywall,
      currentPlanLabel:
          (_entitlementController?.tier ?? SubscriptionTier.free).label,
      isProUser: isPro,
      onOpenAiVisual: _openAiVisual,
      // SafeDate: entrada al centro solo si el master switch remoto está ON y
      // hay servicio inyectado. OFF por defecto → invisible.
      onOpenBoostStore: widget.boostService == null ? null : _openBoostStore,
      onOpenSafeDate: (_safeDateFlags.enabled && widget.safeDateService != null)
          ? _openSafeDate
          : null,
      onSetSlowDating: widget.onSetSlowDating,
      // Modo Amigos: solo si hay callback inyectado (si no, se oculta).
      onOpenFriendMode: widget.onSetIntentMode == null ? null : _openFriendMode,
      onOpenGroups: (widget.friendGroupService == null ||
              widget.socialDiscoveryService == null)
          ? null
          : _openGroups,
    );

    final List<Widget> tabs = <Widget>[
      feedTab,
      likesTab,
      chatsTab,
      profileTab,
    ];

    final List<NavigationDestination> destinations = <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Icons.explore_outlined),
        selectedIcon: const Icon(Icons.explore_rounded),
        label: l10n.navFeed,
      ),
      NavigationDestination(
        icon: const Icon(Icons.favorite_border_rounded),
        selectedIcon: const Icon(Icons.favorite_rounded),
        label: l10n.navLikes,
      ),
      NavigationDestination(
        icon: const Icon(Icons.forum_outlined),
        selectedIcon: const Icon(Icons.forum_rounded),
        label: l10n.navChats,
      ),
      NavigationDestination(
        icon: const Icon(Icons.person_outline_rounded),
        selectedIcon: const Icon(Icons.person_rounded),
        label: l10n.navProfile,
      ),
    ];

    return Scaffold(
      body: AttraAppShellBackground(
        child: Stack(
          children: <Widget>[
            IndexedStack(index: _destination.index, children: tabs),
            // Tour guiado (obligatorio): superpuesto sobre el cuerpo; la barra de
            // navegación queda visible abajo, con la pestaña del paso resaltada.
            if (_tourStep >= 0)
              _TourOverlay(
                step: _tourStep,
                total: _tourSteps.length,
                stepData: _tourSteps[_tourStep],
                onNext: _tourNext,
              ),
          ],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: context.colors.surfaceLine),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _destination.index,
          onDestinationSelected: (int index) =>
              goTo(_HomeDestination.values[index]),
          destinations: destinations,
        ),
      ),
    );
  }

  void _openAiVisual() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AiVisualScreen(
        uid: widget.user?.uid ?? '',
        isPro: _entitlementController?.isProActive ?? false,
        hasConsent: widget.user?.aiVisualConsent ?? false,
        service: widget.aiVisualService,
        onUpgrade: _openPaywall,
        onGiveConsent: () => widget.onSetAiConsent(true),
        onRevokeConsent: () => widget.onSetAiConsent(false),
        // Activa el filtro de parecidos y lleva al feed: antes el botón
        // principal de la IA visual no hacía nada.
        onSearchSimilar: () => setState(() {
          _visualSearchToken++;
          _destination = _HomeDestination.discover;
        }),
      ),
    ));
  }

  /// Modo Amigos: abre el selector de intención y persiste el cambio a través
  /// de SessionController (escribe con los campos requeridos por las reglas Y
  /// recarga el usuario, para que el perfil y el feed reflejen el cambio ya).
  Future<void> _openFriendMode() async {
    final Future<void> Function(IntentMode)? setMode = widget.onSetIntentMode;
    if (setMode == null) return;
    final IntentMode current = widget.user?.intentMode ?? IntentMode.dating;
    final IntentMode? chosen = await IntentModeSelector.show(context, current);
    if (chosen == null || chosen == current) return;
    try {
      await setMode(chosen);
      if (mounted) {
        setState(
            () => _feedReloadToken++); // refresca el feed con el nuevo modo
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Modo actualizado')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo cambiar el modo.')));
      }
    }
  }

  /// Config remota de SafeDate (todo OFF por defecto; fallback seguro).
  SafeDateFlags get _safeDateFlags => SafeDateFlags.fromMap(
      _entitlementController?.flags.rawConfig ?? const <String, dynamic>{});

  /// Config remota del directo (OFF por defecto; fallback seguro).
  LiveFlags get _liveFlags => LiveFlags.fromMap(
      _entitlementController?.flags.rawConfig ?? const <String, dynamic>{});

  /// Abre el directo (vídeo 1:1 con desconocidos).
  ///
  /// Al hacer match desde ahí, el chat ya existe (lo crea el backend con el
  /// mismo `writeMatchAndChat` que el resto de la app): cerramos el directo y
  /// llevamos a Chats. No abrimos la conversación concreta porque
  /// `ChatDetailScreen` se monta desde la lista con su propio contexto, y
  /// duplicar aquí ese cableado sería otra copia que mantener.
  void _openLive() {
    final String uid = widget.user?.uid ?? '';
    if (uid.isEmpty) return;
    openLiveScreen(
      context,
      uid: uid,
      matchService: widget.matchService,
      profileSummaryRepository: widget.profileSummaryRepository,
      onOpenChat: (String _, String __) {
        Navigator.of(context).maybePop();
        if (mounted) setState(() => _destination = _HomeDestination.chats);
      },
    );
  }

  /// Abre el centro de Attra SafeDate (solo si el master switch está ON).
  void _openSafeDate() {
    final SafeDateService? svc = widget.safeDateService;
    final String uid = widget.user?.uid ?? '';
    if (svc == null || uid.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SafeDateHomeScreen(
        uid: uid,
        service: svc,
        flags: _safeDateFlags,
      ),
    ));
  }

  /// Modo Amigos: abre la pantalla de grupos y planes.
  void _openGroups() {
    final FriendGroupService? gs = widget.friendGroupService;
    final SocialDiscoveryService? ds = widget.socialDiscoveryService;
    final String uid = widget.user?.uid ?? '';
    if (gs == null || ds == null || uid.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GroupsScreen(
        uid: uid,
        groupService: gs,
        discoveryService: ds,
        summaries: widget.profileSummaryRepository,
        currentUserName: widget.user?.displayName ?? '',
        city: widget.user?.city ?? '',
        myInterests: widget.user?.socialInterests ?? const <String>[],
      ),
    ));
  }

  Future<void> _openTravelSheet() async {
    await showTravelSheet(
      context,
      canUseTravelMode: _entitlementController?.canUseTravelMode ?? false,
      active: widget.user?.isTraveling ?? false,
      iso2: widget.user?.travelIso2,
      city: widget.user?.travelCity,
      country: widget.user?.travelCountry,
      onApply: widget.onSetTravelLocation,
      onUpgrade: () {
        Navigator.of(context).maybePop();
        _openPaywall();
      },
    );
    // Tras cambiar el destino, refresca el feed (re-centra la ubicación).
    if (mounted) setState(() => _feedReloadToken++);
  }

  /// Tienda de Boosts y Swipes. Usa el MISMO IapService de la sesión para que
  /// no haya dos escuchas del stream compitiendo por la misma compra.
  void _openBoostStore() {
    final BoostService? service = widget.boostService;
    if (service == null) return;
    showBoostStoreSheet(
      context,
      service: service,
      user: widget.user,
      iapService: _purchases?.iap,
      purchases: _purchases,
      flags: _entitlementController?.flags ?? const MonetizationFeatureFlags(),
      onChanged: () => _entitlementController?.load(),
    );
  }

  void _openPaywall() {
    final SubscriptionTier tier =
        _entitlementController?.tier ?? SubscriptionTier.free;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PaywallScreen(
        currentTier: tier,
        // Flags REMOTOS: los numeros del paywall (Attras/Boosts al mes, tope de
        // likes) salen de aqui. Con los defaults compilados, cambiar un valor
        // en config/featureFlags dejaria el paywall anunciando el anterior.
        flags:
            _entitlementController?.flags ?? const MonetizationFeatureFlags(),
        iapService: _purchases?.iap,
        verifySubscription: widget.boostService == null
            ? null
            : ({
                required String productId,
                required String platform,
                required String verificationData,
                String? purchaseId,
                String? period,
              }) =>
                widget.boostService!.verifySubscription(
                  productId: productId,
                  platform: platform,
                  verificationData: verificationData,
                  purchaseId: purchaseId,
                  period: period,
                ),
        onPurchased: () => _entitlementController?.load(),
      ),
    ));
  }

  void _openNotifications() {
    final NotificationService? service = widget.notificationService;
    final String uid = widget.user?.uid ?? '';
    if (service == null || uid.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NotificationsScreen(
        service: service,
        uid: uid,
        onOpenRoute: _handleNotifRoute,
      ),
    ));
  }

  /// Destino principal para una ruta lógica de notificación.
  _HomeDestination? _destinationForRoute(String route) {
    switch (route.split(':').first) {
      case 'feed':
        return _HomeDestination.discover;
      case 'likes':
        return _HomeDestination.connections;
      case 'chats':
      case 'chat':
        return _HomeDestination.chats;
      case 'profile':
        return _HomeDestination.profile;
    }
    return null;
  }

  /// Desde la bandeja in-app: cierra la bandeja y cambia de pestaña.
  void _handleNotifRoute(String route) {
    final _HomeDestination? destination = _destinationForRoute(route);
    if (destination != null && mounted) {
      Navigator.of(context).maybePop(); // cierra la bandeja
      setState(() => _destination = destination);
    }
  }

  void _openSettings() {
    final SettingsController? c = _settingsController;
    if (c == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Ajustes')),
        body: SettingsScreen(
          controller: c,
          onSetThemeMode: widget.onSetThemeMode,
          busyModeFeatureEnabled:
              _antiGhosting.enabled && _antiGhosting.busyModeEnabled,
          initialBusyUntil: widget.user?.busyModeUntilOrNull,
          onSetBusyMode: widget.onSetBusyMode,
        ),
      ),
    ));
  }
}

class _AttraTitleLogo extends StatelessWidget {
  const _AttraTitleLogo();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Attra',
      image: true,
      child: Image.asset(
        'assets/images/ATTRA.png',
        height: 28,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        // El wordmark conserva el blanco original sobre la cabecera oscura.
        color: Colors.white,
      ),
    );
  }
}

/// Distintivo visible cuando Slow Dating está activo (junto al título del feed).
class _SlowDatingBadge extends StatelessWidget {
  const _SlowDatingBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.accentSoft,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(
          color: context.colors.accent.withValues(alpha: 0.42),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.spa_rounded, size: 13, color: context.colors.accent),
          const SizedBox(width: 5),
          Text(
            'Slow Dating',
            style: TextStyle(
              color: context.colors.accent,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Un paso del tour guiado: qué pestaña resalta y qué explica.
class _TourStep {
  const _TourStep(this.destination, this.icon, this.title, this.body);
  final _HomeDestination destination;
  final IconData icon;
  final String title;
  final String body;
}

/// Superposición del tour guiado: una tarjeta sobre la barra de navegación que
/// explica la pestaña actual (ya seleccionada). No se puede cerrar sin avanzar
/// (tutorial obligatorio). Un foco resalta el destino activo abajo.
class _TourOverlay extends StatelessWidget {
  const _TourOverlay({
    required this.step,
    required this.total,
    required this.stepData,
    required this.onNext,
  });

  final int step;
  final int total;
  final _TourStep stepData;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final bool isLast = step >= total - 1;
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.62),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              const Spacer(),
              // Tarjeta explicativa.
              Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(color: context.colors.surfaceLine),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: context.colors.accentSoft,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusMd),
                          ),
                          child: Icon(stepData.icon,
                              color: context.colors.accent, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            stepData.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        Text(
                          '${step + 1}/$total',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      stepData.body,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: <Widget>[
                        for (int i = 0; i < total; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 5),
                            width: i == step ? 20 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: i == step
                                  ? context.colors.accent
                                  : context.colors.surfaceLine,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        const Spacer(),
                        FilledButton(
                          onPressed: onNext,
                          child: Text(isLast ? '¡Listo!' : 'Siguiente'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Flecha que apunta a la barra de navegación (pestaña resaltada).
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: context.colors.accent,
                size: 30,
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}
