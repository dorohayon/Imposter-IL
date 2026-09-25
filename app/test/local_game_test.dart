import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/local/local_game.dart';
import 'package:imposter_il/local/words.g.dart';

LocalGame game({int players = 4, int seed = 7, int? hintSeconds = 30}) =>
    LocalGame(
      players: [
        for (var i = 0; i < players; i++)
          LocalPlayer(name: 'שחקן ${i + 1}', avatar: 'a$i'),
      ],
      categoryIds: const ['food'],
      hintSeconds: hintSeconds,
      rng: Random(seed),
    );

/// Walks role reveal and a hint round, leaving the game at the vote.
void toVote(LocalGame g) {
  while (g.phase == LocalPhase.roleReveal) {
    g.reveal();
    g.roleSeen(g.currentPlayer);
  }
  g.startRound();
  while (g.phase == LocalPhase.hints) {
    g.hintSpoken(g.currentPlayer);
  }
  g.startVoting();
}

/// Everybody active votes for [target], except the target themselves.
void allVoteFor(LocalGame g, int target) {
  final voters = g.activePlayers.length;
  for (var i = 0; i < voters; i++) {
    final me = g.currentPlayer;
    g.castVote(me == target ? g.candidatesFor(me).first : target);
  }
}

void main() {
  test('a match deals one impostor and a word from the chosen categories', () {
    final g = game();
    expect(g.impostor, inInclusiveRange(0, 3));
    expect(g.category, 'אוכל ושתייה');
    expect(g.secretWord, isNotEmpty);
    // Only the chosen category's words are in play.
    expect(
      localCategories.firstWhere((c) => c.id == 'food').words,
      contains(g.secretWord),
    );
  });

  test('every player is shown their role, one at a time', () {
    final g = game();
    final seen = <int>[];
    while (g.phase == LocalPhase.roleReveal) {
      seen.add(g.currentPlayer);
      g.reveal();
      g.roleSeen(g.currentPlayer);
    }
    expect(seen, [0, 1, 2, 3]);
    expect(g.phase, LocalPhase.ready);
  });

  test('a repeated role acknowledgement cannot skip the next player', () {
    final g = game();
    final player = g.currentPlayer;
    g.reveal();
    g.roleSeen(player);
    expect(g.currentPlayer, isNot(player));

    g.roleSeen(player);
    expect(g.currentPlayer, 1);
    expect(g.revealed, isFalse);
  });

  test('voting out a citizen starts another round and keeps them watching', () {
    final g = game(players: 5);
    toVote(g);
    final victim = g.activePlayers.firstWhere((i) => i != g.impostor);
    allVoteFor(g, victim);

    expect(g.phase, LocalPhase.elimination);
    expect(g.lastEliminated, victim);
    expect(g.players[victim].eliminated, isTrue);

    g.afterElimination();
    expect(g.phase, LocalPhase.ready);
    expect(g.round, 2);
    // A spectator takes no turn and is nobody's candidate.
    expect(g.turnOrder, isNot(contains(victim)));
    g.startRound();
    while (g.phase == LocalPhase.hints) {
      expect(g.currentPlayer, isNot(victim));
      g.hintSpoken(g.currentPlayer);
    }
    g.startVoting();
    for (final voter in g.activePlayers) {
      expect(g.candidatesFor(voter), isNot(contains(victim)));
    }
  });

  test('the impostor wins the moment one citizen is left', () {
    final g = game(players: 4); // three citizens and an impostor
    toVote(g);
    var citizens = g.activePlayers.where((i) => i != g.impostor).toList();
    allVoteFor(g, citizens.first);
    g.afterElimination();
    expect(g.phase, LocalPhase.ready);

    // One more, and the last citizen is alone with the impostor.
    g.startRound();
    while (g.phase == LocalPhase.hints) {
      g.hintSpoken(g.currentPlayer);
    }
    g.startVoting();
    citizens = g.activePlayers.where((i) => i != g.impostor).toList();
    allVoteFor(g, citizens.first);
    g.afterElimination();

    expect(g.phase, LocalPhase.ended);
    expect(g.outcome, LocalOutcome.impostorWin);
    expect(g.endReason, LocalEndReason.impostorParity);
  });

  test('catching the impostor goes to one guess, either way', () {
    for (final right in [true, false]) {
      final g = game();
      toVote(g);
      allVoteFor(g, g.impostor);
      expect(g.phase, LocalPhase.guess);

      g.submitGuess(right ? g.secretWord : 'לאיודע');
      expect(g.phase, LocalPhase.ended);
      expect(g.outcome,
          right ? LocalOutcome.impostorWin : LocalOutcome.citizensWin);
      expect(
        g.endReason,
        right
            ? LocalEndReason.impostorGuessedWord
            : LocalEndReason.impostorGuessWrong,
      );
    }
  });

  test('a tie goes to a runoff between the tied only', () {
    final g = game();
    toVote(g);
    final order = g.activePlayers;
    g.castVote(order[1]);
    g.castVote(order[0]);
    g.castVote(order[1]);
    g.castVote(order[0]);

    // The table is told there was a tie before the phone goes round again:
    // online everybody sees it on their own screen at once, and here there is
    // only the one screen.
    expect(g.phase, LocalPhase.tie);
    expect(g.tiedVotes, 2);
    expect(g.runoffCandidates, unorderedEquals([order[0], order[1]]));
    g.startRunoff();
    expect(g.phase, LocalPhase.runoff);
    for (final voter in g.activePlayers) {
      expect(g.candidatesFor(voter), everyElement(isIn(g.runoffCandidates)));
    }
  });

  test('a runoff that ties again eliminates nobody', () {
    final g = game();
    toVote(g);
    final order = g.activePlayers;
    // A clean two-two tie.
    g.castVote(order[1]);
    g.castVote(order[0]);
    g.castVote(order[1]);
    g.castVote(order[0]);
    expect(g.phase, LocalPhase.tie);
    g.startRunoff();

    // And the same again in the runoff.
    g.castVote(order[1]);
    g.castVote(order[0]);
    g.castVote(order[1]);
    g.castVote(order[0]);
    expect(g.phase, LocalPhase.tieAgain);
    g.afterSecondTie();
    expect(g.phase, LocalPhase.ready);
    expect(g.round, 2);
    expect(g.players.every((p) => !p.eliminated), isTrue);
    // And the table is told, on a screen of its own, before the round begins.
    expect(g.tieCandidates, unorderedEquals([order[0], order[1]]));
  });

  test('nobody votes for themselves', () {
    final g = game(players: 5);
    toVote(g);
    for (final voter in g.activePlayers) {
      expect(g.candidatesFor(voter), isNot(contains(voter)));
    }
  });

  test('the turn order is drawn again each round', () {
    // Over several seeds the order must not always be the seating order.
    var reordered = 0;
    for (var seed = 0; seed < 20; seed++) {
      final g = game(players: 6, seed: seed);
      toVote(g);
      if (g.turnOrder.toString() != g.activePlayers.toString()) reordered++;
    }
    expect(reordered, greaterThan(0));
  });

  test('the ready screen order is the order used for the hint round', () {
    final g = game(players: 6);
    while (g.phase == LocalPhase.roleReveal) {
      g.reveal();
      g.roleSeen(g.currentPlayer);
    }
    final announced = [...g.turnOrder];
    g.startRound();
    expect(g.turnOrder, announced);
  });

  test('hint and transition timers advance without typed input', () {
    final g = game(hintSeconds: 20);
    while (g.phase == LocalPhase.roleReveal) {
      g.reveal();
      g.roleSeen(g.currentPlayer);
    }
    g.startRound();
    final timedOut = g.currentPlayer;
    for (var i = 0; i < 20; i++) {
      g.tick();
    }
    expect(g.missedHintSeats, contains(timedOut));
    expect(g.seat, 1);
    expect(g.secondsRemaining, 20);

    while (g.phase == LocalPhase.hints) {
      g.hintSpoken(g.currentPlayer);
    }
    expect(g.phase, LocalPhase.voteTransition);
    expect(g.secondsRemaining, LocalGame.voteTransitionSeconds);
    for (var i = 0; i < LocalGame.voteTransitionSeconds; i++) {
      g.tick();
    }
    expect(g.phase, LocalPhase.voting);
  });

  test('a stale hint action cannot skip the next speaker', () {
    final g = game();
    while (g.phase == LocalPhase.roleReveal) {
      g.reveal();
      g.roleSeen(g.currentPlayer);
    }
    g.startRound();
    final speaker = g.currentPlayer;
    g.hintSpoken(speaker);
    final next = g.currentPlayer;

    g.hintSpoken(speaker);
    expect(g.currentPlayer, next);
    expect(g.seat, 1);
  });

  test('the caught impostor loses when the guess clock expires', () {
    final g = game();
    toVote(g);
    allVoteFor(g, g.impostor);
    g.reveal();
    expect(g.secondsRemaining, LocalGame.guessSeconds);
    for (var i = 0; i < LocalGame.guessSeconds; i++) {
      g.tick();
    }
    expect(g.outcome, LocalOutcome.citizensWin);
    expect(g.endReason, LocalEndReason.impostorGuessTimeout);
  });

  test('local guesses follow the approved Hebrew matching rules', () {
    expect(isCorrectLocalGuess('הַ-בננה!', 'בננה'), isTrue);
    expect(isCorrectLocalGuess('ושולחן', 'שולחן'), isTrue);
    expect(isCorrectLocalGuess('בננות', 'בננה'), isFalse);
    expect(isCorrectLocalGuess('שלחן', 'שולחן'), isFalse);
  });

  group('saving and restoring', () {
    test('a restored match never comes back with a secret on screen', () {
      // Every phase that can have something private on the screen.
      for (final reach in [
        (LocalGame g) {
          g.reveal(); // a role, mid-reveal
        },
        (LocalGame g) {
          toVote(g);
          g.reveal(); // a ballot
        },
        (LocalGame g) {
          toVote(g);
          allVoteFor(g, g.impostor);
          g.reveal(); // the guess
        },
      ]) {
        final g = game();
        reach(g);
        expect(g.revealed, isTrue, reason: 'the test did not reach a secret');

        final back = localGameFromJson(g.toJson(), rng: Random(1))!;
        expect(back.revealed, isFalse,
            reason: 'a restored match showed a secret without being asked');
        expect(back.phase, g.phase);
        expect(back.currentPlayer, g.currentPlayer);
      }
    });

    test('background privacy covers every kind of secret screen', () {
      for (final reach in [
        (LocalGame g) => g.reveal(),
        (LocalGame g) {
          toVote(g);
          g.reveal();
        },
        (LocalGame g) {
          toVote(g);
          allVoteFor(g, g.impostor);
          g.reveal();
        },
      ]) {
        final g = game();
        reach(g);
        expect(g.revealed, isTrue);
        g.hidePrivateContent();
        expect(g.revealed, isFalse);
      }
    });

    test('a restored match carries the whole position', () {
      final g = game(players: 5);
      toVote(g);
      final victim = g.activePlayers.firstWhere((i) => i != g.impostor);
      allVoteFor(g, victim);
      g.afterElimination();
      g.startRound();
      g.hintSpoken(g.currentPlayer);

      final back = localGameFromJson(g.toJson(), rng: Random(1))!;
      expect(back.secretWord, g.secretWord);
      expect(back.category, g.category);
      expect(back.impostor, g.impostor);
      expect(back.round, g.round);
      expect(back.seat, g.seat);
      expect(back.turnOrder, g.turnOrder);
      expect(back.phase, g.phase);
      expect(back.secondsRemaining, g.secondsRemaining);
      expect(back.missedHintSeats, g.missedHintSeats);
      expect(back.eliminations, g.eliminations);
      expect([for (final p in back.players) p.eliminated],
          [for (final p in g.players) p.eliminated]);
      expect([for (final p in back.players) p.name],
          [for (final p in g.players) p.name]);
    });

    test('votes already cast survive a restore', () {
      final g = game();
      toVote(g);
      final order = g.activePlayers;
      g.castVote(order[1]);
      g.castVote(order[0]);

      final back = localGameFromJson(g.toJson(), rng: Random(1))!;
      expect(back.votes, g.votes);
      expect(back.seat, g.seat);
    });

    test('a confirmed vote resumes hidden and is not lost', () {
      final g = game();
      toVote(g);
      g.reveal();
      final voter = g.currentPlayer;
      final target = g.candidatesFor(voter).first;
      g.confirmVote(target);

      final back = localGameFromJson(g.toJson(), rng: Random(1))!;
      expect(back.revealed, isFalse);
      expect(back.ballotSaved, isTrue);
      expect(back.votes[voter], target);
      expect(back.currentPlayer, voter);

      back.reveal();
      back.finishVote();
      expect(back.currentPlayer, isNot(voter));
    });

    test('a snapshot it cannot read is dropped rather than half-restored', () {
      expect(localGameFromJson(const {'phase': 'nonsense'}), isNull);
      expect(localGameFromJson(const {}), isNull);
    });
  });

  test('playing without a timer is allowed', () {
    final g = game(hintSeconds: null);
    expect(g.hintSeconds, isNull);
    toVote(g);
    expect(g.phase, LocalPhase.voting);
  });

  test('local guess accepts configured alternate spellings', () {
    expect(isCorrectLocalGuess('פקמן', 'פאקמן'), isTrue);
    expect(isCorrectLocalGuess('וויפי', 'וויי פיי'), isTrue);
    expect(isCorrectLocalGuess('טטריס', 'פאקמן'), isFalse);
  });
}
