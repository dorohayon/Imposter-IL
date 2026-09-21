import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/invite.dart';
import '../data/models.dart';
import '../models/player.dart';
import '../state/game_session.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';
import 'secondary_screens.dart';

// A private room and its games, driven entirely by the server's room.state
// and game.state snapshots. Every timer counts down to a server deadline.

const _commandErrors = {
  'not_room_host': 'רק מנהל החדר יכול לבצע את הפעולה הזאת.',
  'not_enough_players': 'צריך לפחות 4 שחקנים כדי להתחיל.',
  'content_unavailable': 'אי אפשר להתחיל משחק כרגע. נסו שוב בעוד רגע.',
  'room_in_game': 'כבר מתנהל משחק בחדר הזה.',
  'wrong_phase': 'השלב הזה כבר הסתיים.',
  'not_your_turn': 'זה לא התור שלכם.',
  'hint_empty': 'כתבו רמז לפני השליחה.',
  'hint_not_one_word': 'אפשר לשלוח מילה אחת בלבד.',
  'hint_too_long': 'הרמז יכול להכיל עד 25 תווים.',
  'hint_inappropriate': 'הרמז הזה לא מתאים. נסו מילה אחרת.',
  'hint_contains_secret': 'הרמז מכיל את המילה הסודית. בחרו מילה אחרת.',
  'hint_duplicate': 'הרמז הזה כבר נשלח במשחק. בחרו מילה אחרת.',
  'self_vote': 'אי אפשר להצביע לעצמכם.',
  'invalid_vote_target': 'אי אפשר להצביע לשחקן הזה.',
  'network_error': 'אין חיבור לשרת. בדקו את החיבור ונסו שוב.',
};

/// Opens the system share sheet. Tests replace it.
Future<void> Function(String text) shareText =
    (text) => SharePlus.instance.share(ShareParams(text: text));

String commandMessage(String code) =>
    _commandErrors[code] ?? 'משהו השתבש. נסו שוב בעוד רגע.';

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
      isEliminated: info.status == 'eliminated',
    );

/// Counts down to a server deadline in the top-left timer circle.
class LiveCountdown extends StatefulWidget {
  const LiveCountdown({required this.deadline, this.large = false, super.key});

  final DateTime deadline;
  final bool large;

  @override
  State<LiveCountdown> createState() => _LiveCountdownState();
}

class _LiveCountdownState extends State<LiveCountdown> {
  Timer? _timer;

  /// How long this phase had left when the countdown first appeared, so the
  /// dial can drain against it. The server sends a deadline, not a duration.
  Duration? _total;

  @override
  void initState() {
    super.initState();
    // Four ticks a second: the digits still change once a second, but the
    // draining wedge moves smoothly instead of jumping.
    _timer = Timer.periodic(
        const Duration(milliseconds: 250), (_) => setState(() {}));
  }

  @override
  void didUpdateWidget(LiveCountdown old) {
    super.didUpdateWidget(old);
    // A new deadline is a new phase or a restarted turn, so the dial refills.
    if (old.deadline != widget.deadline) _total = null;
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
    _total ??= left > Duration.zero ? left : null;
    final seconds = (left.inMilliseconds / 1000).ceil();
    final shown = seconds < 0 ? 0 : seconds;
    final total = _total;
    final remaining = total == null || total.inMilliseconds <= 0
        ? null
        : left.inMilliseconds / total.inMilliseconds;
    if (!widget.large) {
      return TimerBadge(seconds: shown, remaining: remaining);
    }
    return TimerBadge(seconds: shown, remaining: remaining, size: 120);
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
      return ServerErrorScreen(
        gameStopped: true,
        onRetry: () async {
          try {
            await session.loadContent();
            session.dismissSessionLost();
            _goHome();
          } on Object {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('עדיין אי אפשר להתחבר. נסו שוב בעוד רגע.'),
                ),
              );
            }
          }
        },
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
          const SnackBar(content: Text('מנהל החדר הסיר אתכם מהחדר.')),
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
      final disconnectNumber = (me.disconnects + 1).clamp(1, 3);
      final disconnectedDuringMyTurn =
          game.phase == 'hints' && game.currentTurnPlayerId == session.playerId;
      return Material(
        color: const Color(0xF20A091A),
        child: SafeArea(
          minimum: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              LiveCountdown(deadline: deadline, large: true),
              const SizedBox(height: 20),
              Text(
                'מתחברים מחדש...',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 10),
              Text(
                disconnectedDuringMyTurn
                    ? 'החיבור אבד בזמן התור שלכם. ננסה להחזיר אתכם למשחק במשך 30 שניות.'
                    : 'החיבור אבד. ננסה להחזיר אתכם למשחק במשך 30 שניות.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.muted, fontSize: 15, height: 1.5),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.yellow.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.yellow.withValues(alpha: .42)),
                ),
                child: Text(
                  disconnectedDuringMyTurn
                      ? 'ניתוק $disconnectNumber מתוך 3 במשחק הזה. אם תחזרו בזמן, תקבלו תור מלא מחדש.'
                      : 'ניתוק $disconnectNumber מתוך 3 במשחק הזה. אם לא תחזרו בזמן, תוצאו מהמשחק.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Color(0xFFFFF0C2), fontSize: 13, height: 1.45),
                ),
              ),
              const SizedBox(height: 18),
              if (onLeaveGame != null)
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: 'יציאה מהמשחק',
                    variant: ButtonVariant.danger,
                    onPressed: onLeaveGame,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    final disconnectNumber = me == null ? 1 : (me.disconnects + 1).clamp(1, 3);
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
                          'ניתוק $disconnectNumber מתוך 3',
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
    final session = SessionScope.of(context);
    final count = search.players.length;
    final found = count == 1
        ? 'נמצא שחקן אחד מתוך ${search.maxPlayers}'
        : 'נמצאו $count מתוך ${search.maxPlayers} שחקנים';
    final missing = search.maxPlayers - count;
    final status = switch (search.status) {
      'waiting_for_more' when missing > 0 =>
        'מחכים עד 30 שניות ל$missing שחקנים נוספים. ב${search.maxPlayers} שחקנים נתחיל מיד.',
      'waiting_for_more' => 'מחכים עד 30 שניות לשחקנים נוספים.',
      'countdown' => 'המשחק מתחיל בעוד רגע.',
      _ => 'המשחק יתחיל כשיהיו לפחות 4 שחקנים.',
    };
    return GameScaffold(
      // Screen 05 keeps the timer at the foot of the screen beside the line
      // that explains it, rather than in the header circle: here the wait is
      // the message, not a deadline to race.
      title: 'מרכיבים צוות חקירה',
      onExit: onCancel,
      bottom: PrimaryButton(
          label: 'ביטול חיפוש',
          variant: ButtonVariant.danger,
          onPressed: onCancel),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.turquoise.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(999),
              border:
                  Border.all(color: AppColors.turquoise.withValues(alpha: .42)),
            ),
            child: Text(
              found,
              style: const TextStyle(
                color: AppColors.turquoise,
                fontFamily: 'Secular One',
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Above the list, not below it: at the foot of a full roster it sat
          // past the fold and had to be scrolled to.
          Row(
            children: [
              if (search.deadline != null) ...[
                LiveCountdown(deadline: search.deadline!),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  status,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'נא לא לעזוב עמוד זה.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.yellow,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: search.maxPlayers,
            separatorBuilder: (_, __) => const SizedBox(height: 7),
            itemBuilder: (context, index) {
              if (index >= count) {
                return Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    color: AppColors.cream.withValues(alpha: .035),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: AppColors.cream.withValues(alpha: .12)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
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
                      const SizedBox(width: 12),
                      const Text(
                        'מחפשים שחקן...',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }
              final player = search.players[index];
              return Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 11),
                decoration: BoxDecoration(
                  color: AppColors.cream.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    AvatarView(asset: player.avatarAsset, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        player.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (player.id == session.playerId)
                      const Text(
                        'אתם',
                        style:
                            TextStyle(color: AppColors.turquoise, fontSize: 12),
                      ),
                  ],
                ),
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
      title: 'לא נמצא משחק בקטגוריות שבחרתם',
      body: 'אפשר לנסות שוב עם אותן קטגוריות, או לבחור קטגוריות אחרות.',
      image: 'assets/illustrations/no-category-match.webp',
      primary: ('ניסיון נוסף', onRetry),
      secondary: ('בחירת קטגוריות אחרות', onCategories),
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
      onExit: onLeave,
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
                        LtrText(
                          // Grouped for reading aloud; copy and share
                          // still use the plain code.
                          '${room.code.substring(0, 3)} ${room.code.substring(3)}',
                          semanticsLabel:
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
                      'בואו לשחק איתי ב״מי המתחזה?״\nקוד החדר: ${room.code}\n'
                      '${inviteLink(room.code)}',
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
            const _Notice('מחכים ששחקן נוסף יתחבר ויקבל את ניהול החדר.'),
          if (transfer != null && host != null)
            _Notice(
              transfer.to == me
                  ? 'מנהל החדר לא חזר בזמן. הניהול עבר אליכם.'
                  : 'הניהול עבר ל־${host.nickname}.',
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
                          if (p.id == me) 'אתם',
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
    final positive = text.contains('עבר');
    final color = positive ? AppColors.turquoise : AppColors.yellow;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .42)),
        ),
        child: Row(
          children: [
            Icon(
              positive ? Icons.check_circle_rounded : Icons.info_rounded,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ),
          ],
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
      // hint_break is gone from the engine, but a server that has not been
      // deployed yet still sends it, and an unknown phase falls through to the
      // result screen — which, with no result, is a spinner between turns.
      'hints' || 'hint_break' => _Hints(game: game, onLeave: onLeave),
      'pre_voting' => _ToVoting(game: game, onLeave: onLeave),
      'voting' || 'runoff_voting' => _Voting(game: game, onLeave: onLeave),
      'impostor_guess' => _Guess(game: game, onLeave: onLeave),
      _ => _Result(game: game, onHome: onLeave),
    };
  }
}

Widget? _timer(GameView game) {
  if (game.deadline == null) return null;
  return LiveCountdown(deadline: game.deadline!);
}

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
      // The pill below names the category; the header said it a second time.
      title: '',
      timer: _timer(game),
      onExit: onLeave,
      accent: impostor ? const Color(0xFF4A2A8C) : const Color(0xFF1B4F4A),
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
          CategoryPill(category: game.category),
          const SizedBox(height: 12),
          Illustration(
            impostor
                ? 'assets/illustrations/role-impostor.webp'
                : 'assets/illustrations/role-citizen.webp',
            height: 158,
          ),
          const SizedBox(height: 4),
          Text(
            impostor ? 'את/ה המתחזה' : 'את/ה אזרח/ית',
            style: Theme.of(context).textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          SecretWordCard(word: game.secretWord, impostor: impostor),
          if (!impostor) ...[
            const SizedBox(height: 12),
            // Screen 07 carries this line under the word card, before the
            // numbered tips.
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
          const SizedBox(height: 16),
          for (final (index, tip) in (impostor
                  ? const [
                      'הקשיבו לרמזים של האחרים ונסו להשתלב.',
                      'אם תיתפסו — תקבלו הזדמנות אחת לנחש את המילה ולנצח.',
                    ]
                  : const [
                      'בתורכם, כתבו רמז של מילה אחת שמתאים למילה הסודית.',
                      'רמז ברור מדי יעזור למתחזה. רמז דק מדי יעורר חשד.',
                    ])
              .indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: StepCard(number: index + 1, text: tip),
            ),
        ],
      ),
    );
  }
}

/// Screen 11א: every hint is in, and the vote opens on its own in a moment.
/// The countdown is the whole screen here, not a badge in the corner.
class _ToVoting extends StatelessWidget {
  const _ToVoting({required this.game, required this.onLeave});

  final GameView game;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return ToVotingView(
      onExit: onLeave,
      note: 'זה הזמן להחליט מי המתחזה',
      countdown: game.deadline == null
          ? const SizedBox.shrink()
          : LiveCountdown(deadline: game.deadline!, large: true),
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
  // One key per participant, so a reaction can rise from the card of whoever
  // sent it.
  final _cardKeys = <String, GlobalKey>{};
  GameSession? _session;
  String? _error;
  bool _busy = false;
  bool _wordOpen = false;
  int _seed = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = SessionScope.read(context)..onReaction = _onReaction;
  }

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
    _session?.onReaction = null;
    _controller.dispose();
    super.dispose();
  }

  /// Floats a reaction off [playerId]'s card. A card that is not on screen has
  /// no key yet, and then the reaction is simply not animated.
  void _pop(String playerId, String text) {
    if (_cardKeys[playerId] case final key?) {
      floatReaction(context, text, anchor: key, seed: _seed++);
    }
  }

  /// Everyone else's reactions arrive as their own event, which is the only
  /// message that names the sender. Yours is not animated twice: it already
  /// popped on touch.
  void _onReaction(String playerId, String reactionId) {
    final session = _session;
    if (!mounted || session == null || !session.showReactions) return;
    if (playerId == session.playerId || session.muted.contains(playerId)) {
      return;
    }
    for (final r in session.reactions) {
      if (r.id == reactionId) _pop(playerId, r.text);
    }
  }

  /// Your own reaction pops on touch, so the bubble does not wait for the
  /// server. The echo names you, and is skipped above.
  Future<void> _react(ReactionOption r) async {
    final session = SessionScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    _pop(session.playerId ?? '', r.text);
    final code = await session.send('game.react', {
      'gameId': widget.game.id,
      'hintIndex': widget.game.hints.length - 1,
      'reactionId': r.id,
    });
    if (code == null) return;
    messenger.showSnackBar(SnackBar(content: Text(commandMessage(code))));
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

  /// Screen C04: every clue a player has given, by round, opened from the
  /// bottom by tapping their card.
  void _openHistory(PlayerInfo p) {
    final session = SessionScope.read(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _HintHistorySheet(
        player: p,
        // Keeping each hint's index: reporting addresses a hint by where it
        // sits in the match, not on the screen.
        hints: [
          for (final (i, h) in widget.game.hints.indexed)
            if (h.playerId == p.id) (i, h),
        ],
        // Nobody reports themself.
        reportable: p.id != session.playerId,
      ),
    );
  }

  /// The line under a participant's name, following screens C01 to C07.
  /// The clue a participant's card leads with: the one they gave in this
  /// round, and nothing before it — a new round starts the board empty, and
  /// earlier rounds open from the card. The player writing right now has
  /// nothing to show either; the line underneath says so.
  String _word(PlayerInfo p, {required bool active}) {
    if (active) return '';
    for (final h in widget.game.hints.reversed) {
      if (h.playerId == p.id && h.round == widget.game.round && !h.missing) {
        return _hintText(h);
      }
    }
    return '';
  }

  /// The line under the clue: how many clues that player has given, or what is
  /// happening to them instead.
  (String, Color, bool) _line(PlayerInfo p, {required bool active}) {
    final me = p.id == SessionScope.read(context).playerId;
    if (p.status == 'eliminated') {
      return (me ? 'הודחת · צופה' : 'הודח/ה · צופה', AppColors.coral, false);
    }
    if (p.status != 'active') return ('יצא/ה מהמשחק', AppColors.muted, false);
    if (!p.connected) {
      return ('מנותק · ממתינים 30 שניות', AppColors.coral, false);
    }
    if (active) return ('כותב/ת רמז', AppColors.yellow, true);
    final said = [
      for (final h in widget.game.hints)
        if (h.playerId == p.id) h,
    ].length;
    if (said == 0) return ('ממתין/ה לתור', AppColors.muted, false);
    return (said == 1 ? '1 רמז' : '$said רמזים', AppColors.muted, false);
  }

  /// A reported player's hints are hidden wherever they are shown.
  String _hintText(HintView h) {
    if (h.missing) return 'לא נשלח רמז';
    return SessionScope.read(context).muted.contains(h.playerId)
        ? 'הוסתר'
        : h.text;
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final game = widget.game;
    final me = session.playerId;
    // The server holds each hint for a moment so it can be read; nobody has
    // the turn during it.
    final holding = game.phase == 'hint_break';
    final myTurn = game.currentTurnPlayerId == me && !holding;
    final watching = game.isEliminated(me);
    final word = game.secretWord;
    final current = holding ? null : game.player(game.currentTurnPlayerId);
    final playing = [
      for (final p in game.players)
        if (p.status == 'active') p,
    ];
    // "תור 3 מתוך 8": how far this round has got, not a hint index.
    final given = [
      for (final h in game.hints)
        if (h.round == game.round) h,
    ].length;
    final turn = (given + (holding ? 0 : 1))
        .clamp(1, playing.isEmpty ? 1 : playing.length);

    return GameScaffold(
      title: game.category,
      titleLabel: 'קטגוריה',
      timer: _timer(game),
      onExit: widget.onLeave,
      scrollable: false,
      contentPadding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (watching)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: SpectatorNote(),
            )
          else if (game.awaitingReconnect && current != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _DisconnectBanner(nickname: current.nickname),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                // The impostor is never sent the word, so there is nothing to
                // open.
                if (word != null) ...[
                  _WordButton(
                    open: _wordOpen,
                    onPressed: () => setState(() => _wordOpen = !_wordOpen),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    'סיבוב ${game.round} · תור $turn מתוך ${playing.length}',
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: Row(
                        children: [
                          Text(
                            'הרמזים בסיבוב',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 9, 20, 4),
                        child: LayoutBuilder(
                          // Two columns, each card as tall as its own text, so
                          // a long clue wraps instead of being cut.
                          builder: (context, box) => Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final p in game.players)
                                SizedBox(
                                  width: (box.maxWidth - 8) / 2,
                                  child: _ParticipantCard(
                                    key: _cardKeys.putIfAbsent(
                                      p.id,
                                      GlobalKey.new,
                                    ),
                                    player: p,
                                    isMe: p.id == me,
                                    active: p.id == current?.id,
                                    word: _word(
                                      p,
                                      active: p.id == current?.id,
                                    ),
                                    line: _line(
                                      p,
                                      active: p.id == current?.id,
                                    ),
                                    onTap: () => _openHistory(p),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (myTurn && !watching)
                      _Composer(
                        controller: _controller,
                        error: _error,
                        busy: _busy,
                        onChanged: () => setState(() => _error = null),
                        onSubmit: _submit,
                      )
                    else if (current != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                        child: _DashedNote(
                          text: '${current.nickname} כותב/ת עכשיו. '
                              'אפשר להמשיך להגיב למטה.',
                        ),
                      ),
                  ],
                ),
                // C03: the word opens from the top, under its button, over a
                // scrim. The header stays above it, so the timer keeps running
                // in view.
                if (_wordOpen && word != null) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => setState(() => _wordOpen = false),
                      child: const ColoredBox(color: Color(0xA8090818)),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 16,
                    right: 16,
                    child: _WordCard(
                      category: game.category,
                      word: word,
                      onClose: () => setState(() => _wordOpen = false),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // The bar is general, not tied to one clue, but the count it adds to
          // still belongs to the newest hint.
          if (session.showReactions &&
              MediaQuery.viewInsetsOf(context).bottom == 0)
            _ReactionDock(
              reactions: session.reactions,
              onReact: game.hints.isEmpty ? null : _react,
            ),
        ],
      ),
    );
  }
}

/// One participant in the two-column grid, led by the clue they last gave,
/// with their name above it and how many clues they have given below. States
/// follow C01 to C08 — active, yours, disconnected and eliminated each carry
/// their own frame as well as their own line of text.
class _ParticipantCard extends StatelessWidget {
  const _ParticipantCard({
    required this.player,
    required this.isMe,
    required this.active,
    required this.word,
    required this.line,
    required this.onTap,
    super.key,
  });

  final PlayerInfo player;
  final bool isMe;
  final bool active;

  /// The clue to lead with, empty when there is none to show yet.
  final String word;
  final (String, Color, bool) line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final out = player.status != 'active';
    final bad = !out && !player.connected;
    // Frame and fill per state, in the order a card can be in more than one:
    // out, then whose turn it is, then dropped, then yours.
    final (Color border, Color fill, double width) = out
        ? (
            AppColors.cream.withValues(alpha: .2),
            AppColors.cream.withValues(alpha: .03),
            1.0
          )
        : active
            ? (AppColors.yellow, AppColors.yellow.withValues(alpha: .13), 2.0)
            : bad
                ? (
                    AppColors.coral.withValues(alpha: .45),
                    AppColors.coral.withValues(alpha: .1),
                    1.0
                  )
                : isMe
                    ? (
                        AppColors.purple.withValues(alpha: .55),
                        AppColors.purple.withValues(alpha: .14),
                        1.0
                      )
                    : (
                        AppColors.cream.withValues(alpha: .14),
                        AppColors.cream.withValues(alpha: .05),
                        1.0
                      );
    final (text, colour, bold) = line;
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          constraints: const BoxConstraints(minHeight: 96),
          padding: EdgeInsets.all(width == 2 ? 8 : 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: border, width: width),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  AvatarView(
                    asset: player.avatarAsset,
                    size: 26,
                    disconnected: bad,
                    eliminated: out,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      isMe ? '${player.nickname} · אני' : player.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: active
                            ? AppColors.yellow
                            : AppColors.cream.withValues(alpha: out ? .5 : .72),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: 38,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    word,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.cream.withValues(alpha: out ? .5 : 1),
                      fontFamily: 'Secular One',
                      fontSize: 22,
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: AppColors.cream.withValues(alpha: .12),
                    ),
                  ),
                ),
                // Two lines' worth, always: long states like "מנותק ·
                // ממתינים 30 שניות" need the room, and a card that grew to
                // fit one would stand taller than the card beside it.
                child: SizedBox(
                  height: 28,
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colour,
                                  fontSize: 11,
                                  height: 1.2,
                                  fontWeight:
                                      bold ? FontWeight.w700 : FontWeight.w400,
                                ),
                              ),
                            ),
                            if (active) TypingDots(colour: colour),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.cream.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 14,
                          color: AppColors.cream.withValues(alpha: .7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// C02 and C05: the clue field, its counter and the send button, in a frame
/// that turns coral when the clue was refused.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.error,
    required this.busy,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String? error;
  final bool busy;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final bad = error != null;
    final accent = bad ? AppColors.coral : AppColors.yellow;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: bad ? .12 : .1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'הרמז שלך · מילה אחת',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: bad ? const Color(0xFFFFB7B7) : AppColors.yellow,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              LtrText(
                '${controller.text.characters.length}/25',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 9),
          TextField(
            controller: controller,
            maxLength: 25,
            autofocus: false,
            textAlign: TextAlign.start,
            style: const TextStyle(
              color: AppColors.night,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
            decoration: const InputDecoration(
              hintText: 'הרמז שלכם',
              counterText: '',
            ),
            onChanged: (_) => onChanged(),
            onSubmitted: (_) => onSubmit(),
          ),
          if (error != null) ...[
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.coral,
                    shape: BoxShape.circle,
                  ),
                  child: const Text(
                    '!',
                    style: TextStyle(
                      color: Color(0xFF3B1214),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$error הרמז לא נשלח.',
                    style: const TextStyle(
                      color: Color(0xFFFFD9D9),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 9),
          PrimaryButton(
            label: 'שליחת רמז',
            variant: ButtonVariant.confirm,
            onPressed: busy || bad ? null : onSubmit,
          ),
        ],
      ),
    );
  }
}

/// The pill that opens the word card, top-right of the board (C01, C03).
class _WordButton extends StatelessWidget {
  const _WordButton({required this.open, required this.onPressed});

  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: open
          ? AppColors.yellow.withValues(alpha: .16)
          : AppColors.cream.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 38),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: open
                  ? AppColors.yellow
                  : AppColors.cream.withValues(alpha: .22),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.visibility_outlined,
                size: 16,
                color: AppColors.yellow,
              ),
              const SizedBox(width: 8),
              Text(
                'הצגת המילה שלי',
                style: TextStyle(
                  color: open ? AppColors.yellow : AppColors.cream,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// C03: the word, over the board, until it is closed. The timer above it keeps
/// running, which is the point of opening it here rather than on its own page.
class _WordCard extends StatelessWidget {
  const _WordCard({
    required this.category,
    required this.word,
    required this.onClose,
  });

  final String category;
  final String word;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cream,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'המילה שלי',
                  style: TextStyle(
                    color: AppColors.night,
                    fontFamily: 'Secular One',
                    fontSize: 18,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onClose,
                  tooltip: 'סגירה',
                  icon: const Icon(Icons.close_rounded),
                  color: AppColors.night.withValues(alpha: .65),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.night, width: 2),
              ),
              child: Column(
                children: [
                  Text(
                    'קטגוריה: $category',
                    style: TextStyle(
                      color: AppColors.night.withValues(alpha: .6),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    word,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.night,
                      fontFamily: 'Secular One',
                      fontSize: 30,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// C04: what one player has said, round by round.
class _HintHistorySheet extends StatelessWidget {
  const _HintHistorySheet({
    required this.player,
    required this.hints,
    required this.reportable,
  });

  final PlayerInfo player;

  /// Each hint with its index in the match, which is how a report names it.
  final List<(int, HintView)> hints;
  final bool reportable;

  @override
  Widget build(BuildContext context) {
    // Read live: reporting from this sheet has to hide the clue under it.
    final hidden = SessionScope.of(context).muted.contains(player.id);
    final canReport = reportable && !hidden;
    final first = hints.isEmpty ? 0 : hints.first.$2.round;
    final last = hints.isEmpty ? 0 : hints.last.$2.round;
    final rounds = hints.isEmpty
        ? ''
        : first == last
            ? 'סיבוב $first'
            : 'סיבובים $first–$last';
    final count = hints.length == 1 ? '1 רמז' : '${hints.length} רמזים';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Material(
          color: AppColors.cream,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'הרמזים של ${player.nickname}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.night,
                          fontFamily: 'Secular One',
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'סגירה',
                      icon: const Icon(Icons.close_rounded),
                      color: AppColors.night.withValues(alpha: .65),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      AvatarView(asset: player.avatarAsset, size: 44),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          hints.isEmpty
                              ? 'עוד לא נשלחו רמזים.'
                              : '$count · $rounds',
                          style: TextStyle(
                            color: AppColors.night.withValues(alpha: .65),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (index, h) in hints)
                          Container(
                            constraints: const BoxConstraints(minHeight: 50),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: AppColors.night.withValues(alpha: .12),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  'סיבוב ${h.round}',
                                  style: TextStyle(
                                    color:
                                        AppColors.night.withValues(alpha: .55),
                                    fontSize: 13,
                                  ),
                                ),
                                const Spacer(),
                                Flexible(
                                  child: Text(
                                    h.missing
                                        ? 'לא נשלח רמז'
                                        : hidden
                                            ? 'הוסתר'
                                            : h.text,
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(
                                      color: AppColors.night,
                                      fontFamily: 'Secular One',
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                                // Not in the design, but the stores require a
                                // way to report what another player wrote, and
                                // this is the only place a clue is now read on
                                // its own.
                                if (canReport && !h.missing)
                                  IconButton(
                                    tooltip: 'דיווח על הרמז',
                                    icon: const Icon(
                                      Icons.flag_outlined,
                                      size: 20,
                                    ),
                                    color: AppColors.night.withValues(
                                      alpha: .55,
                                    ),
                                    onPressed: () => _reportHint(
                                      context,
                                      playerId: player.id,
                                      nickname: player.nickname,
                                      hintIndex: index,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
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

/// C01: who is writing, while you wait. A quiet line rather than a card, so
/// the board above it keeps the room's attention.
class _DashedNote extends StatelessWidget {
  const _DashedNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        // ponytail: a solid faint border, not the design's dashes — dashes
        // need a painter, and nothing here is signalled by the border alone.
        border: Border.all(color: AppColors.cream.withValues(alpha: .22)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.cream.withValues(alpha: .62),
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }
}

/// C06: the player whose turn it is dropped, and the table is waiting.
class _DisconnectBanner extends StatelessWidget {
  const _DisconnectBanner({required this.nickname});

  final String nickname;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.coral.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.coral.withValues(alpha: .45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded,
              size: 18, color: Color(0xFFFF9B9B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$nickname התנתק. ממתינים לו עד 30 שניות — '
              'אחר כך התור שלו ידולג.',
              style: const TextStyle(
                color: Color(0xFFFFD9D9),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The reaction bar, pinned under the board and scrolling sideways. It belongs
/// to the table, not to one clue, so it carries no clue text.
class _ReactionDock extends StatelessWidget {
  const _ReactionDock({required this.reactions, required this.onReact});

  final List<ReactionOption> reactions;

  /// Null before the first clue of the match, when there is nothing to react
  /// to yet.
  final ValueChanged<ReactionOption>? onReact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.cream.withValues(alpha: .14)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
            child: Row(
              children: [
                const Text(
                  'תגובות',
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'גררו לצדדים לעוד תגובות ↔',
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.muted.withValues(alpha: .8),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final r in reactions)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 7),
                    child: _ReactionChip(
                      reaction: r,
                      onTap: onReact == null ? null : () => onReact!(r),
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

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.reaction, required this.onTap});

  final ReactionOption reaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Emoji get the bigger, tighter pill; the structured messages are text.
    final emoji = !RegExp(r'[֐-׿]').hasMatch(reaction.text);
    return Opacity(
      opacity: onTap == null ? .45 : 1,
      child: Material(
        color: AppColors.cream.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            constraints: const BoxConstraints(minHeight: 42),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.cream.withValues(alpha: .2)),
            ),
            child: Text(
              reaction.text,
              softWrap: false,
              style: TextStyle(
                color: AppColors.cream,
                fontSize: emoji ? 19 : 14,
                fontWeight: emoji ? FontWeight.w400 : FontWeight.w500,
              ),
            ),
          ),
        ),
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

/// What a player has said across the whole match, for the vote to weigh. An
/// empty string is a turn that passed without a hint; null is a player who has
/// not spoken at all.
String? _saidSoFar(GameView game, GameSession session, String id) {
  final said = game.hintsOf(id);
  if (said.isEmpty) return null;
  if (session.muted.contains(id)) return 'הוסתר';
  final words = [
    for (final h in said)
      if (!h.missing) h.text,
  ];
  return words.join(' · ');
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
    final watching = game.isEliminated(me);

    return GameScaffold(
      title: runoff ? 'הצבעה חוזרת' : 'מי המתחזה?',
      timer: _timer(game),
      onExit: widget.onLeave,
      bottom: watching
          ? null
          : PrimaryButton(
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
          if (game.round > 1) ...[
            RoundBadge(round: game.round),
            const SizedBox(height: 12),
          ],
          if (watching) ...[
            const SpectatorNote(),
            const SizedBox(height: 14),
          ],
          if (!runoff && !watching)
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Text(
                'בחרו שחקן אחד. אפשר לשנות את הבחירה עד שהזמן נגמר.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          if (runoff)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.coral.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: AppColors.coral.withValues(alpha: .42)),
                ),
                child: const Text(
                  'היה תיקו. מצביעים שוב רק בין השחקנים שקיבלו את מספר הקולות הגבוה. תיקו נוסף — איש לא מודח והמשחק ממשיך לסבב נוסף.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFFFD9D9), height: 1.4),
                ),
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
                    // Everything they have said this match, not just the last
                    // of it: by the third round the earlier rounds are most of
                    // what there is to go on.
                    hint: _saidSoFar(game, session, id),
                  ),
                  note: id == me
                      ? 'אי אפשר להצביע לעצמכם'
                      : switch (game.previousVotes[id]) {
                          null => null,
                          1 => 'קול אחד בסבב הקודם',
                          final votes => '$votes קולות בסבב הקודם',
                        },
                  enabled: id != me && !watching,
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
      title: 'נתפסתם',
      timer: _timer(game),
      onExit: widget.onLeave,
      accent: const Color(0xFF4A2A8C),
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
            height: 170,
          ),
          Text(
            'עוד אפשר לנצח',
            style: Theme.of(context).textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          if (game.isImpostor) ...[
            const Text(
              'נחשו את המילה הסודית. יש לכם ניסיון אחד.',
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
              decoration: const InputDecoration(hintText: 'מה המילה?'),
            ),
            const SizedBox(height: 8),
            // Screen 14 reassures the impostor that typing is private, and
            // spells out what losing the clock costs.
            const Text(
              'הניחוש לא מוצג לשחקנים בזמן ההקלדה',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            const Text(
              'אם הזמן ייגמר או שהניחוש יהיה שגוי — האזרחים מנצחים.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: AppColors.muted, fontSize: 14, height: 1.4),
            ),
          ] else
            const Text(
              'המתחזה נתפס ועכשיו הוא מנסה לנחש את המילה.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 17),
            ),
        ],
      ),
    );
  }
}

const _resultReasons = {
  'impostor_not_caught': 'ההצבעה סימנה אזרח, והמתחזה נשאר במשחק.',
  'impostor_guessed_word': 'המתחזה נתפס, אבל הצליח לנחש את המילה.',
  'impostor_guess_wrong': 'המתחזה נתפס ולא הצליח לנחש את המילה.',
  'impostor_guess_timeout': 'המתחזה נתפס, אבל הזמן לניחוש נגמר.',
  'impostor_gone': 'המתחזה עזב את המשחק.',
  'not_enough_players': 'נשארו פחות משלושה שחקנים, ולכן המשחק הופסק.',
  'abandoned': 'שני סבבי הצבעה עברו בלי אף הצבעה, ולכן המשחק בוטל. '
      'הוא לא נספר לאף אחד — לא כניצחון ולא כהפסד.',
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
      title: '',
      showBack: false,
      showHeader: false,
      accent: stopped
          ? null
          : citizensWon
              ? const Color(0xFF14514A)
              : const Color(0xFF4A2A8C),
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
            height: 168,
          ),
          Text(
            result.reason == 'abandoned'
                ? 'המשחק בוטל'
                : stopped
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
          // A match that was called off is recorded for nobody, so there is
          // nothing to tell anyone they earned.
          if (outcome != null && outcome != 'none') ...[
            const SizedBox(height: 10),
            StatusBanner(
              text: outcome == 'win' ? 'נרשם לכם ניצחון' : 'נרשם לכם הפסד',
              positive: outcome == 'win',
            ),
          ],
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  ListTile(
                    title: const Text('המתחזה היה'),
                    trailing: Text(
                      impostor?.nickname ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('המילה הייתה'),
                    trailing: Text(
                      result.secretWord,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (votes.isNotEmpty || abstained > 0) ...[
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
      body: 'התנתקתם שלוש פעמים במשחק הזה, ולכן שאר השחקנים ממשיכים בלעדיכם.',
      banner: ('נרשם לכם הפסד', false),
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
      title: '',
      showBack: false,
      showHeader: false,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(label: primary.$1, onPressed: primary.$2),
          if (secondary != null) ...[
            const SizedBox(height: 8),
            PrimaryButton(
              label: secondary.$1,
              variant: ButtonVariant.secondary,
              onPressed: secondary.$2,
            ),
          ],
        ],
      ),
      child: Column(
        children: [
          Illustration(image, height: 170),
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

/// A hint with the report action beside it.
///
/// Required of any app that shows text one player wrote to another (App Store
/// review guideline 1.2, Google Play's UGC policy). It is a visible button
/// rather than a long-press, so the action is not hidden behind a gesture.
/// Reports one hint and hides that player's hints on this device. Not part of
/// the clue-screen design, but the stores require a way to report what another
/// player wrote, so it hangs off the clue history.
Future<void> _reportHint(
  BuildContext context, {
  required String playerId,
  required String nickname,
  required int hintIndex,
}) async {
  final session = SessionScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('לדווח על הרמז?'),
      content: Text(
        'הרמז יישלח לבדיקה, ולא תראו יותר רמזים של $nickname במכשיר הזה.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('ביטול'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('דיווח'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  final code = await session.reportPlayer(playerId, hintIndex: hintIndex);
  // The hiding is local and holds either way; the report itself may not have
  // reached the server, and saying it did would be a lie.
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        code == null
            ? 'הדיווח נשלח. הרמזים האלה יוסתרו.'
            : 'הרמזים האלה יוסתרו, אבל הדיווח לא נשלח. ${commandMessage(code)}',
      ),
    ),
  );
}
