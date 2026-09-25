import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/main.dart';
import 'package:imposter_il/screens/home_screen.dart';
import 'package:imposter_il/screens/legal_screens.dart';
import 'package:imposter_il/screens/live_room.dart';
import 'package:imposter_il/widgets/game_ui.dart';
import 'package:imposter_il/state/game_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_monetization.dart';
import 'fake_server.dart';

/// Starts the real app against [api] on the narrowest supported phone
/// (320px), so layout overflows fail the tests too. Existing tests are about
/// post-consent product flows, so they start with the current legal version
/// accepted; legal-gate tests can override the key explicitly.
///
/// Unless a test is about monetization, the player owns lifetime Premium:
/// every category open and no ads, as the flows under test always assumed.
Future<GameSession> startApp(
  WidgetTester tester,
  FakeApi api, {
  Map<String, Object> saved = const {},
  FakeStore? store,
  FakeAds? ads,
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    legalAcceptedVersionKey: legalVersion,
    ...saved,
  });

  final session =
      GameSession(api, reconnectDelay: const Duration(milliseconds: 50));
  addTearDown(session.dispose);
  final monetization = fakeMonetization(api, store: store, ads: ads);
  addTearDown(monetization.dispose);
  await session.restore();
  await monetization.start();
  monetization.attach(session);
  await tester.pumpWidget(
    ImposterApp(session: session, monetization: monetization),
  );
  await tester.pumpAndSettle();
  return session;
}

/// Starts the app and passes onboarding.
Future<GameSession> startAtHomeWith(
  WidgetTester tester, {
  FakeApi? api,
  FakeStore? store,
  FakeAds? ads,
}) async {
  final session =
      await startApp(tester, api ?? FakeApi(), store: store, ads: ads);
  if (!session.signedIn) {
    await tapTooltip(tester, 'פרופיל');
    await tester.enterText(find.byType(TextField), 'דור');
    await tapText(tester, 'ממשיכים');
  }
  expect(find.byType(HomeScreen), findsOneWidget);
  return session;
}

/// Starts the app and passes onboarding.
Future<GameSession> startAtHome(WidgetTester tester, [FakeApi? api]) async {
  final session = await startAtHomeWith(tester, api: api);
  await tester.ensureVisible(find.byTooltip('הגדרות'));
  await tester.pumpAndSettle();
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
  final primary = find.widgetWithText(PrimaryButton, label);
  if (primary.evaluate().isNotEmpty) {
    return tester.widget<PrimaryButton>(primary.first).onPressed != null;
  }
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

/// Confirms the "leaving is a loss" dialog that guards leaving a live game.
Future<void> confirmLeave(WidgetTester tester) async {
  expect(find.text('יציאה באמצע המשחק נרשמת כהפסד.'), findsOneWidget);
  await tester.tap(find.descendant(
      of: find.byType(AlertDialog), matching: find.text('יציאה')));
  await settle(tester);
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

/// Whether a category tile is shown as selected. A selected tile carries the
/// small yellow check from the approved category design.
///
/// The grid is lazy, so only ask about tiles that are on screen.
bool isSelectedTile(WidgetTester tester, String label) {
  final tile =
      find.ancestor(of: find.text(label), matching: find.byType(Stack)).first;
  return find
      .descendant(of: tile, matching: find.byIcon(Icons.check_rounded))
      .evaluate()
      .isNotEmpty;
}

/// Opens a private room this device just created, ready for game snapshots.
Future<void> openCreatedRoom(WidgetTester tester, FakeApi api) async {
  api.responses['POST /v1/rooms'] = {'room': roomJson()};
  await openPrivateRoom(tester);
  await tapText(tester, 'יצירת חדר');
  await tapLive(tester, 'יצירת חדר');
  expect(find.byType(LiveRoomScreen), findsOneWidget);
}

/// The private room moved behind `משחק ברשת`, so getting to it is two taps.
Future<void> openPrivateRoom(WidgetTester tester) async {
  await tapText(tester, 'משחק ברשת');
  await tapText(tester, 'חדר פרטי');
}

/// Quick matchmaking moved behind `משחק ברשת` as well.
Future<void> openQuickGame(WidgetTester tester) async {
  await tapText(tester, 'משחק ברשת');
  await tapText(tester, 'משחק מהיר');
}
