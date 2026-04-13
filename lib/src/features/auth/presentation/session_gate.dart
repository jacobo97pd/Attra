import 'package:flutter/material.dart';

import '../../home/presentation/home_screen.dart';
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

        switch (state.status) {
          case SessionStatus.initializing:
          case SessionStatus.loadingProfile:
          case SessionStatus.signingOut:
            return const SplashScreen();
          case SessionStatus.authenticating:
          case SessionStatus.unauthenticated:
            return LoginScreen(
              isLoading: state.status == SessionStatus.authenticating,
              errorMessage: state.errorMessage,
              phoneCodeSent: state.phoneCodeSent,
              onGooglePressed: controller.signInWithGoogle,
              onApplePressed: controller.signInWithApple,
              onSendPhoneCode: controller.sendPhoneCode,
              onVerifyPhoneCode: controller.verifyPhoneCode,
            );
          case SessionStatus.onboardingRequired:
            return OnboardingScreen(
              user: state.user,
              errorMessage: state.errorMessage,
              onLoadDraft: controller.loadOnboardingDraft,
              onSaveDraft: controller.saveOnboardingDraft,
              onUploadLiveSelfieDraft:
                  controller.uploadOnboardingLiveSelfieDraft,
              onSubmitOnboarding: controller.submitOnboarding,
              onLogout: controller.signOut,
            );
          case SessionStatus.authenticated:
            return HomeScreen(
              user: state.user,
              errorMessage: state.errorMessage,
              onLogout: controller.signOut,
              onLoadProfileState: controller.loadProfileCompletionState,
              onUploadAdditionalPhoto: controller.uploadAdditionalPhoto,
              onDeleteAdditionalPhoto: controller.deleteAdditionalPhoto,
              onAddPrompt: controller.addOptionalPrompt,
              onClaimReward: controller.claimProfileReward,
              onLoadSeedProfiles: controller.loadSeedProfiles,
              onDeleteAccount: controller.deleteAccount,
            );
        }
      },
    );
  }
}
