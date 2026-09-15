// End-to-end: four app sessions play a private game against a real server.
//
//   cd server && IMPOSTER_DEV_POLICY=1 PORT=18080 go run ./cmd/server
//   cd app && IMPOSTER_E2E_SERVER=http://localhost:18080 flutter test test/e2e
//
// Skipped when IMPOSTER_E2E_SERVER is not set.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/data/server.dart';
import 'package:imposter_il/state/game_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _server = Platform.environment['IMPOSTER_E2E_SERVER'];

/// Waits until [condition] holds, re-checking whenever the session changes.
Future<void> until(GameSession session, bool Function() condition,
    {Duration timeout = const Duration(seconds: 10)}) async {
  if (condition()) return;
  final done = Completer<void>();
  void check() {
    if (condition() && !done.isCompleted) done.complete();
  }

  session.addListener(check);
  try {
    await done.future.timeout(timeout);
  } finally {
    session.removeListener(check);
  }
}

Future<void> ok(Future<String?> command) async =>
    expect(await command, isNull, reason: 'command failed');

void main() {
  test(
    'four players play a private game to the end and return to the lobby',
    () async {
      SharedPreferences.setMockInitialValues({});
      final api = ApiClient(Uri.parse(_server!));
      final names = ['דור', 'נועה', 'יובל', 'מאיה'];
      final players = <GameSession>[];
      addTearDown(() {
        for (final p in players) {
          p.dispose();
        }
      });
      for (final name in names) {
        final session = GameSession(api);
        players.add(session);
        await session.signIn(name, 'avatar-m04-detective-hat');
        await until(session, () => session.connected);
        expect(session.categories.map((c) => c.id), contains('animals'));
      }
      final host = players.first;

      await host
          .createRoom(maxPlayers: 8, hintSeconds: 15, categoryIds: ['animals']);
      final code = host.room!.code;
      for (final p in players.skip(1)) {
        await p.joinRoom(code);
      }
      await until(host, () => host.room?.players.length == 4);
      expect(host.room!.hostId, host.playerId);

      await ok(host.send('room.start', {'roomId': host.roomId}));
      for (final p in players) {
        await until(p, () => p.game?.phase == 'role_reveal');
      }
      final impostors = players.where((p) => p.game!.isImpostor).toList();
      expect(impostors, hasLength(1));
      final impostor = impostors.single;
      for (final p in players) {
        expect(p.game!.secretWord == null, p == impostor);
        await ok(p.send('game.confirmRole', {'gameId': p.game!.id}));
      }

      await until(host, () => host.game?.phase == 'hints');
      final byId = {for (final p in players) p.playerId!: p};
      final hints = ['גדול', 'אפור', 'אוזניים', 'זיכרון'];
      for (final hint in hints) {
        final turn = byId[host.game!.currentTurnPlayerId]!;
        await ok(turn.send('game.submitHint', {
          'gameId': turn.game!.id,
          'text': hint,
        }));
        await until(
            host, () => host.game!.hints.length == hints.indexOf(hint) + 1);
      }
      await ok(players[1].send('game.react', {
        'gameId': host.game!.id,
        'hintIndex': 0,
        'reactionId': 'suspicious',
      }));
      await until(
          host, () => host.game!.hints.first.reactions['suspicious'] == 1);

      await until(host, () => host.game!.phase == 'voting');
      for (final p in players) {
        final target = p == impostor
            ? players.firstWhere((other) => other != impostor).playerId
            : impostor.playerId;
        await ok(p.send(
            'game.vote', {'gameId': p.game!.id, 'targetPlayerId': target}));
      }

      // Voting runs its full 20 seconds on the server.
      await until(impostor, () => impostor.game!.phase == 'impostor_guess',
          timeout: const Duration(seconds: 30));
      final word = players.firstWhere((p) => p != impostor).game!.secretWord!;
      await ok(impostor.send('game.submitGuess', {
        'gameId': impostor.game!.id,
        'text': 'ה$word',
      }));

      for (final p in players) {
        await until(p, () => p.game?.phase == 'ended');
        final result = p.game!.result!;
        expect(result.winner, 'impostor');
        expect(result.reason, 'impostor_guessed_word');
        expect(result.impostorId, impostor.playerId);
      }

      await ok(host.send('game.playAgain', {'gameId': host.game!.id}));
      await until(
          host, () => host.activity == 'room' && host.room?.status == 'lobby');
    },
    skip: _server == null
        ? 'set IMPOSTER_E2E_SERVER to run against a server'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
