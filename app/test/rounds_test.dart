import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/widgets/game_ui.dart';

import 'support/fake_server.dart';
import 'support/helpers.dart';

/// The board in a later round, with one player already voted out.
Map<String, dynamic> laterRound({
  required String phase,
  String me = 'active',
  String? turn,
  List<String> candidates = const [],
}) =>
    gameJson(
      phase: phase,
      round: 3,
      turn: turn,
      candidates: candidates,
      players: [
        player('p_me', 'דור', status: me),
        player('p_2', 'נועה'),
        player('p_3', 'יובל', status: 'eliminated'),
        player('p_4', 'מאיה'),
      ],
      hints: [
        {
          'playerId': 'p_3',
          'text': 'חדק',
          'round': 1,
          'missing': false,
          'reactions': <String, int>{}
        },
        {
          'playerId': 'p_2',
          'text': 'אפריקה',
          'round': 2,
          'missing': false,
          'reactions': <String, int>{}
        },
      ],
    );

void main() {
  testWidgets('a later round says which round it is', (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    await openCreatedRoom(tester, api);
    api.channel.event('session.state', {
      'playerId': 'p_me',
      'activity': 'game',
      'roomId': 'r_1',
      'gameId': 'g_1'
    });
    api.channel.snapshot(
        'game.state', 'game', laterRound(phase: 'hints', turn: 'p_2'));
    await settle(tester);

    // The round, and how far its turn has got, sit above the board. Only the
    // three players still in it are counted.
    expect(find.text('סיבוב 3 · תור 1 מתוך 3'), findsOneWidget);
    expect(find.text('כותב/ת רמז…'), findsOneWidget);
    expect(find.text('הודח/ה · צופה'), findsOneWidget);

    // Earlier rounds are not spread over the board any more: each is kept
    // under the player who said it, by round.
    expect(find.text('חדק'), findsNothing);
    await tester.tap(find.text('יובל'));
    await settle(tester);
    expect(find.text('הרמזים של יובל'), findsOneWidget);
    expect(find.text('סיבוב 1'), findsOneWidget);
    expect(find.text('חדק'), findsOneWidget);
  });

  testWidgets('a first round is not divided into rounds', (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
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
        gameJson(
          phase: 'hints',
          turn: 'p_2',
          hints: [
            {
              'playerId': 'p_3',
              'text': 'חדק',
              'round': 1,
              'missing': false,
              'reactions': <String, int>{}
            },
          ],
        ));
    await settle(tester);

    // One round in, the header still counts the turn, over all four players.
    expect(find.text('סיבוב 1 · תור 2 מתוך 4'), findsOneWidget);
    expect(find.text('סבב 1'), findsNothing);
  });

  testWidgets('a player who was voted out watches and cannot write',
      (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    await openCreatedRoom(tester, api);
    api.channel.event('session.state', {
      'playerId': 'p_me',
      'activity': 'game',
      'roomId': 'r_1',
      'gameId': 'g_1'
    });
    // Their own turn would have come round, and it does not.
    api.channel.snapshot('game.state', 'game',
        laterRound(phase: 'hints', me: 'eliminated', turn: 'p_me'));
    await settle(tester);

    expect(find.byType(SpectatorNote), findsOneWidget);
    expect(find.text('הודחתם מהמשחק'), findsOneWidget);
    expect(find.text('שליחת רמז'), findsNothing);
    expect(find.text('התור שלכם'), findsNothing);
  });

  testWidgets('a player who was voted out cannot vote', (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
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
        laterRound(
          phase: 'voting',
          me: 'eliminated',
          candidates: ['p_2', 'p_4'],
        ));
    await settle(tester);

    expect(find.byType(SpectatorNote), findsOneWidget);
    expect(find.text('אישור הצבעה'), findsNothing);
    // Tapping a candidate selects nothing, because the row is not enabled.
    await tester.tap(find.text('נועה').first);
    await settle(tester);
    expect(api.channel.commands('game.vote'), isEmpty);
  });

  testWidgets('a player still in the round votes as before', (tester) async {
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
        laterRound(phase: 'voting', candidates: ['p_2', 'p_4']));
    await settle(tester);

    expect(find.byType(SpectatorNote), findsNothing);
    expect(find.text('אישור הצבעה'), findsOneWidget);
    await tapLive(tester, 'נועה');
    await tapLive(tester, 'אישור הצבעה');
    expect(api.channel.commands('game.vote').single['payload'],
        {'gameId': 'g_1', 'targetPlayerId': 'p_2'});
  });

  testWidgets('a card carries the newest clue, the rest opens from it',
      (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    await openCreatedRoom(tester, api);
    api.channel.event('session.state', {
      'playerId': 'p_me',
      'activity': 'game',
      'roomId': 'r_1',
      'gameId': 'g_1'
    });
    api.channel.snapshot(
        'game.state', 'game', laterRound(phase: 'hints', turn: 'p_4'));
    await settle(tester);

    // נועה last said אפריקה, in the round before this one, and that is what
    // her card carries — nobody has to read down a board to find it.
    expect(find.text('רמז קודם: אפריקה'), findsOneWidget);

    // Her history opens from her card and names the round of each clue.
    await tester.tap(find.text('נועה'));
    await settle(tester);
    expect(find.text('רמז אחד · סיבוב 2'), findsOneWidget);
    expect(find.text('אפריקה'), findsOneWidget);
  });

  testWidgets('the vote shows everything each player has said', (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
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
        gameJson(
          phase: 'voting',
          round: 3,
          candidates: ['p_2', 'p_4'],
          hints: [
            {
              'playerId': 'p_2',
              'text': 'אפור',
              'round': 1,
              'missing': false,
              'reactions': <String, int>{}
            },
            {
              'playerId': 'p_4',
              'text': 'גדול',
              'round': 1,
              'missing': false,
              'reactions': <String, int>{}
            },
            {
              'playerId': 'p_2',
              'text': 'חדק',
              'round': 2,
              'missing': false,
              'reactions': <String, int>{}
            },
          ],
        ));
    await settle(tester);

    // Both of p_2's rounds are on their card, not only the latest.
    expect(find.text('אפור · חדק'), findsOneWidget);
    expect(find.text('גדול'), findsOneWidget);
  });

  testWidgets('a match called off is not recorded as a win or a loss',
      (tester) async {
    final api = FakeApi();
    final session = await startAtHome(tester, api);
    await openCreatedRoom(tester, api);
    final wins = session.wins;
    final losses = session.losses;

    api.channel.event('session.state', {
      'playerId': 'p_me',
      'activity': 'game',
      'roomId': 'r_1',
      'gameId': 'g_1'
    });
    api.channel.snapshot(
        'game.state',
        'game',
        gameJson(
          phase: 'ended',
          round: 3,
          result: {
            'winner': null,
            'reason': 'abandoned',
            'impostorPlayerId': 'p_4',
            'secretWord': 'פיל',
            'voteRounds': <Map<String, String>>[],
            'abstentions': <int>[],
            'outcomes': {
              'p_me': 'none',
              'p_2': 'none',
              'p_3': 'none',
              'p_4': 'none',
            },
          },
        ));
    await settle(tester);

    expect(find.text('המשחק בוטל'), findsOneWidget);
    expect(find.textContaining('בלי אף הצבעה'), findsOneWidget);
    // Neither banner, and nothing added to the profile.
    expect(find.text('נרשם לכם ניצחון'), findsNothing);
    expect(find.text('נרשם לכם הפסד'), findsNothing);
    expect(session.wins, wins);
    expect(session.losses, losses);
  });
}
