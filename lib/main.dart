import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'app_init_error.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await _initializeFirebase();
    runApp(const AttraApp());
  } catch (error) {
    runApp(AppInitErrorApp(error: error.toString()));
  }
}

Future<void> _initializeFirebase() async {
  if (!kIsWeb) {
    await Firebase.initializeApp();
    return;
  }

  const String apiKey = String.fromEnvironment(
    'FIREBASE_WEB_API_KEY',
    defaultValue: 'AIzaSyC8h_q2epE4Ut_o4cFTqy4yvv9K_TTWAGc',
  );
  const String appId = String.fromEnvironment(
    'FIREBASE_WEB_APP_ID',
    defaultValue: '1:825052601260:web:1f3a9517001ab2ad9df809',
  );
  const String messagingSenderId = String.fromEnvironment(
    'FIREBASE_WEB_MESSAGING_SENDER_ID',
    defaultValue: '825052601260',
  );
  const String projectId = String.fromEnvironment(
    'FIREBASE_WEB_PROJECT_ID',
    defaultValue: 'attra-database',
  );
  const String authDomain = String.fromEnvironment(
    'FIREBASE_WEB_AUTH_DOMAIN',
    defaultValue: 'attra-database.firebaseapp.com',
  );
  const String storageBucket = String.fromEnvironment(
    'FIREBASE_WEB_STORAGE_BUCKET',
    defaultValue: 'attra-database.firebasestorage.app',
  );
  const String measurementId =
      String.fromEnvironment('FIREBASE_WEB_MEASUREMENT_ID');

  final List<String> missing = <String>[];
  if (apiKey.isEmpty) missing.add('FIREBASE_WEB_API_KEY');
  if (appId.isEmpty) missing.add('FIREBASE_WEB_APP_ID');
  if (messagingSenderId.isEmpty) {
    missing.add('FIREBASE_WEB_MESSAGING_SENDER_ID');
  }
  if (projectId.isEmpty) missing.add('FIREBASE_WEB_PROJECT_ID');

  if (missing.isNotEmpty) {
    throw StateError(
      'Falta configuracion de Firebase para Web. Define estas variables: ${missing.join(', ')}',
    );
  }

  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: authDomain.isEmpty ? null : authDomain,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
      measurementId: measurementId.isEmpty ? null : measurementId,
    ),
  );
}
