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
    this.justOnboarded = false,
  });

  const SessionState.initializing()
      : status = SessionStatus.initializing,
        user = null,
        errorMessage = null,
        phoneCodeSent = false,
        justOnboarded = false;

  final SessionStatus status;
  final AppUser? user;
  final String? errorMessage;
  final bool phoneCodeSent;

  /// True solo en la transición a [SessionStatus.authenticated] que ocurre
  /// justo después de COMPLETAR el onboarding (usuario nuevo). Lo usa HomeShell
  /// para mostrar el tutorial una única vez. Es transitorio: cualquier otro
  /// estado emitido lo deja en false.
  final bool justOnboarded;

  SessionState copyWith({
    SessionStatus? status,
    AppUser? user,
    bool clearUser = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? phoneCodeSent,
    bool? justOnboarded,
  }) {
    return SessionState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      phoneCodeSent: phoneCodeSent ?? this.phoneCodeSent,
      justOnboarded: justOnboarded ?? this.justOnboarded,
    );
  }
}
