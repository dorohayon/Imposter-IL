import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/crash_reporting.dart';

void main() {
  test('every level prints in debug builds and is safe without Crashlytics',
      () {
    final lines = <String?>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add(message);
    logToConsole = true;
    addTearDown(() {
      debugPrint = original;
      logToConsole = false;
    });

    logDebug('ws', '-> game.vote ok');
    logInfo('nav', 'open HomeScreen');
    logWarning('net', 'GET /v1/config network_error', 'Connection refused');
    logError('local', 'saved game unreadable', FormatException);

    expect(lines, [
      'D ws: -> game.vote ok',
      'I nav: open HomeScreen',
      'W net: GET /v1/config network_error (Connection refused)',
      'E local: saved game unreadable (FormatException)',
    ]);
  });
}
