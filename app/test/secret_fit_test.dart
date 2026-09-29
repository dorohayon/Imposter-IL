import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/l10n/l10n.dart';
import 'package:imposter_il/local/words.g.dart';
import 'package:imposter_il/theme/app_theme.dart';
import 'package:imposter_il/widgets/game_ui.dart';

import 'support/helpers.dart';

void main() {
  // "Pirates of the Caribbean" wrapped into three lines, and a long single
  // word broke in the middle. Every secret now keeps one line, and the
  // shrinking stops well before it is hard to read.
  testWidgets('every secret fits the word card at 320 px', (tester) async {
    await loadRealFonts();
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final (lang, dir) in [
      ('he', TextDirection.rtl),
      ('en', TextDirection.ltr),
    ]) {
      for (final category in localCategoriesFor(lang)) {
        for (final word in category.words) {
          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.dark,
            locale: Locale(lang),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Directionality(
              textDirection: dir,
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SecretWordCard(word: word, impostor: false),
                ),
              ),
            ),
          ));
          expect(tester.takeException(), isNull, reason: word);
          final box = tester.getSize(find.byType(FittedBox));
          final text = tester
              .renderObject<RenderParagraph>(find.descendant(
                  of: find.byType(FittedBox), matching: find.byType(RichText)))
              .size;
          final shown = 38 * (box.width / text.width).clamp(0, 1);
          expect(shown, greaterThanOrEqualTo(18), reason: '$word: $shown');
        }
      }
    }
  });
}
