import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/local/local_screens.dart';
import 'package:imposter_il/monetization/store.dart';
import 'package:imposter_il/screens/home_screen.dart';
import 'package:imposter_il/screens/legal_screens.dart';
import 'package:imposter_il/screens/live_room.dart';
import 'package:imposter_il/screens/online_flow.dart';
import 'package:imposter_il/screens/secondary_screens.dart';

import 'support/fake_monetization.dart';
import 'support/fake_server.dart';
import 'support/helpers.dart';

/// Banners on the screen the player is looking at, not on a route below.
final _banner = find.byElementPredicate(
  (e) =>
      e.widget.key == const ValueKey('ad-banner') &&
      (ModalRoute.of(e)?.isCurrent ?? true),
);

Future<(FakeApi, FakeStore, FakeAds)> _freePlayer(
  WidgetTester tester, {
  Set<String> owned = const {},
}) async {
  final api = FakeApi();
  final store = FakeStore(owned: owned);
  final ads = FakeAds();
  await startAtHomeWith(tester, api: api, store: store, ads: ads);
  return (api, store, ads);
}

Future<void> _openPicker(WidgetTester tester) async {
  await openQuickGame(tester);
  expect(find.byType(CategorySelectionScreen), findsOneWidget);
}

/// Locked tiles and chips announce themselves this way.
Finder _locked(String name) => find.byWidgetPredicate(
      (w) =>
          w is Semantics && w.properties.label == '$name — נעולה, לחצו לפתיחה',
    );

Future<void> _tapLocked(WidgetTester tester, String name) async {
  await tester.ensureVisible(_locked(name));
  await tester.pumpAndSettle();
  await tester.tap(_locked(name));
  await tester.pumpAndSettle();
}

Future<void> _buy(WidgetTester tester) async {
  await tester.tap(find.textContaining('קנייה'));
  await tester.pumpAndSettle();
}

List<String> _searched(FakeApi api) =>
    (api.channel.commands('matchmaking.join').last['payload']['categoryIds']
            as List)
        .cast<String>();

Map<String, dynamic> _ended(String? winner, String reason) => gameJson(
      phase: 'ended',
      result: {
        'winner': winner,
        'reason': reason,
        'impostorPlayerId': 'p_3',
        'secretWord': 'פיל',
        'voteRounds': [
          {'p_me': 'p_3', 'p_2': 'p_3', 'p_4': 'p_3'},
        ],
        'abstentions': [0],
        'outcomes': {'p_me': 'win', 'p_3': 'loss'},
      },
    );

/// The server moving this session into the room's game, then its snapshot.
Future<void> _game(
    WidgetTester tester, FakeApi api, Map<String, dynamic> game) async {
  api.channel.event('session.state', {
    'playerId': 'p_me',
    'activity': 'game',
    'roomId': 'r_1',
    'gameId': 'g_1',
  });
  api.channel.snapshot('game.state', 'game', game);
  await settle(tester);
}

void main() {
  group('locked categories', () {
    testWidgets('a free player sees three open categories and the rest locked',
        (tester) async {
      final (api, _, _) = await _freePlayer(tester);
      await _openPicker(tester);

      expect(find.text('אפשר לבחור כמה קטגוריות · 3 פתוחות בחינם'),
          findsOneWidget);
      expect(find.text('כל הפתוחות'), findsOneWidget);
      // Every category stays visible: the locked ones are there, marked.
      for (final name in ['ספורט וכושר', 'עבודה ומשרד', 'גיימינג']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('לפתיחה'), findsNWidgets(15));

      await tapLive(tester, 'חפש משחק');
      expect(_searched(api), ['food', 'film_tv', 'places']);
    });

    testWidgets('a locked category opens the popup with the store prices',
        (tester) async {
      await _freePlayer(tester);
      await _openPicker(tester);
      await _tapLocked(tester, 'ספורט וכושר');

      expect(find.text('״ספורט וכושר״ נעולה'), findsOneWidget);
      expect(find.text('בחרו איך לפתוח אותה'), findsOneWidget);
      expect(find.text('רק ״ספורט וכושר״'), findsOneWidget);
      expect(find.text('פרימיום חודשי'), findsOneWidget);
      expect(find.text('פרימיום לכל החיים'), findsOneWidget);
      expect(find.text('9.90 ₪'), findsOneWidget);
      expect(find.text('14.90 ₪'), findsOneWidget);
      expect(find.text('59.90 ₪'), findsOneWidget);
      // The category the player tapped is chosen for them.
      expect(find.textContaining('קנייה'), findsOneWidget);
      expect(find.textContaining('הפרסומות ממשיכות להופיע'), findsOneWidget);
      expect(find.text('שחזור רכישות'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'fits 320px');
    });

    testWidgets('buying a category unlocks it and adds it to the choice',
        (tester) async {
      final (api, store, _) = await _freePlayer(tester);
      await _openPicker(tester);
      await tapText(tester, 'אוכל ושתייה'); // an explicit choice, not "הכול"
      await _tapLocked(tester, 'ספורט וכושר');

      await _buy(tester);
      expect(store.bought, ['category_sports']);
      expect(find.text('״ספורט וכושר״ נפתחה!'), findsOneWidget);
      expect(find.text('הקטגוריה שלכם לתמיד. הפרסומות ממשיכות להופיע.'),
          findsOneWidget);
      await tapText(tester, 'בוחרים ב״ספורט וכושר״');

      expect(find.text('״ספורט וכושר״ נעולה'), findsNothing);
      expect(find.text('לפתיחה'), findsNWidgets(14));
      await tapLive(tester, 'חפש משחק');
      expect(_searched(api), ['food', 'sports']);
    });

    testWidgets('monthly Premium states the renewal before joining',
        (tester) async {
      final (_, store, _) = await _freePlayer(tester);
      await _openPicker(tester);
      await _tapLocked(tester, 'גיימינג');
      await tapText(tester, 'פרימיום חודשי');

      expect(find.text('הצטרפות לפרימיום'), findsOneWidget);
      expect(
        find.textContaining(
            'המנוי מתחדש אוטומטית ב־\u206614.90 ₪\u2069 בכל חודש עד לביטול'),
        findsOneWidget,
      );
      expect(find.textContaining('לפחות 24 שעות לפני מועד החידוש'),
          findsOneWidget);

      await tapText(tester, 'הצטרפות לפרימיום');
      expect(store.bought, [monthly]);
      expect(find.text('ברוכים הבאים לפרימיום'), findsOneWidget);
      expect(find.text('בלי באנרים ובלי מודעות במסך מלא'), findsOneWidget);
      await tapText(tester, 'מתחילים לשחק');

      // Everything is open, and the header says so.
      expect(find.text('לפתיחה'), findsNothing);
      expect(find.text('פרימיום'), findsOneWidget);
      expect(find.text('כל הקטגוריות'), findsOneWidget);
    });

    testWidgets('the popup links the terms and the privacy policy',
        (tester) async {
      await _freePlayer(tester);
      await _openPicker(tester);
      await _tapLocked(tester, 'ספורט וכושר');
      await tapText(tester, 'תנאי שימוש');
      expect(find.byType(TermsScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tapText(tester, 'מדיניות פרטיות');
      expect(find.byType(PrivacyScreen), findsOneWidget);
    });

    testWidgets('a cancelled purchase charges nothing and can be closed',
        (tester) async {
      final (_, store, _) = await _freePlayer(tester);
      store.outcome = StoreStatus.canceled;
      await _openPicker(tester);
      await _tapLocked(tester, 'ספורט וכושר');
      await _buy(tester);

      expect(find.text('הרכישה בוטלה. לא בוצע חיוב.'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('״ספורט וכושר״ נעולה'), findsNothing);
      expect(find.text('לפתיחה'), findsNWidgets(15));
    });

    testWidgets('while the store works, the popup stays open', (tester) async {
      final (_, store, _) = await _freePlayer(tester);
      store.outcome = null; // the store never answers in this test
      await _openPicker(tester);
      await _tapLocked(tester, 'ספורט וכושר');
      await _buy(tester);

      expect(find.text('מתחברים לחנות…'), findsOneWidget);
      expect(
        find.text('ממשיכים בחלון התשלום של החנות. אין לסגור את האפליקציה.'),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('״ספורט וכושר״ נעולה'), findsOneWidget);
    });

    testWidgets('an error names the cause and offers another try',
        (tester) async {
      final (_, store, _) = await _freePlayer(tester);
      store.outcome = StoreStatus.error;
      await _openPicker(tester);
      await _tapLocked(tester, 'ספורט וכושר');
      await _buy(tester);
      expect(
        find.text(
            'הרכישה לא הושלמה ולא בוצע חיוב. בדקו את החיבור לאינטרנט ונסו שוב.'),
        findsOneWidget,
      );
      store.outcome = StoreStatus.purchased;
      await tapText(tester, 'ניסיון נוסף');
      expect(find.text('״ספורט וכושר״ נפתחה!'), findsOneWidget);
    });

    testWidgets('prices that cannot load do not trap the player',
        (tester) async {
      final (_, store, _) = await _freePlayer(tester);
      store.productsFail = true;
      await _openPicker(tester);
      await _tapLocked(tester, 'ספורט וכושר');
      expect(
        find.textContaining('לא הצלחנו לטעון את המחירים מהחנות'),
        findsOneWidget,
      );
      store.productsFail = false;
      await tapText(tester, 'ניסיון נוסף');
      expect(find.text('9.90 ₪'), findsOneWidget);
    });

    testWidgets('restore in the popup reopens a bought category',
        (tester) async {
      final (_, store, _) = await _freePlayer(tester);
      await _openPicker(tester);
      await _tapLocked(tester, 'ספורט וכושר');
      await tapText(tester, 'שחזור רכישות');
      expect(find.text('לא נמצאו רכישות קודמות בחשבון החנות הזה.'),
          findsOneWidget);

      store.owned.add('category_sports'); // bought on another phone
      await tapText(tester, 'שחזור רכישות');
      expect(find.text('הרכישות שוחזרו'), findsOneWidget);
      expect(find.text('״ספורט וכושר״ פתוחה שוב במכשיר הזה.'), findsOneWidget);
      await tapText(tester, 'סגירה');
      expect(find.text('לפתיחה'), findsNWidgets(14));
      expect(find.text('✓ נרכשה'), findsOneWidget);
    });

    testWidgets('a private room offers the host\'s categories only',
        (tester) async {
      final (api, _, _) = await _freePlayer(tester);
      api.responses['POST /v1/rooms'] = {'room': roomJson()};
      await openPrivateRoom(tester);
      await tapText(tester, 'יצירת חדר');
      expect(find.text('3 פתוחות בחינם'), findsOneWidget);

      await _tapLocked(tester, 'ספורט וכושר');
      expect(find.text('״ספורט וכושר״ נעולה'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      await tapLive(tester, 'יצירת חדר');
      final body = api.requests.lastWhere((r) => r.$2 == '/v1/rooms').$3!
          as Map<String, Object?>;
      expect(body['categoryIds'], ['food', 'film_tv', 'places']);
    });

    testWidgets('one-device play locks the same categories', (tester) async {
      await _freePlayer(tester, owned: {'category_gaming'});
      await tapText(tester, 'משחק במכשיר אחד');
      await tapText(tester, 'המשך להגדרות');
      expect(find.text('4 פתוחות'), findsOneWidget);
      for (final name in ['ספורט וכושר', 'עבודה ומשרד']) {
        expect(_locked(name), findsOneWidget);
      }
      await tapText(tester, 'מתחילים');
      final screen =
          tester.widget<LocalGameScreen>(find.byType(LocalGameScreen));
      expect(screen.categoryIds, ['food', 'film_tv', 'places', 'gaming']);
    });
  });

  group('ads', () {
    testWidgets('a free player gets banners on the non-game screens',
        (tester) async {
      final (_, _, ads) = await _freePlayer(tester);
      expect(ads.started, 1, reason: 'started from home, after the gate');
      expect(_banner, findsOneWidget);

      await tapTooltip(tester, 'הגדרות');
      expect(_banner, findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await _openPicker(tester);
      expect(_banner, findsOneWidget);
    });

    testWidgets('a single category purchase keeps the banners', (tester) async {
      await _freePlayer(tester, owned: {'category_sports'});
      expect(_banner, findsOneWidget);
    });

    testWidgets('Premium players never see a banner', (tester) async {
      for (final product in [lifetime, monthly]) {
        final ads = FakeAds();
        await startAtHomeWith(tester,
            store: FakeStore(owned: {product}), ads: ads);
        expect(_banner, findsNothing, reason: product);
        expect(ads.started, 0, reason: product);
      }
    });

    testWidgets('no banner during a game', (tester) async {
      final (api, _, _) = await _freePlayer(tester);
      await openCreatedRoom(tester, api);
      expect(_banner, findsOneWidget, reason: 'the lobby has one');

      for (final phase in ['role_reveal', 'hints', 'voting']) {
        await _game(tester, api, gameJson(phase: phase, turn: 'p_2'));
        expect(_banner, findsNothing, reason: phase);
      }
      await _game(tester, api, _ended('citizens', 'impostor_guess_wrong'));
      expect(find.text('האזרחים ניצחו!'), findsOneWidget);
      expect(_banner, findsNothing, reason: 'the full result comes first');
    });

    testWidgets('after a completed match the ad comes before the next game',
        (tester) async {
      final (api, _, ads) = await _freePlayer(tester);
      ads.holdOpen = true;
      await openCreatedRoom(tester, api);
      await _game(tester, api, _ended('citizens', 'impostor_guess_wrong'));

      await tapLive(tester, 'משחק נוסף');
      expect(ads.shown, 1);
      expect(api.channel.commands('game.playAgain'), isEmpty,
          reason: 'nothing moves until the ad is closed');
      ads.close();
      await settle(tester);
      expect(api.channel.commands('game.playAgain'), hasLength(1));
    });

    testWidgets('a second tap while the ad is up does nothing', (tester) async {
      final (api, _, ads) = await _freePlayer(tester);
      ads.holdOpen = true;
      await openCreatedRoom(tester, api);
      await _game(tester, api, _ended('citizens', 'impostor_guess_wrong'));

      await tapLive(tester, 'משחק נוסף');
      await tapLive(tester, 'משחק נוסף');
      await tapLive(tester, 'חזרה למסך הבית');
      expect(ads.shown, 1);
      ads.close();
      await settle(tester);
      expect(api.channel.commands('game.playAgain'), hasLength(1));
      expect(api.channel.commands('game.leave'), isEmpty);
    });

    testWidgets('going home after a match shows the ad first too',
        (tester) async {
      final (api, _, ads) = await _freePlayer(tester);
      await openCreatedRoom(tester, api);
      await _game(tester, api, _ended('impostor', 'impostor_guessed_word'));
      await tapLive(tester, 'חזרה למסך הבית');
      expect(ads.shown, 1);
      expect(api.channel.commands('game.leave'), hasLength(1));
    });

    for (final (reason, winner) in [
      ('abandoned', null),
      ('not_enough_players', null),
      ('impostor_gone', 'citizens'),
    ]) {
      testWidgets('no ad after a match that ended as $reason', (tester) async {
        final (api, _, ads) = await _freePlayer(tester);
        await openCreatedRoom(tester, api);
        await _game(tester, api, _ended(winner, reason));
        await tapLive(tester, 'משחק נוסף');
        expect(ads.shown, 0);
        expect(api.channel.commands('game.playAgain'), hasLength(1));
      });
    }

    testWidgets('a missing ad never holds the player', (tester) async {
      final (api, _, ads) = await _freePlayer(tester);
      await openCreatedRoom(tester, api);
      ads.loaded = false; // the network had no ad to give
      await _game(tester, api, _ended('citizens', 'impostor_guess_wrong'));
      await tapLive(tester, 'משחק נוסף');
      expect(ads.shown, 0);
      expect(api.channel.commands('game.playAgain'), hasLength(1));
    });

    testWidgets('Premium players never get an interstitial', (tester) async {
      final api = FakeApi();
      final ads = FakeAds()..loaded = true;
      await startAtHomeWith(tester,
          api: api, store: FakeStore(owned: {monthly}), ads: ads);
      await openCreatedRoom(tester, api);
      await _game(tester, api, _ended('citizens', 'impostor_guess_wrong'));
      await tapLive(tester, 'משחק נוסף');
      expect(ads.shown, 0);
    });
  });

  testWidgets('settings can restore purchases', (tester) async {
    final (_, store, _) = await _freePlayer(tester);
    await tapTooltip(tester, 'הגדרות');
    await tapText(tester, 'שחזור רכישות');
    expect(
        find.text('לא נמצאו רכישות קודמות בחשבון החנות הזה.'), findsOneWidget);
    store.owned.add(lifetime);
    await tester.pump(const Duration(seconds: 5)); // let the snack bar go
    await tester.pumpAndSettle();
    await tapText(tester, 'שחזור רכישות');
    expect(find.text('הרכישות שוחזרו.'), findsOneWidget);
    expect(find.text('פרימיום'), findsOneWidget);
    expect(_banner, findsNothing, reason: 'Premium came back, ads went');
  });

  testWidgets('a subscriber can manage the subscription from Settings',
      (tester) async {
    final opened = <Uri>[];
    final original = openExternal;
    openExternal = (uri) async {
      opened.add(uri);
      return true;
    };
    addTearDown(() => openExternal = original);

    await startAtHomeWith(tester, store: FakeStore(owned: {monthly}));
    await tapTooltip(tester, 'הגדרות');
    await tapText(tester, 'ניהול המנוי');
    expect(opened.single.host, anyOf('play.google.com', 'apps.apple.com'));
    if (opened.single.host == 'play.google.com') {
      expect(opened.single.queryParameters,
          {'sku': 'premium_monthly', 'package': 'com.imposteril.app'});
    }
  });

  for (final (who, owned) in [
    ('a free player', <String>{}),
    ('a lifetime owner', {lifetime}),
  ]) {
    testWidgets('$who gets no subscription row', (tester) async {
      await startAtHomeWith(tester, store: FakeStore(owned: owned));
      await tapTooltip(tester, 'הגדרות');
      expect(find.text('ניהול המנוי'), findsNothing);
    });
  }

  group('design fixes', () {
    testWidgets('the clue card is one short row', (tester) async {
      final api = FakeApi();
      await startAtHome(tester, api);
      await openCreatedRoom(tester, api);
      await _game(tester, api, gameJson(phase: 'hints', turn: 'p_me'));

      expect(find.text('שליחה'), findsOneWidget);
      expect(find.byTooltip('שליחת רמז'), findsOneWidget);
      expect(find.text('הרמז שלך · מילה אחת'), findsNothing);
      final field = tester.getRect(find.byType(TextField));
      final send = tester.getRect(find.text('שליחה'));
      expect(send.center.dy, closeTo(field.center.dy, 4),
          reason: 'the field and the button share a row');
      expect(field.height, lessThan(60));
    });

    testWidgets('the impostor sees every clue while guessing', (tester) async {
      final api = FakeApi();
      await startAtHome(tester, api);
      await openCreatedRoom(tester, api);
      await _game(
        tester,
        api,
        gameJson(phase: 'impostor_guess', role: 'impostor', hints: [
          for (final (id, text) in [('p_2', 'חדק'), ('p_3', 'אפור')])
            {
              'playerId': id,
              'text': text,
              'missing': false,
              'reactions': <String, dynamic>{},
            },
          {
            'playerId': 'p_4',
            'text': '',
            'missing': true,
            'reactions': <String, dynamic>{},
          },
        ]),
      );

      expect(find.text('הרמזים של שאר השחקנים'), findsOneWidget);
      expect(find.text('קטגוריה: חיות'), findsOneWidget);
      expect(find.text('חדק'), findsOneWidget);
      expect(find.text('אפור'), findsOneWidget);
      expect(find.text('לא נשלח רמז'), findsOneWidget);
      for (final name in ['נועה', 'יובל', 'מאיה']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('דור'), findsNothing, reason: 'not their own card');
      expect(find.text('מה המילה?'), findsOneWidget);
      expect(find.text('שליחת ניחוש'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('home keeps its buttons clear of the edge without a banner',
      (tester) async {
    await startAtHome(tester); // lifetime Premium: no banner
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(_banner, findsNothing);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).bottomNavigationBar,
      isNull,
    );
  });

  testWidgets('the live room shows its banner only in the lobby',
      (tester) async {
    final (api, _, _) = await _freePlayer(tester);
    await openCreatedRoom(tester, api);
    expect(find.byType(LiveRoomScreen), findsOneWidget);
    expect(_banner, findsOneWidget);
  });
}
