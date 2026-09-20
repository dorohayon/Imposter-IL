import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/data/server.dart';
import 'package:imposter_il/screens/home_screen.dart';
import 'package:imposter_il/screens/live_room.dart';
import 'package:imposter_il/state/game_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_server.dart';
import 'support/helpers.dart';

Map<String, dynamic> endedGame(String id, String myOutcome) =>
    gameJson(phase: 'ended', result: {
      'winner': myOutcome == 'win' ? 'citizens' : 'impostor',
      'reason':
          myOutcome == 'win' ? 'impostor_guess_wrong' : 'impostor_not_caught',
      'impostorPlayerId': 'p_3',
      'secretWord': 'פיל',
      'voteRounds': [],
      'outcomes': {'p_me': myOutcome},
    })
      ..['gameId'] = id;

void enterGame(FakeChannel channel, String gameId) =>
    channel.event('session.state', {
      'playerId': 'p_me',
      'activity': 'game',
      'roomId': 'r_1',
      'gameId': gameId,
    });

Future<GameSession> openActiveGame(
  WidgetTester tester,
  FakeApi api,
) async {
  final session = await startAtHome(tester, api);
  api.responses['POST /v1/rooms'] = {'room': roomJson()};
  await openPrivateRoom(tester);
  await tapText(tester, 'יצירת חדר');
  await tapLive(tester, 'יצירת חדר');
  enterGame(api.channel, 'g_1');
  api.channel.snapshot(
    'game.state',
    'game',
    gameJson(phase: 'hints', turn: 'p_me'),
  );
  await settle(tester);
  return session;
}

void main() {
  testWidgets('edit nickname and avatar on the server', (tester) async {
    final api = FakeApi()
      ..responses['PATCH /v1/sessions/me'] = {'playerId': 'p_me'};
    await startAtHome(tester, api);
    await tester.tap(find.byTooltip('פרופיל'));
    await tester.pumpAndSettle();
    await tapText(tester, 'עריכת כינוי ואווטאר');

    api.responses['PATCH /v1/sessions/me'] =
        const ApiException('invalid_nickname', 422);
    await tester.enterText(find.byType(TextField), 'נועה');
    await tapText(tester, 'שמירה');
    expect(
      find.text('בחרו כינוי באורך 2–18 תווים, כולל ניקוד ואימוג׳י.'),
      findsOneWidget,
    );

    api.responses['PATCH /v1/sessions/me'] = {'playerId': 'p_me'};
    await tester.tap(find.bySemanticsLabel('דמות 12'));
    await tapText(tester, 'שמירה');
    final (_, _, body) =
        api.requests.lastWhere((r) => r.$2 == '/v1/sessions/me');
    expect(body, {
      'nickname': 'נועה',
      'avatarId': 'avatar-m06-magnifying-glass',
    });
    expect(find.text('נועה'), findsOneWidget); // back on the profile
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('session.nickname'), 'נועה');
  });

  testWidgets('nickname length follows the server rune count', (tester) async {
    final api = FakeApi();
    await startApp(tester, api);
    await tapText(tester, 'משחק ברשת');

    // One displayed grapheme, but two Unicode code points: the same count the
    // Go server validates.
    await tester.enterText(find.byType(TextField), 'א\u05B0');
    await tapText(tester, 'ממשיכים');
    final (_, _, body) =
        api.requests.lastWhere((request) => request.$2 == '/v1/sessions');
    expect(body, {'nickname': 'א\u05B0', 'avatarId': 'avatar-f01-notebook'});
  });

  testWidgets('wins and losses are counted once per game and kept',
      (tester) async {
    final api = FakeApi();
    final session = await startAtHome(tester, api);
    await openPrivateRoom(tester);
    api.responses['POST /v1/rooms'] = {'room': roomJson()};
    await tapText(tester, 'יצירת חדר');
    await tapLive(tester, 'יצירת חדר');
    final channel = api.channel;

    enterGame(channel, 'g_1');
    channel.snapshot('game.state', 'game', endedGame('g_1', 'win'));
    channel.snapshot('game.state', 'game', endedGame('g_1', 'win')); // again
    await settle(tester);

    // Leaving a second game before it ends is a loss.
    enterGame(channel, 'g_2');
    channel.snapshot('game.state', 'game',
        gameJson(phase: 'hints', turn: 'p_2')..['gameId'] = 'g_2');
    await settle(tester);
    channel.errors['game.leave'] = 'network_error';
    await tester.tap(find.byTooltip('יציאה'));
    await settle(tester);
    expect(session.losses, 0); // still in the game

    channel.errors.remove('game.leave');
    await tester.tap(find.byTooltip('יציאה'));
    await tester.pumpAndSettle(); // let the game screen finish closing

    await tapTooltip(tester, 'פרופיל');
    Finder stat(String label) => find.descendant(
          of: find.ancestor(of: find.text(label), matching: find.byType(Card)),
          matching: find.byType(Text),
        );
    expect(tester.widget<Text>(stat('ניצחונות').first).data, '1');
    expect(tester.widget<Text>(stat('הפסדים').first).data, '1');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('stats.wins'), 1);
    expect(prefs.getInt('stats.losses'), 1);
  });

  testWidgets('an offline leave survives another dropped connection',
      (tester) async {
    final api = FakeApi();
    final session = await openActiveGame(tester, api);

    api.connectError = Exception('down');
    await api.channel.close();
    await settle(tester);
    await tapLive(tester, 'יציאה מהמשחק');
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(session.losses, 0); // no decision from a stale local snapshot

    // First retry: the command is sent, then this socket drops before either
    // session.state or the reply can confirm it.
    api
      ..channelAutoReply = false
      ..channelEmitLeaveState = false
      ..connectError = null;
    await settle(tester);
    final firstRetry = api.channel;
    firstRetry.event('session.state', {
      'playerId': 'p_me',
      'activity': 'game',
      'roomId': 'r_1',
      'gameId': 'g_1',
    });
    await settle(tester);
    expect(firstRetry.commands('game.leave'), hasLength(1));

    api.connectError = Exception('down');
    await firstRetry.close();
    await settle(tester);

    // Second retry still has the pending leave and completes it.
    api
      ..channelAutoReply = true
      ..channelEmitLeaveState = true
      ..channelLeaveOutcome = 'loss'
      ..connectError = null;
    await settle(tester);
    final secondRetry = api.channel;
    secondRetry.event('session.state', {
      'playerId': 'p_me',
      'activity': 'game',
      'roomId': 'r_1',
      'gameId': 'g_1',
    });
    await settle(tester);

    expect(secondRetry.commands('game.leave'), hasLength(1));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(session.losses, 1);
  });

  testWidgets('offline leave records the server result, not a stale loss',
      (tester) async {
    final api = FakeApi();
    final session = await openActiveGame(tester, api);

    api.connectError = Exception('down');
    await api.channel.close();
    await settle(tester);
    await tapLive(tester, 'יציאה מהמשחק');
    expect(session.wins, 0);
    expect(session.losses, 0);

    // The match actually finished as a win while this device was offline.
    api
      ..channelLeaveOutcome = 'win'
      ..connectError = null;
    await settle(tester);
    api.channel.event('session.state', {
      'playerId': 'p_me',
      'activity': 'game',
      'roomId': 'r_1',
      'gameId': 'g_1',
    });
    await settle(tester);

    expect(session.wins, 1);
    expect(session.losses, 0);
  });

  testWidgets('settings are saved; hiding reactions hides the buttons',
      (tester) async {
    final vibrations = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') vibrations.add('buzz');
        return null;
      },
    );
    final api = FakeApi();
    await startAtHome(tester, api);
    await tester.tap(find.byTooltip('הגדרות'));
    await tester.pumpAndSettle();
    await tapText(tester, 'הצגת תגובות');
    await tapText(tester, 'רטט');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('settings.showReactions'), isFalse);
    expect(prefs.getBool('settings.vibration'), isFalse);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await openPrivateRoom(tester);
    api.responses['POST /v1/rooms'] = {'room': roomJson()};
    await tapText(tester, 'יצירת חדר');
    await tapLive(tester, 'יצירת חדר');
    enterGame(api.channel, 'g_1');
    api.channel.snapshot(
        'game.state',
        'game',
        gameJson(phase: 'hints', turn: 'p_2', hints: [
          {
            'playerId': 'p_me',
            'text': 'חדק',
            'missing': false,
            'reactions': {}
          },
        ]));
    await settle(tester);
    expect(find.text('✓ חדק · רמז אחד'), findsOneWidget);
    expect(find.text('זה מחשיד'), findsNothing); // the whole dock is gone
    expect(find.text('תגובות'), findsNothing);
    expect(vibrations, isEmpty); // vibration is off
  });

  testWidgets('a reopened app keeps its stats and does not recount a game',
      (tester) async {
    final api = FakeApi();
    final session = await startApp(tester, api, saved: {
      'session.token': 'token-1',
      'session.playerId': 'p_me',
      'session.nickname': 'דור',
      'session.avatarId': 'avatar-f01-notebook',
      'stats.wins': 3,
      'stats.losses': 1,
      'stats.countedGames': ['g_1'],
    });
    enterGame(api.channel, 'g_1');
    api.channel.snapshot('game.state', 'game', endedGame('g_1', 'win'));
    await settle(tester);
    expect((session.wins, session.losses), (3, 1));
  });

  testWidgets('saved settings are restored when the app opens', (tester) async {
    final session = await startApp(tester, FakeApi(), saved: {
      'settings.vibration': false,
      'settings.showReactions': false,
    });
    expect(session.vibrationOn, isFalse);
    expect(session.showReactions, isFalse);
  });

  testWidgets('vibrates when my turn comes and when voting starts',
      (tester) async {
    final vibrations = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') vibrations.add('buzz');
        return null;
      },
    );
    final api = FakeApi();
    await startAtHome(tester, api);
    await openPrivateRoom(tester);
    api.responses['POST /v1/rooms'] = {'room': roomJson()};
    await tapText(tester, 'יצירת חדר');
    await tapLive(tester, 'יצירת חדר');

    enterGame(api.channel, 'g_1');
    api.channel.snapshot('game.state', 'game', gameJson(phase: 'role_reveal'));
    await settle(tester);
    expect(vibrations, hasLength(1)); // the game started

    api.channel
        .snapshot('game.state', 'game', gameJson(phase: 'hints', turn: 'p_2'));
    await settle(tester);
    expect(vibrations, hasLength(1)); // someone else's turn

    api.channel
        .snapshot('game.state', 'game', gameJson(phase: 'hints', turn: 'p_me'));
    await settle(tester);
    expect(vibrations, hasLength(2));

    api.channel.snapshot(
        'game.state', 'game', gameJson(phase: 'voting', candidates: ['p_2']));
    await settle(tester);
    expect(vibrations, hasLength(3));
  });

  testWidgets('share opens the system sheet with the room code',
      (tester) async {
    final shared = <String>[];
    final original = shareText;
    shareText = (text) async => shared.add(text);
    addTearDown(() => shareText = original);

    final api = FakeApi();
    await startAtHome(tester, api);
    await openPrivateRoom(tester);
    api.responses['POST /v1/rooms'] = {'room': roomJson()};
    await tapText(tester, 'יצירת חדר');
    await tapLive(tester, 'יצירת חדר');
    await tester.tap(find.byTooltip('שיתוף הקוד'));
    await settle(tester);
    expect(shared.single, contains('482913'));
  });

  testWidgets('the reconnecting overlay counts only when the server does',
      (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    await openPrivateRoom(tester);
    api.responses['POST /v1/rooms'] = {'room': roomJson()};
    await tapText(tester, 'יצירת חדר');
    await tapLive(tester, 'יצירת חדר');
    enterGame(api.channel, 'g_1');

    final bannerCountdown = find.descendant(
      of: find.ancestor(
          of: find.text('מתחברים מחדש...'), matching: find.byType(Material)),
      matching: find.byType(LiveCountdown),
    );
    Future<void> dropWith(
        {required String turn, required int disconnects}) async {
      api.channel.snapshot(
          'game.state',
          'game',
          gameJson(phase: 'hints', turn: turn, players: [
            {...player('p_me', 'דור'), 'disconnects': disconnects},
            player('p_2', 'נועה'),
            player('p_3', 'יובל'),
            player('p_4', 'מאיה'),
          ]),
          version: 10 + disconnects); // newer than the previous connection's
      await settle(tester);
      api.connectError = Exception('down');
      await api.channel.close();
      await settle(tester);
      expect(find.text('מתחברים מחדש...'), findsOneWidget);
    }

    Future<void> reconnect() async {
      api.connectError = null; // no retry timer may outlive the test
      await settle(tester);
      expect(find.text('מתחברים מחדש...'), findsNothing);
    }

    // Someone else's turn: the drop is counted but nothing is timed.
    await dropWith(turn: 'p_2', disconnects: 0);
    expect(find.text('ניתוק 1 מתוך 3'), findsOneWidget);
    expect(bannerCountdown, findsNothing);
    await reconnect();

    // My turn: the server holds it for 30 seconds, on a screen of its own.
    await dropWith(turn: 'p_me', disconnects: 1);
    expect(find.textContaining('ניתוק 2 מתוך 3'), findsOneWidget);
    expect(bannerCountdown, findsOneWidget);
    expect(find.descendant(of: bannerCountdown, matching: find.text('30')),
        findsOneWidget);
    expect(
        find.text(
            'החיבור אבד בזמן התור שלכם. ננסה להחזיר אתכם למשחק במשך 30 שניות.'),
        findsOneWidget);
    expect(find.text('יציאה מהמשחק'), findsOneWidget);
    await reconnect();

    // Even a defensive out-of-range server value is clamped in the copy.
    await dropWith(turn: 'p_2', disconnects: 7);
    expect(find.textContaining('ניתוק 3 מתוך 3'), findsOneWidget);
    expect(find.textContaining('ניתוק 8 מתוך 3'), findsNothing);
    expect(bannerCountdown, findsOneWidget);
    await reconnect();
  });
}
