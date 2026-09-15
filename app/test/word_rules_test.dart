import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/models/word_rules.dart';

// The same cases the Go engine runs, so client and server cannot drift.
void main() {
  final cases = jsonDecode(
    File('../server/internal/game/testdata/word_rules.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  test('normalizeWord', () {
    for (final row in cases['normalize'] as List) {
      expect(normalizeWord(row[0] as String), row[1], reason: '${row[0]}');
    }
  });

  for (final (name, check) in [
    ('containsSecret', hintContainsSecret),
    ('sameHint', sameHint),
    ('guessMatches', guessMatches),
  ]) {
    test(name, () {
      final rows = cases[name] as List;
      expect(rows, isNotEmpty);
      for (final row in rows) {
        expect(
          check(row[0] as String, row[1] as String),
          row[2],
          reason: '$name(${row[0]}, ${row[1]})',
        );
      }
    });
  }
}
