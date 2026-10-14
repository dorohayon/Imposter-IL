import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/screens/home_screen.dart';
import 'package:imposter_il/screens/legal_screens.dart';

import 'support/fake_server.dart';
import 'support/helpers.dart';

void main() {
  testWidgets('a fresh install opens on home and sends nothing',
      (tester) async {
    final api = FakeApi();
    await startApp(tester, api);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(api.requests.where((r) => r.$2 == '/v1/sessions'), isEmpty);
  });

  // App Review guideline 1.2: players agree to the Terms where they first
  // send something others will read, their nickname.
  testWidgets('choosing a nickname is agreeing to the documents',
      (tester) async {
    await startApp(tester, FakeApi());
    await tapTooltip(tester, 'פרופיל');

    await tester.scrollUntilVisible(find.text('מדיניות פרטיות'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('בלחיצה על ״ממשיכים״'), findsOneWidget);
    await tapText(tester, 'תנאי שימוש');
    expect(find.byType(TermsScreen), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('מדיניות פרטיות'));
    await tapText(tester, 'מדיניות פרטיות');
    expect(find.byType(PrivacyScreen), findsOneWidget);
  });

  // The email is on the public site only; the app points there.
  testWidgets('the documents name the support page, not an email',
      (tester) async {
    await startAtHome(tester);
    await tapTooltip(tester, 'הגדרות');
    for (final document in ['תנאי שימוש', 'מדיניות פרטיות']) {
      await tapText(tester, document);
      expect(find.textContaining('imposteril.github.io/support'), findsWidgets);
      expect(find.textContaining('@'), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('settings opens both current legal documents', (tester) async {
    await startAtHome(tester);
    await tester.tap(find.byTooltip('הגדרות'));
    await tester.pumpAndSettle();

    expect(find.text('גרסה $legalVersion'), findsNWidgets(2));
    await tapText(tester, 'תנאי שימוש');
    expect(find.byType(TermsScreen), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tapText(tester, 'מדיניות פרטיות');
    expect(find.byType(PrivacyScreen), findsOneWidget);
  });

  // docs/legal.md says the in-app copies and the published ones must stay
  // aligned. They drifted once already — the app was missing whole sections
  // the public policy had — so the alignment is checked rather than promised.
  for (final (document, page, open) in [
    ('מדיניות פרטיות', 'privacy', 'מדיניות פרטיות'),
    ('תנאי שימוש', 'terms', 'תנאי שימוש'),
  ]) {
    testWidgets('$document matches the published copy', (tester) async {
      final html = File('../site/$page/index.html').readAsStringSync();
      final published = RegExp(r'<h2[^>]*>(.*?)</h2>', dotAll: true)
          .allMatches(html)
          .map((m) => m.group(1)!.trim())
          .toList();
      expect(published, isNotEmpty, reason: 'no sections found in $page');

      await startAtHome(tester);
      await tapTooltip(tester, 'הגדרות');
      await tapText(tester, open);
      for (final section in published) {
        expect(find.text(section), findsOneWidget,
            reason: '$section is published but not in the app');
      }
    });
  }

  // site/en is the app's English text, section for section (docs/legal.md).
  final english =
      jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map;
  for (final document in ['privacy', 'terms']) {
    test('the English $document page matches the app\'s English text', () {
      final html = File('../site/en/$document/index.html').readAsStringSync();
      final published = RegExp(r'<h2[^>]*>(.*?)</h2>', dotAll: true)
          .allMatches(html)
          .map((m) => m.group(1)!.trim().replaceAll('&amp;', '&'))
          .toList();
      expect(published, [
        for (var i = 1; english.containsKey('$document${i}Title'); i++)
          english['$document${i}Title'],
      ]);
    });
  }
}
