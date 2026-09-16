import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/screens/home_screen.dart';

import 'support/helpers.dart';

void main() {
  testWidgets('onboarding opens the Hebrew home screen', (tester) async {
    await startAtHome(tester);

    expect(find.text('מי המתחזה?'), findsOneWidget);
    expect(find.text('משחק ברשת'), findsOneWidget);
    expect(find.text('משחק עם חברים'), findsOneWidget);
    expect(find.byTooltip('פרופיל'), findsOneWidget);
    expect(find.byTooltip('הגדרות'), findsOneWidget);
  });

  testWidgets('non-game screens have a visible back button', (tester) async {
    await startAtHome(tester);

    for (final entry in {
      'הגדרות': 'הגדרות',
      'פרופיל': 'הפרופיל שלי',
    }.entries) {
      await tester.tap(find.byTooltip(entry.key));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    }

    await tapText(tester, 'איך משחקים?');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tapText(tester, 'משחק עם חברים');
    await tapText(tester, 'הצטרפות לחדר');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('יצירת חדר'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('features without content yet are shown as unavailable',
      (tester) async {
    await startAtHome(tester);

    await tester.tap(find.byTooltip('הגדרות'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).first).onChanged, isNull);
    for (final title in ['תנאי שימוש', 'מדיניות פרטיות']) {
      expect(find.text(title), findsOneWidget);
    }
  });
}
