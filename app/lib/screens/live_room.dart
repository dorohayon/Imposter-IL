import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

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
  'not_your_turn': 'זה לא התור שלכם',
  'hint_empty': 'צריך לכתוב רמז',
  'hint_not_one_word': 'הרמז חייב להיות מילה אחת',
  'hint_too_long': 'הרמז ארוך מדי',
  'hint_inappropriate': 'הרמז הזה לא מתאים. נסו מילה אחרת.',
  'hint_contains_secret': 'אסור לחשוף את המילה הסודית',
  'hint_duplicate': 'כבר השתמשו ברמז הזה',
  'self_vote': 'אי אפשר להצביע לעצמכם',
  'invalid_vote_target': 'אי אפשר להצביע לשחקן הזה',
  'network_error': 'אין חיבור לשרת. בדקו את החיבור ונסו שוב.',
};

/// Opens the system share sheet. Tests replace it.
Future<void> Function(String text) shareText =
    (text) => SharePlus.instance.share(ShareParams(text: text));

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

  bool _leaveInFlight = false;

  /// Runs a leave command and navigates only once the server confirmed it.
  Future<void> _leaveThen(
    Future<String?> Function() leave,
    VoidCallback navigate,
  ) async {
    if (_leaveInFlight) return;
    _leaveInFlight = true;
    final messenger = ScaffoldMessenger.of(context);
    final code = await leave();
    _leaveInFlight = false;
    if (code != null) {
      messenger.showSnackBar(SnackBar(content: Text(commandMessage(code))));
      return;
    }
    navigate();
  }

  void _leaveRoom() =>
      _leaveThen(SessionScope.read(context).leaveRoom, _goHome);

  void _leaveGame() =>
      _leaveThen(SessionScope.read(context).leaveGame, _goHome);

  /// Back to the category picker, which opened the search.
  void _backToCategories() {
    if (_leaving || !mounted) return;
    _leaving = true;
    Navigator.of(context).pop();
  }

  void _cancelSearch() =>
      _leaveThen(SessionScope.read(context).cancelSearch, _backToCategories);

  GameView? _lastGame;

  /// Vibrates when a game starts, when it becomes my turn and when voting
  /// starts, if the player enabled vibration.
  void _vibrateOnChanges(GameSession session, GameView? game) {
    final previous = _lastGame;
    _lastGame = game;
    if (game == null || !session.vibrationOn) return;
    final myTurnNow = game.phase == 'hints' &&
        game.currentTurnPlayerId == session.playerId &&
        previous?.currentTurnPlayerId != session.playerId;
    final votingNow =
        (game.phase == 'voting' || game.phase == 'runoff_voting') &&
            previous?.phase != game.phase;
    if (previous?.id != game.id || myTurnNow || votingNow) {
      _afterFrame(HapticFeedback.mediumImpact);
    }
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
          const SnackBar(content: Text('מנהל החדר הוציא אתכם מהחדר')),
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
    _vibrateOnChanges(session, inGame ? game : null);
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
          if (!session.connected)
            _Reconnecting(onLeaveGame: inGame ? _leaveGame : null),
        ],
      ),
    );
  }
}

/// Screens 21 and 26: shown over the current screen while the connection is
/// down. While the server is holding the player's turn it takes the whole
/// screen with the countdown; otherwise it is a banner on top.
class _Reconnecting extends StatelessWidget {
  const _Reconnecting({required this.onLeaveGame});

  final VoidCallback? onLeaveGame;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final game = session.activity == 'game' ? session.game : null;
    final me = game?.player(session.playerId);
    final inPlay = game != null && game.phase != 'ended' && me != null;
    final deadline = session.reconnectDeadline;
    if (inPlay && deadline != null) {
      return Material(
        color: AppColors.night,
        child: GameScaffold(
          title: 'מתחברים מחדש...',
          timer: LiveCountdown(deadline: deadline),
          showBack: false,
          bottom: onLeaveGame == null
              ? null
              : PrimaryButton(
                  label: 'יציאה מהמשחק',
                  variant: ButtonVariant.danger,
                  onPressed: onLeaveGame,
                ),
          child: Column(
            children: [
              const Illustration(
                'assets/illustrations/connection-error.webp',
                height: 220,
              ),
              Text(
                'קטגוריה: ${game.category}',
                style: const TextStyle(
                  color: AppColors.turquoise,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'החיבור אבד בזמן התור שלכם. אנחנו מנסים לחזור למשחק במשך 30 שניות.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 17,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                // The server counts this drop once it notices it.
                'ניתוק ${me.disconnects + 1} מתוך 3',
                style: const TextStyle(
                  color: AppColors.cream,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'אם תחזרו — נמשיך מהתור שלכם; בניתוק השלישי תוצאו מהמשחק.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        minimum: const EdgeInsets.symmetric(horizontal: 16),
        child: Material(
          color: AppColors.purple,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.cream,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'מתחברים מחדש...',
                        style: TextStyle(
                          color: AppColors.cream,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (inPlay)
                        Text(
                          // The server counts this drop once it notices it.
                          'ניתוק ${me.disconnects + 1} מתוך 3',
                          style: const TextStyle(color: AppColors.cream),
                        ),
                    ],
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
      title: 'מרכיבים צוות חקירה',
      timer: search.deadline == null
          ? null
          : LiveCountdown(deadline: search.deadline!),
      onExit: onCancel,
      bottom: PrimaryButton(
          label: 'ביטול חיפוש',
          variant: ButtonVariant.danger,
          onPressed: onCancel),
      child: Column(
        children: [
          const Illustration(
            'assets/illustrations/matchmaking-team.webp',
            height: 180,
          ),
          Text(
            'נמצאו $count מתוך ${search.maxPlayers}',
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
              mainAxisExtent: 126, // two lines fit under an empty slot
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
                      'מחפשים שחקן...',
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
                          // Grouped for reading aloud; copy and share
                          // still use the plain code.
                          '${room.code.substring(0, 3)} ${room.code.substring(3)}',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'שיתוף הקוד',
                    onPressed: () => shareText(
                      'בואו לשחק איתי ב״מי המתחזה?״. קוד החדר: ${room.code}',
                    ),
                    icon: const Icon(Icons.share_rounded),
                  ),
                  const SizedBox(width: 8),
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
                  ? 'הניהול עבר אליכם'
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    children: [
                      Text('קטגוריות: $categoryNames'),
                      Text('${room.hintSeconds} שניות לרמז'),
                    ],
                  ),
                  if (room.settingsLocked) ...[
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        Icon(Icons.lock_rounded,
                            size: 16, color: AppColors.yellow),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'ההגדרות נעולות מאז שהצטרפו שחקנים',
                            style: TextStyle(
                              color: AppColors.yellow,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
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
      title: 'המשימה שלכם',
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
            impostor ? 'אתם המתחזה' : 'אתם אזרחים',
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
            child: Column(
              children: [
                Text(
                  'המילה הסודית',
                  style: TextStyle(
                    color: impostor
                        ? AppColors.cream.withValues(alpha: 0.75)
                        : AppColors.night.withValues(alpha: 0.55),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  impostor
                      ? 'המילה לא מוצגת לכם — רק הקטגוריה.'
                      : game.secretWord ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: impostor ? AppColors.cream : AppColors.night,
                    fontSize: impostor ? 17 : 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final (index, tip) in (impostor
                  ? const [
                      'הקשיבו לרמזים של האחרים ונסו להשתלב.',
                      'אם תיתפסו — תקבלו הזדמנות אחת לנחש את המילה ולנצח.',
                    ]
                  : const [
                      'בתור שלכם כותבים רמז של מילה אחת שמתאים למילה הסודית.',
                      'רמז ברור מדי יעזור למתחזה. רמז מרומז מדי יעורר חשד.',
                    ])
              .indexed)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.yellow,
                  foregroundColor: AppColors.night,
                  child: Text('${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
                title: Text(tip),
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
                'המילה שלכם',
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
              variant: ButtonVariant.confirm,
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
              'התור שלכם',
              style: Theme.of(context).textTheme.headlineLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'מילה אחת, עד 25 תווים',
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
              buildCounter: (context,
                      {required currentLength,
                      required isFocused,
                      maxLength}) =>
                  Text(
                '$currentLength / $maxLength',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
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
          if (lastHint != null &&
              !lastHint.missing &&
              session.showReactions) ...[
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
  void didUpdateWidget(_Voting old) {
    super.didUpdateWidget(old);
    // A runoff (or any new candidate list) starts without a selection.
    if (old.game.phase != widget.game.phase ||
        !listEquals(old.game.voteCandidates, widget.game.voteCandidates)) {
      _selected = null;
    }
  }

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
                  note: id == me
                      ? 'אי אפשר להצביע לעצמכם'
                      : switch (game.previousVotes[id]) {
                          null => null,
                          final votes => '$votes קולות בסבב הקודם',
                        },
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
    final mostVotes = votes.values.fold(0, (a, b) => a > b ? a : b);
    final abstained = result.abstentions.isEmpty ? 0 : result.abstentions.last;
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
            StatusBanner(
              text: outcome == 'win' ? 'נרשם לכם ניצחון' : 'נרשם לכם הפסד',
              positive: outcome == 'win',
            ),
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
                    for (final entry
                        in (votes.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value))))
                      _VoteBar(
                        name: game.player(entry.key)?.nickname ?? '',
                        votes: entry.value,
                        of: mostVotes,
                      ),
                    if (abstained > 0)
                      _VoteBar(name: 'נמנעו', votes: abstained, of: mostVotes),
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

/// One row of the vote breakdown: a name, a bar and the number of votes.
class _VoteBar extends StatelessWidget {
  const _VoteBar({required this.name, required this.votes, required this.of});

  final String name;
  final int votes;
  final int of;

  @override
  Widget build(BuildContext context) {
    final muted = name == 'נמנעו';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted ? AppColors.muted : null),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: of == 0 ? 0 : votes / of,
                minHeight: 10,
                backgroundColor: AppColors.night,
                color: muted ? AppColors.muted : AppColors.yellow,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text('$votes', style: const TextStyle(fontWeight: FontWeight.w900)),
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
      title: 'יצאתם מהמשחק',
      body: 'התנתקתם שלוש פעמים במשחק הזה, ולכן המשחק ממשיך בלעדיכם.',
      banner: ('נרשם לכם הפסד', false),
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
      body: 'המשחק הופסק בגלל תקלה בחיבור לשרת. זו לא אשמתכם.',
      banner: ('לא נרשם לכם הפסד', true),
      primary: ('חזרה למסך הבית', onHome),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.title,
    required this.body,
    required this.primary,
    this.banner,
    this.secondary,
    this.image = 'assets/illustrations/connection-error.webp',
  });

  final String title;
  final String body;

  /// An optional status line under the text: (text, positive).
  final (String, bool)? banner;
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
          if (banner case final shown?) ...[
            const SizedBox(height: 16),
            StatusBanner(text: shown.$1, positive: shown.$2),
          ],
        ],
      ),
    );
  }
}
