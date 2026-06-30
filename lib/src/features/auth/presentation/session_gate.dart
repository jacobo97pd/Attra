import 'package:flutter/material.dart';

import '../../home/presentation/home_shell.dart';
import '../../onboarding/presentation/onboarding_screen.dart';
import '../../splash/presentation/splash_screen.dart';
import 'login_screen.dart';
import 'session_controller.dart';
import 'session_state.dart';

class SessionGate extends StatelessWidget {
  const SessionGate({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        final SessionState state = controller.state;
        final Widget screen;

        switch (state.status) {
          case SessionStatus.initializing:
          case SessionStatus.loadingProfile:
          case SessionStatus.signingOut:
            screen = const SplashScreen();
            break;
          case SessionStatus.authenticating:
          case SessionStatus.unauthenticated:
            screen = LoginScreen(
              isLoading: state.status == SessionStatus.authenticating,
              errorMessage: state.errorMessage,
              phoneCodeSent: state.phoneCodeSent,
              onGooglePressed: controller.signInWithGoogle,
              onApplePressed: controller.signInWithApple,
              onSendPhoneCode: controller.sendPhoneCode,
              onVerifyPhoneCode: controller.verifyPhoneCode,
            );
            break;
          case SessionStatus.onboardingRequired:
            screen = OnboardingScreen(
              user: state.user,
              errorMessage: state.errorMessage,
              onLoadDraft: controller.loadOnboardingDraft,
              onSaveDraft: controller.saveOnboardingDraft,
              onUploadLiveSelfieDraft:
                  controller.uploadOnboardingLiveSelfieDraft,
              onSubmitOnboarding: controller.submitOnboarding,
              onLogout: controller.signOut,
            );
            break;
          case SessionStatus.authenticated:
            screen = HomeShell(
              user: state.user,
              errorMessage: state.errorMessage,
              showTutorial: state.justOnboarded,
              onLogout: controller.signOut,
              onLoadProfileState: controller.loadProfileCompletionState,
              onUploadAdditionalPhoto: controller.uploadAdditionalPhoto,
              onDeleteAdditionalPhoto: controller.deleteAdditionalPhoto,
              onAddPrompt: controller.addOptionalPrompt,
              onClaimReward: controller.claimProfileReward,
              onLoadSeedProfiles: controller.loadSeedProfiles,
              onDeleteAccount: controller.deleteAccount,
              onLoadProfileRaw: controller.loadProfileRaw,
              onSetTrait: controller.setProfileTrait,
              onSetTraitVisibility: controller.setTraitVisibility,
              onLoadProfilePrompts: controller.loadProfilePrompts,
              onSaveProfilePrompts: controller.saveProfilePrompts,
              onLoadIntroMedia: controller.loadIntroMedia,
              onUploadIntroAudio: controller.uploadIntroAudio,
              onDeleteIntroAudio: controller.deleteIntroAudio,
              onUploadIntroVideo: controller.uploadIntroVideo,
              onDeleteIntroVideo: controller.deleteIntroVideo,
              settingsRepository: controller.settingsRepository,
              entitlementService: controller.entitlementService,
              featureFlagService: controller.featureFlagService,
              matchService: controller.matchService,
              chatService: controller.chatService,
              boostService: controller.boostService,
              sparkService: controller.sparkService,
              feedMetricsService: controller.feedMetricsService,
              notificationService: controller.notificationService,
              profileSummaryRepository: controller.profileSummaryRepository,
              rankingSignalsRepository: controller.rankingSignalsRepository,
              integrationConnector: controller.integrationConnector,
              storyService: controller.storyService,
              aiVisualService: controller.aiVisualService,
              onSetAiConsent: controller.setAiVisualConsent,
              onSetSlowDating: controller.setSlowDatingEnabled,
              onSetThemeMode: controller.setThemeMode,
              onRepublishDiscovery: controller.republishDiscovery,
              onSetTravelLocation: controller.setTravelLocation,
              onLoadProfileByUid: controller.loadProfileByUid,
            );
            break;
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          child: KeyedSubtree(
            key: ValueKey<SessionStatus>(state.status),
            child: screen,
          ),
        );
      },
    );
  }
}
