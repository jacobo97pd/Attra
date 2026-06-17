import 'package:firebase_core/firebase_core.dart';

import 'onboarding_repository.dart';

String onboardingSaveErrorMessage(Object error) {
  if (error is OnboardingRepositoryException) {
    return error.message;
  }
  if (error is FirebaseException) {
    final String detail = (error.message ?? '').trim();
    switch (error.code) {
      case 'permission-denied':
        return 'No se pudo guardar onboarding (code: ${error.code}). '
            'Detalle: ${detail.isEmpty ? 'sin detalle' : detail}';
      case 'failed-precondition':
        return 'No se pudo guardar onboarding porque Firestore no esta configurado para este proyecto/base de datos. (code: ${error.code})';
      case 'no-app':
      case 'core/no-app':
        return 'No se pudo guardar onboarding porque Firebase no esta inicializado. (code: ${error.code})';
      default:
        return 'No se pudo guardar onboarding. (code: ${error.code})';
    }
  }
  if (error is StateError) {
    return error.message;
  }
  return 'No se pudo guardar onboarding. Intentalo nuevamente.';
}
