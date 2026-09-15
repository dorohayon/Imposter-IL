// Hebrew word rules from docs/decisions.md, mirroring
// server/internal/game/words.go. Both are tested against
// server/internal/game/testdata/word_rules.json. The server has the final say;
// the app checks early only to show the error before sending.

/// Letters that can be attached in front of a Hebrew word (אותיות שימוש).
const _prefixLetters = 'והבכלמש';
const _maxPrefixLetters = 3;
const _minStemLetters = 2;

final _notLetterOrDigit = RegExp(r'[^\p{L}\p{Nd}]', unicode: true);
const _finalLetters = {'ך': 'כ', 'ם': 'מ', 'ן': 'נ', 'ף': 'פ', 'ץ': 'צ'};

/// Keeps letters and digits only (dropping niqqud, geresh, gershayim, maqaf,
/// hyphens and other punctuation), lowercases, and maps final letters to their
/// regular forms. Spelling is otherwise strict.
String normalizeWord(String word) => word
    .replaceAll(_notLetterOrDigit, '')
    .toLowerCase()
    .split('')
    .map((letter) => _finalLetters[letter] ?? letter)
    .join();

/// Whether [long] is [short] with 1 to 3 prefix letters in front, leaving at
/// least 2 letters.
bool _isPrefixed(String long, String short) {
  final l = long.runes.toList();
  final s = short.runes.length;
  final n = l.length - s;
  return n >= 1 &&
      n <= _maxPrefixLetters &&
      s >= _minStemLetters &&
      long.endsWith(short) &&
      l.take(n).every((r) => _prefixLetters.contains(String.fromCharCode(r)));
}

/// Applies only to citizens; the impostor does not know the word.
bool hintContainsSecret(String hint, String secret) {
  final s = normalizeWord(secret);
  return s.isNotEmpty && normalizeWord(hint).contains(s);
}

/// Equal hints, or one is the other with prefix letters: "הבית" repeats "בית"
/// but "לבית" does not repeat "הבית".
bool sameHint(String a, String b) {
  final x = normalizeWord(a), y = normalizeWord(b);
  return x == y || _isPrefixed(x, y) || _isPrefixed(y, x);
}

/// Accepts the secret word, optionally with prefix letters.
bool guessMatches(String guess, String secret) {
  final g = normalizeWord(guess), s = normalizeWord(secret);
  return g == s || _isPrefixed(g, s);
}
