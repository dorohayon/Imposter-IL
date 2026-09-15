import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../models/player.dart';
import '../state/game_session.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';

// A private room and its games, driven entirely by the server's room.state
// and game.state snapshots. Every timer counts down to a server deadline.

const _commandErrors = {
  'not_room_host': 'רק מנהל החדר יכול לעשות את זה',
  'not_enough_players': 'צריך לפחות 4 שחקנים כדי להתחיל',
  'content_unavailable': 'השרת עדיין לא מוכן להתחלת משחקים',
  'room_in_game': 'משחק כבר מתנהל בחדר',
  'wrong_phase': 'השלב הזה כבר הסתיים',
  'not_your_turn': 'זה לא התור שלך',
  'hint_empty': 'צריך לכתוב רמז',
  'hint_not_one_word': 'הרמז חייב להיות מילה אחת',
  'hint_too_long': 'הרמז ארוך מדי',
  'hint_inappropriate': 'הרמז הזה לא מתאים. נסו מילה אחרת.',
  'hint_contains_secret': 'אסור לחשוף את המילה הסודית',
  'hint_duplicate': 'כבר השתמשו ברמז הזה',
  'self_vote': 'אי אפשר להצביע לעצמך',
  'invalid_vote_target': 'אי אפשר להצביע לשחקן הזה',
  'network_error': 'אין חיבור לשרת. בדקו את החיבור ונסו שוב.',
};

String commandMessage(String code) =>
    _commandErrors[code] ?? 'משהו השתבש. נסו שוב.';

/// Sends a command and shows its error, if any, as a snack bar.
Future<void> runCommand(BuildContext context, Future<String?> command) async {
  final messenger = ScaffoldMessenger.of(context);
  final code = await command;
  if (code != null) {
    messenger.showSnackBar(SnackBar(content: Text(commandMessage(code))));
  }
}

Player _player(PlayerInfo info, String? me, {String? hint}) => Player(
      nickname: info.nickname,
      avatar: info.avatarAsset,
      hint: hint,
      isMe: info.id == me,
      isDisconnected: !info.connected,
    );

/// Counts down to a server deadline in the top-left timer circle.
class LiveCountdown extends StatefulWidget {
  const LiveCountdown({required this.deadline, super.key});

  final DateTime deadline;

  @override
  State<LiveCountdown> createState() => _LiveCountdownState();
}

class _LiveCountdownState extends State<LiveCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left =
        widget.deadline.difference(SessionScope.read(context).serverNow);
    final seconds = (left.inMilliseconds / 1000).ceil();
    return TimerBadge(seconds: seconds < 0 ? 0 : seconds);
  }
}

class LiveRoomScreen extends StatefulWidget {
  const LiveRoomScreen({super.key});

  @override
  State<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends State<LiveRoomScreen> {
  bool _leaving = false;

  void _goHome() {
    if (_leaving || !mounted) return;
    _leaving = true;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _leaveRoom() {
    final session = SessionScope.read(context);
    _goHome();
    unawaited(session.leaveRoom());
  }

  void _leaveGame() {
    final session = SessionScope.read(context);
    _goHome();
    unawaited(session.leaveGame());
  }

  /// Back to the category picker, which opened the search.
  void _backToCategories() {
    if (_leaving || !mounted) return;
    _leaving = true;
    Navigator.of(context).pop();
  }

  void _cancelSearch() {
    final session = SessionScope.read(context);
    _backToCategories();
    unawaited(session.cancelSearch());
  }

  void _afterFrame(VoidCallback action) =>
      WidgetsBinding.instance.addPostFrameCallback((_) => action());

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);

    if (session.sessionLost) {
      return _ServerError(
        onHome: () {
          session.dismissSessionLost();
          _goHome();
        },
      );
    }
    final noMatch = session.noMatchCategories;
    if (noMatch != null) {
      return _NoMatch(
        onCategories: () {
          session.dismissNoMatch();
          _backToCategories();
        },
        onRetry: () async {
          final messenger = ScaffoldMessenger.of(context);
          final code = await session.startSearch(noMatch);
          if (code != null) {
            messenger.showSnackBar(
              SnackBar(content: Text(commandMessage(code))),
            );
          }
        },
      );
    }
    if (session.kicked) {
      _afterFrame(() {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('מנהל החדר הוציא אותך מהחדר')),
        );
        session.consumeKicked();
        _goHome();
      });
    } else if (session.activity == 'none') {
      _afterFrame(_goHome); // the room is gone, for example after leaving
    }

    final game = session.game;
    final room = session.room;
    final search = session.search;
    final inGame = session.activity == 'game' && game != null;
    final searching = session.activity == 'matchmaking';
    final Widget body = inGame
        ? _LiveGame(game: game, onLeave: _leaveGame)
        : searching && search != null
            ? _Search(search: search, onCancel: _cancelSearch)
            : !searching && room != null
                ? _Lobby(room: room, onLeave: _leaveRoom)
                : const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (inGame) {
          _leaveGame();
        } else if (searching) {
          _cancelSearch();
        } else {
          _leaveRoom();
        }
      },
      child: Stack(
        children: [
          body,
          if (!session.connected) const _ReconnectingBanner(),
        ],
      ),
    );
  }
}

class _ReconnectingBanner extends StatelessWidget {
  const _ReconnectingBanner();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Material(
          color: AppColors.purple,
          borderRadius: BorderRadius.circular(18),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.cream,
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  'מתחברים מחדש...',
                  style: TextStyle(
                    color: AppColors.cream,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Search extends StatelessWidget {
  const _Search({required this.search, required this.onCancel});

  final MatchmakingView search;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final count = search.players.length;
    final status = switch (search.status) {
      'waiting_for_more' => 'נמצאו $count! מחכים עד 30 שניות לשחקנים נוספים',
      'countdown' => 'המשחק מתחיל בעוד רגע!',
      _ => 'צריך לפחות 4 שחקנים כדי להתחיל',
    };
    return GameScaffold(
      title: 'מחפשים שחקנים',
      timer: search.deadline == null
          ? null
          : LiveCountdown(deadline: search.deadline!),
      onExit: onCancel,
      bottom:
          PrimaryButton(label: 'ביטול', secondary: true, onPressed: onCancel),
      child: Column(
        children: [
          const Illustration(
            'assets/illustrations/matchmaking-team.webp',
            height: 180,
          ),
          Text(
            '$count מתוך ${search.maxPlayers}',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 6),
          Text(
            status,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 16),
          ),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: search.maxPlayers,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisExtent: 112,
              mainAxisSpacing: 12,
              crossAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              if (index >= count) {
                return Column(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF5C586E),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.search_rounded,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'מחפשים...',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                );
              }
              final player = search.players[index];
              return Column(
                children: [
                  AvatarView(asset: player.avatarAsset, size: 60),
                  const SizedBox(height: 7),
                  Text(
                    player.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.onCategories, required this.onRetry});

  final VoidCallback onCategories;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _StateMessage(
      title: 'לא נמצא משחק מתאים',
      body: 'אפשר לבחור קטגוריות אחרות או לנסות שוב.',
      image: 'assets/illustrations/no-category-match.webp',
      primary: ('בחירת קטגוריות מחדש', onCategories),
      secondary: ('ניסיון נוסף', onRetry),
    );
  }
}

class _Lobby extends StatelessWidget {
  const _Lobby({required this.room, required this.onLeave});

  final RoomView room;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final me = session.playerId;
    final host = room.player(room.hostId);
    final iAmHost = room.hostId != null && room.hostId == me;
    final transfer = room.hostTransfer;
    final categoryNames = [
      for (final c in session.categories)
        if (room.categoryIds.contains(c.id)) c.name,
    ].join(', ');

    return GameScaffold(
      title: host == null ? 'חדר פרטי' : 'החדר של ${host.nickname}',
      onBack: onLeave,
      timer: room.hostReconnectDeadline == null
          ? null
          : LiveCountdown(deadline: room.hostReconnectDeadline!),
      bottom: PrimaryButton(
        label: iAmHost ? 'התחלת משחק' : 'רק מנהל החדר יכול להתחיל',
        onPressed: iAmHost && room.players.length >= 4
            ? () => runCommand(
                  context,
                  session.send('room.start', {'roomId': room.id}),
                )
            : null,
      ),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'קוד החדר',
                          style: TextStyle(color: AppColors.muted),
                        ),
                        Text(
                          room.code,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'העתקת הקוד',
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: room.code));
                      messenger.showSnackBar(
                        const SnackBar(content: Text('קוד החדר הועתק')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                  ),
                ],
              ),
            ),
          ),
          if (room.hostReconnectDeadline != null)
            const _Notice('מנהל החדר התנתק. ממתינים שיחזור.'),
          if (host == null)
            const _Notice('ממתינים ששחקן נוסף יתחבר וינהל את החדר.'),
          if (transfer != null && host != null)
            _Notice(
              transfer.to == me
                  ? 'הניהול עבר אליך'
                  : 'הניהול עבר ל${host.nickname}',
            ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              '${room.players.length} מתוך ${room.maxPlayers} שחקנים',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          if (iAmHost && room.players.length < 4)
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'צריך לפחות 4 שחקנים כדי להתחיל',
                style: TextStyle(
                  color: AppColors.coral,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 8),
          for (final p in room.players)
            Card(
              child: ListTile(
                leading: AvatarView(
                  asset: p.avatarAsset,
                  size: 52,
                  disconnected: !p.connected,
                ),
                title: Text(
                  p.nickname,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: p.id == room.hostId || p.id == me || !p.connected
                    ? Text(
                        [
                          if (p.id == room.hostId) 'מנהל החדר',
                          if (p.id == me) 'אני',
                          if (!p.connected) 'מנותק',
                        ].join(' · '),
                      )
                    : null,
                trailing: iAmHost && p.id != me
                    ? IconButton(
                        tooltip: 'הסרת ${p.nickname}',
                        onPressed: () => runCommand(
                          context,
                          session.send(
                            'room.kick',
                            {'roomId': room.id, 'playerId': p.id},
                          ),
                        ),
                        icon: const Icon(
                          Icons.person_remove_rounded,
                          color: AppColors.coral,
                        ),
                      )
                    : null,
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                children: [
                  Text('קטגוריות: $categoryNames'),
                  Text('${room.hintSeconds} שניות לרמז'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.yellow,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LiveGame extends StatelessWidget {
  const _LiveGame({required this.game, required this.onLeave});

  final GameView game;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final me = game.player(SessionScope.of(context).playerId);
    if (me?.status == 'removed') return _Removed(onHome: onLeave);
    return switch (game.phase) {
      'role_reveal' => _RoleReveal(game: game, onLeave: onLeave),
      'hints' => _Hints(game: game, onLeave: onLeave),
      'voting' || 'runoff_voting' => _Voting(game: game, onLeave: onLeave),
      'impostor_guess' => _Guess(game: game, onLeave: onLeave),
      _ => _Result(game: game, onHome: onLeave),
    };
  }
}

Widget? _timer(GameView game) =>
    game.deadline == null ? null : LiveCountdown(deadline: game.deadline!);

class _RoleReveal extends StatelessWidget {
  const _RoleReveal({required this.game, required this.onLeave});

  final GameView game;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final confirmed = game.player(session.playerId)?.roleConfirmed ?? false;
    final impostor = game.isImpostor;
    return GameScaffold(
      title: 'המשימה שלך',
      timer: _timer(game),
      onExit: onLeave,
      bottom: PrimaryButton(
        label: confirmed ? 'ממתינים לשאר השחקנים' : 'הבנתי',
        onPressed: confirmed
            ? null
            : () => runCommand(
                  context,
                  session.send('game.confirmRole', {'gameId': game.id}),
                ),
      ),
      child: Column(
        children: [
          Illustration(
            impostor
                ? 'assets/illustrations/role-impostor.webp'
                : 'assets/illustrations/role-citizen.webp',
            height: 245,
          ),
          Text(
            'קטגוריה: ${game.category}',
            style: const TextStyle(
              color: AppColors.turquoise,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            impostor ? 'אתה המתחזה' : 'המילה שלך',
            style: Theme.of(context).textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: impostor ? AppColors.purple : AppColors.cream,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              impostor ? 'המילה נשארת סודית' : game.secretWord ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: impostor ? AppColors.cream : AppColors.night,
                fontSize: 32,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            impostor
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

class _Hints extends StatefulWidget {
  const _Hints({required this.game, required this.onLeave});

  final GameView game;
  final VoidCallback onLeave;

  @override
  State<_Hints> createState() => _HintsState();
}

class _HintsState extends State<_Hints> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void didUpdateWidget(_Hints old) {
    super.didUpdateWidget(old);
    if (old.game.currentTurnPlayerId != widget.game.currentTurnPlayerId) {
      _error = null;
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final session = SessionScope.read(context);
    setState(() => _busy = true);
    final code = await session.send(
      'game.submitHint',
      {'gameId': widget.game.id, 'text': _controller.text},
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = code == null ? null : commandMessage(code);
    });
  }

  void _showSecretWord(String word) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cream,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'המילה שלך',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.night,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                word,
                style: const TextStyle(
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

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final game = widget.game;
    final me = session.playerId;
    final myTurn = game.currentTurnPlayerId == me;
    final current = game.player(game.currentTurnPlayerId);
    final word = game.secretWord;
    final lastHint = game.hints.isEmpty ? null : game.hints.last;

    return GameScaffold(
      title: 'קטגוריה: ${game.category}',
      timer: _timer(game),
      onExit: widget.onLeave,
      bottom: myTurn
          ? PrimaryButton(
              label: 'שליחת רמז',
              onPressed: _busy ? null : _submit,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The impostor never receives the word, so there is nothing to show.
          if (!game.isImpostor && word != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => _showSecretWord(word),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('הצגת המילה'),
              ),
            ),
          const SizedBox(height: 4),
          if (myTurn) ...[
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
              decoration:
                  InputDecoration(hintText: 'הרמז שלי', errorText: _error),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
          ] else if (current != null) ...[
            Center(
              child: AvatarView(
                asset: current.avatarAsset,
                size: 92,
                disconnected: !current.connected,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              game.awaitingReconnect
                  ? '${current.nickname} התנתק. ממתינים שיחזור...'
                  : '${current.nickname} כותב רמז...',
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
          if (game.hints.isEmpty)
            const Text(
              'עדיין לא נשלחו רמזים',
              style: TextStyle(color: AppColors.muted),
            ),
          for (final h in game.hints)
            if (game.player(h.playerId) case final p?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PlayerCard(
                  player: _player(p, me, hint: h.missing ? '' : h.text),
                ),
              ),
          if (lastHint != null && !lastHint.missing) ...[
            const SizedBox(height: 10),
            Text(
              'תגובות לרמז של ${game.player(lastHint.playerId)?.nickname ?? ''}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in session.reactions)
                  ActionChip(
                    onPressed: () => runCommand(
                      context,
                      session.send('game.react', {
                        'gameId': game.id,
                        'hintIndex': game.hints.length - 1,
                        'reactionId': r.id,
                      }),
                    ),
                    avatar: (lastHint.reactions[r.id] ?? 0) == 0
                        ? null
                        : CircleAvatar(
                            child: Text('${lastHint.reactions[r.id]}'),
                          ),
                    label: Text(r.text),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Voting extends StatefulWidget {
  const _Voting({required this.game, required this.onLeave});

  final GameView game;
  final VoidCallback onLeave;

  @override
  State<_Voting> createState() => _VotingState();
}

class _VotingState extends State<_Voting> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final game = widget.game;
    final me = session.playerId;
    final selected = _selected ?? game.myVote;
    final isConfirmed = selected != null && selected == game.myVote;
    final runoff = game.phase == 'runoff_voting';

    return GameScaffold(
      title: runoff ? 'הצבעה חוזרת' : 'מי המתחזה?',
      timer: _timer(game),
      onExit: widget.onLeave,
      bottom: PrimaryButton(
        label: isConfirmed ? 'ההצבעה נקלטה' : 'אישור הצבעה',
        onPressed: selected == null || isConfirmed
            ? null
            : () => runCommand(
                  context,
                  session.send(
                    'game.vote',
                    {'gameId': game.id, 'targetPlayerId': selected},
                  ),
                ),
      ),
      child: Column(
        children: [
          const Illustration('assets/illustrations/voting.webp', height: 150),
          if (runoff)
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
          if (game.myVote != null)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'אפשר לשנות את הבחירה עד שהזמן נגמר',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          for (final id in game.voteCandidates)
            if (game.player(id) case final p?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PlayerCard(
                  player: _player(
                    p,
                    me,
                    hint: switch (game.hintOf(id)) {
                      null => null,
                      final h => h.missing ? '' : h.text,
                    },
                  ),
                  enabled: id != me,
                  selected: selected == id,
                  onTap: () => setState(() => _selected = id),
                ),
              ),
        ],
      ),
    );
  }
}

class _Guess extends StatefulWidget {
  const _Guess({required this.game, required this.onLeave});

  final GameView game;
  final VoidCallback onLeave;

  @override
  State<_Guess> createState() => _GuessState();
}

class _GuessState extends State<_Guess> {
  final _guess = TextEditingController();

  @override
  void dispose() {
    _guess.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final game = widget.game;
    return GameScaffold(
      title: 'הזדמנות אחרונה',
      timer: _timer(game),
      onExit: widget.onLeave,
      bottom: game.isImpostor
          ? PrimaryButton(
              label: 'שליחת ניחוש',
              onPressed: () => runCommand(
                context,
                session.send(
                  'game.submitGuess',
                  {'gameId': game.id, 'text': _guess.text},
                ),
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
          if (game.isImpostor) ...[
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
            const Text(
              'המתחזה נתפס ומנסה לנחש את המילה',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 17),
            ),
        ],
      ),
    );
  }
}

const _resultReasons = {
  'impostor_not_caught': 'המתחזה לא נתפס בהצבעה',
  'second_tie': 'גם ההצבעה החוזרת נגמרה בתיקו',
  'impostor_guessed_word': 'המתחזה נתפס אבל ניחש את המילה',
  'impostor_guess_wrong': 'המתחזה נתפס ולא ניחש את המילה',
  'impostor_guess_timeout': 'המתחזה נתפס ולא הספיק לנחש',
  'impostor_gone': 'המתחזה יצא מהמשחק',
  'not_enough_players': 'לא נשארו מספיק שחקנים כדי להמשיך',
};

class _Result extends StatelessWidget {
  const _Result({required this.game, required this.onHome});

  final GameView game;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final result = game.result;
    if (result == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final stopped = result.winner == null;
    final citizensWon = result.winner == 'citizens';
    final outcome = result.outcomes[session.playerId];
    final votes = <String, int>{};
    for (final target in (result.voteRounds.isEmpty
        ? const <String>[]
        : result.voteRounds.last.values)) {
      votes[target] = (votes[target] ?? 0) + 1;
    }
    final impostor = game.player(result.impostorId);

    return GameScaffold(
      title: 'תוצאות המשחק',
      showBack: false,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(
            label: 'משחק נוסף',
            onPressed: () => runCommand(
              context,
              session.send('game.playAgain', {'gameId': game.id}),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onHome, child: const Text('חזרה למסך הבית')),
        ],
      ),
      child: Column(
        children: [
          Illustration(
            stopped
                ? 'assets/illustrations/connection-error.webp'
                : citizensWon
                    ? 'assets/illustrations/result-citizens-win.webp'
                    : 'assets/illustrations/result-impostor-win.webp',
            height: 250,
          ),
          Text(
            stopped
                ? 'המשחק הופסק'
                : citizensWon
                    ? 'האזרחים ניצחו!'
                    : 'המתחזה ניצח!',
            style: Theme.of(context).textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            _resultReasons[result.reason] ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 17),
          ),
          if (outcome != null) ...[
            const SizedBox(height: 10),
            Chip(label: Text(outcome == 'win' ? 'ניצחת' : 'הפסדת')),
          ],
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  ListTile(
                    title: const Text('המתחזה'),
                    trailing: Text(
                      impostor?.nickname ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('המילה'),
                    trailing: Text(
                      result.secretWord,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (votes.isNotEmpty) ...[
                    const Divider(),
                    const ListTile(title: Text('חלוקת הקולות')),
                    for (final entry in votes.entries)
                      ListTile(
                        dense: true,
                        title: Text(game.player(entry.key)?.nickname ?? ''),
                        trailing: Text('${entry.value}'),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Removed extends StatelessWidget {
  const _Removed({required this.onHome});

  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return _StateMessage(
      title: 'הוצאת מהמשחק',
      body: 'זה היה הניתוק השלישי ונרשם הפסד.',
      primary: ('חזרה למסך הבית', onHome),
    );
  }
}

class _ServerError extends StatelessWidget {
  const _ServerError({required this.onHome});

  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return _StateMessage(
      title: 'משהו השתבש',
      body: 'המשחק הופסק עקב תקלה בחיבור לשרת. לא נרשם הפסד.',
      primary: ('חזרה למסך הבית', onHome),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.title,
    required this.body,
    required this.primary,
    this.secondary,
    this.image = 'assets/illustrations/connection-error.webp',
  });

  final String title;
  final String body;
  final String image;
  final (String, VoidCallback) primary;
  final (String, VoidCallback)? secondary;

  @override
  Widget build(BuildContext context) {
    final secondary = this.secondary;
    return GameScaffold(
      title: title,
      showBack: false,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(label: primary.$1, onPressed: primary.$2),
          if (secondary != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: secondary.$2, child: Text(secondary.$1)),
          ],
        ],
      ),
      child: Column(
        children: [
          Illustration(image, height: 260),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            body,
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
