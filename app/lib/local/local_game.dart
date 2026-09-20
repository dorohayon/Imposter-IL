import 'dart:math';

import 'words.g.dart';

/// Where a one-device match is, screen by screen. The device is the only
/// source of truth here: there is no server to ask and nothing to reconcile.
enum LocalPhase {
  /// Handing the device round so each player can see their role alone.
  roleReveal,

  /// Everybody knows who they are; the device goes back on the table.
  ready,

  /// A player says their hint out loud. Nothing is typed.
  hints,

  /// The beat before the vote, so the table can settle.
  voteTransition,

  /// Handing the device round so each player votes alone.
  voting,

  /// Telling the table there was a tie, before the phone starts going round
  /// again. Online every player sees the tie on their own screen at once;
  /// here there is one screen, so the announcement needs its own moment.
  tie,

  /// A runoff that tied as well: nobody goes, and the table is told so before
  /// the next round of hints (design 15ג).
  tieAgain,

  /// A tie, voted again between the tied players only.
  runoff,

  /// Naming who the table voted out, and what they were.
  elimination,

  /// The impostor was caught and has one guess at the word.
  guess,
  ended,
}

enum LocalOutcome { citizensWin, impostorWin }

/// Why a match ended, for the result screen to explain.
enum LocalEndReason {
  impostorGuessedWord,
  impostorGuessWrong,
  impostorGuessTimeout,
  impostorParity,
}

class LocalPlayer {
  LocalPlayer({required this.name, required this.avatar});

  final String name;
  final String avatar;

  /// Voted out: watching, no turn and no vote, and still on their team's side
  /// of the result.
  bool eliminated = false;
}

/// A one-device match.
///
/// Every rule here matches the online game (docs/decisions.md): one impostor,
/// rounds until one side wins, a runoff on a tie, a second tie eliminating
/// nobody, and parity handing it to the impostor. What differs is only what a
/// shared device can do — hints are spoken, so nothing is typed and nothing
/// can be checked, and every active player must cast a private vote.
class LocalGame {
  LocalGame({
    required this.players,
    required this.categoryIds,
    required this.hintSeconds,
    required Random rng,
  })  : _rng = rng,
        assert(players.length >= minPlayers && players.length <= maxPlayers) {
    final pool = <(String, String)>[
      for (final c in localCategories)
        if (categoryIds.contains(c.id))
          for (final word in c.words) (c.name, word),
    ];
    if (pool.isEmpty) {
      throw ArgumentError.value(
        categoryIds,
        'categoryIds',
        'must contain at least one known category',
      );
    }
    final picked = _rng.nextInt(pool.length);
    final chosen = pool[picked];
    category = chosen.$1;
    secretWord = chosen.$2;
    impostor = _rng.nextInt(players.length);
    _shuffleTurnOrder();
  }

  /// Rebuilds a match from a snapshot, without dealing a new word or role.
  LocalGame.restored({
    required this.players,
    required this.categoryIds,
    required this.hintSeconds,
    required this.secretWord,
    required this.category,
    required this.impostor,
    required Random rng,
  }) : _rng = rng;

  /// For [localGameFromJson], which restores the tie a runoff came from.
  void restorePreviousVotes(Map<int, int> votes) => _previousVotes = votes;

  static const minPlayers = 3;
  static const maxPlayers = 12;
  static const voteTransitionSeconds = 5;
  static const guessSeconds = 60;

  final List<LocalPlayer> players;
  final List<String> categoryIds;

  /// Seconds per hint, or null to play without a timer.
  final int? hintSeconds;
  final Random _rng;

  late String secretWord;
  late String category;

  /// Index into [players].
  late int impostor;

  LocalPhase phase = LocalPhase.roleReveal;
  int round = 1;

  /// Whose turn it is to be handed the device, or to speak.
  int seat = 0;

  /// The order the active players speak in, reshuffled each round.
  List<int> turnOrder = [];

  /// Seconds left in the current timed phase. It is part of the snapshot so
  /// backgrounding or killing the app cannot silently restart a turn.
  int? secondsRemaining;

  /// Seats whose hint clock expired in this round. Spoken hints are not typed,
  /// but the order still needs to say that no hint was given.
  final Set<int> missedHintSeats = {};

  /// Votes of this round: voter index -> target index.
  final Map<int, int> votes = {};

  /// The current voter's choice has been confirmed and hidden, but the phone
  /// has not yet been handed onwards. Keeping this in the snapshot lets a
  /// restart return to a privacy screen without losing or exposing the vote.
  bool ballotSaved = false;

  /// The players a runoff is between, when there is one.
  List<int> runoffCandidates = [];

  /// Votes each runoff candidate took in the round that tied, for the runoff
  /// screen to show.
  Map<int, int> _previousVotes = {};
  Map<int, int> get previousVotes => Map.unmodifiable(_previousVotes);

  /// Who was voted out, and in which round, for the result screen.
  final List<(int, int)> eliminations = [];

  /// Whether the player holding the device has said it is them. False is the
  /// "hand the device to X" screen; true is the secret behind it.
  ///
  /// This lives in the state rather than in a screen so that a match restored
  /// from the device can never come back with a role or a ballot already on
  /// screen — see [LocalGame.fromJson], which always restores it false.
  bool revealed = false;

  /// Who the table voted out this round, once it has.
  int? lastEliminated;

  /// How many votes each tied player took, for the tie announcement.
  int tiedVotes = 0;

  /// Set when a runoff tied as well, so the next round can say nobody went.
  /// The tied players, for the announcement to name them. Kept apart from
  /// [votes], which says who chose whom and never leaves the ballot: an
  /// announcement the whole table reads may carry totals and nothing else.
  List<int> tieCandidates = [];
  String? submittedGuess;
  LocalOutcome? outcome;
  LocalEndReason? endReason;

  /// Everybody still playing, in seating order.
  List<int> get activePlayers => [
        for (var i = 0; i < players.length; i++)
          if (!players[i].eliminated) i,
      ];

  bool get impostorIsActive => !players[impostor].eliminated;

  /// Everybody watching rather than playing, in seating order.
  List<int> get eliminatedSeats => [
        for (var i = 0; i < players.length; i++)
          if (players[i].eliminated) i,
      ];
  int get activeCitizens => activePlayers.where((i) => i != impostor).length;

  /// Who the device is waiting for, during role reveal or voting.
  int get currentPlayer => switch (phase) {
        LocalPhase.roleReveal => seat,
        LocalPhase.voting || LocalPhase.runoff => activePlayers[seat],
        LocalPhase.hints => turnOrder[seat],
        _ => seat,
      };

  // ---- role reveal -------------------------------------------------------

  /// The player the device was handed to says it is them.
  void reveal() {
    revealed = true;
    if (phase == LocalPhase.guess && secondsRemaining == null) {
      secondsRemaining = guessSeconds;
    }
  }

  /// Covers any private screen before the app leaves the foreground.
  void hidePrivateContent() {
    if (phase == LocalPhase.roleReveal ||
        phase == LocalPhase.voting ||
        phase == LocalPhase.runoff ||
        phase == LocalPhase.guess) {
      revealed = false;
    }
  }

  /// The next player has seen their role.
  void roleSeen(int player) {
    if (phase != LocalPhase.roleReveal ||
        !revealed ||
        player != currentPlayer) {
      return;
    }
    revealed = false;
    seat++;
    if (seat >= players.length) {
      seat = 0;
      phase = LocalPhase.ready;
    }
  }

  void startRound() {
    if (phase != LocalPhase.ready) return;
    revealed = false;
    seat = 0;
    phase = LocalPhase.hints;
    secondsRemaining = hintSeconds;
  }

  // ---- hints -------------------------------------------------------------

  /// A hint was spoken, or the turn ran out of time. Either way the device
  /// moves on; with nothing typed there is nothing to record.
  void hintSpoken(int player, {bool timedOut = false}) {
    if (phase != LocalPhase.hints || player != currentPlayer) return;
    if (timedOut) missedHintSeats.add(currentPlayer);
    seat++;
    if (seat >= turnOrder.length) {
      seat = 0;
      phase = LocalPhase.voteTransition;
      secondsRemaining = voteTransitionSeconds;
    } else {
      secondsRemaining = hintSeconds;
    }
  }

  void startVoting() {
    if (phase != LocalPhase.voteTransition) return;
    votes.clear();
    runoffCandidates = [];
    revealed = false;
    ballotSaved = false;
    seat = 0;
    secondsRemaining = null;
    phase = LocalPhase.voting;
  }

  // ---- voting ------------------------------------------------------------

  /// Who this voter may choose: everybody still playing except themselves,
  /// narrowed to the tied players during a runoff.
  List<int> candidatesFor(int voter) {
    final pool = runoffCandidates.isEmpty ? activePlayers : runoffCandidates;
    return [
      for (final i in pool)
        if (i != voter) i,
    ];
  }

  /// Stores a private choice without advancing to the next player. The saved
  /// confirmation screen deliberately never says who was chosen.
  void confirmVote(int target) {
    if (phase != LocalPhase.voting && phase != LocalPhase.runoff) return;
    if (!candidatesFor(currentPlayer).contains(target)) {
      throw ArgumentError.value(target, 'target', 'is not a valid candidate');
    }
    votes[currentPlayer] = target;
    ballotSaved = true;
  }

  /// Clears the confirmed ballot from view and hands the device onwards.
  void finishVote() {
    if (phase != LocalPhase.voting && phase != LocalPhase.runoff) return;
    if (!ballotSaved || !votes.containsKey(currentPlayer)) return;
    revealed = false;
    ballotSaved = false;
    seat++;
    if (seat < activePlayers.length) return;
    seat = 0;
    _tally();
  }

  /// Atomic convenience for deterministic rule tests.
  void castVote(int target) {
    confirmVote(target);
    finishVote();
  }

  void _tally() {
    if (votes.isEmpty) return;
    final counts = <int, int>{};
    for (final target in votes.values) {
      counts[target] = (counts[target] ?? 0) + 1;
    }
    final most = counts.values.reduce(max);
    final top = [
      for (final e in counts.entries)
        if (e.value == most) e.key,
    ];

    if (top.length > 1) {
      // A tie goes to a runoff between the tied; a tie there eliminates
      // nobody and the table goes around again.
      if (phase == LocalPhase.voting) {
        tiedVotes = most;
        tieCandidates = [...top]..sort();
        runoffCandidates = top..sort();
        _previousVotes = {
          for (final c in top) c: counts[c] ?? 0,
        };
        votes.clear();
        revealed = false;
        ballotSaved = false;
        phase = LocalPhase.tie;
        return;
      }
      // A runoff that tied as well: nobody goes, and the next round says why.
      // Nobody goes, and the table is told so rather than finding out by
      // nothing happening.
      tiedVotes = most;
      tieCandidates = [...top]..sort();
      votes.clear();
      revealed = false;
      ballotSaved = false;
      phase = LocalPhase.tieAgain;
      return;
    }

    lastEliminated = top.first;
    players[top.first].eliminated = true;
    eliminations.add((top.first, round));
    if (top.first == impostor) {
      phase = LocalPhase.guess;
      return;
    }
    if (activeCitizens <= 1) {
      _end(LocalOutcome.impostorWin, LocalEndReason.impostorParity);
      return;
    }
    phase = LocalPhase.elimination;
  }

  /// Moves on from naming the citizen who was voted out.
  void afterElimination() {
    if (phase != LocalPhase.elimination) return;
    _nextRound();
  }

  /// The table has read the second tie; the next round of hints begins.
  void afterSecondTie() {
    if (phase != LocalPhase.tieAgain) return;
    _nextRound();
  }

  /// The table has read the tie; the phone starts going round again.
  void startRunoff() {
    if (phase != LocalPhase.tie) return;
    seat = 0;
    revealed = false;
    phase = LocalPhase.runoff;
  }

  void _nextRound() {
    round++;
    votes.clear();
    runoffCandidates = [];
    lastEliminated = null;
    revealed = false;
    ballotSaved = false;
    secondsRemaining = null;
    missedHintSeats.clear();
    _shuffleTurnOrder();
    seat = 0;
    phase = LocalPhase.ready;
  }

  // ---- the guess ---------------------------------------------------------

  /// The caught impostor's one guess. Matching is deliberately forgiving about
  /// spacing and case; the table can see the word on the result screen either
  /// way.
  void submitGuess(String guess) {
    if (phase != LocalPhase.guess) return;
    submittedGuess = guess.trim();
    final correct = isCorrectLocalGuess(guess, secretWord);
    _end(
      correct ? LocalOutcome.impostorWin : LocalOutcome.citizensWin,
      correct
          ? LocalEndReason.impostorGuessedWord
          : LocalEndReason.impostorGuessWrong,
    );
  }

  /// Advances whichever local timer is visible. Secret phases are only timed
  /// after the intended player has passed the privacy screen.
  void tick() {
    final left = secondsRemaining;
    if (left == null || left <= 0) return;
    secondsRemaining = left - 1;
    if (secondsRemaining! > 0) return;
    switch (phase) {
      case LocalPhase.hints:
        hintSpoken(currentPlayer, timedOut: true);
      case LocalPhase.voteTransition:
        startVoting();
      case LocalPhase.guess:
        _end(LocalOutcome.citizensWin, LocalEndReason.impostorGuessTimeout);
      default:
        secondsRemaining = null;
    }
  }

  void _end(LocalOutcome result, LocalEndReason reason) {
    outcome = result;
    endReason = reason;
    phase = LocalPhase.ended;
    secondsRemaining = null;
    revealed = false;
    ballotSaved = false;
  }

  void _shuffleTurnOrder() {
    turnOrder = activePlayers..shuffle(_rng);
  }
}

/// The same forgiving Hebrew comparison used by the approved online rules:
/// punctuation and niqqud are ignored, final letters are folded, and up to
/// three Hebrew use-prefix letters may precede the secret word.
bool isCorrectLocalGuess(String guess, String secretWord) {
  final said = _normaliseHebrewWord(guess);
  final word = _normaliseHebrewWord(secretWord);
  if (said == word) return true;
  const prefixes = 'והבכלמש';
  for (var count = 1; count <= 3 && count < said.length; count++) {
    if (!prefixes.contains(said[count - 1])) break;
    if (said.length - count >= 2 && said.substring(count) == word) return true;
  }
  return false;
}

String _normaliseHebrewWord(String value) => value
    .toLowerCase()
    .replaceAll('ך', 'כ')
    .replaceAll('ם', 'מ')
    .replaceAll('ן', 'נ')
    .replaceAll('ף', 'פ')
    .replaceAll('ץ', 'צ')
    .replaceAll(RegExp(r'[^\u05D0-\u05EAa-z0-9]'), '');

/// Saving and restoring a match in progress.
///
/// A phone that is passed between people gets closed, backgrounded and picked
/// up again, so a local match is written down after every move. The one rule
/// that matters on the way back: [revealed] is always false, so a match never
/// reopens with somebody's role or ballot already on the screen. The person
/// holding the phone has to say it is them first, the same as the first time.
extension LocalGameSnapshot on LocalGame {
  Map<String, dynamic> toJson() => {
        'players': [
          for (final p in players)
            {'name': p.name, 'avatar': p.avatar, 'eliminated': p.eliminated},
        ],
        'categoryIds': categoryIds,
        'hintSeconds': hintSeconds,
        'secretWord': secretWord,
        'category': category,
        'impostor': impostor,
        'phase': phase.name,
        'round': round,
        'seat': seat,
        'turnOrder': turnOrder,
        'secondsRemaining': secondsRemaining,
        'missedHintSeats': missedHintSeats.toList(),
        'votes': {for (final e in votes.entries) '${e.key}': e.value},
        'ballotSaved': ballotSaved,
        'runoffCandidates': runoffCandidates,
        'tiedVotes': tiedVotes,
        'tieCandidates': tieCandidates,
        'previousVotes': {
          for (final e in previousVotes.entries) '${e.key}': e.value,
        },
        'lastEliminated': lastEliminated,
        'submittedGuess': submittedGuess,
        'eliminations': [
          for (final (who, round) in eliminations) [who, round],
        ],
        'outcome': outcome?.name,
        'endReason': endReason?.name,
      };
}

/// Rebuilds a saved match. Returns null for anything it cannot read, so a
/// snapshot from an older build is dropped rather than half-restored.
LocalGame? localGameFromJson(Map<String, dynamic> json, {Random? rng}) {
  try {
    final players = [
      for (final p in (json['players'] as List))
        LocalPlayer(
          name: (p as Map)['name'] as String,
          avatar: p['avatar'] as String,
        )..eliminated = p['eliminated'] as bool? ?? false,
    ];
    final game = LocalGame.restored(
      players: players,
      categoryIds: (json['categoryIds'] as List).cast<String>(),
      hintSeconds: json['hintSeconds'] as int?,
      secretWord: json['secretWord'] as String,
      category: json['category'] as String,
      impostor: json['impostor'] as int,
      rng: rng ?? Random(),
    );
    game.phase = LocalPhase.values.byName(json['phase'] as String);
    game.round = json['round'] as int;
    game.seat = json['seat'] as int;
    game.turnOrder = (json['turnOrder'] as List).cast<int>();
    game.secondsRemaining = json['secondsRemaining'] as int?;
    game.missedHintSeats.addAll(
      (json['missedHintSeats'] as List? ?? const []).cast<int>(),
    );
    game.votes.addAll({
      for (final e in (json['votes'] as Map).entries)
        int.parse(e.key as String): e.value as int,
    });
    game.runoffCandidates = (json['runoffCandidates'] as List).cast<int>();
    game.ballotSaved = json['ballotSaved'] as bool? ?? false;
    game.restorePreviousVotes({
      for (final e in (json['previousVotes'] as Map? ?? {}).entries)
        int.parse(e.key as String): e.value as int,
    });
    game.tiedVotes = json['tiedVotes'] as int? ?? 0;
    game.tieCandidates =
        ((json['tieCandidates'] as List?) ?? const []).cast<int>();
    game.lastEliminated = json['lastEliminated'] as int?;
    game.submittedGuess = json['submittedGuess'] as String?;
    for (final pair in (json['eliminations'] as List? ?? [])) {
      game.eliminations.add(((pair as List)[0] as int, pair[1] as int));
    }
    final outcome = json['outcome'] as String?;
    if (outcome != null) game.outcome = LocalOutcome.values.byName(outcome);
    final reason = json['endReason'] as String?;
    if (reason != null) game.endReason = LocalEndReason.values.byName(reason);
    // Never restored: a role or a ballot must be asked for again.
    game.revealed = false;
    return game;
  } on Object {
    return null;
  }
}
