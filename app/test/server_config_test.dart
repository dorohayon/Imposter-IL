import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/data/server.dart';

void main() {
  test('release builds use the production server without a build flag', () {
    expect(
      defaultServerUrl(releaseMode: true),
      Uri.parse(productionServerUrl),
    );
  });
}
