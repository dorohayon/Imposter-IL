import 'dart:io';

import 'package:flutter/services.dart';

const _vibrator = MethodChannel('imposter/vibrate');

/// The vibration of a game moment: a game starting, my turn, voting.
///
/// Android gets a real one (android/.../MainActivity.kt): Flutter's haptics
/// there are a keyboard tick, faint, and nothing at all when the phone's touch
/// feedback is off. iPhone gets its strongest haptic tap.
Future<void> buzz() async {
  if (Platform.isAndroid) {
    try {
      await _vibrator.invokeMethod<void>('vibrate', 150);
      return;
    } on Object {
      // No vibrator bridge: fall back to the haptic below.
    }
  }
  await HapticFeedback.heavyImpact();
}
