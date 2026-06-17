import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../ai_visual/data/ai_visual_service.dart';
import '../../ai_visual/presentation/ai_visual_screen.dart';
import '../../auth/domain/app_user.dart';
import '../../chat/data/chat_service.dart';
import '../../chat/presentation/chats_screen.dart';
import '../../feed/data/feed_metrics_service.dart';
import '../../feed/presentation/feed_screen.dart';
import '../../integrations/domain/integration_connector.dart';
import '../../match/data/match_service.dart';
import '../../match/presentation/likes_received_screen.dart';
import '../../stories/data/story_service.dart';
import '../../monetization/data/boost_service.dart';
import '../../monetization/data/entitlement_service.dart';
import '../../monetization/data/feature_flag_service.dart';
import '../../monetization/domain/subscription_tier.dart';
import '../../monetization/presentation/boost_store_sheet.dart';
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
    this.boostService,
    this.sparkService,
    this.feedMetricsService,
    required this.profileSummaryRepository,
    required this.storyService,
    required this.aiVisualService,
    required this.onSetAiConsent,
    required this.onLoadProfileByUid,
    this.integrationConnector,
    this.user,
    this.errorMessage,
  });

  final AppUser? user;
  final String? errorMessage;
  final VoidCallback onLogout;
  final Future<ProfileCompletionState> Function() onLoadProfileState;
  final Future<void> Function({
    required Uint8List photoBytes,
    required String fileExtension,
    required String source,
  }) onUploadAdditionalPhoto;
  final Future<void> Function(String storagePath) onDeleteAdditionalPhoto;
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
  final BoostService? boostService;
  final SparkService? sparkService;
  final FeedMetricsService? feedMetricsService;
  final ProfileSummaryRepository profileSummaryRepository;
  final StoryService storyService;
  final AiVisualService aiVisualService;
  final Future<void> Function(bool granted) onSetAiConsent;
  final Future<SeedProfile?> Function(String uid) onLoadProfileByUid;
  final IntegrationConnector? integrationConnector;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  int _feedReloadToken = 0;
  SettingsController? _settingsController;
  EntitlementController? _entitlementController;

  @override
  void initState() {
    super.initState();
    _maybeBuildSessionControllers();
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
    );
  }

  void _onEntitlementsChanged() {
    if (mounted) setState(() {});
  }

  void _disposeSessionControllers() {
    _entitlementController?.removeListener(_onEntitlementsChanged);
    _entitlementController?.dispose();
    _entitlementController = null;
    _settingsController?.dispose();
    _settingsController = null;
  }

  @override
  void dispose() {
    _disposeSessionControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String uid = widget.user?.uid ?? '';
    final int attrasBalance = _entitlementController?.attrasBalance ?? 0;

    final bool isPro = _entitlementController?.isProActive ?? false;
    final bool slowDating = widget.user?.slowDatingEnabled ?? false;
    final Widget feedTab = Scaffold(
      appBar: AppBar(
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
          if (widget.boostService != null)
            IconButton(
              tooltip: 'Boosts y Swipes',
              icon: const Icon(Icons.bolt_rounded, color: Color(0xFFFF4F68)),
              onPressed: _openBoostStore,
            ),
          if (!isPro)
            TextButton.icon(
              onPressed: _openPaywall,
              icon:
                  const Icon(Icons.workspace_premium, color: Color(0xFFB8860B)),
              label: const Text('Plus / Pro',
                  style: TextStyle(
                      color: Color(0xFFB8860B), fontWeight: FontWeight.w700)),
            ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: widget.onLogout,
          ),
        ],
      ),
      body: FeedScreen(
        user: widget.user,
        onLoadSeedProfiles: widget.onLoadSeedProfiles,
        matchService: widget.matchService,
        chatService: widget.chatService,
        attrasBalance: attrasBalance,
        canComment: _entitlementController?.isPlusActive ?? false,
        reloadToken: _feedReloadToken,
        storyService: widget.storyService,
        isPlus: _entitlementController?.isPlusActive ?? false,
        aiVisualService: widget.aiVisualService,
        canUseVisualMatch:
            (_entitlementController?.canUseAiVisualMatching ?? false) &&
                (widget.user?.aiVisualConsent ?? false),
        canSeeLikedMe: _entitlementController?.canSeeAllLikes ?? false,
        metrics: widget.feedMetricsService,
        boostService: widget.boostService,
      ),
    );

    final Widget likesTab = Scaffold(
      appBar: AppBar(title: const Text('Likes')),
      body: uid.isEmpty
          ? const SizedBox.shrink()
          : LikesReceivedScreen(
              currentUid: uid,
              matchService: widget.matchService,
              chatService: widget.chatService,
              summaries: widget.profileSummaryRepository,
              canSeeAll: _entitlementController?.canSeeAllLikes ?? false,
              onUpgrade: _openPaywall,
              sparkService: widget.sparkService,
              sparkEnabled: _entitlementController?.sparkEnabled ?? false,
            ),
    );

    final Widget chatsTab = Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: uid.isEmpty
          ? const SizedBox.shrink()
          : ChatsScreen(
              currentUid: uid,
              chatService: widget.chatService,
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
            ),
    );

    final Widget profileTab = HomeScreen(
      user: widget.user,
      errorMessage: widget.errorMessage,
      onLogout: widget.onLogout,
      onLoadProfileState: widget.onLoadProfileState,
      onUploadAdditionalPhoto: widget.onUploadAdditionalPhoto,
      onDeleteAdditionalPhoto: widget.onDeleteAdditionalPhoto,
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
    );

    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: <Widget>[
          feedTab,
          likesTab,
          chatsTab,
          profileTab,
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (int index) => setState(() {
          // Al (re)entrar en Feed, fuerza recarga para re-excluir matched/likeados.
          if (index == 0 && _tab != 0) _feedReloadToken++;
          _tab = index;
        }),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Feed',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'Likes',
          ),
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
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
      ),
    ));
  }

  void _openPaywall() {
    final SubscriptionTier tier =
        _entitlementController?.tier ?? SubscriptionTier.free;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PaywallScreen(
        currentTier: tier,
        onBuyPlus: () => _comingSoon('Attra Plus'),
        onBuyPro: () => _comingSoon('Attra Pro'),
        onRestore: () => _comingSoon('Restaurar compras'),
      ),
    ));
  }

  void _comingSoon(String what) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what: disponible próximamente.')),
    );
  }

  void _openBoostStore() {
    final BoostService? service = widget.boostService;
    if (service == null) return;
    showBoostStoreSheet(
      context,
      service: service,
      user: widget.user,
    );
  }

  void _openSettings() {
    final SettingsController? c = _settingsController;
    if (c == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Ajustes')),
        body: SettingsScreen(controller: c),
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
        color: const Color(0xFFE5384E).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border:
            Border.all(color: const Color(0xFFE5384E).withValues(alpha: 0.5)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.spa_rounded, size: 13, color: Color(0xFFE5384E)),
          SizedBox(width: 5),
          Text(
            'Slow Dating',
            style: TextStyle(
              color: Color(0xFFE5384E),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
