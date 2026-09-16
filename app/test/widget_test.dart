import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/data/server.dart';
import 'package:imposter_il/screens/home_screen.dart';
import 'package:imposter_il/screens/secondary_screens.dart';

import 'support/fake_server.dart';
import 'support/helpers.dart';

void main() {
  testWidgets('a build the server refuses can only update', (tester) async {
    final api = FakeApi()
      ..responses['GET /v1/categories'] =
          const ApiException('client_too_old', 426);

    final session = await startApp(tester, api, saved: {
      'session.token': 'token-1',
      'session.playerId': 'p_me',
      'session.nickname': 'דור',
      'session.avatarId': 'avatar-m04-detective-hat',
    });

    expect(session.needsUpdate, isTrue);
    expect(find.byType(UpdateRequiredScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    // No way out: an unsupported build cannot reach the rest of the app.
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('the update screen covers pushed routes too', (tester) async {
    final api = FakeApi();
    final session = await startAtHome(tester, api);

    // Deep in the stack, the way a player is when the server stops serving
    // their build mid-session.
    await tapText(tester, 'איך משחקים?');
    expect(find.text('איך משחקים?'), findsWidgets);

    api.responses['GET /v1/categories'] =
        const ApiException('client_too_old', 426);
    await session.loadContent().catchError((Object _) {});
    await tester.pumpAndSettle();

    expect(find.byType(UpdateRequiredScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

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
    final sound = find.ancestor(
      of: find.text('צלילים'),
      matching: find.byType(SwitchListTile),
    );
    expect(tester.widget<SwitchListTile>(sound).onChanged, isNull);
    for (final title in ['תנאי שימוש', 'מדיניות פרטיות']) {
      final tile = find.ancestor(
        of: find.text(title),
        matching: find.byType(ListTile),
      );
      expect(tester.widget<ListTile>(tile).enabled, isFalse);
    }
  });
}
