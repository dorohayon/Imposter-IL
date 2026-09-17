import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/data/invite.dart';

void main() {
  test('an invitation link carries the room code', () {
    // What the friend receives, what the invitation page hands to the app, and
    // the bare route the platform delivers.
    for (final link in [
      'https://imposter.example/join/123456',
      'imposteril://join/123456',
      '/join/123456',
      '/join/123456/',
      '  https://imposter.example/join/123456  ',
    ]) {
      expect(roomCodeFromLink(link), '123456', reason: link);
    }
  });

  test('anything else is not an invitation', () {
    for (final link in [
      null,
      '',
      '/',
      '/join/12345',
      '/join/1234567',
      '/join/abcdef',
      '/joined/123456',
      'https://imposter.example/privacy/',
    ]) {
      expect(roomCodeFromLink(link), isNull, reason: '$link');
    }
  });

  test('the shared link points at the room', () {
    expect(inviteLink('123456').path, '/join/123456');
  });
}
