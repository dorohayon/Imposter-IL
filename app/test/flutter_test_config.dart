import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The suites read the Hebrew UI, the template language; english_test.dart
/// switches to English for its own checks.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    // Only where a widget test already made its binding: test/e2e talks to a
    // real server with plain tests, and a test binding would fake its HTTP.
    if (BindingBase.debugBindingType() == null) return;
    TestWidgetsFlutterBinding.instance.platformDispatcher.localesTestValue =
        const [Locale('he')];
  });
  await testMain();
}
