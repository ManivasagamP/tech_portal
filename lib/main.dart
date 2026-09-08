import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/env.dart';
import 'core/network/api_client.dart';
import 'core/offline/offline_db.dart';
import 'core/push/push_service.dart';
import 'core/storage/secure_store.dart';
import 'core/storage/session_store.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  final secureStore = SecureStore();
  final sessionStore = await SessionStore.open();
  final offlineDb = await OfflineDb.open();
  final api = ApiClient(
    secureStore: secureStore,
    baseUrl: sessionStore.readBaseUrlOverride() ?? Env.defaultApiBaseUrl,
  );

  runApp(
    ProviderScope(
      overrides: [
        secureStoreProvider.overrideWithValue(secureStore),
        sessionStoreProvider.overrideWithValue(sessionStore),
        offlineDbProvider.overrideWithValue(offlineDb),
        apiClientProvider.overrideWithValue(api),
      ],
      child: const TechnicianApp(),
    ),
  );
}
