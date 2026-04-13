import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'src/features/auth/data/auth_service.dart';
import 'src/features/auth/data/user_repository.dart';
import 'src/features/auth/presentation/session_controller.dart';
import 'src/features/auth/presentation/session_gate.dart';
import 'src/features/onboarding/data/onboarding_repository.dart';

class AttraApp extends StatefulWidget {
  const AttraApp({super.key});

  @override
  State<AttraApp> createState() => _AttraAppState();
}

class _AttraAppState extends State<AttraApp> {
  late final SessionController _sessionController;
  static const String _firestoreDatabaseId = String.fromEnvironment(
    'FIREBASE_FIRESTORE_DATABASE_ID',
    defaultValue: 'attra-database',
  );

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint(
        '[Attra] Firebase projectId=${Firebase.app().options.projectId} databaseId=$_firestoreDatabaseId',
      );
    }
    if (kDebugMode) {
      FirebaseAuth.instance
          .setSettings(appVerificationDisabledForTesting: true);
    }
    _sessionController = SessionController(
      authService: AuthService(
        firebaseAuth: FirebaseAuth.instance,
        googleSignIn: GoogleSignIn(scopes: const <String>['email']),
      ),
      userRepository: UserRepository(
        firestore: FirebaseFirestore.instanceFor(
          app: Firebase.app(),
          databaseId: _firestoreDatabaseId,
        ),
        storage: FirebaseStorage.instance,
      ),
      onboardingRepository: OnboardingRepository(
        firestore: FirebaseFirestore.instanceFor(
          app: Firebase.app(),
          databaseId: _firestoreDatabaseId,
        ),
        storage: FirebaseStorage.instance,
      ),
    );
  }

  @override
  void dispose() {
    _sessionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Attra',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1D6A96)),
      ),
      home: SessionGate(controller: _sessionController),
    );
  }
}
