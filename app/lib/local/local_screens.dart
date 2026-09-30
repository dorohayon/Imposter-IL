import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/player.dart';
import '../monetization/monetization.dart';
import '../state/sounds.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';
import 'local_game.dart';
import 'local_setup_screens.dart';
import 'local_store.dart';

/// The whole one-device match, phase by phase.
///
/// One screen rather than a stack of routes: the device is passed around and
/// the match is the thing on it, so a back button through half-finished votes
/// would be a way to see what somebody else chose. Leaving is a deliberate
/// act with a confirmation, and everything else is the state machine.
class LocalGameScreen extends StatefulWidget {
  const LocalGameScreen({
    this.players,
    this.categoryIds,
    this.hintSeconds,
    this.language = 'he',
    this.resumed,
    super.key,
  });

  final List<LocalPlayer>? players;
  final List<String>? categoryIds;
  final int? hintSeconds;

  /// The language of a new match's words (one-device play has no server).
  final String language;

  /// A match read back off the device, instead of a new one.
  final LocalGame? resumed;

  @override
  State<LocalGameScreen> createState() => _LocalGameScreenState();
}

class _LocalGameScreenState extends State<LocalGameScreen>
    with WidgetsBindingObserver {
  late LocalGame _game;
  Timer? _ticker;
  final _guess = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _game = widget.resumed ??
        LocalGame(
          players: widget.players!,
          categoryIds: widget.categoryIds!,
          hintSeconds: widget.hintSeconds,
          rng: Random(),
          language: widget.language,
        );
    unawaited(LocalStore.save(_game));
    _syncTimer();
    // A game resumed in the vote has its music; no stage has just begun.
    _soundChanges(_game.phase);
    _rejoinCountdown();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    sounds
      ..stop(Sound.countdown)
      ..loop(null);
    _guess.dispose();
    super.dispose();
  }

  /// Every move is written down before the screen changes: the phone is the
  /// only copy of this match.
  void _apply(void Function() move) {
    final before = _game.phase;
    setState(move);
    // Whatever the move was, a turn that was counting down is over.
    sounds.stop(Sound.countdown);
    _soundChanges(before);
    _syncTimer();
    if (_game.phase == LocalPhase.ended) {
      unawaited(LocalStore.clear());
    } else {
      unawaited(LocalStore.save(_game));
    }
  }

  bool get _timerShouldRun =>
      _game.secondsRemaining != null &&
      switch (_game.phase) {
        LocalPhase.hints || LocalPhase.voteTransition => true,
        LocalPhase.guess => _game.revealed,
        _ => false,
      };

  void _syncTimer() {
    _ticker?.cancel();
    _ticker = null;
    if (!_timerShouldRun) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final phase = _game.phase;
      setState(_game.tick);
      _soundChanges(phase);
      if (_game.secondsRemaining == 5 &&
          (_game.phase == LocalPhase.hints ||
              _game.phase == LocalPhase.guess)) {
        sounds.play(Sound.countdown);
      }
      if (_game.phase == LocalPhase.ended) {
        unawaited(LocalStore.clear());
      } else {
        unawaited(LocalStore.save(_game));
      }
      if (_game.phase != phase || !_timerShouldRun) _syncTimer();
    });
  }

  /// The sounds of a change of stage (docs/decisions.md, "צלילים"). No role
  /// sound here: the whole table would hear who the impostor is. The result
  /// is celebrated whoever won, as everyone is watching the same screen.
  void _soundChanges(LocalPhase before) {
    final phase = _game.phase;
    sounds.loop(phase == LocalPhase.voting || phase == LocalPhase.runoff
        ? Bed.voting
        : null);
    if (phase == before) return;
    if (phase == LocalPhase.voteTransition) sounds.play(Sound.voteStart);
    if (phase == LocalPhase.ended) sounds.play(Sound.win);
  }

  /// A turn that comes back inside its last seconds, from the background or a
  /// saved game, joins the countdown's beats where the clock is: the ticker
  /// only starts them on the tick that reaches five.
  void _rejoinCountdown() {
    final left = _game.secondsRemaining;
    if (_timerShouldRun &&
        left != null &&
        left > 1 &&
        left <= 5 &&
        (_game.phase == LocalPhase.hints || _game.phase == LocalPhase.guess)) {
      sounds.play(Sound.countdown, from: Duration(seconds: 5 - left));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncTimer();
      _rejoinCountdown();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _ticker?.cancel();
      _ticker = null;
      if (mounted) setState(_game.hidePrivateContent);
      unawaited(LocalStore.save(_game));
    }
  }

  Future<void> _leave() async {
    // A translucent dialog must never leave a role or a ballot readable
    // underneath it. Cancelling intentionally returns to the neutral handoff
    // screen, so only the intended player can reveal it again. The guess has
    // no secret and stays (LocalGame.hidePrivateContent).
    if (_game.revealed) {
      setState(_game.hidePrivateContent);
      _syncTimer();
      unawaited(LocalStore.save(_game));
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.nightRaised,
        title: Text(context.l10n.leaveGameTitle),
        content: Text(
          context.l10n.localDeleteWarning,
          style: TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.resumeGame),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.leaveAndDelete,
                style: TextStyle(color: AppColors.coral)),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    await LocalStore.clear();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  LocalPlayer get _current => _game.players[_game.currentPlayer];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: switch (_game.phase) {
        LocalPhase.roleReveal =>
          _game.revealed ? _roleReveal() : _passDevice(forVoting: false),
        LocalPhase.ready => _ready(),
        LocalPhase.hints => _hints(),
        LocalPhase.voteTransition => _voteTransition(),
        LocalPhase.tie => _tie(),
        LocalPhase.tieAgain => _tieAgain(),
        LocalPhase.voting ||
        LocalPhase.runoff =>
          _game.revealed ? _ballot() : _passDevice(forVoting: true),
        LocalPhase.elimination => _elimination(),
        LocalPhase.guess => _game.revealed ? _guessScreen() : _passToImpostor(),
        LocalPhase.ended => _result(),
      },
    );
  }

  // ---- privacy -----------------------------------------------------------

  /// Screens 07 and 13. Nothing secret is on the screen until the person
  /// holding the phone says it is them.
  Widget _passDevice({required bool forVoting}) {
    final done = _game.seat;
    return GameScaffold(
      title: '',
      showHeader: false,
      accent: forVoting ? const Color(0xFF42203C) : const Color(0xFF3A3470),
      bottom: PrimaryButton(
        label: forVoting
            ? context.l10n.iAmVote(_current.name)
            : context.l10n.iAmShow(_current.name),
        onPressed: () => _apply(_game.reveal),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Text(
            forVoting
                ? context.l10n.votedOf(done, _game.activePlayers.length)
                : context.l10n.countOfMax(done + 1, _game.players.length),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          const Illustration('assets/illustrations/pass-the-device.webp',
              height: 180),
          const SizedBox(height: 16),
          Text(
            context.l10n.passDeviceTo(_current.name),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            forVoting
                ? context.l10n.noOneElseLooking
                : context.l10n.onlyPlayerLooking(_current.name),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _passToImpostor() {
    final impostor = _game.players[_game.impostor];
    return GameScaffold(
      title: '',
      showHeader: false,
      accent: const Color(0xFF3A3470),
      bottom: PrimaryButton(
        label: context.l10n.iAmShow(impostor.name),
        onPressed: () => _apply(_game.reveal),
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          const Illustration('assets/illustrations/pass-the-device.webp',
              height: 180),
          const SizedBox(height: 16),
          Text(
            context.l10n.passDeviceTo(impostor.name),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.onlyPlayerLooking(impostor.name),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, height: 1.45),
          ),
        ],
      ),
    );
  }

  // ---- roles -------------------------------------------------------------

  Widget _roleReveal() {
    final impostor = _game.currentPlayer == _game.impostor;
    final player = _game.currentPlayer;
    return GameScaffold(
      title: '',
      showHeader: false,
      accent: impostor ? const Color(0xFF4A2A8C) : const Color(0xFF1B4F4A),
      bottom: PrimaryButton(
        label: context.l10n.gotItHide,
        onPressed: () => _apply(() => _game.roleSeen(player)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _current.name,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 15),
          ),
          const SizedBox(height: 10),
          Center(child: CategoryPill(category: _game.category)),
          const SizedBox(height: 12),
          Illustration(
            impostor
                ? 'assets/illustrations/role-impostor.webp'
                : 'assets/illustrations/role-citizen.webp',
            height: 150,
          ),
          const SizedBox(height: 10),
          Text(
            impostor ? context.l10n.youAreImpostor : context.l10n.youAreCitizen,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: impostor ? AppColors.yellow : AppColors.cream,
                ),
          ),
          const SizedBox(height: 12),
          SecretWordCard(word: _game.secretWord, impostor: impostor),
          if (!impostor) ...[
            const SizedBox(height: 12),
            Text(
              context.l10n.impostorDoesntKnow,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 15,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 14),
          for (final (i, tip) in (impostor
                  ? [
                      context.l10n.localImpostorTip,
                      context.l10n.impostorTip2,
                    ]
                  : [
                      context.l10n.localCitizenTip,
                      context.l10n.citizenTip2,
                    ])
              .indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: StepCard(number: i + 1, text: tip, purple: impostor),
            ),
        ],
      ),
    );
  }

  Widget _ready() {
    if (_game.round > 1) return _nextRound();
    final first = _game.players[_game.turnOrder.first];
    return GameScaffold(
      title: '',
      showHeader: false,
      accent: _game.round == 1 ? const Color(0xFF2A2455) : null,
      bottom: PrimaryButton(
        label: _game.round == 1
            ? context.l10n.startRound1
            : context.l10n.startRoundN(_game.round),
        onPressed: () => _apply(_game.startRound),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Illustration('assets/illustrations/local-one-device.webp',
              height: 140),
          const SizedBox(height: 12),
          Text(
            _game.round == 1
                ? context.l10n.everyoneKnowsRoles
                : context.l10n.anotherRound,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            _game.round == 1
                ? context.l10n.placeDevice
                : context.l10n.impostorStillAmong,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, height: 1.45),
          ),
          const SizedBox(height: 16),
          InfoCard(
            label: context.l10n.turnOrderThisRound,
            child: Column(
              children: [
                for (final i in _game.turnOrder)
                  _PlayerRow(
                    player: _game.players[i],
                    note: i == _game.turnOrder.first
                        ? context.l10n.startsFirst
                        : null,
                  ),
                for (final i in _game.eliminatedSeats)
                  _PlayerRow(
                      player: _game.players[i], note: context.l10n.spectator),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            first.name.isEmpty ? '' : '',
            style: const TextStyle(fontSize: 0),
          ),
          Text(
            context.l10n.hintRuleLocal,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.45),
          ),
        ],
      ),
    );
  }

  /// Design L18: the table again, the voted-out as watchers.
  Widget _nextRound() {
    return GameScaffold(
      title: '',
      showHeader: false,
      bottom: PrimaryButton(
        label: context.l10n.startRoundN(_game.round),
        onPressed: () => _apply(_game.startRound),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(
            context.l10n.anotherRound,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Secular One',
              fontSize: 32,
              height: 1.1,
              color: AppColors.cream,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.impostorStillAmong,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.cream.withValues(alpha: .68),
              fontSize: 15,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.turnOrderThisRound,
            style: TextStyle(
              color: AppColors.cream.withValues(alpha: .6),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          for (final i in _game.turnOrder) ...[
            _RoundPlayerRow(
              player: _game.players[i],
              note:
                  i == _game.turnOrder.first ? context.l10n.startsFirst : null,
            ),
            const SizedBox(height: 9),
          ],
          for (final i in _game.eliminatedSeats) ...[
            _RoundPlayerRow(player: _game.players[i], watching: true),
            const SizedBox(height: 9),
          ],
          const SizedBox(height: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.cream.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 18, color: AppColors.cream.withValues(alpha: .6)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.l10n.hintRuleLocal,
                    style: TextStyle(
                      color: AppColors.cream.withValues(alpha: .6),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- hints -------------------------------------------------------------

  Widget _hints() {
    final speakerSeat = _game.currentPlayer;
    final speaker = _game.players[speakerSeat];
    return GameScaffold(
      title: context.l10n.roundCategory(_game.round, _game.category),
      onExit: _leave,
      timer: _game.hintSeconds == null
          ? const Icon(Icons.timer_off_outlined, color: AppColors.muted)
          : TimerBadge(
              seconds: _game.secondsRemaining ?? _game.hintSeconds!,
              remaining: (_game.secondsRemaining ?? _game.hintSeconds!) /
                  _game.hintSeconds!,
            ),
      bottom: PrimaryButton(
        label: context.l10n.hintSaid,
        variant: ButtonVariant.confirm,
        onPressed: () => _apply(() => _game.hintSpoken(speakerSeat)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: AvatarView(asset: speaker.avatar, size: 96)),
          const SizedBox(height: 12),
          Text(
            context.l10n.turnOf(speaker.name),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.sayHintAloud,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 15),
          ),
          const SizedBox(height: 16),
          InfoCard(
            label: context.l10n.turnOrder,
            child: Column(
              children: [
                for (final (i, seat) in _game.turnOrder.indexed)
                  _PlayerRow(
                    player: _game.players[seat],
                    note: switch (i) {
                      _ when i == _game.seat => context.l10n.now,
                      _ when i == _game.seat + 1 => context.l10n.nextUp,
                      _
                          when i < _game.seat &&
                              _game.missedHintSeats.contains(seat) =>
                        context.l10n.noHintSaid,
                      _ when i < _game.seat => context.l10n.said,
                      _ => context.l10n.waiting,
                    },
                  ),
                for (final i in _game.eliminatedSeats)
                  _PlayerRow(
                      player: _game.players[i], note: context.l10n.spectator),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.hintsSpokenAloud,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _voteTransition() {
    final left = _game.secondsRemaining ?? LocalGame.voteTransitionSeconds;
    return ToVotingView(
      onExit: _leave,
      // The one line the two games say differently: online is deciding, and
      // here the phone has to go round the table first.
      note: context.l10n.passDeviceVote,
      countdown: TimerBadge(
        seconds: left,
        remaining: left / LocalGame.voteTransitionSeconds,
        size: 120,
      ),
    );
  }

  // ---- the ballot --------------------------------------------------------

  Widget _ballot() {
    final voter = _game.currentPlayer;
    final runoff = _game.phase == LocalPhase.runoff;
    return _Ballot(
      game: _game,
      voter: voter,
      runoff: runoff,
      onConfirm: (target) => _apply(() => _game.confirmVote(target)),
      onHidden: () => _apply(_game.finishVote),
    );
  }

  // ---- what the vote decided ---------------------------------------------

  /// Design 15ב. Online a tie reaches every player's own screen at once; with
  /// one phone the table needs a moment of its own, before the phone starts
  /// going round again.
  Widget _tie() => _TieAnnouncement(
        game: _game,
        title: context.l10n.tie,
        subtitle: context.l10n
            .tieCandidates(_game.tieCandidates.length, _game.tiedVotes),
        explanation: context.l10n.tieRevoteExplain,
        action: context.l10n.startRevote,
        footnote: context.l10n.thenPassNext,
        onExit: _leave,
        onContinue: () => _apply(_game.startRunoff),
      );

  /// Design 15ג. A runoff that tied as well: nobody goes, and saying so is the
  /// difference between a rule and a round that looks like nothing happened.
  Widget _tieAgain() => _TieAnnouncement(
        game: _game,
        title: context.l10n.tieAgain,
        subtitle: context.l10n.votesSplitAgain,
        explanation: context.l10n.noOneEliminatedNextRound,
        action: context.l10n.nextRoundContinues,
        onExit: _leave,
        onContinue: () => _apply(_game.afterSecondTie),
      );

  Widget _elimination() {
    final out = _game.players[_game.lastEliminated!];
    return GameScaffold(
      title: '',
      showHeader: false,
      accent: const Color(0xFF2A2455),
      bottom: PrimaryButton(
        label: context.l10n.continuingToRound(_game.round + 1),
        onPressed: () => _apply(_game.afterElimination),
      ),
      child: EliminationRevealContent(
        eliminatedName: out.name,
        eliminatedAvatar: out.avatar,
        roleLine: context.l10n.wasCitizen(out.name),
        remaining: [
          for (final i in _game.activePlayers)
            (_game.players[i].name, _game.players[i].avatar),
        ],
      ),
    );
  }

  Widget _guessScreen() {
    final impostor = _game.players[_game.impostor];
    return GameScaffold(
      // The screen's name; who was caught is read large in the body.
      title: context.l10n.guessTheWord,
      showHeader: true,
      onExit: _leave,
      timer: TimerBadge(
        seconds: _game.secondsRemaining ?? LocalGame.guessSeconds,
        remaining: (_game.secondsRemaining ?? LocalGame.guessSeconds) /
            LocalGame.guessSeconds,
      ),
      accent: const Color(0xFF4A2A8C),
      bottom: PrimaryButton(
        label: context.l10n.sendGuess,
        onPressed: _guess.text.trim().isEmpty
            ? null
            : () => _apply(() => _game.submitGuess(_guess.text)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // As large as "עוד אפשר לנצח" below it, in the caught pink.
          Text(
            context.l10n.youreCaught(impostor.name),
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineLarge
                ?.copyWith(color: const Color(0xFFFF9B9B)),
          ),
          const SizedBox(height: 10),
          const Illustration('assets/illustrations/role-impostor.webp',
              height: 140),
          const SizedBox(height: 12),
          Text(
            context.l10n.stillCanWin,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.guessWinsLocal,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.45),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _guess,
            textAlign: TextAlign.start,
            style: const TextStyle(
              color: AppColors.night,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(hintText: context.l10n.whatsTheWord),
            onChanged: (_) => setState(() {}),
          ),
          // Not "the guess is not shown while typing": that is the online
          // screen, where everyone has a phone. Here only the impostor looks.
          const SizedBox(height: 10),
          Text(
            context.l10n.onlyPlayerLookingNoDot(impostor.name),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ---- the end -----------------------------------------------------------

  /// A one-device match only reaches its result by being played to a winner,
  /// so the interstitial always follows it (L20, L21) — after the full result,
  /// once the players chose to go on. Leaving mid-match never reaches here.
  Future<void> _afterMatch() async {
    if (!mounted) return;
    await MonetizationScope.maybeRead(context)?.afterCompletedMatch();
  }

  /// Set from the first tap on a result button until the screen is gone: a
  /// second tap while the ad is up must not navigate twice.
  bool _continuing = false;

  Widget _result() {
    final impostor = _game.players[_game.impostor];
    final winner =
        _game.outcome == LocalOutcome.citizensWin ? 'citizens' : 'impostor';
    return GameScaffold(
      title: '',
      showHeader: false,
      showBack: false,
      accent: GameResultContent.accentFor(winner),
      bottom: ResultButtons(
        onAgain: _continuing
            ? null
            : () async {
                setState(() => _continuing = true);
                final navigator = Navigator.of(context);
                await LocalStore.clear();
                await _afterMatch();
                if (!mounted) return;
                navigator.pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => LocalRulesScreen(
                      players: [
                        for (final p in _game.players)
                          LocalPlayer(name: p.name, avatar: p.avatar),
                      ],
                      initialCategoryIds: _game.categoryIds,
                      initialHintSeconds: _game.hintSeconds,
                    ),
                  ),
                );
              },
        onHome: _continuing
            ? null
            : () async {
                setState(() => _continuing = true);
                final navigator = Navigator.of(context);
                await LocalStore.clear();
                await _afterMatch();
                if (mounted) navigator.popUntil((r) => r.isFirst);
              },
      ),
      child: GameResultContent(
        winner: winner,
        title: winner == 'citizens'
            ? context.l10n.citizensWon
            : context.l10n.impostorWon,
        reason: switch (_game.endReason) {
          LocalEndReason.impostorGuessedWord => context.l10n.localReasonGuessed,
          LocalEndReason.impostorGuessWrong => context.l10n.localReasonMissed,
          LocalEndReason.impostorGuessTimeout =>
            context.l10n.reasonGuessTimeout,
          LocalEndReason.impostorParity => context.l10n.reasonParity,
          null => '',
        },
        impostorName: impostor.name,
        impostorAvatar: impostor.avatar,
        secretWord: _game.secretWord,
        impostorLabel: context.l10n.theImpostor,
        cardLabel: context.l10n.howItEnded,
        guess: _game.submittedGuess,
        rounds: _game.round,
        children: [
          if (_game.eliminations.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ResultSectionLabel(context.l10n.whoWasEliminated),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (who, round) in _game.eliminations)
                      _EliminatedChip(
                        player: _game.players[who],
                        round: round,
                        impostor: who == _game.impostor,
                      ),
                  ],
                ),
              ],
            ),
          ResultNote(
            icon: Icons.info_outline_rounded,
            color: AppColors.turquoise,
            text: context.l10n.localNoStats,
          ),
        ],
      ),
    );
  }
}

/// Design L20/L21: one voted-out player and the round they went in; the
/// impostor's chip in purple.
class _EliminatedChip extends StatelessWidget {
  const _EliminatedChip({
    required this.player,
    required this.round,
    required this.impostor,
  });

  final LocalPlayer player;
  final int round;
  final bool impostor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: impostor
            ? AppColors.purple.withValues(alpha: .16)
            : AppColors.cream.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(14),
        border: impostor
            ? Border.all(color: AppColors.purple.withValues(alpha: .45))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarView(asset: player.avatar, size: 32, eliminated: !impostor),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              context.l10n.playerRound(player.name, round),
              style: TextStyle(
                color: impostor
                    ? const Color(0xFFD9C8FF)
                    : AppColors.cream.withValues(alpha: .75),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player, this.note});

  final LocalPlayer player;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          AvatarView(
            asset: player.avatar,
            size: 30,
            eliminated: player.eliminated,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              player.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: player.eliminated ? AppColors.muted : AppColors.cream,
              ),
            ),
          ),
          if (note != null)
            Text(note!, style: const TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }
}

/// One player's ballot, kept in its own widget so the choice lives and dies
/// with the screen rather than surviving to the next player's turn.
class _Ballot extends StatefulWidget {
  const _Ballot({
    required this.game,
    required this.voter,
    required this.runoff,
    required this.onConfirm,
    required this.onHidden,
  });

  final LocalGame game;
  final int voter;
  final bool runoff;
  final ValueChanged<int> onConfirm;
  final VoidCallback onHidden;

  @override
  State<_Ballot> createState() => _BallotState();
}

class _BallotState extends State<_Ballot> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    if (game.ballotSaved) {
      final voted = game.seat + 1;
      return GameScaffold(
        title: '',
        showHeader: false,
        accent: const Color(0xFF14514A),
        bottom: PrimaryButton(
          label: context.l10n.hiddenNextPlayer,
          variant: ButtonVariant.confirm,
          onPressed: widget.onHidden,
        ),
        child: Column(
          children: [
            const SizedBox(height: 30),
            Text(
              context.l10n.votedOf(voted, game.activePlayers.length),
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            const Icon(Icons.check_circle_rounded,
                color: AppColors.turquoise, size: 78),
            const SizedBox(height: 16),
            Text(
              context.l10n.voteSaved,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.choiceHidden,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.45),
            ),
          ],
        ),
      );
    }

    final candidates =
        widget.runoff ? game.runoffCandidates : game.activePlayers;
    final me = game.players[widget.voter];
    return GameScaffold(
      title: widget.runoff ? context.l10n.tie : context.l10n.whoIsImpostor,
      showBack: false,
      accent: const Color(0xFF42203C),
      bottom: PrimaryButton(
        label: context.l10n.confirmVote,
        onPressed:
            _selected == null ? null : () => widget.onConfirm(_selected!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.runoff
                ? context.l10n.votingAgainSecret(me.name)
                : context.l10n.votingSecret(me.name),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          for (final i in candidates)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PlayerCard(
                player: Player(
                  nickname: game.players[i].name,
                  avatar: game.players[i].avatar,
                ),
                note: widget.runoff && game.previousVotes[i] != null
                    ? context.l10n.nVotesPrevious(game.previousVotes[i]!)
                    : i == widget.voter
                        ? context.l10n.cantVoteSelf
                        : null,
                secondaryNote: widget.runoff && i == widget.voter
                    ? context.l10n.cantVoteSelf
                    : null,
                enabled: i != widget.voter,
                selected: _selected == i,
                onTap: i == widget.voter
                    ? null
                    : () => setState(() => _selected = i),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            widget.runoff
                ? context.l10n.ifTieAgain
                : context.l10n.screenClearsNext,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// The tie announcement, in both its forms (design 15ב and 15ג).
///
/// It carries totals and names only. Who voted for whom stays on the ballot
/// that cast it — this is the one tie screen the whole table reads together.
class _TieAnnouncement extends StatelessWidget {
  const _TieAnnouncement({
    required this.game,
    required this.title,
    required this.subtitle,
    required this.explanation,
    required this.action,
    required this.onExit,
    required this.onContinue,
    this.footnote,
  });

  final LocalGame game;
  final String title;
  final String subtitle;
  final String explanation;
  final String action;
  final String? footnote;
  final VoidCallback onExit;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: title,
      onExit: onExit,
      accent: const Color(0xFF42203C),
      bottom: PrimaryButton(label: action, onPressed: onContinue),
      child: TieAnnouncementContent(
        subtitle: subtitle,
        explanation: explanation,
        footnote: footnote,
        candidates: [
          for (final i in game.tieCandidates)
            (
              game.players[i].name,
              game.players[i].avatar,
              // "1 vote", as online: never "1 votes".
              game.tiedVotes == 1
                  ? context.l10n.oneVote
                  : context.l10n.nVotes(game.tiedVotes),
            ),
        ],
      ),
    );
  }
}

/// A row of design L18: an active player, or a watcher behind a dashed line.
class _RoundPlayerRow extends StatelessWidget {
  const _RoundPlayerRow({
    required this.player,
    this.watching = false,
    this.note,
  });

  final LocalPlayer player;
  final bool watching;

  /// The pill's text; watchers always read "צופה". None, no pill.
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.cream.withValues(alpha: watching ? .035 : .07),
        borderRadius: BorderRadius.circular(18),
        border: watching
            ? Border.all(color: AppColors.cream.withValues(alpha: .16))
            : null,
      ),
      child: Row(
        children: [
          AvatarView(asset: player.avatar, size: 44, eliminated: watching),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              player.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: watching
                    ? AppColors.cream.withValues(alpha: .5)
                    : AppColors.cream,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (watching || note != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: watching
                    ? AppColors.cream.withValues(alpha: .1)
                    : AppColors.turquoise.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (watching)
                    Icon(Icons.visibility_outlined,
                        size: 13, color: AppColors.cream.withValues(alpha: .65))
                  else
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.turquoise,
                        shape: BoxShape.circle,
                      ),
                    ),
                  const SizedBox(width: 6),
                  Text(
                    watching ? context.l10n.spectator : note!,
                    style: TextStyle(
                      color: watching
                          ? AppColors.cream.withValues(alpha: .65)
                          : AppColors.turquoise,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
