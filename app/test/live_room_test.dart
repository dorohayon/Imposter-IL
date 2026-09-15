import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/data/server.dart';
import 'package:imposter_il/screens/home_screen.dart';
import 'package:imposter_il/screens/live_room.dart';
import 'package:imposter_il/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_server.dart';
import 'support/helpers.dart';

Future<void> openCreatedRoom(WidgetTester tester, FakeApi api) async {
  api.responses['POST /v1/rooms'] = {'room': roomJson()};
  await tapText(tester, 'משחק עם חברים');
  await tapText(tester, 'יצירת חדר');
  await tapLive(tester, 'יצירת חדר');
  expect(find.byType(LiveRoomScreen), findsOneWidget);
}

void main() {
  testWidgets('onboarding creates a session and remembers it', (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);

    final (_, _, body) = api.requests.firstWhere((r) => r.$2 == '/v1/sessions');
    expect(body, {'nickname': 'דור', 'avatarId': 'avatar-f01-notebook'});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('session.token'), 'token-1');
    expect(api.channels, hasLength(1));
  });

  testWidgets('a saved identity starts on the home screen', (tester) async {
    await startApp(tester, FakeApi(), saved: {
      'session.token': 'token-1',
      'session.playerId': 'p_me',
      'session.nickname': 'דור',
      'session.avatarId': 'avatar-f01-notebook',
    });
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
  });

  testWidgets('onboarding shows server errors', (tester) async {
    final api = FakeApi()
      ..responses['POST /v1/sessions'] = const ApiException('network_error');
    await startApp(tester, api);
    await tester.enterText(find.byType(TextField), 'דור');
    await tapText(tester, 'ממשיכים');
    expect(
        find.text('אין חיבור לשרת. בדקו את החיבור ונסו שוב.'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('create a room with server categories, manage the lobby',
      (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    api.responses['POST /v1/rooms'] = {'room': roomJson()};
    await tapText(tester, 'משחק עם חברים');
    await tapText(tester, 'יצירת חדר');

    // Categories come from the server; deselect one before creating.
    expect(find.text('חפצים'), findsOneWidget);
    await tapText(tester, 'חפצים');
    await tapText(tester, '10 שניות');
    await tapLive(tester, 'יצירת חדר');

    final (_, _, body) = api.requests.firstWhere((r) => r.$2 == '/v1/rooms');
    expect(body, {
      'maxPlayers': 8,
      'hintSeconds': 10,
      'categoryIds': ['food', 'animals', 'sports', 'professions', 'places'],
    });
    expect(find.text('482913'), findsOneWidget);
    expect(find.text('מנהל החדר · אני'), findsOneWidget);
    expect(isEnabled(tester, 'התחלת משחק'), isFalse);

    api.channel.snapshot(
        'room.state',
        'room',
        roomJson(players: [
          player('p_me', 'דור'),
          player('p_2', 'נועה'),
          player('p_3', 'יובל', connected: false),
          player('p_4', 'מאיה'),
        ]));
    await settle(tester);
    expect(find.text('4 מתוך 8 שחקנים'), findsOneWidget);
    expect(find.text('מנותק'), findsOneWidget);
    expect(find.byTooltip('הסרת דור'), findsNothing);

    await tester.ensureVisible(find.byTooltip('הסרת נועה'));
    await tester.tap(find.byTooltip('הסרת נועה'));
    await settle(tester);
    expect(api.channel.commands('room.kick').single['payload'],
        {'roomId': 'r_1', 'playerId': 'p_2'});

    api.channel.errors['room.start'] = 'content_unavailable';
    await tapLive(tester, 'התחלת משחק');
    expect(api.channel.commands('room.start'), hasLength(1));
    expect(find.text('השרת עדיין לא מוכן להתחלת משחקים'), findsOneWidget);
  });

  testWidgets('join errors are shown inline; a joiner cannot start',
      (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    await tapText(tester, 'משחק עם חברים');
    await tapText(tester, 'הצטרפות לחדר');

    api.responses['POST /v1/rooms/join'] =
        const ApiException('room_not_found', 404);
    await tester.enterText(find.byType(TextField), '111111');
    await tapText(tester, 'הצטרפות');
    expect(find.text('החדר לא נמצא. בדקו את הקוד ונסו שוב.'), findsOneWidget);

    api.responses['POST /v1/rooms/join'] = {
      'room': roomJson(host: 'p_2', players: [
        player('p_2', 'נועה'),
        player('p_me', 'דור'),
      ]),
    };
    await tester.enterText(find.byType(TextField), '482913');
    await tester.pump(); // typing clears the error and restores the label
    await tapLive(tester, 'הצטרפות');
    expect(find.text('החדר של נועה'), findsOneWidget);
    expect(isEnabled(tester, 'רק מנהל החדר יכול להתחיל'), isFalse);
    expect(find.byIcon(Icons.person_remove_rounded), findsNothing);
  });

  testWidgets('a live game from role reveal to another game', (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    await openCreatedRoom(tester, api);
    final channel = api.channel;

    channel.event('session.state', {
      'playerId': 'p_me',
      'activity': 'game',
      'roomId': 'r_1',
      'gameId': 'g_1'
    });
    channel.snapshot('game.state', 'game', gameJson(phase: 'role_reveal'));
    await settle(tester);
    expect(find.text('המילה שלך'), findsOneWidget);
    expect(find.text('פיל'), findsOneWidget);
    await tapLive(tester, 'הבנתי');
    expect(channel.commands('game.confirmRole').single['payload'],
        {'gameId': 'g_1'});

    // My turn: a blocked hint shows the server's reason under the field.
    channel.snapshot(
        'game.state', 'game', gameJson(phase: 'hints', turn: 'p_me'));
    await settle(tester);
    expect(find.text('התור שלך'), findsOneWidget);
    channel.errors['game.submitHint'] = 'hint_contains_secret';
    await tester.enterText(find.byType(TextField), 'הפיל');
    await tapLive(tester, 'שליחת רמז');
    expect(find.text('אסור לחשוף את המילה הסודית'), findsOneWidget);
    channel.errors.remove('game.submitHint');
    await tester.enterText(find.byType(TextField), 'חדק');
    await tapLive(tester, 'שליחת רמז');
    expect(channel.commands('game.submitHint').last['payload'],
        {'gameId': 'g_1', 'text': 'חדק'});

    // Someone else's turn, with reactions to the last hint.
    channel.snapshot(
        'game.state',
        'game',
        gameJson(
          phase: 'hints',
          turn: 'p_2',
          hints: [
            {
              'playerId': 'p_me',
              'text': 'חדק',
              'missing': false,
              'reactions': {'laugh': 2}
            },
          ],
        ));
    await settle(tester);
    expect(find.text('נועה כותב רמז...'), findsOneWidget);
    expect(find.text('הרמז: חדק'), findsOneWidget);
    await tapLive(tester, 'זה מחשיד');
    expect(channel.commands('game.react').single['payload'],
        {'gameId': 'g_1', 'hintIndex': 0, 'reactionId': 'suspicious'});

    // A stale snapshot is ignored.
    channel.snapshot('game.state', 'game', gameJson(phase: 'role_reveal'),
        version: 1);
    await settle(tester);
    expect(find.text('נועה כותב רמז...'), findsOneWidget);

    // Voting: I cannot pick myself; my choice is sent on confirm.
    channel.snapshot(
        'game.state',
        'game',
        gameJson(
          phase: 'voting',
          candidates: ['p_me', 'p_2', 'p_3', 'p_4'],
        ),
        version: 10);
    await settle(tester);
    expect(isEnabled(tester, 'אישור הצבעה'), isFalse);
    await tapLive(tester, 'יובל');
    await tapLive(tester, 'אישור הצבעה');
    expect(channel.commands('game.vote').single['payload'],
        {'gameId': 'g_1', 'targetPlayerId': 'p_3'});

    // The result, then another game back in the lobby.
    channel.snapshot(
        'game.state',
        'game',
        gameJson(phase: 'ended', result: {
          'winner': 'impostor',
          'reason': 'impostor_guessed_word',
          'impostorPlayerId': 'p_3',
          'secretWord': 'פיל',
          'voteRounds': [
            {'p_me': 'p_3', 'p_2': 'p_3', 'p_4': 'p_3', 'p_3': 'p_2'},
          ],
          'outcomes': {'p_me': 'loss', 'p_3': 'win'},
        }));
    await settle(tester);
    expect(find.text('המתחזה ניצח!'), findsOneWidget);
    expect(find.text('המתחזה נתפס אבל ניחש את המילה'), findsOneWidget);
    expect(find.text('הפסדת'), findsOneWidget);
    await tapLive(tester, 'משחק נוסף');
    expect(channel.commands('game.playAgain'), hasLength(1));
    channel.event('session.state',
        {'playerId': 'p_me', 'activity': 'room', 'roomId': 'r_1'});
    await settle(tester);
    expect(find.text('482913'), findsOneWidget);
  });

  testWidgets('the impostor never gets a word button', (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    await openCreatedRoom(tester, api);
    api.channel.event('session.state', {
      'playerId': 'p_me',
      'activity': 'game',
      'roomId': 'r_1',
      'gameId': 'g_1'
    });
    api.channel.snapshot('game.state', 'game',
        gameJson(phase: 'hints', role: 'impostor', turn: 'p_2'));
    await settle(tester);
    expect(find.text('הצגת המילה'), findsNothing);
    expect(find.text('פיל'), findsNothing);
  });

  testWidgets('leaving a game sends game.leave and goes home', (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    await openCreatedRoom(tester, api);
    api.channel.event('session.state', {
      'playerId': 'p_me',
      'activity': 'game',
      'roomId': 'r_1',
      'gameId': 'g_1'
    });
    api.channel.snapshot('game.state', 'game', gameJson(phase: 'role_reveal'));
    await settle(tester);

    await tester.tap(find.byTooltip('יציאה'));
    await settle(tester);
    expect(api.channel.commands('game.leave').single['payload'],
        {'gameId': 'g_1'});
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('a removed player sees screen 27, a kicked player goes home',
      (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    await openCreatedRoom(tester, api);

    api.channel.event('room.kicked', {'roomId': 'r_1'});
    api.channel
        .event('session.state', {'playerId': 'p_me', 'activity': 'none'});
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('מנהל החדר הוציא אותך מהחדר'), findsOneWidget);

    await openCreatedRoom(tester, api);
    api.channel.event('session.state', {
      'playerId': 'p_me',
      'activity': 'game',
      'roomId': 'r_1',
      'gameId': 'g_1'
    });
    api.channel.snapshot(
        'game.state',
        'game',
        gameJson(phase: 'hints', players: [
          player('p_me', 'דור', status: 'removed', connected: false),
          player('p_2', 'נועה'),
          player('p_3', 'יובל'),
        ]),
        version: 100);
    await settle(tester);
    expect(find.text('זה היה הניתוק השלישי ונרשם הפסד.'), findsOneWidget);
    await tapLive(tester, 'חזרה למסך הבית');
    expect(api.channel.commands('game.leave'), hasLength(1));
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('a dropped connection shows the banner and reconnects',
      (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    await openCreatedRoom(tester, api);

    api.connectError = Exception('down');
    await api.channel.close();
    await settle(tester);
    expect(find.text('מתחברים מחדש...'), findsOneWidget);

    api.connectError = null;
    await tester.pump(const Duration(milliseconds: 100));
    await settle(tester);
    expect(api.channels, hasLength(2));
    expect(find.text('מתחברים מחדש...'), findsNothing);
  });

  testWidgets('a session lost mid-room shows screen 29 without a loss',
      (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    await openCreatedRoom(tester, api);

    // The server restarted: the socket closes and the token is unknown.
    api.unknownTokens.add('token-1');
    api.responses['POST /v1/sessions'] = {
      'playerId': 'p_new',
      'sessionToken': 'token-2',
    };
    api.connectError = Exception('down');
    await api.channel.close();
    await settle(tester);
    api.connectError = null;
    await settle(tester);

    expect(find.text('המשחק הופסק עקב תקלה בחיבור לשרת. לא נרשם הפסד.'),
        findsOneWidget);
    await tapLive(tester, 'חזרה למסך הבית');
    expect(find.byType(HomeScreen), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('session.token'), 'token-2');
  });

  testWidgets('reopening the app mid-game returns to the game', (tester) async {
    final api = FakeApi();
    await startApp(tester, api, saved: {
      'session.token': 'token-1',
      'session.playerId': 'p_me',
      'session.nickname': 'דור',
      'session.avatarId': 'avatar-f01-notebook',
    });
    expect(find.byType(HomeScreen), findsOneWidget);

    api.channel.event('session.state', {
      'playerId': 'p_me',
      'activity': 'game',
      'roomId': 'r_1',
      'gameId': 'g_1',
    });
    api.channel.snapshot('game.state', 'game', gameJson(phase: 'role_reveal'));
    await settle(tester);
    expect(find.byType(LiveRoomScreen), findsOneWidget);
    expect(find.text('המשימה שלך'), findsOneWidget);
  });

  testWidgets('leaving waits for the server and stays put if it fails',
      (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    await openCreatedRoom(tester, api);

    api.channel.errors['room.leave'] = 'network_error';
    await tester.tap(find.byType(BackButton).last);
    await settle(tester);
    expect(find.byType(LiveRoomScreen), findsOneWidget);
    expect(
        find.text('אין חיבור לשרת. בדקו את החיבור ונסו שוב.'), findsOneWidget);

    api.channel.errors.remove('room.leave');
    await tester.tap(find.byType(BackButton).last);
    await settle(tester);
    expect(api.channel.commands('room.leave'), hasLength(2));
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('a runoff starts without the earlier vote selection',
      (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    await openCreatedRoom(tester, api);
    api.channel.event('session.state', {
      'playerId': 'p_me',
      'activity': 'game',
      'roomId': 'r_1',
      'gameId': 'g_1',
    });
    api.channel.snapshot('game.state', 'game',
        gameJson(phase: 'voting', candidates: ['p_me', 'p_2', 'p_3', 'p_4']));
    await settle(tester);
    await tapLive(tester, 'נועה');
    expect(isEnabled(tester, 'אישור הצבעה'), isTrue);

    api.channel.snapshot('game.state', 'game',
        gameJson(phase: 'runoff_voting', candidates: ['p_2', 'p_3']));
    await settle(tester);
    expect(find.text('תיקו נוסף מעניק ניצחון למתחזה'), findsOneWidget);
    expect(isEnabled(tester, 'אישור הצבעה'), isFalse);
  });
}
