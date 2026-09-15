import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/main.dart';
import 'package:imposter_il/screens/home_screen.dart';
import 'package:imposter_il/state/game_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_server.dart';

/// Starts the real app against [api] on the narrowest supported phone
/// (320px), so layout overflows fail the tests too.
Future<GameSession> startApp(
  WidgetTester tester,
  FakeApi api, {
  Map<String, Object> saved = const {},
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(saved);

  final session =
      GameSession(api, reconnectDelay: const Duration(milliseconds: 50));
  addTearDown(session.dispose);
  await session.restore();
  await tester.pumpWidget(ImposterApp(session: session));
  await tester.pumpAndSettle();
  return session;
}

/// Starts the app and passes onboarding.
Future<GameSession> startAtHome(WidgetTester tester, [FakeApi? api]) async {
  final session = await startApp(tester, api ?? FakeApi());
  await tester.enterText(find.byType(TextField), 'דור');
  await tapText(tester, 'ממשיכים');
  expect(find.byType(HomeScreen), findsOneWidget);
  return session;
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

/// Live screens never settle (their countdowns tick), so pump a fixed time.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapLive(WidgetTester tester, String text) async {
  final finder = find.text(text).last;
  await tester.ensureVisible(finder);
  await settle(tester);
  await tester.tap(finder);
  await settle(tester);
}

/// Taps an icon button by tooltip, scrolling it into view first (the home
/// list keeps its scroll position after navigating back).
Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
  final finder = find.byTooltip(tooltip, skipOffstage: false);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
}
