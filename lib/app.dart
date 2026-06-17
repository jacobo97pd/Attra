import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
import 'src/features/ai_visual/data/ai_visual_service.dart';
import 'src/features/chat/data/chat_repository.dart';
import 'src/features/chat/data/chat_service.dart';
import 'src/features/feed/data/feed_metrics_service.dart';
import 'src/features/integrations/data/spotify_auth_service.dart';
import 'src/features/integrations/domain/integration_connector.dart';
import 'src/features/match/data/match_repository.dart';
import 'src/features/match/data/match_service.dart';
import 'src/features/monetization/data/boost_service.dart';
import 'src/features/monetization/data/entitlement_service.dart';
import 'src/features/monetization/data/feature_flag_service.dart';
import 'src/features/onboarding/data/onboarding_repository.dart';
import 'src/features/profile/data/profile_summary_repository.dart';
import 'src/features/settings/data/settings_repository.dart';
import 'src/features/spark/data/spark_analytics.dart';
import 'src/features/spark/data/spark_repository.dart';
import 'src/features/spark/data/spark_service.dart';
import 'src/theme/app_theme.dart';
import 'src/features/stories/data/story_repository.dart';
import 'src/features/stories/data/story_service.dart';

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

    final FirebaseFirestore firestore = FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: _firestoreDatabaseId,
    );
    // Las Cloud Functions estan desplegadas en europe-west1 (ver functions/).
    final FirebaseFunctions functions =
        FirebaseFunctions.instanceFor(region: 'europe-west1');

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
      settingsRepository: SettingsRepository(
        firestore: FirebaseFirestore.instanceFor(
          app: Firebase.app(),
          databaseId: _firestoreDatabaseId,
        ),
      ),
      entitlementService: FirestoreEntitlementService(
        firestore: FirebaseFirestore.instanceFor(
          app: Firebase.app(),
          databaseId: _firestoreDatabaseId,
        ),
      ),
      featureFlagService: FirestoreFeatureFlagService(
        firestore: FirebaseFirestore.instanceFor(
          app: Firebase.app(),
          databaseId: _firestoreDatabaseId,
        ),
      ),
      matchService: MatchService(
        repository: MatchRepository(firestore: firestore),
        functions: functions,
      ),
      chatService: ChatService(
        repository: ChatRepository(firestore: firestore),
        functions: functions,
        storage: FirebaseStorage.instance,
      ),
      profileSummaryRepository:
          ProfileSummaryRepository(firestore: firestore),
      integrationConnector: CompositeIntegrationConnector(<IntegrationConnector>[
        SpotifyAuthService(functions: functions),
      ]),
      storyService: StoryService(
        repository: StoryRepository(firestore: firestore),
        functions: functions,
        storage: FirebaseStorage.instance,
      ),
      aiVisualService: AiVisualService(
        functions: functions,
        storage: FirebaseStorage.instance,
      ),
      sparkService: SparkService(
        repository: SparkRepository(firestore: firestore),
        analytics: SparkAnalytics(firestore: firestore),
        functions: functions,
      ),
      boostService: BoostService(
        firestore: firestore,
        functions: functions,
      ),
      feedMetricsService: FeedMetricsService(firestore: firestore),
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
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: SessionGate(controller: _sessionController),
    );
  }
}
