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

    expect(find.byType(RoundBadge), findsOneWidget);
    expect(find.text('סבב 3'), findsOneWidget);
    // Hints from earlier rounds are still on the board.
    expect(find.text('חדק'), findsWidgets);
    expect(find.text('אפריקה'), findsWidgets);
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
