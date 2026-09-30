import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/screens/live_room.dart';
import 'package:imposter_il/screens/secondary_screens.dart';
import 'package:imposter_il/state/game_session.dart';
import 'package:imposter_il/state/sounds.dart';

import 'support/fake_server.dart';
import 'support/helpers.dart';

// docs/decisions.md, "צלילים": which moment plays what.

Map<String, dynamic> _deadlineIn(Map<String, dynamic> game, int seconds) => game
  ..['deadline'] =
      DateTime.now().add(Duration(seconds: seconds)).toUtc().toIso8601String();

Future<FakeChannel> _inGame(WidgetTester tester, FakeApi api) async {
  await startAtHome(tester, api);
  await openCreatedRoom(tester, api);
  api.channel.event('session.state', {
    'playerId': 'p_me',
    'activity': 'game',
    'roomId': 'r_1',
    'gameId': 'g_1',
  });
  return api.channel;
}

void main() {
  setUp(() {
    sounds
      ..loop(null)
      ..played.clear();
  });

  testWidgets('an online game plays each moment once', (tester) async {
    final channel = await _inGame(tester, FakeApi());

    channel.snapshot('game.state', 'game', gameJson(phase: 'role_reveal'));
    await settle(tester);
    expect(sounds.played, ['reveal']);

    // My turn, with 7 seconds on the clock: the beats start at 5.
    channel.snapshot('game.state', 'game',
        _deadlineIn(gameJson(phase: 'hints', turn: 'p_me'), 7));
    await settle(tester);
    expect(sounds.played, isNot(contains('countdown')));
    await tester.pump(const Duration(seconds: 2));
    expect(sounds.played.last, 'countdown');

    // Someone else's turn has no countdown for me.
    sounds.played.clear();
    channel.snapshot('game.state', 'game',
        _deadlineIn(gameJson(phase: 'hints', turn: 'p_2'), 7));
    await settle(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(sounds.played, isEmpty);

    channel.event('game.reaction', {
      'gameId': 'g_1',
      'hintIndex': 0,
      'reactionId': 'laugh',
      'playerId': 'p_2',
    });
    await tester.pump();
    expect(sounds.played, ['reaction']);

    sounds.played.clear();
    channel.snapshot('game.state', 'game', gameJson(phase: 'pre_voting'));
    await settle(tester);
    channel.snapshot('game.state', 'game', gameJson(phase: 'voting'));
    await settle(tester);
    // The runoff keeps the music going rather than starting it again.
    channel.snapshot('game.state', 'game',
        gameJson(phase: 'runoff_voting', candidates: ['p_2', 'p_3']));
    await settle(tester);
    // "Time to vote" repeats through its screen and stops as the vote opens;
    // the vote itself has no music.
    expect(sounds.played, ['bed:vote_start', 'bed:off']);

    channel.snapshot(
        'game.state',
        'game',
        gameJson(phase: 'ended', result: {
          'winner': 'citizens',
          'reason': 'impostor_guess_wrong',
          'impostorPlayerId': 'p_3',
          'secretWord': 'פיל',
          'voteRounds': [
            {'p_me': 'p_3', 'p_2': 'p_3', 'p_4': 'p_3'},
          ],
          'abstentions': [1],
          'outcomes': {'p_me': 'win', 'p_3': 'loss'},
        }));
    await settle(tester);
    expect(sounds.played, ['bed:vote_start', 'bed:off', 'win']);
  });

  // On a test host this is the iPhone path: the strongest haptic tap. Android
  // takes a real vibration through MainActivity instead (lib/state/buzz.dart).
  testWidgets('a written clue pops; a missed turn and a hidden one do not',
      (tester) async {
    final channel = await _inGame(tester, FakeApi());
    Map<String, dynamic> hint(String from, {bool missing = false}) => {
          'playerId': from,
          'text': missing ? '' : 'חדק',
          'missing': missing,
          'reactions': {},
        };
    channel.snapshot(
        'game.state', 'game', gameJson(phase: 'hints', turn: 'p_2'));
    await settle(tester);
    SessionScope.read(tester.element(find.byType(LiveRoomScreen))).muted = {
      'p_4'
    };
    sounds.played.clear();
    final board = <Map<String, dynamic>>[];
    for (final (h, sound) in [
      (hint('p_2'), ['hint']),
      (hint('p_3', missing: true), <String>[]),
      (hint('p_4'), <String>[]),
      (hint('p_me'), ['hint']),
    ]) {
      board.add(h);
      channel.snapshot('game.state', 'game',
          gameJson(phase: 'hints', turn: 'p_2', hints: [...board]));
      await settle(tester);
      expect(sounds.played, sound, reason: '${h['playerId']}');
      sounds.played.clear();
    }
  });

  testWidgets('a game start vibrates when vibration is on', (tester) async {
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final channel = await _inGame(tester, FakeApi());
    channel.snapshot('game.state', 'game', gameJson(phase: 'role_reveal'));
    await settle(tester);
    expect(haptics, ['HapticFeedbackType.heavyImpact']);
  });

  testWidgets('back in the last seconds of my turn, the beats rejoin',
      (tester) async {
    final channel = await _inGame(tester, FakeApi());
    channel.snapshot('game.state', 'game',
        _deadlineIn(gameJson(phase: 'hints', turn: 'p_me'), 4));
    await settle(tester);
    expect(sounds.played, ['countdown']);
    sounds.played.clear();
    // Away and back, one state at a time as a phone reports them.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    expect(sounds.played, ['countdown']);
  });

  testWidgets('the vote counts down for a voter who already voted',
      (tester) async {
    final channel = await _inGame(tester, FakeApi());
    channel.snapshot(
        'game.state',
        'game',
        _deadlineIn(
            gameJson(phase: 'voting', candidates: ['p_2'], myVote: 'p_2'), 7));
    await settle(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(sounds.played, ['countdown']);
  });

  testWidgets('a removed player hears nothing of the game', (tester) async {
    final channel = await _inGame(tester, FakeApi());
    channel.snapshot(
        'game.state',
        'game',
        _deadlineIn(
            gameJson(phase: 'voting', candidates: [
              'p_2'
            ], players: [
              player('p_me', 'דור', status: 'removed'),
              player('p_2', 'נועה'),
              player('p_3', 'יובל'),
              player('p_4', 'מאיה'),
            ]),
            7));
    await settle(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(sounds.played, isEmpty);
  });

  testWidgets('a removed player is not buzzed on reconnecting', (tester) async {
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final channel = await _inGame(tester, FakeApi());
    channel.snapshot(
        'game.state',
        'game',
        gameJson(phase: 'voting', candidates: [
          'p_2'
        ], players: [
          player('p_me', 'דור', status: 'removed'),
          player('p_2', 'נועה'),
          player('p_3', 'יובל'),
          player('p_4', 'מאיה'),
        ]));
    await settle(tester);
    expect(haptics, isEmpty);
  });

  testWidgets('a hidden player\'s reaction makes no sound', (tester) async {
    final channel = await _inGame(tester, FakeApi());
    channel.snapshot(
        'game.state', 'game', gameJson(phase: 'hints', turn: 'p_3'));
    await settle(tester);
    SessionScope.read(tester.element(find.byType(LiveRoomScreen))).muted = {
      'p_2'
    };
    for (final from in ['p_2', 'p_4']) {
      channel.event('game.reaction', {
        'gameId': 'g_1',
        'hintIndex': 0,
        'reactionId': 'laugh',
        'playerId': from,
      });
      await tester.pump();
    }
    expect(sounds.played, ['reaction'], reason: 'p_4 only');
  });

  testWidgets('a server error silences the move to voting', (tester) async {
    final channel = await _inGame(tester, FakeApi());
    channel.snapshot('game.state', 'game', gameJson(phase: 'pre_voting'));
    await settle(tester);
    channel.event('game.aborted', {'gameId': 'g_1'});
    await settle(tester);
    expect(sounds.played, ['bed:vote_start', 'bed:off']);
  });

  testWidgets('the impostor hears the citizens\' reveal', (tester) async {
    final channel = await _inGame(tester, FakeApi());
    channel.snapshot(
        'game.state', 'game', gameJson(phase: 'role_reveal', role: 'impostor'));
    await settle(tester);
    expect(sounds.played, ['reveal']);
  });

  testWidgets('Sounds off in Settings keeps the game silent', (tester) async {
    final api = FakeApi();
    await startAtHome(tester, api);
    await tapTooltip(tester, 'הגדרות');
    await tapText(tester, 'צלילים');
    expect(sounds.enabled, isFalse);
    Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
    await tester.pumpAndSettle();

    await openCreatedRoom(tester, api);
    api.channel.event('session.state', {
      'playerId': 'p_me',
      'activity': 'game',
      'roomId': 'r_1',
      'gameId': 'g_1',
    });
    api.channel.snapshot('game.state', 'game', gameJson(phase: 'role_reveal'));
    await settle(tester);
    api.channel.snapshot('game.state', 'game', gameJson(phase: 'voting'));
    await settle(tester);
    expect(sounds.played, isEmpty);
    sounds.enabled = true;
  });
}
