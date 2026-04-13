import '../domain/app_user.dart';

enum SessionStatus {
  initializing,
  unauthenticated,
  authenticating,
  loadingProfile,
  onboardingRequired,
  authenticated,
  signingOut,
}

class SessionState {
  const SessionState({
    required this.status,
    this.user,
    this.errorMessage,
    this.phoneCodeSent = false,
  });

  const SessionState.initializing()
      : status = SessionStatus.initializing,
        user = null,
        errorMessage = null,
        phoneCodeSent = false;

  final SessionStatus status;
  final AppUser? user;
  final String? errorMessage;
  final bool phoneCodeSent;

  SessionState copyWith({
    SessionStatus? status,
    AppUser? user,
    bool clearUser = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? phoneCodeSent,
  }) {
    return SessionState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      phoneCodeSent: phoneCodeSent ?? this.phoneCodeSent,
    );
  }
}
