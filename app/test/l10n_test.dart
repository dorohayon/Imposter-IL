import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every language's ARB against the Hebrew template (docs/localization.md).
/// A placeholder the template does not declare turns into an extra argument
/// in the generated code for that language alone.
void main() {
  Map<String, dynamic> arb(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final template = arb('lib/l10n/app_he.arb');
  final placeholder = RegExp(r'\{(\w+)[,}]');
  final languages = Directory('lib/l10n')
      .listSync()
      .map((f) => f.path)
      .where((p) => p.endsWith('.arb') && !p.endsWith('app_he.arb'));

  test('there is a language besides the template', () {
    expect(languages, isNotEmpty);
  });

  for (final path in languages) {
    test('$path uses only the template\'s keys and placeholders', () {
      final messages = arb(path);
      for (final MapEntry(:key, :value) in messages.entries) {
        if (key.startsWith('@')) continue;
        expect(template.containsKey(key), isTrue,
            reason: '$key: not in the template');
        final declared = ((template['@$key'] as Map?)?['placeholders'] as Map?)
                ?.keys
                .toSet() ??
            <String>{};
        for (final m in placeholder.allMatches(value as String)) {
          expect(declared, contains(m.group(1)),
              reason: '$key: {${m.group(1)}} is not a template placeholder');
        }
      }
      for (final key in template.keys.where((k) => !k.startsWith('@'))) {
        expect(messages.containsKey(key), isTrue, reason: '$key: untranslated');
      }
    });
  }
}
