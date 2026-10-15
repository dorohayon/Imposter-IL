import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'data/server.dart';

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

bool _started = false;

/// Sends crashes and errors to Firebase Crashlytics, in release builds only
/// (disclosed in privacy policy section 7). Never stops the app from starting.
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
  // Every Crashlytics call below drops its own failure (ignore): one that
  // escaped would land back here, fail again and loop.
  PlatformDispatcher.instance.onError = (error, stack) {
    crashlytics.recordError(error, stack, fatal: true).ignore();
    return true;
  };
  _started = true;
  crashlytics.setCustomKey('build', clientBuild).ignore();
  // Builds up to 9 kept collection off until a consent screen was accepted,
  // and the native setting persists: installs that never accepted would
  // otherwise stay silent.
  crashlytics.setCrashlyticsCollectionEnabled(true).ignore();
}

enum LogLevel { debug, info, warning, error }

/// Debug builds and TEST_ADS tester builds print the log. The tests turn it
/// off (test/flutter_test_config.dart): thousands of lines hid the failures.
var logToConsole = !kReleaseMode || const bool.fromEnvironment('TEST_ADS');

/// The app's log. Debug builds (and TEST_ADS tester builds) print every
/// level. Release builds drop debug and keep the rest in Crashlytics' rolling
/// log, which is uploaded only with the next crash or error report, so a
/// session that goes well uploads nothing; an error is also reported as a
/// non-fatal issue.
///
/// Privacy section 7: ids, message types, error codes, phases and counts
/// only — never a nickname, hint, guess, secret word or room code.
void appLog(
  LogLevel level,
  String tag,
  String message, {
  Object? error,
  StackTrace? stack,
}) {
  final line = '${level.name[0].toUpperCase()} $tag: $message'
      '${error == null ? '' : ' ($error)'}';
  if (logToConsole) debugPrint(line);
  if (!_started || level == LogLevel.debug) return;
  final crashlytics = FirebaseCrashlytics.instance;
  crashlytics.log(line).ignore();
  if (level == LogLevel.error) {
    crashlytics
        .recordError(
          error ?? message,
          stack ?? StackTrace.current,
          reason: '$tag: $message',
        )
        .ignore();
  }
}

void logDebug(String tag, String message) =>
    appLog(LogLevel.debug, tag, message);
void logInfo(String tag, String message) => appLog(LogLevel.info, tag, message);
void logWarning(String tag, String message, [Object? error]) =>
    appLog(LogLevel.warning, tag, message, error: error);
void logError(String tag, String message, Object error, [StackTrace? stack]) =>
    appLog(LogLevel.error, tag, message, error: error, stack: stack);

/// Names the player in reports, so a report leads to the server's logs of
/// the same player (jsonPayload.playerId in Cloud Logging, deploy/README.md).
/// The id is a random guest id that ends with the guest session.
void logPlayer(String playerId) {
  if (_started) {
    FirebaseCrashlytics.instance.setUserIdentifier(playerId).ignore();
  }
}
