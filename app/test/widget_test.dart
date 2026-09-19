import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/data/server.dart';
import 'package:imposter_il/screens/home_screen.dart';
import 'package:imposter_il/screens/secondary_screens.dart';
import 'package:imposter_il/widgets/game_ui.dart';

import 'support/fake_server.dart';
import 'support/helpers.dart';

void main() {
  testWidgets('primary buttons expose their tap action to assistive tech',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrimaryButton(label: 'פעולה', onPressed: () {}),
        ),
      ),
    );

    final data =
        tester.getSemantics(find.byType(PrimaryButton)).getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });

  testWidgets('primary buttons support focus and keyboard activation',
      (tester) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrimaryButton(
            label: 'פעולה',
            onPressed: () => presses++,
          ),
        ),
      ),
    );

    final ink = tester.widget<InkWell>(
      find.descendant(
        of: find.byType(PrimaryButton),
        matching: find.byType(InkWell),
      ),
    );
    ink.focusNode!.requestFocus();
    await tester.pump();
    expect(ink.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(presses, 1);
  });

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
    expect(find.text('משחק במכשיר אחד'), findsOneWidget);
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

    await openPrivateRoom(tester);
    await tapText(tester, 'הצטרפות לחדר');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('יצירת חדר'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('משחק מהיר'), findsOneWidget);
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

  // PrimaryButton is a GestureDetector behind an ExcludeSemantics, so the
  // parent Semantics node has to carry the action itself. Without this the
  // buttons stay tappable by finger and become unreachable to TalkBack and
  // VoiceOver, which is invisible to every other test.
  testWidgets('a screen reader can activate the main buttons', (tester) async {
    await startAtHome(tester);

    final handle = tester.ensureSemantics();
    final button = find.byWidgetPredicate(
      (widget) => widget is PrimaryButton && widget.label == 'משחק במכשיר אחד',
    );
    expect(
        tester.getSemantics(button),
        matchesSemantics(
          label: 'משחק במכשיר אחד',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
        ));

    // Activating through the semantics tree, the way assistive tech does.
    tester.semantics.performAction(
      find.semantics.byLabel('משחק במכשיר אחד'),
      SemanticsAction.tap,
    );
    await tester.pumpAndSettle();
    expect(find.text('מי משחק?'), findsOneWidget);
    handle.dispose();
  });
}
