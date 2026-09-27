import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/player.dart';
import '../monetization/monetization.dart';
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
    this.resumed,
    super.key,
  });

  final List<LocalPlayer>? players;
  final List<String>? categoryIds;
  final int? hintSeconds;

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
        );
    unawaited(LocalStore.save(_game));
    _syncTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _guess.dispose();
    super.dispose();
  }

  /// Every move is written down before the screen changes: the phone is the
  /// only copy of this match.
  void _apply(void Function() move) {
    setState(move);
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
      if (_game.phase == LocalPhase.ended) {
        unawaited(LocalStore.clear());
      } else {
        unawaited(LocalStore.save(_game));
      }
      if (_game.phase != phase || !_timerShouldRun) _syncTimer();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncTimer();
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
    // A translucent dialog must never leave a role, ballot or typed guess
    // readable underneath it. Cancelling intentionally returns to the neutral
    // handoff screen, so only the intended player can reveal it again.
    if (_game.revealed) {
      setState(_game.hidePrivateContent);
      _syncTimer();
      unawaited(LocalStore.save(_game));
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.nightRaised,
        title: const Text('לצאת מהמשחק?'),
        content: const Text(
          'המשחק הנוכחי יימחק ולא יהיה אפשר להמשיך אותו.',
          style: TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('המשך משחק'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('יציאה ומחיקה',
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
            ? 'אני ${_current.name} — להצבעה'
            : 'אני ${_current.name} — הציגו לי',
        onPressed: () => _apply(_game.reveal),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Text(
            forVoting
                ? 'הצביעו $done מתוך ${_game.activePlayers.length}'
                : '${done + 1} מתוך ${_game.players.length}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          const Illustration('assets/illustrations/pass-the-device.webp',
              height: 180),
          const SizedBox(height: 16),
          Text(
            'העבירו את המכשיר ל${_current.name}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            forVoting
                ? 'אף אחד אחר לא מסתכל על המסך.'
                : 'רק ${_current.name} מסתכל/ת על המסך.',
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
        label: 'אני ${impostor.name} — הציגו לי',
        onPressed: () => _apply(_game.reveal),
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          const Illustration('assets/illustrations/pass-the-device.webp',
              height: 180),
          const SizedBox(height: 16),
          Text(
            'העבירו את המכשיר ל${impostor.name}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'רק ${impostor.name} מסתכל/ת על המסך.',
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
        label: 'הבנתי — הסתירו',
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
            impostor ? 'את/ה המתחזה' : 'את/ה אזרח/ית',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: impostor ? AppColors.yellow : AppColors.cream,
                ),
          ),
          const SizedBox(height: 12),
          SecretWordCard(word: _game.secretWord, impostor: impostor),
          if (!impostor) ...[
            const SizedBox(height: 12),
            const Text(
              'המתחזה לא יודע את המילה הסודית. שמרו עליה בסוד.',
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
                  ? const [
                      'הקשיבו לרמזים, השתלבו ונסו לגלות את המילה.',
                      'אם תיתפסו — תקבלו הזדמנות אחת לנחש את המילה ולנצח.',
                    ]
                  : const [
                      'בתור שלכם אומרים בקול רמז של מילה אחת.',
                      'רמז ברור מדי יעזור למתחזה. רמז דק מדי יעורר חשד.',
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
        label:
            _game.round == 1 ? 'מתחילים סיבוב 1' : 'התחלת סיבוב ${_game.round}',
        onPressed: () => _apply(_game.startRound),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Illustration('assets/illustrations/local-one-device.webp',
              height: 140),
          const SizedBox(height: 12),
          Text(
            _game.round == 1 ? 'כולם יודעים מי הם' : 'סיבוב נוסף',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            _game.round == 1
                ? 'מניחים את המכשיר במקום שכולם רואים.'
                : 'המתחזה עדיין ביניכם. סדר התורות הוגרל מחדש.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, height: 1.45),
          ),
          const SizedBox(height: 16),
          InfoCard(
            label: 'סדר התורות בסיבוב זה',
            child: Column(
              children: [
                for (final i in _game.turnOrder)
                  _PlayerRow(
                    player: _game.players[i],
                    note: i == _game.turnOrder.first ? 'מתחיל/ה' : null,
                  ),
                for (final i in _game.eliminatedSeats)
                  _PlayerRow(player: _game.players[i], note: 'צופה'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            first.name.isEmpty ? '' : '',
            style: const TextStyle(fontSize: 0),
          ),
          const Text(
            'רמז של מילה אחת, בלי לחזור על רמז קודם ובלי לומר את המילה עצמה.',
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
        label: 'התחלת סיבוב ${_game.round}',
        onPressed: () => _apply(_game.startRound),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Text(
            'סיבוב נוסף',
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
            'המתחזה עדיין ביניכם. סדר התורות הוגרל מחדש.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.cream.withValues(alpha: .68),
              fontSize: 15,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'סדר התורות בסיבוב זה',
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
              note: i == _game.turnOrder.first ? 'מתחיל/ה' : null,
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
                    'רמז של מילה אחת, בלי לחזור על רמז קודם ובלי לומר את המילה עצמה.',
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
      title: 'סיבוב ${_game.round} · ${_game.category}',
      onExit: _leave,
      timer: _game.hintSeconds == null
          ? const Icon(Icons.timer_off_outlined, color: AppColors.muted)
          : TimerBadge(
              seconds: _game.secondsRemaining ?? _game.hintSeconds!,
              remaining: (_game.secondsRemaining ?? _game.hintSeconds!) /
                  _game.hintSeconds!,
            ),
      bottom: PrimaryButton(
        label: 'הרמז נאמר',
        variant: ButtonVariant.confirm,
        onPressed: () => _apply(() => _game.hintSpoken(speakerSeat)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: AvatarView(asset: speaker.avatar, size: 96)),
          const SizedBox(height: 12),
          Text(
            'התור של ${speaker.name}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            'אומרים בקול רמז של מילה אחת',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 15),
          ),
          const SizedBox(height: 16),
          InfoCard(
            label: 'סדר התורות',
            child: Column(
              children: [
                for (final (i, seat) in _game.turnOrder.indexed)
                  _PlayerRow(
                    player: _game.players[seat],
                    note: switch (i) {
                      _ when i == _game.seat => 'עכשיו',
                      _ when i == _game.seat + 1 => 'הבא בתור',
                      _
                          when i < _game.seat &&
                              _game.missedHintSeats.contains(seat) =>
                        'לא נאמר רמז',
                      _ when i < _game.seat => 'אמר/ה',
                      _ => 'ממתין/ה',
                    },
                  ),
                for (final i in _game.eliminatedSeats)
                  _PlayerRow(player: _game.players[i], note: 'צופה'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'הרמזים נאמרים בקול — אין הקלדה ואין לוח רמזים.',
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
      note: 'מעבירים את המכשיר בין השחקנים. אל תגלו למי הצבעתם.',
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
        title: 'יש תיקו',
        subtitle: '${_game.tieCandidates.length} מועמדים קיבלו '
            '${_game.tiedVotes} קולות',
        explanation:
            'היה תיקו. מצביעים שוב רק בין השחקנים שקיבלו את מספר הקולות הגבוה. תיקו נוסף — איש לא מודח והמשחק ממשיך לסבב נוסף.',
        action: 'מתחילים הצבעה חוזרת',
        footnote: 'אחר כך מעבירים את המכשיר לשחקן הבא',
        onExit: _leave,
        onContinue: () => _apply(_game.startRunoff),
      );

  /// Design 15ג. A runoff that tied as well: nobody goes, and saying so is the
  /// difference between a rule and a round that looks like nothing happened.
  Widget _tieAgain() => _TieAnnouncement(
        game: _game,
        title: 'שוב יש תיקו',
        subtitle: 'גם הפעם הקולות התחלקו שווה בשווה',
        explanation: 'איש לא הודח. ממשיכים לסבב רמזים נוסף.',
        action: 'ממשיכים לסבב הבא',
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
        label: 'ממשיכים לסיבוב ${_game.round + 1}',
        onPressed: () => _apply(_game.afterElimination),
      ),
      child: EliminationRevealContent(
        eliminatedName: out.name,
        eliminatedAvatar: out.avatar,
        roleLine: '${out.name} היה/הייתה אזרח/ית',
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
      title: '${impostor.name}, נתפסת',
      showHeader: true,
      onExit: _leave,
      timer: TimerBadge(
        seconds: _game.secondsRemaining ?? LocalGame.guessSeconds,
        remaining: (_game.secondsRemaining ?? LocalGame.guessSeconds) /
            LocalGame.guessSeconds,
      ),
      accent: const Color(0xFF4A2A8C),
      bottom: PrimaryButton(
        label: 'שליחת ניחוש',
        onPressed: _guess.text.trim().isEmpty
            ? null
            : () => _apply(() => _game.submitGuess(_guess.text)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Illustration('assets/illustrations/role-impostor.webp',
              height: 140),
          const SizedBox(height: 12),
          Text(
            'עוד אפשר לנצח',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'ניחוש נכון של המילה הסודית מעניק לך את הניצחון. יש ניסיון אחד.',
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
            decoration: const InputDecoration(hintText: 'מה המילה?'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          const Text(
            'הניחוש לא מוצג לשחקנים בזמן ההקלדה',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Text(
            'רק ${impostor.name} מסתכל/ת על המסך',
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
        title: winner == 'citizens' ? 'האזרחים ניצחו!' : 'המתחזה ניצח!',
        reason: switch (_game.endReason) {
          LocalEndReason.impostorGuessedWord =>
            'המתחזה נתפס וניחש נכון את המילה.',
          LocalEndReason.impostorGuessWrong => 'המתחזה נתפס ולא ניחש את המילה.',
          LocalEndReason.impostorGuessTimeout =>
            'המתחזה נתפס, אבל הזמן לניחוש נגמר.',
          LocalEndReason.impostorParity =>
            'נשארו אזרח אחד ומתחזה — ובשלב הזה המתחזה מנצח מיד.',
          null => '',
        },
        impostorName: impostor.name,
        impostorAvatar: impostor.avatar,
        secretWord: _game.secretWord,
        impostorLabel: 'המתחזה',
        cardLabel: 'איך זה נגמר',
        guess: _game.submittedGuess,
        rounds: _game.round,
        children: [
          if (_game.eliminations.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ResultSectionLabel('מי הודח במהלך המשחק'),
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
          const ResultNote(
            icon: Icons.info_outline_rounded,
            color: AppColors.turquoise,
            text: 'משחק במכשיר אחד אינו משנה את הסטטיסטיקה בפרופיל.',
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
              '${player.name} · סיבוב $round',
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
          label: 'הסתרתי — לשחקן הבא',
          variant: ButtonVariant.confirm,
          onPressed: widget.onHidden,
        ),
        child: Column(
          children: [
            const SizedBox(height: 30),
            Text(
              'הצביעו $voted מתוך ${game.activePlayers.length}',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            const Icon(Icons.check_circle_rounded,
                color: AppColors.turquoise, size: 78),
            const SizedBox(height: 16),
            Text(
              'ההצבעה נשמרה',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'הבחירה הוסתרה מהמסך. אף אחד לא יראה למי הצבעת.',
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
      title: widget.runoff ? 'יש תיקו' : 'מי המתחזה?',
      showBack: false,
      accent: const Color(0xFF42203C),
      bottom: PrimaryButton(
        label: 'אישור הצבעה',
        onPressed:
            _selected == null ? null : () => widget.onConfirm(_selected!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.runoff
                ? '${me.name} מצביע/ה שוב · הבחירה תישאר סודית'
                : '${me.name} מצביע/ה · הבחירה תישאר סודית',
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
                    ? '${game.previousVotes[i]} קולות בסבב הקודם'
                    : i == widget.voter
                        ? 'אי אפשר להצביע לעצמכם'
                        : null,
                secondaryNote: widget.runoff && i == widget.voter
                    ? 'אי אפשר להצביע לעצמכם'
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
                ? 'אם גם עכשיו יהיה תיקו — אף אחד לא יודח ומתחיל סיבוב רמזים חדש.'
                : 'אחרי האישור המסך יתנקה לפני ההעברה לשחקן הבא.',
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
              '${game.tiedVotes} קולות',
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
                    watching ? 'צופה' : note!,
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
