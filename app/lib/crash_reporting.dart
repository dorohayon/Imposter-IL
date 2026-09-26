import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Firebase for iOS (Android reads android/app/google-services.json). Not
/// secrets: they only name the Firebase app.
const _ios = FirebaseOptions(
  apiKey: 'AIzaSyCicdEF4dmjeSjYe1eQE130COyiLkrqXl4',
  appId: '1:665896750521:ios:92c1053ef330674d227a68',
  messagingSenderId: '665896750521',
  projectId: 'imposter-il-game',
  storageBucket: 'imposter-il-game.firebasestorage.app',
  iosBundleId: 'com.imposteril.app',
);

/// Sends crashes and uncaught errors to Firebase Crashlytics, in release
/// builds only (privacy policy section 7). Never stops the app from starting.
Future<void> startCrashReporting() async {
  if (!kReleaseMode) return;
  try {
    await Firebase.initializeApp(
      options: defaultTargetPlatform == TargetPlatform.iOS ? _ios : null,
    );
  } on Object catch (e) {
    debugPrint('crash reporting off: $e');
    return;
  }
  final crashlytics = FirebaseCrashlytics.instance;
  FlutterError.onError = crashlytics.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    crashlytics.recordError(error, stack, fatal: true);
    return true;
  };
}
