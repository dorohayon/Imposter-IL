import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/data/server.dart';
import 'package:imposter_il/local/words.g.dart';
import 'package:imposter_il/local/local_setup_screens.dart';
import 'package:imposter_il/local/online_choice_screen.dart';
import 'package:imposter_il/screens/legal_screens.dart';
import 'package:imposter_il/screens/online_flow.dart';
import 'package:imposter_il/screens/private_flow.dart';
import 'package:imposter_il/screens/secondary_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_monetization.dart';
import 'support/fake_server.dart';
import 'support/helpers.dart';

// The app in English (docs/localization.md). The other suites read Hebrew;
// these run on a phone set to another language.

const _signedIn = {
  'session.token': 'token-1',
  'session.playerId': 'p_me',
  'session.nickname': 'Dana',
  'session.avatarId': 'avatar-f01-notebook',
};

void _phone(List<Locale> locales) =>
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .localesTestValue = locales;

void main() {
  setUp(() => _phone(const [Locale('en', 'US')]));

  testWidgets('an English phone opens the app in English, left to right',
      (tester) async {
    final session = await startApp(tester, FakeApi(), saved: _signedIn);
    expect(find.text('Online game'), findsOneWidget);
    expect(find.text('One-device game'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('Online game'))),
        TextDirection.ltr);
    expect(session.language, 'en');
    expect(tester.takeException(), isNull, reason: 'fits 320 px');
  });

  testWidgets('a phone language the app lacks falls back to English',
      (tester) async {
    _phone(const [Locale('fr'), Locale('de')]);
    await startApp(tester, FakeApi(), saved: _signedIn);
    expect(find.text('Online game'), findsOneWidget);
  });

  testWidgets('a Hebrew phone still opens in Hebrew', (tester) async {
    _phone(const [Locale('fr'), Locale('he', 'IL')]);
    await startApp(tester, FakeApi(), saved: _signedIn);
    expect(find.text('משחק ברשת'), findsOneWidget);
  });

  testWidgets('Settings switches the language and remembers the choice',
      (tester) async {
    final session = await startApp(tester, FakeApi(), saved: _signedIn);
    await tapTooltip(tester, 'Settings');
    expect(find.text('Phone language · English'), findsOneWidget);

    await tapText(tester, 'Language');
    await tapText(tester, 'עברית');
    expect(find.text('הגדרות'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('הגדרות'))),
        TextDirection.rtl);
    expect(session.language, 'he');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.language'), 'he');

    await tapText(tester, 'שפה');
    await tapText(tester, 'שפת הטלפון');
    expect(find.text('Settings'), findsOneWidget);
    expect(prefs.getString('settings.language'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an English search asks for English content and players',
      (tester) async {
    final api = FakeApi();
    await startApp(tester, api, saved: _signedIn);
    await tapText(tester, 'Online game');
    await tapText(tester, 'Quick game');
    await tapLive(tester, 'Find a game');

    expect(
        api.requests.map((r) => r.$2),
        containsAll(
            ['/v1/categories?language=en', '/v1/reactions?language=en']));
    expect(api.channel.commands('matchmaking.join').single['payload'],
        containsPair('language', 'en'));
  });

  testWidgets('a room in another language says which, and offers Settings',
      (tester) async {
    final api = FakeApi()
      ..responses['POST /v1/rooms/join'] =
          const ApiException('room_language_mismatch', 409, {'language': 'he'});
    await startApp(tester, api, saved: _signedIn);
    await open(tester, const JoinRoomScreen(code: '482913'));
    await tapText(tester, 'Join');

    expect(api.requests.last.$3, {'code': '482913', 'language': 'en'});
    expect(
      find.text(
          "This room's language is עברית. To join, switch the language in Settings."),
      findsOneWidget,
    );
    await tapText(tester, 'Settings');
    expect(find.text('Language'), findsOneWidget);
  });

  testWidgets('one-device play offers the English words', (tester) async {
    await startApp(tester, FakeApi(), saved: _signedIn);
    await tapText(tester, 'One-device game');
    await tapText(tester, 'Continue to settings');
    expect(find.text('Food & Drink'), findsOneWidget);
    expect(find.text('אוכל ושתייה'), findsNothing);
    expect(tester.takeException(), isNull, reason: 'fits 320 px');
  });

  // English runs longer than Hebrew: every screen outside a game, at 320 px.
  testWidgets('the screens fit 320 px in English', (tester) async {
    await startApp(tester, FakeApi(), saved: _signedIn);
    for (final screen in <Widget>[
      const OnlineChoiceScreen(),
      const CategorySelectionScreen(),
      const FriendsScreen(),
      const CreateRoomScreen(),
      const JoinRoomScreen(),
      const ProfileScreen(),
      const SettingsScreen(),
      const HowToPlayScreen(),
      const TermsScreen(),
      const PrivacyScreen(),
      const LocalPlayersScreen(),
    ]) {
      await open(tester, screen);
      expect(tester.takeException(), isNull, reason: '${screen.runtimeType}');
      Navigator.of(tester.element(find.byWidget(screen))).pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('the purchase popup fits 320 px in English', (tester) async {
    final api = FakeApi()
      ..responses['GET /v1/categories'] = {
        'categories': [
          {'id': 'food', 'name': 'Food & Drink'},
          {'id': 'gaming', 'name': 'Gaming'},
        ],
      };
    await startApp(tester, api, saved: _signedIn, store: FakeStore());
    await tapText(tester, 'Online game');
    await tapText(tester, 'Quick game');
    final locked = find.byWidgetPredicate((w) =>
        w is Semantics &&
        w.properties.label == 'Gaming — locked, tap to unlock');
    await tester.ensureVisible(locked);
    await tester.pumpAndSettle();
    await tester.tap(locked);
    await tester.pumpAndSettle();
    expect(find.text('"Gaming" is locked'), findsOneWidget);
    expect(find.text('Watch an ad'), findsWidgets);
    expect(find.text('Only "Gaming"'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('every language the app has has one-device words', () {
    for (final code in ['he', 'en']) {
      expect(localCategoriesFor(code), hasLength(18), reason: code);
    }
    expect(localCategoriesFor('en').first.name, 'Food & Drink');
  });
}
