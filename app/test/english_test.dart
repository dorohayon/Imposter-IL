import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/data/server.dart';
import 'package:imposter_il/local/words.g.dart';
import 'package:imposter_il/local/local_setup_screens.dart';
import 'package:imposter_il/local/online_choice_screen.dart';
import 'package:imposter_il/screens/legal_screens.dart';
import 'package:imposter_il/screens/online_flow.dart';
import 'package:imposter_il/screens/private_flow.dart';
import 'package:imposter_il/screens/secondary_screens.dart';
import 'package:imposter_il/state/game_session.dart';
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
    // The header mirrors: profile at the start (left), settings at the end.
    expect(tester.getCenter(find.byTooltip('Profile')).dx,
        lessThan(tester.getCenter(find.byTooltip('Settings')).dx));
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
    // The Hebrew design: profile top right, settings top left.
    expect(tester.getCenter(find.byTooltip('פרופיל')).dx,
        greaterThan(tester.getCenter(find.byTooltip('הגדרות')).dx));
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

    // Switched from here, the message follows the new language.
    await tapText(tester, 'Language');
    await tapText(tester, 'עברית');
    Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.text('שפת החדר: עברית. כדי להצטרף, מחליפים שפה בהגדרות.'),
        findsOneWidget);
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
    expect(find.textContaining('“Gaming” is locked'), findsOneWidget);
    // The lock sits across the header from the close button: X on the left
    // in English, the lock on the right, the title between them.
    final header = find.ancestor(
        of: find.textContaining('is locked'), matching: find.byType(Row));
    final lock = tester.getCenter(find
        .descendant(of: header.first, matching: find.byIcon(Icons.lock_rounded))
        .first);
    final close = tester.getCenter(find.byIcon(Icons.close_rounded).last);
    final title = tester.getCenter(find.textContaining('is locked'));
    expect(close.dx < title.dx && title.dx < lock.dx, isTrue,
        reason: 'close ${close.dx}, title ${title.dx}, lock ${lock.dx}');
    expect(find.text('Watch an ad'), findsWidgets);
    expect(find.text('Only “Gaming”'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the language is resolved before anything loads', () async {
    SharedPreferences.setMockInitialValues({});
    final session = GameSession(FakeApi());
    addTearDown(session.dispose);
    await session.restore(phoneLocales: const [Locale('fr'), Locale('en')]);
    expect(session.language, 'en');
  });

  test('content answered after the language changed is asked for again',
      () async {
    final api = _HeldApi();
    final session = GameSession(api)..token = 'token-1';
    addTearDown(session.dispose);
    session.language = 'he';
    final load = session.loadContent();
    session.languageResolved('en'); // while the Hebrew answer is on its way
    api.release();
    await load;
    expect(api.requests.map((r) => r.$2).where((p) => p.contains('categories')),
        ['/v1/categories?language=he', '/v1/categories?language=en']);
    expect(session.categories.first.name, 'Food & Drink');
  });

  // Reported from the phone: long English names ran under the lock and the
  // category icon, the check covered a letter, and some names were cut.
  for (final width in [320.0, 390.0]) {
    testWidgets('category tiles keep every English name whole at $width px',
        (tester) async {
      // The real fonts: the test font draws every letter as a wide square.
      await loadRealFonts();
      final api = FakeApi()
        ..responses['GET /v1/categories'] = {
          'categories': [
            for (final c in localCategoriesFor('en'))
              {'id': c.id, 'name': c.name},
          ],
        };
      await startApp(tester, api, saved: _signedIn, store: FakeStore());
      tester.view.physicalSize = Size(width, 844);
      await tester.pumpAndSettle();
      await tapText(tester, 'Online game');
      await tapText(tester, 'Quick game');
      // A selected tile, with its check. The name may carry a line break.
      final movies = find.textContaining('Movies');
      await tester.ensureVisible(movies);
      await tester.pumpAndSettle();
      await tester.tap(movies);
      await tester.pumpAndSettle();

      final grid = find.byType(GridView);
      for (var i = 0; i < 12; i++) {
        final names = tester
            .renderObjectList<RenderParagraph>(
                find.descendant(of: grid, matching: find.byType(RichText)))
            .where((p) => p.text.style?.fontFamily == 'Secular One');
        final marks = [
          for (final m in find
              .descendant(
                  of: grid,
                  matching: find.byWidgetPredicate((w) =>
                      w is Icon ||
                      w.runtimeType.toString() == '_SelectedCategoryCheck'))
              .evaluate())
            (m.renderObject! as RenderBox).localToGlobal(Offset.zero) &
                (m.renderObject! as RenderBox).size,
        ];
        for (final p in names) {
          final text = p.text.toPlainText();
          expect(p.didExceedMaxLines, isFalse, reason: 'cut: $text');
          final rect = p.localToGlobal(Offset.zero) & p.size;
          for (final mark in marks) {
            expect(rect.overlaps(mark.deflate(1)), isFalse,
                reason: '"$text" runs under a mark at $width px');
          }
        }
        await tester.drag(grid, const Offset(0, -120));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }

  test('every language the app has has one-device words', () {
    for (final code in ['he', 'en']) {
      expect(localCategoriesFor(code), hasLength(21), reason: code);
    }
    expect(localCategoriesFor('en').first.name, 'Food & Drink');
  });
}

/// Holds the first content answer until [release], and answers in the
/// language asked for.
class _HeldApi extends FakeApi {
  final _held = Completer<void>();
  var _first = true;

  void release() => _held.complete();

  @override
  Future<Map<String, dynamic>> request(String method, String path,
      {String? token, Object? body}) async {
    if (_first && path.startsWith('/v1/categories')) {
      _first = false;
      requests.add((method, path, body));
      await _held.future;
      return {
        'categories': [
          {'id': 'food', 'name': 'אוכל ושתייה'},
        ],
      };
    }
    if (path.startsWith('/v1/categories?language=en')) {
      requests.add((method, path, body));
      return {
        'categories': [
          {'id': 'food', 'name': 'Food & Drink'},
        ],
      };
    }
    return super.request(method, path, token: token, body: body);
  }
}
