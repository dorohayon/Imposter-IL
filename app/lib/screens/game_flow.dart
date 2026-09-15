import 'dart:async';

import 'package:flutter/material.dart';

import '../demo/demo_countdown.dart';
import '../demo/demo_data.dart';
import '../models/player.dart';
import '../models/word_rules.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';

// Every game screen replaces the previous one, so the route below a game is
// always where it started: the category picker (online) or the private lobby.

void _leaveGame(BuildContext context) =>
    Navigator.of(context).popUntil((route) => route.isFirst);

void _replace(BuildContext context, Widget screen) =>
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => screen),
    );

class RoleRevealScreen extends StatelessWidget {
  const RoleRevealScreen({required this.game, super.key});

  final DemoGame game;

  void _toHints(BuildContext context) =>
      _replace(context, HintRoundScreen(game: game));

  @override
  Widget build(BuildContext context) {
    final isImpostor = game.isImpostor;
    return GameScaffold(
      title: 'המשימה שלך',
      timer: DemoCountdown(seconds: 10, onDone: () => _toHints(context)),
      onExit: () => _leaveGame(context),
      bottom: PrimaryButton(
        label: 'הבנתי',
        onPressed: () => _toHints(context),
      ),
      child: Column(
        children: [
          Illustration(
            isImpostor
                ? 'assets/illustrations/role-impostor.webp'
                : 'assets/illustrations/role-citizen.webp',
            height: 245,
          ),
          const Text(
            'קטגוריה: $demoCategory',
            style: TextStyle(
              color: AppColors.turquoise,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isImpostor ? 'אתה המתחזה' : 'המילה שלך',
            style: Theme.of(context).textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: isImpostor ? AppColors.purple : AppColors.cream,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              isImpostor ? 'המילה נשארת סודית' : demoWord,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isImpostor ? AppColors.cream : AppColors.night,
                fontSize: 32,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isImpostor
                ? 'נסה להשתלב, להבין את הרמזים ולגלות את המילה.'
                : 'תן רמז של מילה אחת בלי לחשוף את המילה הסודית.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 17,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class HintRoundScreen extends StatefulWidget {
  const HintRoundScreen({required this.game, super.key});

  final DemoGame game;

  @override
  State<HintRoundScreen> createState() => _HintRoundScreenState();
}

class _HintRoundScreenState extends State<HintRoundScreen> {
  static const reactionOptions = [
    '😂',
    '🤔',
    '🔥',
    'חשוד מאוד',
    'רמז טוב!',
    'לא הבנתי',
  ];

  final _controller = TextEditingController();
  late final List<Player> _players = widget.game.players;
  late final int _meIndex = _players.indexWhere((player) => player.isMe);

  /// Index of the player whose turn it is; players before it have sent.
  /// Demo: the round opens on the current player's turn.
  late int _turn = _meIndex;
  String _myHint = '';
  String? _error;
  final _reactions = <String>[];
  Timer? _demoTimer;

  bool get _isMyTurn => _turn == _meIndex;
  bool get _roundOver => _turn >= _players.length;

  List<Player> get _revealed => [
        for (var i = 0; i < _turn && i < _players.length; i++)
          i == _meIndex
              ? _players[i].copyWith(hint: _myHint)
              // ponytail: the demo script can't react to a typed hint, so a
              // scripted hint that repeats it is shown as not sent.
              : _players[i].copyWith(
                  hint:
                      _myHint.isNotEmpty && sameHint(_players[i].hint!, _myHint)
                          ? ''
                          : _players[i].hint,
                ),
      ];

  @override
  void dispose() {
    _demoTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final hint = _controller.text.trim();
    final words =
        hint.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
    final error = hint.isEmpty
        ? 'צריך לכתוב רמז'
        : words.length != 1
            ? 'הרמז חייב להיות מילה אחת'
            // The impostor does not know the word, so it is not checked.
            : !widget.game.isImpostor && hintContainsSecret(hint, demoWord)
                ? 'אסור לחשוף את המילה הסודית'
                : _revealed.any(
                    (player) =>
                        player.hint!.isNotEmpty && sameHint(player.hint!, hint),
                  )
                    ? 'כבר השתמשו ברמז הזה'
                    : null;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    _myHint = hint;
    _nextTurn();
  }

  void _nextTurn() {
    setState(() {
      _turn++;
      _error = null;
      _reactions.clear();
    });
    _demoTimer?.cancel();
    _demoTimer = Timer(demoTurnDelay, () {
      if (!mounted) return;
      if (_roundOver) {
        _replace(
          context,
          VotingScreen(game: widget.game, players: _revealed),
        );
      } else {
        _nextTurn();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final revealed = _revealed;
    return GameScaffold(
      title: 'קטגוריה: $demoCategory',
      timer: _roundOver
          ? null
          : DemoCountdown(
              key: ValueKey(_turn),
              seconds: widget.game.hintSeconds,
              // The other players' turns end on the demo script instead.
              onDone: _isMyTurn ? _nextTurn : null,
            ),
      onExit: () => _leaveGame(context),
      bottom: _isMyTurn
          ? PrimaryButton(label: 'שליחת רמז', onPressed: _submit)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The impostor sees the category only, so there is nothing to show.
          if (!widget.game.isImpostor)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => _showSecretWord(context),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('הצגת המילה'),
              ),
            ),
          const SizedBox(height: 4),
          if (_isMyTurn) ...[
            Text(
              'התור שלך',
              style: Theme.of(context).textTheme.headlineLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'רמז אחד, מילה אחת',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLength: 25,
              autofocus: true,
              textAlign: TextAlign.start,
              style: const TextStyle(
                color: AppColors.night,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                hintText: 'הרמז שלי',
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
          ] else if (_roundOver) ...[
            Text(
              'כל הרמזים נשלחו',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'עוברים להצבעה...',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
          ] else ...[
            Center(child: AvatarView(asset: _players[_turn].avatar, size: 92)),
            const SizedBox(height: 10),
            Text(
              '${_players[_turn].nickname} כותב רמז...',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 22),
          const Text(
            'הרמזים שנחשפו',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (revealed.isEmpty)
            const Text(
              'עדיין לא נשלחו רמזים',
              style: TextStyle(color: AppColors.muted),
            ),
          ...revealed.map(
            (player) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PlayerCard(player: player),
            ),
          ),
          if (revealed.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'תגובות לרמז של ${revealed.last.nickname}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: reactionOptions.map((reaction) {
                final count =
                    _reactions.where((value) => value == reaction).length;
                return ActionChip(
                  onPressed: () => setState(() => _reactions.add(reaction)),
                  avatar:
                      count == 0 ? null : CircleAvatar(child: Text('$count')),
                  label: Text(reaction),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  void _showSecretWord(BuildContext context) {
    assert(!widget.game.isImpostor, 'The impostor must never see the word');
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cream,
      showDragHandle: true,
      builder: (context) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'המילה שלך',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.night,
                ),
              ),
              SizedBox(height: 10),
              Text(
                demoWord,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: AppColors.night,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VotingScreen extends StatefulWidget {
  const VotingScreen({
    required this.game,
    required this.players,
    this.isRevote = false,
    super.key,
  });

  final DemoGame game;
  final List<Player> players;
  final bool isRevote;

  @override
  State<VotingScreen> createState() => _VotingScreenState();
}

class _VotingScreenState extends State<VotingScreen> {
  String? _selected;
  String? _confirmed;

  @override
  Widget build(BuildContext context) {
    // Demo tie for the revote: the first two other players.
    final candidates = widget.isRevote
        ? widget.players.where((player) => !player.isMe).take(2).toList()
        : widget.players;
    final isConfirmed = _selected != null && _selected == _confirmed;
    return GameScaffold(
      title: widget.isRevote ? 'הצבעה חוזרת' : 'מי המתחזה?',
      // Votes can change until time is up; the demo then says the impostor
      // was caught.
      timer: DemoCountdown(
        seconds: widget.isRevote ? 15 : 20,
        onDone: () => _replace(context, ImpostorGuessScreen(game: widget.game)),
      ),
      onExit: () => _leaveGame(context),
      bottom: PrimaryButton(
        label: isConfirmed ? 'ההצבעה נקלטה' : 'אישור הצבעה',
        onPressed: _selected == null || isConfirmed
            ? null
            : () => setState(() => _confirmed = _selected),
      ),
      child: Column(
        children: [
          const Illustration('assets/illustrations/voting.webp', height: 150),
          if (widget.isRevote)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'תיקו נוסף מעניק ניצחון למתחזה',
                style: TextStyle(
                  color: AppColors.coral,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          if (_confirmed != null)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'אפשר לשנות את הבחירה עד שהזמן נגמר',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          for (final player in candidates)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PlayerCard(
                player: player,
                enabled: !player.isMe,
                selected: _selected == player.nickname,
                onTap: () => setState(() => _selected = player.nickname),
              ),
            ),
        ],
      ),
    );
  }
}

class ImpostorGuessScreen extends StatefulWidget {
  const ImpostorGuessScreen({required this.game, super.key});

  final DemoGame game;

  @override
  State<ImpostorGuessScreen> createState() => _ImpostorGuessScreenState();
}

class _ImpostorGuessScreenState extends State<ImpostorGuessScreen> {
  final _guess = TextEditingController();

  @override
  void dispose() {
    _guess.dispose();
    super.dispose();
  }

  void _finish({required bool citizensWon}) => _replace(
        context,
        ResultScreen(game: widget.game, citizensWon: citizensWon),
      );

  @override
  Widget build(BuildContext context) {
    final isImpostor = widget.game.isImpostor;
    return GameScaffold(
      title: 'הזדמנות אחרונה',
      // No guess in time counts as a wrong guess. For citizens the demo
      // impostor never guesses right.
      timer: DemoCountdown(
        seconds: 15,
        onDone: () => _finish(citizensWon: true),
      ),
      onExit: () => _leaveGame(context),
      bottom: isImpostor
          ? PrimaryButton(
              label: 'שליחת ניחוש',
              onPressed: () => _finish(
                citizensWon: !guessMatches(_guess.text, demoWord),
              ),
            )
          : null,
      child: Column(
        children: [
          const Illustration(
            'assets/illustrations/role-impostor.webp',
            height: 230,
          ),
          Text(
            'המתחזה עדיין יכול לנצח',
            style: Theme.of(context).textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          if (isImpostor) ...[
            const Text(
              'מה הייתה המילה הסודית?',
              style: TextStyle(color: AppColors.muted, fontSize: 17),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _guess,
              textAlign: TextAlign.start,
              style: const TextStyle(
                color: AppColors.night,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
              decoration: const InputDecoration(hintText: 'הניחוש שלי'),
            ),
          ] else
            Text(
              '${widget.game.impostor} נתפס ומנסה לנחש את המילה',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 17),
            ),
        ],
      ),
    );
  }
}

class ResultScreen extends StatelessWidget {
  const ResultScreen(
      {required this.game, required this.citizensWon, super.key});

  final DemoGame game;
  final bool citizensWon;

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'תוצאות המשחק',
      showBack: false,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(
            label: 'משחק נוסף',
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _leaveGame(context),
            child: const Text('חזרה למסך הבית'),
          ),
        ],
      ),
      child: Column(
        children: [
          Illustration(
            citizensWon
                ? 'assets/illustrations/result-citizens-win.webp'
                : 'assets/illustrations/result-impostor-win.webp',
            height: 250,
          ),
          Text(
            citizensWon ? 'האזרחים ניצחו!' : 'המתחזה ניצח!',
            style: Theme.of(context).textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            citizensWon
                ? 'המתחזה נתפס ולא ניחש את המילה'
                : 'המתחזה נתפס אבל ניחש את המילה',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 17),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  ListTile(
                    title: const Text('המתחזה'),
                    trailing: Text(
                      game.impostor,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const Divider(),
                  const ListTile(
                    title: Text('המילה'),
                    trailing: Text(
                      demoWord,
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('חלוקת הקולות'),
                    trailing: Text('${game.impostor} — 4'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
