import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/data/server.dart';
import 'package:imposter_il/screens/home_screen.dart';
import 'package:imposter_il/widgets/game_ui.dart';
import 'package:imposter_il/screens/live_room.dart';
import 'package:imposter_il/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_server.dart';
import 'support/helpers.dart';

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
    await tapText(tester, 'משחק ברשת');
    await tester.enterText(find.byType(TextField), 'דור');
    await tapText(tester, 'ממשיכים');
    expect(
        find.text('אין חיבור לשרת. בדקו את החיבור ונסו שוב.'), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('create a room with server categories, manage the lobby',
      (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    api.responses['POST /v1/rooms'] = {'room': roomJson()};
    await openPrivateRoom(tester);
    await tapText(tester, 'יצירת חדר');

    // Categories come from the server. "הכול" is the default; tapping one
    // leaves it and picks just that one.
    expect(find.text('חפצים'), findsOneWidget);
    await tapText(tester, 'חפצים');
    await tapText(tester, '30 שניות');
    await tapLive(tester, 'יצירת חדר');

    final (_, _, body) = api.requests.firstWhere((r) => r.$2 == '/v1/rooms');
    expect(body, {
      'maxPlayers': 8,
      'hintSeconds': 30,
      'categoryIds': ['objects'],
    });
    expect(find.text('482 913'), findsOneWidget); // grouped in the lobby
    expect(
      find.ancestor(
        of: find.text('482 913'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Directionality &&
              widget.textDirection == TextDirection.ltr,
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('מנהל החדר · אתם'), findsOneWidget);
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
    expect(
      find.text('אי אפשר להתחיל משחק כרגע. נסו שוב בעוד רגע.'),
      findsOneWidget,
    );
  });

  testWidgets('join errors are shown inline; a joiner cannot start',
      (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    await openPrivateRoom(tester);
    await tapText(tester, 'הצטרפות לחדר');

    api.responses['POST /v1/rooms/join'] =
        const ApiException('room_not_found', 404);
    final codeField = tester.widget<TextField>(find.byType(TextField));
    expect(codeField.readOnly, isTrue);
    expect(codeField.canRequestFocus, isFalse);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
    for (var i = 0; i < 6; i++) {
      await tapText(tester, '1');
    }
    await tapText(tester, 'הצטרפות');
    expect(
      find.text('החדר לא נמצא או שאינו זמין. בדקו את הקוד עם מי שפתח את החדר.'),
      findsOneWidget,
    );

    api.responses['POST /v1/rooms/join'] = {
      'room': roomJson(host: 'p_2', players: [
        player('p_2', 'נועה'),
        player('p_me', 'דור'),
      ]),
    };
    // The code can be typed on the screen's own keypad.
    for (var i = 0; i < 6; i++) {
      await tapText(tester, 'מחיקה');
    }
    for (final digit in ['4', '8', '2', '9', '1', '9']) {
      await tapText(tester, digit);
    }
    final keypad = find.byType(GridView);
    expect(
      tester
          .getCenter(find.descendant(of: keypad, matching: find.text('1')))
          .dx,
      lessThan(tester
          .getCenter(find.descendant(of: keypad, matching: find.text('3')))
          .dx),
    );
    final codeController =
        tester.widget<TextField>(find.byType(TextField)).controller!;
    expect(codeController.selection.baseOffset, 6);
    expect(isEnabled(tester, 'הצטרפות'), isTrue);
    await tapText(tester, 'מחיקה');
    expect(isEnabled(tester, 'הצטרפות'), isFalse); // five digits is not a code
    await tapText(tester, '3');
    await tapText(tester, '7'); // a seventh digit is ignored
    await tester.pump(); // typing clears the error and restores the label
    await tapLive(tester, 'הצטרפות');
    expect(api.requests.last.$3, {'code': '482913'});
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
    expect(find.text('את/ה אזרח/ית'), findsOneWidget);
    expect(find.text('המילה הסודית'), findsOneWidget);
    expect(find.text('פיל'), findsOneWidget);
    await tapLive(tester, 'הבנתי');
    expect(channel.commands('game.confirmRole').single['payload'],
        {'gameId': 'g_1'});

    // My turn: a blocked hint shows the server's reason under the field.
    channel.snapshot(
        'game.state', 'game', gameJson(phase: 'hints', turn: 'p_me'));
    await settle(tester);
    expect(_clueField, findsOneWidget);
    channel.errors['game.submitHint'] = 'hint_contains_secret';
    await tester.enterText(find.byType(TextField), 'הפיל');
    await tapLive(tester, 'שליחה');
    expect(
      find.text('הרמז מכיל את המילה הסודית. בחרו מילה אחרת. הרמז לא נשלח.'),
      findsOneWidget,
    );
    channel.errors.remove('game.submitHint');
    await tester.enterText(find.byType(TextField), 'חדק');
    await tester.pump();
    expect(
      find.ancestor(
        of: find.text('3/25'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Directionality &&
              widget.textDirection == TextDirection.ltr,
        ),
      ),
      findsOneWidget,
    );
    await tapLive(tester, 'שליחה');
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
    expect(find.text('כותב/ת רמז'), findsOneWidget);
    // My own card leads with my clue, and counts them underneath.
    expect(find.text('חדק'), findsOneWidget);
    expect(find.text('1 רמז'), findsOneWidget);
    final chip = tester.getCenter(find.text('😂'));
    await tapLive(tester, 'זה מחשיד');
    expect(channel.commands('game.react').single['payload'],
        {'gameId': 'g_1', 'hintIndex': 0, 'reactionId': 'suspicious'});

    // The bubble popped on touch, without waiting for the server: the chip in
    // the dock, and the bubble now rising from my own card.
    expect(find.text('זה מחשיד'), findsNWidgets(2));

    // The count coming back in the snapshot must not float a second one.
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
              'reactions': {'laugh': 3, 'suspicious': 1}
            },
          ],
        ));
    await tester.pump();
    await tester.pump();
    expect(find.text('זה מחשיד'), findsNWidgets(2));

    // Someone else's reaction rises from their own card, which is the only
    // thing that names who sent it.
    channel.event('game.reaction', {
      'gameId': 'g_1',
      'hintIndex': 0,
      'reactionId': 'laugh',
      'playerId': 'p_2',
    });
    await tester.pump();
    await tester.pump();
    expect(find.text('😂'), findsNWidgets(2));
    final card = tester.getRect(
      find
          .ancestor(of: find.text('נועה'), matching: find.byType(InkWell))
          .first,
    );
    final bubble = [
      for (var i = 0; i < 2; i++) tester.getCenter(find.text('😂').at(i)),
    ].firstWhere((spot) => spot != chip);
    expect(bubble.dx, greaterThanOrEqualTo(card.left));
    expect(bubble.dx, lessThanOrEqualTo(card.right));

    // Both clear themselves up on the way off the top.
    await tester.pump(const Duration(seconds: 7));
    await tester.pump();
    expect(find.text('זה מחשיד'), findsOneWidget);
    expect(find.text('😂'), findsOneWidget);

    // A stale snapshot is ignored.
    channel.snapshot('game.state', 'game', gameJson(phase: 'role_reveal'),
        version: 1);
    await settle(tester);
    expect(find.text('כותב/ת רמז'), findsOneWidget);

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
            {'p_me': 'p_3', 'p_2': 'p_3', 'p_4': 'p_3'},
          ],
          'abstentions': [1],
          'outcomes': {'p_me': 'loss', 'p_3': 'win'},
        }));
    await settle(tester);
    expect(find.text('המתחזה ניצח!'), findsOneWidget);
    expect(
      find.text('המתחזה נתפס, אבל הצליח לנחש את המילה.'),
      findsOneWidget,
    );
    expect(find.text('נרשם לכם הפסד'), findsOneWidget);
    // The vote breakdown: three votes for the impostor and one abstention.
    expect(find.text('חלוקת הקולות'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('נמנעו'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    await tapLive(tester, 'משחק נוסף');
    expect(channel.commands('game.playAgain'), hasLength(1));
    channel.event('session.state',
        {'playerId': 'p_me', 'activity': 'room', 'roomId': 'r_1'});
    await settle(tester);
    expect(find.text('482 913'), findsOneWidget); // grouped in the lobby
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

    // Leaving is a loss, so it asks first; staying sends nothing.
    await tester.tap(find.byTooltip('יציאה'));
    await settle(tester);
    await tester.tap(find.text('המשך משחק'));
    await settle(tester);
    expect(api.channel.commands('game.leave'), isEmpty);
    expect(find.byType(HomeScreen), findsNothing);

    await tester.tap(find.byTooltip('יציאה'));
    await settle(tester);
    await confirmLeave(tester);
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
    expect(find.text('מנהל החדר הסיר אתכם מהחדר.'), findsOneWidget);

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
    expect(find.text('נרשם לכם הפסד'), findsOneWidget);
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

  testWidgets('a third disconnect outside the player turn uses accurate copy',
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
    api.channel.snapshot(
      'game.state',
      'game',
      gameJson(
        phase: 'voting',
        candidates: ['p_me', 'p_2', 'p_3', 'p_4'],
        players: [
          player('p_me', 'דור', disconnects: 2),
          player('p_2', 'נועה'),
          player('p_3', 'יובל'),
          player('p_4', 'מאיה'),
        ],
      ),
    );
    await settle(tester);

    api.connectError = Exception('down');
    await api.channel.close();
    await settle(tester);

    expect(find.textContaining('החיבור אבד.'), findsOneWidget);
    expect(find.textContaining('החיבור אבד בזמן התור'), findsNothing);
    expect(find.textContaining('תור מלא מחדש'), findsNothing);
    expect(find.textContaining('תוצאו מהמשחק'), findsOneWidget);

    api.connectError = null;
    await tester.pump(const Duration(milliseconds: 100));
    await settle(tester);
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

    expect(find.text('לא נרשם לכם הפסד'), findsOneWidget);
    await tapLive(tester, 'חזרה למסך הבית');
    expect(find.byType(HomeScreen), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('session.token'), 'token-2');
  });

  testWidgets('game.aborted from the server shows screen 29 without a loss',
      (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    await openCreatedRoom(tester, api);

    api.channel.event('game.aborted', {
      'gameId': 'g_1',
      'reason': 'server_error',
      'lossRecorded': false,
    });
    api.channel
        .event('session.state', {'playerId': 'p_me', 'activity': 'none'});
    await settle(tester);

    expect(find.text('לא נרשם לכם הפסד'), findsOneWidget);
  });

  testWidgets('connected from another device: this one becomes a new guest',
      (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    api.responses['POST /v1/sessions'] = {
      'playerId': 'p_new',
      'sessionToken': 'token-2',
    };

    await api.channel.closeReplaced();
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('לא נרשם לכם הפסד'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('session.token'), 'token-2');
    expect(prefs.getString('session.nickname'), 'דור');
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
    expect(find.text('את/ה אזרח/ית'), findsOneWidget);
  });

  testWidgets('leaving waits for the server and stays put if it fails',
      (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    await openCreatedRoom(tester, api);

    api.channel.errors['room.leave'] = 'network_error';
    await tester.tap(find.byTooltip('יציאה'));
    await settle(tester);
    expect(find.byType(LiveRoomScreen), findsOneWidget);
    expect(
        find.text('אין חיבור לשרת. בדקו את החיבור ונסו שוב.'), findsOneWidget);

    api.channel.errors.remove('room.leave');
    await tester.tap(find.byTooltip('יציאה'));
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

    // My own row is shown, and says why it cannot be picked.
    expect(find.text('אי אפשר להצביע לעצמכם'), findsOneWidget);

    api.channel.snapshot(
        'game.state',
        'game',
        gameJson(
          phase: 'runoff_voting',
          candidates: ['p_2', 'p_3'],
          previousVotes: {'p_2': 2, 'p_3': 2},
        ));
    await settle(tester);
    expect(find.textContaining('תיקו נוסף — איש לא מודח'), findsOneWidget);
    expect(isEnabled(tester, 'אישור הצבעה'), isFalse);
    // The tie that led here.
    expect(find.text('2 קולות בסבב הקודם'), findsNWidgets(2));

    // A 1-1 tie is the commonest runoff in a four-player game, so the
    // singular is the default case rather than an edge one.
    api.channel.snapshot(
        'game.state',
        'game',
        gameJson(
          phase: 'runoff_voting',
          candidates: ['p_2', 'p_3'],
          previousVotes: {'p_2': 1, 'p_3': 1},
        ));
    await settle(tester);
    expect(find.text('קול אחד בסבב הקודם'), findsNWidgets(2));
    expect(find.text('1 קולות בסבב הקודם'), findsNothing);
  });

  testWidgets('reporting a hint sends it and hides that player',
      (tester) async {
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
    channel.snapshot(
        'game.state',
        'game',
        gameJson(
          phase: 'hints',
          turn: 'p_3',
          hints: [
            {
              'playerId': 'p_2',
              'text': 'גסות',
              'missing': false,
              'reactions': <String, dynamic>{}
            },
          ],
        ));
    await settle(tester);
    // The clue sits on its author's card, as the card's headline.
    expect(find.text('גסות'), findsOneWidget);
    expect(find.text('1 רמז'), findsOneWidget);

    // Reporting hangs off the clue history, opened from that player's card:
    // a visible button, not a hidden gesture.
    await tester.tap(find.text('נועה'));
    await settle(tester);
    expect(find.text('הרמזים של נועה'), findsOneWidget);
    expect(find.text('גסות'), findsNWidgets(2)); // the card and the sheet
    await tester.tap(find.byTooltip('דיווח על הרמז'));
    await settle(tester);
    await tapLive(tester, 'דיווח');
    await settle(tester);

    expect(channel.commands('game.report').single['payload'],
        {'gameId': 'g_1', 'playerId': 'p_2', 'hintIndex': 0});
    // The hint is hidden on this device, and cannot be reported twice.
    // Hidden in the open sheet and on the card behind it.
    expect(find.text('גסות'), findsNothing);
    expect(find.text('הוסתר'), findsNWidgets(2));
    expect(find.byTooltip('דיווח על הרמז'), findsNothing);
    // The player is told what happens to the report.
    expect(
      find.text(
          'תודה, הדיווח התקבל ויטופל. הרמזים של השחקן יוסתרו במכשיר שלכם.'),
      findsOneWidget,
    );
  });

  testWidgets('a clue the server hid for the table shows as hidden',
      (tester) async {
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
    // Two other players reported p_2; this device reported nobody.
    final hints = [
      {
        'playerId': 'p_2',
        'text': '',
        'hidden': true,
        'missing': false,
        'reactions': <String, dynamic>{}
      },
      {
        'playerId': 'p_3',
        'text': 'חדק',
        'missing': false,
        'reactions': <String, dynamic>{}
      },
    ];
    channel.snapshot('game.state', 'game',
        gameJson(phase: 'hints', turn: 'p_4', hints: hints));
    await settle(tester);
    expect(find.text('הוסתר'), findsOneWidget);
    expect(find.text('חדק'), findsOneWidget);

    // The vote weighs what was said, and a hidden player said nothing shown.
    channel.snapshot(
        'game.state',
        'game',
        gameJson(
            phase: 'voting', hints: hints, candidates: ['p_2', 'p_3', 'p_4']));
    await settle(tester);
    expect(find.text('הוסתר'), findsOneWidget);
    expect(find.text('חדק'), findsOneWidget);
  });

  testWidgets('the board is held before voting opens', (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    await openCreatedRoom(tester, api);
    final channel = api.channel;

    channel.event('session.state', {
      'playerId': 'p_me',
      'activity': 'game',
      'roomId': 'r_1',
      'gameId': 'g_1',
    });
    channel.snapshot('game.state', 'game', gameJson(phase: 'pre_voting'));
    await settle(tester);

    expect(find.text('עוברים להצבעה'), findsOneWidget);
    expect(find.text('כל הרמזים נשלחו'), findsOneWidget);
    expect(find.text('מסך ההצבעה נפתח אוטומטית'), findsOneWidget);
    // Nothing to vote on yet.
    expect(find.text('אישור הצבעה'), findsNothing);

    // The server opens the vote; the app follows.
    channel.snapshot('game.state', 'game',
        gameJson(phase: 'voting', candidates: ['p_me', 'p_2', 'p_3', 'p_4']));
    await settle(tester);
    expect(find.text('עוברים להצבעה'), findsNothing);
    expect(find.text('אישור הצבעה'), findsWidgets);
  });

  testWidgets('a card is the same size with a clue and without one',
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
    // נועה is writing, so her card has no clue to lead with; יובל already has
    // one. The two sit side by side and must not be different heights.
    api.channel.snapshot(
        'game.state',
        'game',
        gameJson(phase: 'hints', turn: 'p_2', hints: [
          {
            'playerId': 'p_3',
            'text': 'חדק',
            'missing': false,
            'reactions': <String, dynamic>{}
          },
        ]));
    await settle(tester);

    double card(String nickname) => tester
        .getRect(
          find
              .ancestor(of: find.text(nickname), matching: find.byType(InkWell))
              .first,
        )
        .height;
    expect(card('נועה'), card('יובל'));
  });

  testWidgets('a server that still holds a hint shows the board, not a spinner',
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
    // This engine no longer sends hint_break, but a server that has not been
    // deployed yet does, and an unknown phase would fall through to the result
    // screen, which has no result to draw.
    api.channel.snapshot(
        'game.state',
        'game',
        gameJson(phase: 'hint_break', hints: [
          {
            'playerId': 'p_2',
            'text': 'גבינה',
            'missing': false,
            'reactions': <String, dynamic>{}
          },
        ]));
    await settle(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('הרמזים בסיבוב'), findsOneWidget);
    expect(find.text('גבינה'), findsOneWidget);
  });

  testWidgets('a hint lands on its card and the turn passes on at once',
      (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    await openCreatedRoom(tester, api);
    final channel = api.channel;

    channel.event('session.state', {
      'playerId': 'p_me',
      'activity': 'game',
      'roomId': 'r_1',
      'gameId': 'g_1',
    });
    channel.snapshot(
        'game.state', 'game', gameJson(phase: 'hints', turn: 'p_2'));
    await settle(tester);
    expect(find.text('כותב/ת רמז'), findsOneWidget);

    // נועה's hint lands and the turn passes to me in the same snapshot: there
    // is no beat in between, because her hint stays on her own card.
    channel.snapshot(
        'game.state',
        'game',
        gameJson(phase: 'hints', turn: 'p_me', hints: [
          {
            'playerId': 'p_2',
            'text': 'גבינה',
            'missing': false,
            'reactions': <String, dynamic>{}
          },
        ]));
    await settle(tester);
    expect(_clueField, findsOneWidget);
    expect(find.text('גבינה'), findsOneWidget);
    // My own card is the active one now (C02), so it says so too.
    expect(find.text('כותב/ת רמז'), findsOneWidget);
    // One clock, in the header.
    expect(find.byType(TimerBadge), findsOneWidget);
    // The keyboard waits to be asked for.
    expect(tester.widget<TextField>(find.byType(TextField)).autofocus, isFalse);

    // The pre-vote screen does not repeat the clue: the hold already showed
    // it, and this screen is about the vote that is opening.
    channel.snapshot(
        'game.state',
        'game',
        gameJson(phase: 'pre_voting', hints: [
          {
            'playerId': 'p_2',
            'text': 'גבינה',
            'missing': false,
            'reactions': <String, dynamic>{}
          },
        ]));
    await settle(tester);
    expect(find.text('עוברים להצבעה'), findsOneWidget);
    expect(_clueField, findsNothing);
  });
}

/// The clue field, by the accessible label that replaced its visible one.
final _clueField = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics && widget.properties.label == 'הרמז שלך · מילה אחת',
);
