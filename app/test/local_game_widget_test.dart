import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/data/server.dart';
import 'package:imposter_il/local/local_game.dart';
import 'package:imposter_il/local/local_screens.dart';
import 'package:imposter_il/local/local_setup_screens.dart';
import 'package:imposter_il/local/local_store.dart';
import 'package:imposter_il/models/player.dart';
import 'package:imposter_il/screens/home_screen.dart';
import 'package:imposter_il/theme/app_theme.dart';
import 'package:imposter_il/widgets/game_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_server.dart';
import 'support/helpers.dart';

LocalGame _game({int players = 4, int? hintSeconds = 30}) => LocalGame(
      players: [
        for (var i = 0; i < players; i++)
          LocalPlayer(
            name: 'שחקן ${i + 1}',
            avatar: avatarAssets[i],
          ),
      ],
      categoryIds: const ['food'],
      hintSeconds: hintSeconds,
      rng: Random(7),
    );

void _toVote(LocalGame game) {
  while (game.phase == LocalPhase.roleReveal) {
    game.reveal();
    game.roleSeen(game.currentPlayer);
  }
  game.startRound();
  while (game.phase == LocalPhase.hints) {
    game.hintSpoken(game.currentPlayer);
  }
  game.startVoting();
}

void _voteFor(LocalGame game, int target) {
  final voters = game.activePlayers.length;
  for (var i = 0; i < voters; i++) {
    final voter = game.currentPlayer;
    game.castVote(
      voter == target ? game.candidatesFor(voter).first : target,
    );
  }
}

Future<void> _pumpGame(WidgetTester tester, LocalGame game) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      theme: AppTheme.dark,
      home: LocalGameScreen(resumed: game),
    ),
  );
  await tester.pump();
}

void main() {
  test('an unreadable local snapshot is removed', () async {
    SharedPreferences.setMockInitialValues({
      'local.game': jsonEncode({'phase': 'from-a-future-build'}),
    });

    expect(await LocalStore.load(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('local.game'), isFalse);
  });

  testWidgets('a fresh offline install can start a local game', (tester) async {
    final api = FakeApi()
      ..responses['POST /v1/sessions'] = const ApiException('network_error');
    await startApp(tester, api);

    expect(find.byType(HomeScreen), findsOneWidget);
    await tapText(tester, 'משחק במכשיר אחד');
    await tapText(tester, 'המשך להגדרות');
    await tapText(tester, 'מתחילים');

    expect(find.byType(LocalGameScreen), findsOneWidget);
    expect(
        api.requests.where((request) => request.$2 == '/v1/sessions'), isEmpty);
  });

  testWidgets('the private ballot shows the voter but never enables self-vote',
      (tester) async {
    final game = _game();
    _toVote(game);
    game.reveal();
    await _pumpGame(tester, game);

    expect(find.text(game.players[game.currentPlayer].name), findsWidgets);
    expect(find.text('אי אפשר להצביע לעצמכם'), findsOneWidget);
    final selfCard = find.ancestor(
      of: find.text('אי אפשר להצביע לעצמכם'),
      matching: find.byType(PlayerCard),
    );
    expect(tester.widget<PlayerCard>(selfCard).enabled, isFalse);
  });

  testWidgets('a complete private local flow reaches results at 320px',
      (tester) async {
    final game = _game(players: 3, hintSeconds: null);
    await _pumpGame(tester, game);

    while (game.phase == LocalPhase.roleReveal) {
      final player = game.players[game.currentPlayer];
      await tapText(tester, 'אני ${player.name} — הציגו לי');
      await tapText(tester, 'הבנתי — הסתירו');
    }
    await tapText(tester, 'מתחילים סיבוב 1');
    while (game.phase == LocalPhase.hints) {
      await tapText(tester, 'הרמז נאמר');
    }
    await seconds(tester, LocalGame.voteTransitionSeconds);
    expect(game.phase, LocalPhase.voting);

    while (game.phase == LocalPhase.voting) {
      final voter = game.currentPlayer;
      await tapText(
        tester,
        'אני ${game.players[voter].name} — להצבעה',
      );
      final target = voter == game.impostor
          ? game.activePlayers.firstWhere((seat) => seat != voter)
          : game.impostor;
      await tester.tap(
        find.widgetWithText(PlayerCard, game.players[target].name),
      );
      await tester.pump();
      await tapText(tester, 'אישור הצבעה');
      await tapText(tester, 'הסתרתי — לשחקן הבא');
    }

    expect(game.phase, LocalPhase.guess);
    await tapText(
      tester,
      'אני ${game.players[game.impostor].name} — הציגו לי',
    );
    await tester.enterText(find.byType(TextField), 'תשובה שגויה');
    await tapText(tester, 'שליחת ניחוש');
    expect(find.text('האזרחים ניצחו!'), findsOneWidget);
  });

  testWidgets('leaving a private phase covers its content before the dialog',
      (tester) async {
    Future<void> expectCovered(LocalGame game, Finder privateContent) async {
      await _pumpGame(tester, game);
      expect(privateContent, findsWidgets);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('לצאת מהמשחק?'), findsOneWidget);
      expect(privateContent, findsNothing);
      expect(game.revealed, isFalse);

      await tapText(tester, 'המשך משחק');
      expect(find.textContaining('העבירו את המכשיר ל'), findsOneWidget);
    }

    final role = _game();
    while (role.currentPlayer == role.impostor) {
      role.reveal();
      role.roleSeen(role.currentPlayer);
    }
    role.reveal();
    await expectCovered(role, find.text(role.secretWord));

    final ballot = _game();
    _toVote(ballot);
    ballot.reveal();
    await expectCovered(ballot, find.text('אישור הצבעה'));

    final guess = _game();
    _toVote(guess);
    _voteFor(guess, guess.impostor);
    guess.reveal();
    await expectCovered(guess, find.byType(TextField));
  });

  // Online, a tie reaches every player on their own screen at once. With one
  // phone the table needs a moment of its own, or the first anybody hears of
  // it is the header on a ballot they are already holding.
  testWidgets('a tie is announced to the table before the phone goes round',
      (tester) async {
    final game = _game();
    _toVote(game);
    final order = game.activePlayers;
    game.castVote(order[1]);
    game.castVote(order[0]);
    game.castVote(order[1]);
    game.castVote(order[0]);
    expect(game.phase, LocalPhase.tie);
    await _pumpGame(tester, game);

    expect(find.text('יש תיקו'), findsOneWidget);
    expect(find.textContaining('היה תיקו.'), findsOneWidget);
    expect(find.text('2 מועמדים קיבלו 2 קולות'), findsOneWidget);
    // Both tied players are named, and nobody has been asked to vote yet.
    for (final i in game.runoffCandidates) {
      expect(find.text(game.players[i].name), findsOneWidget);
    }
    expect(find.textContaining('העבירו את המכשיר'), findsNothing);

    await tapText(tester, 'מתחילים הצבעה חוזרת');
    expect(game.phase, LocalPhase.runoff);
  });

  testWidgets('a second tie tells the next round nobody went', (tester) async {
    final game = _game();
    _toVote(game);
    final order = game.activePlayers;
    for (var i = 0; i < 2; i++) {
      game.castVote(order[1]);
      game.castVote(order[0]);
      game.castVote(order[1]);
      game.castVote(order[0]);
      if (game.phase == LocalPhase.tie) game.startRunoff();
    }
    expect(game.phase, LocalPhase.ready);
    await _pumpGame(tester, game);

    expect(find.textContaining('אף אחד לא הודח'), findsOneWidget);
  });

  testWidgets('a runoff self-card keeps its previous vote count',
      (tester) async {
    final game = _game();
    _toVote(game);
    final order = game.activePlayers;
    game.castVote(order[1]);
    game.castVote(order[0]);
    game.castVote(order[1]);
    game.castVote(order[0]);
    // Past the tie announcement, which the table reads before voting again.
    game.startRunoff();
    game.reveal();
    await _pumpGame(tester, game);

    final self = game.currentPlayer;
    final card = find.byWidgetPredicate(
      (widget) =>
          widget is PlayerCard &&
          widget.player.nickname == game.players[self].name,
    );
    final selfCard = tester.widget<PlayerCard>(card);
    expect(selfCard.note, '${game.previousVotes[self]} קולות בסבב הקודם');
    expect(selfCard.secondaryNote, 'אי אפשר להצביע לעצמכם');
    expect(selfCard.enabled, isFalse);
  });

  testWidgets('home offers a saved game and resumes behind the privacy screen',
      (tester) async {
    final game = _game()..reveal();
    await startApp(tester, FakeApi(), saved: {
      'session.token': 'token-1',
      'session.playerId': 'p_me',
      'session.nickname': 'דור',
      'session.avatarId': 'avatar-m04-detective-hat',
      'local.game': jsonEncode(game.toJson()),
    });

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('להמשיך את המשחק?'), findsOneWidget);
    expect(find.text(game.secretWord), findsNothing);
    await tapText(tester, 'המשך משחק');

    expect(find.byType(LocalGameScreen), findsOneWidget);
    expect(find.text(game.secretWord), findsNothing);
    expect(find.text('העבירו את המכשיר לשחקן 1'), findsOneWidget);
  });

  testWidgets('local result leaves online wins and losses unchanged',
      (tester) async {
    final api = FakeApi();
    final session = await startApp(tester, api, saved: {
      'session.token': 'token-1',
      'session.playerId': 'p_me',
      'session.nickname': 'דור',
      'session.avatarId': 'avatar-m04-detective-hat',
      'stats.wins': 7,
      'stats.losses': 4,
    });
    final game = _game();
    _toVote(game);
    _voteFor(game, game.impostor);
    await open(tester, LocalGameScreen(resumed: game));

    await tapText(
      tester,
      'אני ${game.players[game.impostor].name} — הציגו לי',
    );
    await tester.enterText(find.byType(TextField), 'תשובה שגויה');
    await tapText(tester, 'שליחת ניחוש');

    expect(find.text('האזרחים ניצחו!'), findsOneWidget);
    expect(session.wins, 7);
    expect(session.losses, 4);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('stats.wins'), 7);
    expect(prefs.getInt('stats.losses'), 4);
  });

  testWidgets('server content failure does not block a local game',
      (tester) async {
    final api = FakeApi()
      ..responses['GET /v1/categories'] = const ApiException('network_error');
    await startApp(tester, api, saved: {
      'session.token': 'token-1',
      'session.playerId': 'p_me',
      'session.nickname': 'דור',
      'session.avatarId': 'avatar-m04-detective-hat',
    });
    await tapText(tester, 'משחק במכשיר אחד');
    await tapText(tester, 'המשך להגדרות');
    await tapText(tester, 'מתחילים');

    expect(find.byType(LocalGameScreen), findsOneWidget);
    expect(
      api.requests,
      everyElement(
        predicate<(String, String, Object?)>(
          (request) =>
              request.$1 == 'GET' &&
              (request.$2 == '/v1/categories' || request.$2 == '/v1/reactions'),
        ),
      ),
    );
    expect(api.channels.single.sent, isEmpty);
  });

  testWidgets('duplicate local names are rejected inline', (tester) async {
    await startAtHome(tester);
    await tapText(tester, 'משחק במכשיר אחד');
    await tester.enterText(find.byType(TextField).at(1), 'שחקן 1');
    await tester.pump();

    expect(find.text('לכל שחקן צריך להיות שם שונה'), findsNWidgets(2));
    expect(isEnabled(tester, 'המשך להגדרות'), isFalse);
  });

  testWidgets('local names are visible and summary columns stay aligned',
      (tester) async {
    await startAtHome(tester);
    await tapText(tester, 'משחק במכשיר אחד');

    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.style?.color, AppColors.night);
    }

    await tapText(tester, 'המשך להגדרות');
    for (final label in ['שחקנים', 'קטגוריות', 'זמן לרמז', 'מתחזים', 'הצבעה']) {
      expect(tester.widget<Text>(find.text(label).last).textAlign,
          TextAlign.start);
    }
    for (final value in [
      '4',
      'הכול',
      '30 שניות',
      'מתחזה אחד',
      'הצבעה פרטית במכשיר',
    ]) {
      expect(
          tester.widget<Text>(find.text(value).last).textAlign, TextAlign.end);
    }
  });

  testWidgets(
      'setup supports 12 unique players and disables start with no categories',
      (tester) async {
    await startAtHome(tester);
    await tapText(tester, 'משחק במכשיר אחד');
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byTooltip('עוד שחקנים'));
      await tester.pump();
    }
    expect(find.text('12 שחקנים'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(12));

    await tapText(tester, 'המשך להגדרות');
    expect(find.byType(LocalRulesScreen), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'הכול'));
    await tester.pump();
    expect(isEnabled(tester, 'מתחילים'), isFalse);
  });

  testWidgets('adding players never reuses a customized avatar',
      (tester) async {
    await startAtHome(tester);
    await tapText(tester, 'משחק במכשיר אחד');

    await tester.tap(find.byType(AvatarView).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate(
      (widget) => widget is AvatarView && widget.asset == avatarAssets[4],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('עוד שחקנים'));
    await tester.pump();
    var assigned = [
      for (final widget
          in tester.widgetList<AvatarView>(find.byType(AvatarView)))
        if (widget.size == 44) widget.asset,
    ];
    expect(assigned.toSet(), hasLength(5));

    await tester.tap(find.byTooltip('פחות שחקנים'));
    await tester.pump();
    await tester.tap(find.byTooltip('עוד שחקנים'));
    await tester.pump();
    assigned = [
      for (final widget
          in tester.widgetList<AvatarView>(find.byType(AvatarView)))
        if (widget.size == 44) widget.asset,
    ];
    expect(assigned.toSet(), hasLength(5));
  });
  // The role reveal exists twice — once online and once on one device — and the
  // two drifted: one had the category as a purple pill above the picture, the
  // other as a turquoise line below it and again in the header; one said
  // "אתם אזרחים" and the other "את/ה אזרח/ית"; and only one masked the
  // impostor's word. They share their parts now, and this is what says so.
  group('the role reveal reads the same in both games', () {
    testWidgets('one device', (tester) async {
      final game = _game();
      game.reveal();
      await _pumpGame(tester, game);

      expect(find.byType(CategoryPill), findsOneWidget);
      expect(find.byType(SecretWordCard), findsOneWidget);
      final citizen = game.currentPlayer != game.impostor;
      expect(
        find.text(citizen ? 'את/ה אזרח/ית' : 'את/ה המתחזה'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('online', (tester) async {
      final api = FakeApi();
      await startAtHome(tester, api);
      await openPrivateRoom(tester);
      api.responses['POST /v1/rooms'] = {'room': roomJson()};
      await tapText(tester, 'יצירת חדר');
      await tapLive(tester, 'יצירת חדר');
      api.channel.event('session.state', {
        'playerId': 'p_me',
        'activity': 'game',
        'roomId': 'r_1',
        'gameId': 'g_1',
      });
      api.channel
          .snapshot('game.state', 'game', gameJson(phase: 'role_reveal'));
      await settle(tester);

      expect(find.byType(CategoryPill), findsOneWidget);
      expect(find.byType(SecretWordCard), findsOneWidget);
      expect(find.text('את/ה אזרח/ית'), findsOneWidget);
      // The category is named once, not in the header and again below it.
      expect(find.text('חיות'), findsOneWidget);
    });
  });

  // The beat before the vote was drawn twice too, and drifted the same way:
  // a large dial in the middle online, a small badge in the corner on one
  // device, and headings of different sizes.
  testWidgets('the beat before the vote reads the same in both games',
      (tester) async {
    final game = _game();
    // Every hint spoken, and the beat before the vote opens.
    while (game.phase == LocalPhase.roleReveal) {
      game.reveal();
      game.roleSeen(game.currentPlayer);
    }
    game.startRound();
    while (game.phase == LocalPhase.hints) {
      game.hintSpoken(game.currentPlayer);
    }
    expect(game.phase, LocalPhase.voteTransition);
    await _pumpGame(tester, game);

    expect(find.byType(ToVotingView), findsOneWidget);
    expect(find.text('עוברים להצבעה'), findsOneWidget);
    expect(find.text('כל הרמזים נשלחו'), findsOneWidget);
    expect(find.text('מסך ההצבעה נפתח אוטומטית'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the impostor is shown masked tiles, never the word',
      (tester) async {
    final game = _game();
    // Hand the device round until the impostor is the one holding it.
    while (game.currentPlayer != game.impostor) {
      game.reveal();
      game.roleSeen(game.currentPlayer);
    }
    game.reveal();
    await _pumpGame(tester, game);

    expect(find.byType(SecretWordCard), findsOneWidget);
    expect(find.text(game.secretWord), findsNothing);
    expect(find.text('המילה לא מוצגת לכם — רק הקטגוריה.'), findsOneWidget);
    // And nothing that counts the letters for them: a row of boxes told the
    // impostor how long the word was.
    expect(find.byIcon(Icons.visibility_off_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
