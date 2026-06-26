import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class SignInCancelledFailure extends AuthFailure {
  const SignInCancelledFailure()
      : super('Inicio de sesion con Google cancelado.');
}

class SignInWithAppleCancelledFailure extends AuthFailure {
  const SignInWithAppleCancelledFailure()
      : super('Inicio de sesion con Apple cancelado.');
}

class PhoneAuthSession {
  const PhoneAuthSession({
    this.verificationId,
    this.confirmationResult,
    this.completedSignIn = false,
  });

  final String? verificationId;
  final ConfirmationResult? confirmationResult;
  final bool completedSignIn;

  bool get requiresSmsCode =>
      !completedSignIn &&
      (verificationId != null || confirmationResult != null);
}

class AuthService {
  AuthService({
    required FirebaseAuth firebaseAuth,
    required GoogleSignIn googleSignIn,
  })  : _firebaseAuth = firebaseAuth,
        _googleSignIn = googleSignIn;

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();
  User? get currentUser => _firebaseAuth.currentUser;

  Future<void> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final GoogleAuthProvider provider = GoogleAuthProvider()
          ..addScope('email');
        try {
          await _firebaseAuth.signInWithPopup(provider);
          return;
        } on FirebaseAuthException catch (error) {
          if (error.code == 'popup-blocked') {
            await _firebaseAuth.signInWithRedirect(provider);
            return;
          }
          rethrow;
        }
      }

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw const SignInCancelledFailure();
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      if (googleAuth.idToken == null && googleAuth.accessToken == null) {
        throw const AuthFailure(
          'No se pudieron obtener credenciales validas de Google.',
        );
      }

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await _firebaseAuth.signInWithCredential(credential);
    } on SignInCancelledFailure {
      rethrow;
    } on FirebaseAuthException catch (error) {
      if (error.code == 'popup-closed-by-user' ||
          error.code == 'cancelled-popup-request') {
        throw const SignInCancelledFailure();
      }
      throw AuthFailure(_firebaseErrorMessage(error));
    } catch (_) {
      throw const AuthFailure(
        'No fue posible iniciar sesion ahora mismo. Intentalo otra vez.',
      );
    }
  }

  Future<void> signInWithApple() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      throw const AuthFailure(
        'Sign in with Apple solo esta disponible en iOS.',
      );
    }

    try {
      final String rawNonce = _generateNonce();
      final String hashedNonce = _sha256ofString(rawNonce);

      final AuthorizationCredentialAppleID appleCredential =
          await SignInWithApple.getAppleIDCredential(
        scopes: const <AppleIDAuthorizationScopes>[
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final String? idToken = appleCredential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthFailure(
          'No se pudo obtener el token de Apple.',
        );
      }

      final OAuthCredential credential = OAuthProvider('apple.com').credential(
        idToken: idToken,
        rawNonce: rawNonce,
      );

      await _firebaseAuth.signInWithCredential(credential);
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        throw const SignInWithAppleCancelledFailure();
      }
      throw AuthFailure('Error de Apple Sign-In: ${error.code.name}');
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_firebaseErrorMessage(error));
    } catch (error) {
      if (error is AuthFailure) {
        rethrow;
      }
      throw const AuthFailure(
        'No fue posible iniciar sesion con Apple. Intentalo de nuevo.',
      );
    }
  }

  Future<void> deleteCurrentUserAccount() async {
    final User? user = _firebaseAuth.currentUser;
    if (user == null) {
      throw const AuthFailure('No hay sesion activa para eliminar la cuenta.');
    }

    try {
      await user.delete();
      await _signOutProvidersSilently();
      return;
    } on FirebaseAuthException catch (error) {
      if (error.code != 'requires-recent-login') {
        throw AuthFailure(_firebaseErrorMessage(error));
      }
    }

    await _reauthenticateForDeletion(user);

    try {
      await user.delete();
      await _signOutProvidersSilently();
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_firebaseErrorMessage(error));
    } catch (_) {
      throw const AuthFailure(
        'No se pudo eliminar la cuenta en este momento.',
      );
    }
  }

  Future<void> signOut() async {
    try {
      await _firebaseAuth.signOut();
      await _signOutProvidersSilently();
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_firebaseErrorMessage(error));
    } catch (_) {
      throw const AuthFailure(
        'No se pudo cerrar sesion en este momento.',
      );
    }
  }

  Future<PhoneAuthSession> startPhoneSignIn(String phoneNumber) async {
    try {
      if (kIsWeb) {
        final ConfirmationResult confirmationResult =
            await _firebaseAuth.signInWithPhoneNumber(phoneNumber);
        return PhoneAuthSession(confirmationResult: confirmationResult);
      }

      final Completer<PhoneAuthSession> completer =
          Completer<PhoneAuthSession>();

      await _firebaseAuth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _firebaseAuth.signInWithCredential(credential);
          if (!completer.isCompleted) {
            completer.complete(const PhoneAuthSession(completedSignIn: true));
          }
        },
        verificationFailed: (FirebaseAuthException error) {
          if (!completer.isCompleted) {
            completer.completeError(AuthFailure(_firebaseErrorMessage(error)));
          }
        },
        codeSent: (String verificationId, int? forceResendingToken) {
          if (!completer.isCompleted) {
            completer
                .complete(PhoneAuthSession(verificationId: verificationId));
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (!completer.isCompleted) {
            completer
                .complete(PhoneAuthSession(verificationId: verificationId));
          }
        },
        timeout: const Duration(seconds: 60),
      );

      return completer.future.timeout(
        const Duration(seconds: 75),
        onTimeout: () {
          throw const AuthFailure(
            'No se pudo iniciar la verificacion por telefono. Intentalo nuevamente.',
          );
        },
      );
    } on AuthFailure {
      rethrow;
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_firebaseErrorMessage(error));
    } catch (_) {
      throw const AuthFailure(
        'No fue posible enviar el codigo SMS. Intentalo de nuevo.',
      );
    }
  }

  Future<void> confirmPhoneCode({
    required String smsCode,
    String? verificationId,
    ConfirmationResult? confirmationResult,
  }) async {
    try {
      if (kIsWeb) {
        if (confirmationResult == null) {
          throw const AuthFailure(
            'Falta la sesion de verificacion web. Solicita un nuevo codigo.',
          );
        }
        await confirmationResult.confirm(smsCode);
        return;
      }

      if (verificationId == null) {
        throw const AuthFailure(
          'Falta el identificador de verificacion. Solicita un nuevo codigo.',
        );
      }

      final PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      await _firebaseAuth.signInWithCredential(credential);
    } on AuthFailure {
      rethrow;
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_firebaseErrorMessage(error));
    } catch (_) {
      throw const AuthFailure(
        'No se pudo verificar el codigo SMS. Intentalo nuevamente.',
      );
    }
  }

  Future<void> _reauthenticateForDeletion(User user) async {
    final List<String> providers = user.providerData
        .map((UserInfo provider) => provider.providerId)
        .toList(growable: false);

    if (providers.contains('apple.com')) {
      await _reauthenticateWithApple(user);
      return;
    }
    if (providers.contains('google.com')) {
      await _reauthenticateWithGoogle(user);
      return;
    }

    throw const AuthFailure(
      'Por seguridad, vuelve a iniciar sesion y prueba a eliminar tu cuenta de nuevo.',
    );
  }

  Future<void> _reauthenticateWithApple(User user) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      throw const AuthFailure(
        'No se puede reautenticar con Apple en esta plataforma.',
      );
    }

    try {
      final String rawNonce = _generateNonce();
      final String hashedNonce = _sha256ofString(rawNonce);
      final AuthorizationCredentialAppleID appleCredential =
          await SignInWithApple.getAppleIDCredential(
        scopes: const <AppleIDAuthorizationScopes>[],
        nonce: hashedNonce,
      );

      final String? idToken = appleCredential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthFailure(
          'No se pudo completar la verificacion con Apple.',
        );
      }

      final OAuthCredential oauthCredential =
          OAuthProvider('apple.com').credential(
        idToken: idToken,
        rawNonce: rawNonce,
      );
      await user.reauthenticateWithCredential(oauthCredential);
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        throw const AuthFailure('Eliminacion cancelada por el usuario.');
      }
      throw AuthFailure(
        'No se pudo verificar la identidad con Apple. (${error.code.name})',
      );
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_firebaseErrorMessage(error));
    }
  }

  Future<void> _reauthenticateWithGoogle(User user) async {
    try {
      if (kIsWeb) {
        final GoogleAuthProvider provider = GoogleAuthProvider()
          ..addScope('email');
        await user.reauthenticateWithPopup(provider);
        return;
      }

      final GoogleSignInAccount? account =
          await _googleSignIn.signInSilently() ?? await _googleSignIn.signIn();
      if (account == null) {
        throw const AuthFailure(
          'Eliminacion cancelada por el usuario.',
        );
      }
      final GoogleSignInAuthentication googleAuth =
          await account.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_firebaseErrorMessage(error));
    }
  }

  Future<void> _signOutProvidersSilently() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Best effort cleanup.
    }
  }

  String _firebaseErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'account-exists-with-different-credential':
        return _withCode(
          'Ya existe una cuenta con otro metodo de acceso.',
          error.code,
        );
      case 'invalid-credential':
        return _withCode('La credencial de acceso no es valida.', error.code);
      case 'operation-not-allowed':
        return _withCode(
          'Este metodo de acceso no esta habilitado en Firebase.',
          error.code,
        );
      case 'user-disabled':
        return _withCode('Esta cuenta fue deshabilitada.', error.code);
      case 'user-not-found':
        return _withCode('No se encontro el usuario.', error.code);
      case 'wrong-password':
        return _withCode(
          'La credencial no coincide con el usuario.',
          error.code,
        );
      case 'network-request-failed':
        return _withCode(
          'No hay conexion a internet. Intentalo de nuevo.',
          error.code,
        );
      case 'requires-recent-login':
        return _withCode(
          'Debes volver a autenticarte para completar esta accion.',
          error.code,
        );
      case 'too-many-requests':
        return _withCode(
          'Demasiados intentos. Espera un momento e intentalo de nuevo.',
          error.code,
        );
      case 'popup-blocked':
        return _withCode(
          'El navegador bloqueo la ventana de login. Habilita popups e intentalo de nuevo.',
          error.code,
        );
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return _withCode(
            'Inicio de sesion cancelado por el usuario.', error.code);
      case 'unauthorized-domain':
        return _withCode(
          'Este dominio no esta autorizado en Firebase Auth.',
          error.code,
        );
      case 'invalid-api-key':
        return _withCode(
          'La API key de Firebase Web no es valida para este proyecto.',
          error.code,
        );
      case 'app-not-authorized':
        return _withCode(
          'La app no esta autorizada para Firebase Authentication en este proyecto.',
          error.code,
        );
      case 'invalid-phone-number':
        return _withCode(
          'El numero de telefono no es valido. Usa formato internacional, por ejemplo +34600111222.',
          error.code,
        );
      case 'missing-phone-number':
        return _withCode('Debes introducir un numero de telefono.', error.code);
      case 'invalid-verification-code':
        return _withCode('El codigo SMS no es valido.', error.code);
      case 'invalid-verification-id':
        return _withCode(
          'La verificacion expiro. Solicita un nuevo codigo.',
          error.code,
        );
      case 'session-expired':
        return _withCode(
          'La sesion de verificacion expiro. Solicita un nuevo codigo.',
          error.code,
        );
      case 'captcha-check-failed':
        return _withCode(
          'No se pudo validar reCAPTCHA. Recarga la pagina e intentalo.',
          error.code,
        );
      case 'quota-exceeded':
        return _withCode(
          'Se alcanzo el limite de SMS de Firebase para este proyecto.',
          error.code,
        );
      default:
        return 'Error de autenticacion (${error.code}): ${error.message ?? error.code}';
    }
  }

  String _withCode(String message, String code) => '$message (code: $code)';

  String _generateNonce([int length = 32]) {
    const String charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final Random random = Random.secure();
    return List<String>.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256ofString(String input) {
    final List<int> bytes = utf8.encode(input);
    final Digest digest = sha256.convert(bytes);
    return digest.toString();
  }
}
