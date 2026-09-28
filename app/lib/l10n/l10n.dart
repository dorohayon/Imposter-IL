import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

// UI text in the player's language (docs/localization.md).

extension L10nContext on BuildContext {
  /// The UI text for this context's language. Widgets read it here, so they
  /// rebuild when the language changes.
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// The UI text for code with no BuildContext: error maps and helpers that run
/// inside a build or a callback. MaterialApp's builder keeps it current.
AppLocalizations get l10n => _current;
AppLocalizations _current = lookupAppLocalizations(const Locale('he'));

set currentL10n(AppLocalizations value) => _current = value;

/// A language in its own name ("עברית", "English"), or its code when the app
/// does not have it.
String languageName(Object? code) {
  final locale = Locale('$code');
  return AppLocalizations.delegate.isSupported(locale)
      ? lookupAppLocalizations(locale).languageName
      : '$code';
}
