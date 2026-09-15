import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/demo/demo_data.dart';
import 'package:imposter_il/main.dart';
import 'package:imposter_il/screens/game_flow.dart';
import 'package:imposter_il/screens/home_screen.dart';

/// Starts the real app on the narrowest supported phone (320px) and passes
/// onboarding, so layout overflows fail the tests too.
Future<void> startAtHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const ImposterApp());
  await tester.enterText(find.byType(TextField), 'דור');
  await tapText(tester, 'ממשיכים');
  expect(find.byType(HomeScreen), findsOneWidget);
}

Future<void> tapText(WidgetTester tester, String text) async {
  if (find.text(text).evaluate().isEmpty) {
    // Lazy lists (onboarding, home) build lower items only once scrolled.
    await tester.scrollUntilVisible(
      find.text(text),
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  final finder = find.text(text).last;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> seconds(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pumpAndSettle();
}

Future<void> open(WidgetTester tester, Widget screen) async {
  Navigator.of(tester.element(find.byType(HomeScreen)))
      .push(MaterialPageRoute<void>(builder: (_) => screen));
  await tester.pumpAndSettle();
}

bool isEnabled(WidgetTester tester, String label) {
  final button = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
  );
  return tester.widget<ButtonStyleButton>(button.first).onPressed != null;
}

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

  testWidgets('placeholder actions are disabled', (tester) async {
    await startAtHome(tester);

    await tester.tap(find.byTooltip('פרופיל'));
    await tester.pumpAndSettle();
    expect(isEnabled(tester, 'עריכת פרטים — בקרוב'), isFalse);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('הגדרות'));
    await tester.pumpAndSettle();
    for (final title in ['תנאי שימוש', 'מדיניות פרטיות']) {
      final tile = find.ancestor(
        of: find.text(title),
        matching: find.byType(ListTile),
      );
      expect(tester.widget<ListTile>(tile).enabled, isFalse);
    }
  });

  testWidgets('online game advances only on its own, back to categories',
      (tester) async {
    await startAtHome(tester);
    await tapText(tester, 'משחק ברשת');
    await tapText(tester, 'חפש משחק');

    // No player-controlled start: the demo wait ends the search.
    expect(find.text('6 מתוך 8'), findsOneWidget);
    expect(find.text('התחלת משחק'), findsNothing);
    expect(find.text('30'), findsOneWidget);
    await seconds(tester, 29);
    expect(find.text('מחפשים שחקנים'), findsOneWidget);
    await seconds(tester, 1);

    // Role reveal moves on after 10 seconds without pressing "הבנתי".
    expect(find.text('המילה שלך'), findsOneWidget);
    await seconds(tester, 10);
    expect(find.text('התור שלך'), findsOneWidget);

    // Only hints sent before this turn are shown and checked for duplicates.
    expect(find.text('הרמז: קיץ'), findsOneWidget);
    expect(find.text('הרמז: מתוק'), findsOneWidget);
    expect(find.text('הרמז: קליפה'), findsNothing);
    for (final (hint, error) in [
      ('מתוק', 'כבר השתמשו ברמז הזה'),
      ('והַמתוק', 'כבר השתמשו ברמז הזה'),
      ('בננה', 'אסור לחשוף את המילה הסודית'),
      ('וּבַבננה', 'אסור לחשוף את המילה הסודית'),
      ('שתי מילים', 'הרמז חייב להיות מילה אחת'),
    ]) {
      await tester.enterText(find.byType(TextField), hint);
      await tapText(tester, 'שליחת רמז');
      expect(find.text(error), findsOneWidget);
      expect(find.text('התור שלך'), findsOneWidget);
    }

    // A hint that only appears later in the demo script is accepted.
    await tester.enterText(find.byType(TextField), 'קליפה');
    await tapText(tester, 'שליחת רמז');
    expect(find.text('הרמז: קליפה'), findsOneWidget);
    expect(find.text('אורי כותב רמז...'), findsOneWidget);
    expect(find.text('שליחת רמז'), findsNothing);

    // The remaining turns and the move to voting are automatic.
    await seconds(tester, 3);
    expect(find.text('דנה כותב רמז...'), findsOneWidget);
    await seconds(tester, 6);
    expect(find.text('כל הרמזים נשלחו'), findsOneWidget);
    await seconds(tester, 3);

    expect(find.text('20'), findsOneWidget);
    expect(isEnabled(tester, 'אישור הצבעה'), isFalse);
    await tapText(tester, 'מאיה');
    expect(isEnabled(tester, 'אישור הצבעה'), isFalse);
    await tapText(tester, 'יובל');
    await tapText(tester, 'אישור הצבעה');
    expect(find.text('ההצבעה נקלטה'), findsOneWidget);
    await seconds(tester, 20);

    // A citizen watches the guess and cannot type or send one.
    expect(find.text('יובל נתפס ומנסה לנחש את המילה'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('שליחת ניחוש'), findsNothing);
    await seconds(tester, 15);

    expect(find.text('האזרחים ניצחו!'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    await tapText(tester, 'משחק נוסף');
    expect(find.text('בחירת קטגוריות'), findsOneWidget);
  });

  testWidgets('the impostor never sees the word and is not blocked by it',
      (tester) async {
    await startAtHome(tester);

    await open(
      tester,
      const HintRoundScreen(
        game: DemoGame(me: demoOnlineMe, isImpostor: true),
      ),
    );
    expect(find.text('קטגוריה: $demoCategory'), findsOneWidget);
    expect(find.text('הצגת המילה'), findsNothing);
    expect(find.text(demoWord), findsNothing);
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);

    // The impostor does not know the word, so a hint containing it is sent.
    await tester.enterText(find.byType(TextField), 'הבננה');
    await tapText(tester, 'שליחת רמז');
    expect(find.text('אסור לחשוף את המילה הסודית'), findsNothing);
    expect(find.text('הרמז: הבננה'), findsOneWidget);
  });

  testWidgets('a citizen can open the secret word', (tester) async {
    await startAtHome(tester);

    await open(
      tester,
      const HintRoundScreen(game: DemoGame(me: demoOnlineMe)),
    );
    await tapText(tester, 'הצגת המילה');
    expect(find.text(demoWord), findsOneWidget);
  });

  testWidgets('a correct impostor guess wins for the impostor', (tester) async {
    await startAtHome(tester);

    await open(
      tester,
      const ImpostorGuessScreen(
        game: DemoGame(me: demoOnlineMe, isImpostor: true),
      ),
    );
    // Normalized: niqqud and a prefix letter still count as the word.
    await tester.enterText(find.byType(TextField), ' הבָּנָנָה ');
    await tapText(tester, 'שליחת ניחוש');
    expect(find.text('המתחזה ניצח!'), findsOneWidget);
  });

  testWidgets('private room: host removes players, plays, returns to lobby',
      (tester) async {
    await startAtHome(tester);
    await tapText(tester, 'משחק עם חברים');
    await tapText(tester, 'יצירת חדר');
    await tapText(tester, '10 שניות');
    await tapText(tester, 'יצירת חדר');

    expect(find.text('החדר של נועם'), findsOneWidget);
    expect(find.text('מנהל החדר · אני'), findsOneWidget);
    expect(find.text('6 מתוך 8 שחקנים'), findsOneWidget);
    expect(find.text('10 שניות לרמז'), findsOneWidget);
    expect(find.byTooltip('הסרת נועם'), findsNothing);

    for (final nickname in ['מאיה', 'דנה', 'רועי']) {
      await tester.ensureVisible(find.byTooltip('הסרת $nickname'));
      await tester.tap(find.byTooltip('הסרת $nickname'));
      await tester.pumpAndSettle();
    }
    expect(find.text('3 מתוך 8 שחקנים'), findsOneWidget);
    expect(find.text('צריך לפחות 4 שחקנים כדי להתחיל'), findsOneWidget);
    expect(isEnabled(tester, 'התחלת משחק'), isFalse);

    // Back to a full-enough room by leaving and creating again.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tapText(tester, 'יצירת חדר');
    await tapText(tester, '10 שניות');
    await tapText(tester, 'יצירת חדר');
    for (final nickname in ['מאיה', 'דנה']) {
      await tester.ensureVisible(find.byTooltip('הסרת $nickname'));
      await tester.tap(find.byTooltip('הסרת $nickname'));
      await tester.pumpAndSettle();
    }
    expect(isEnabled(tester, 'התחלת משחק'), isTrue);
    await tapText(tester, 'התחלת משחק');

    await tapText(tester, 'הבנתי');
    expect(find.text('התור שלך'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);

    // The turn times out; removed players never take a turn.
    await seconds(tester, 10);
    expect(find.text('לא נשלח רמז'), findsOneWidget);
    expect(find.text('יובל כותב רמז...'), findsOneWidget);
    await seconds(tester, 3);
    expect(find.text('אורי כותב רמז...'), findsOneWidget);
    await seconds(tester, 3);
    expect(find.text('רועי כותב רמז...'), findsOneWidget);
    await seconds(tester, 6);

    expect(find.text('מי המתחזה?'), findsOneWidget);
    expect(find.text('מאיה'), findsNothing);
    await seconds(tester, 20);
    await seconds(tester, 15);

    await tapText(tester, 'משחק נוסף');
    expect(find.text('החדר של נועם'), findsOneWidget);
    expect(find.text('4 מתוך 8 שחקנים'), findsOneWidget);
  });

  testWidgets('join room: digits only, inline error, joiner is not host',
      (tester) async {
    await startAtHome(tester);
    await tapText(tester, 'משחק עם חברים');
    await tapText(tester, 'הצטרפות לחדר');

    final field = find.byType(TextField);
    await tester.enterText(field, 'ab12cd');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '12');
    expect(isEnabled(tester, 'הצטרפות'), isFalse);

    await tester.enterText(field, '111111');
    await tapText(tester, 'הצטרפות');
    expect(find.text('החדר לא נמצא או שאינו זמין כרגע'), findsOneWidget);
    expect(find.text('ניסיון נוסף'), findsOneWidget);

    // The code stays editable after the error.
    await tester.enterText(field, demoRoomCode);
    await tapText(tester, 'הצטרפות');

    expect(find.text('החדר של נועם'), findsOneWidget);
    expect(find.text('מנהל החדר'), findsOneWidget);
    expect(find.text('אני'), findsOneWidget);
    expect(find.byIcon(Icons.person_remove_rounded), findsNothing);
    expect(isEnabled(tester, 'רק מנהל החדר יכול להתחיל'), isFalse);
  });

  testWidgets('server-only states are reachable in debug builds',
      (tester) async {
    await startAtHome(tester);
    await tapText(tester, 'מצבי Prototype (debug)');

    await tapText(tester, 'תקלה בשרת');
    expect(
      find.text('המשחק הופסק עקב תקלה בחיבור לשרת. לא נרשם הפסד.'),
      findsOneWidget,
    );
    await tapText(tester, 'חזרה למסך הבית');
    expect(find.byType(HomeScreen), findsOneWidget);

    await tapText(tester, 'מצבי Prototype (debug)');
    await tapText(tester, 'הצבעה חוזרת');
    expect(find.text('תיקו נוסף מעניק ניצחון למתחזה'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
  });
}
