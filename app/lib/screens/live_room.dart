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
    final shown = seconds < 0 ? 0 : seconds;
    if (!widget.large) return TimerBadge(seconds: shown);
    return Container(
      width: 120,
      height: 120,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.yellow.withValues(alpha: .08),
        border: Border.all(color: AppColors.yellow, width: 6),
      ),
      child: Text(
        '$shown',
        style: const TextStyle(
          color: AppColors.yellow,
          fontFamily: 'Secular One',
          fontSize: 38,
        ),
      ),
    );
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
        : 'נמצאו $count מתוך ${search.maxPlayers}';
    final status = switch (search.status) {
      'waiting_for_more' => 'מחכים עד 30 שניות לשחקנים נוספים.',
      'countdown' => 'המשחק מתחיל בעוד רגע.',
      _ => 'המשחק יתחיל כשיהיו לפחות 4 שחקנים.',
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
          const SizedBox(height: 10),
          Text(
            status,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 16),
          ),
          const SizedBox(height: 16),
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
      title: game.category,
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
          Illustration(
            impostor
                ? 'assets/illustrations/role-impostor.webp'
                : 'assets/illustrations/role-citizen.webp',
            height: 158,
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
            impostor ? 'אתם המתחזה' : 'אתם בצוות האזרחים',
            style: Theme.of(context).textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          InfoCard(
            label: 'המילה הסודית',
            light: !impostor,
            child: Text(
              impostor ? 'רק הקטגוריה מוצגת לכם.' : game.secretWord ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: impostor ? AppColors.cream : AppColors.night,
                fontFamily: 'Secular One',
                fontSize: impostor ? 18 : 38,
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final (index, tip) in (impostor
                  ? const [
                      'הקשיבו לרמזים של האחרים ונסו להשתלב.',
                      'אם תיתפסו — תקבלו הזדמנות אחת לנחש את המילה ולנצח.',
                    ]
                  : const [
                      'בתורכם, כתבו רמז של מילה אחת שמתאים למילה הסודית.',
                      'רמז ברור מדי יעזור למתחזה. רמז מרומז מדי יעורר חשד.',
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
      title: game.category,
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
          if (!game.isImpostor && word != null) ...[
            _SecretWordPill(
              word: word,
              onShow: () => _showSecretWord(word),
            ),
            const SizedBox(height: 14),
          ],
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
              decoration: const InputDecoration(hintText: 'הרמז שלכם'),
              buildCounter: (context,
                      {required currentLength,
                      required isFocused,
                      maxLength}) =>
                  LtrText(
                '$currentLength / $maxLength',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              StatusBanner(
                text: '${_error!} הרמז לא נשלח.',
                positive: false,
              ),
            ],
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
                  ? 'אין כרגע חיבור ל־${current.nickname}. מחכים לחזרה...'
                  : 'עכשיו התור של ${current.nickname}',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 22),
          const Text(
            'רמזים שנשלחו',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (game.hints.isEmpty)
            const Text(
              'עוד לא נשלחו רמזים.',
              style: TextStyle(color: AppColors.muted),
            ),
          for (final (i, h) in game.hints.indexed)
            if (game.player(h.playerId) case final p?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ReportableHint(
                  card: PlayerCard(
                    player: _player(
                      p,
                      me,
                      hint: switch (h) {
                        _ when h.missing => '',
                        _ when session.muted.contains(h.playerId) => 'הוסתר',
                        _ => h.text,
                      },
                    ),
                  ),
                  playerId: h.playerId,
                  nickname: p.nickname,
                  hintIndex: i,
                  // Nobody reports themself, and a hidden hint is already dealt with.
                  canReport: h.playerId != me &&
                      !h.missing &&
                      !session.muted.contains(h.playerId),
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
                    backgroundColor: AppColors.cream.withValues(alpha: .08),
                    side: BorderSide(
                        color: AppColors.cream.withValues(alpha: .12)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
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

class _SecretWordPill extends StatelessWidget {
  const _SecretWordPill({required this.word, required this.onShow});

  final String word;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'המילה שלכם',
                  style: TextStyle(
                    color: AppColors.night.withValues(alpha: .55),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  word,
                  style: const TextStyle(
                    color: AppColors.night,
                    fontFamily: 'Secular One',
                    fontSize: 22,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onShow,
            style: TextButton.styleFrom(foregroundColor: AppColors.purple),
            icon: const Icon(Icons.visibility_outlined, size: 19),
            label: const Text('הצגה'),
          ),
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
          if (!runoff)
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
                  'היה תיקו. מצביעים שוב רק בין השחקנים שקיבלו את מספר הקולות הגבוה. תיקו נוסף יעניק ניצחון למתחזה.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFFFD9D9), height: 1.4),
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
  'second_tie': 'גם ההצבעה החוזרת הסתיימה בתיקו.',
  'impostor_guessed_word': 'המתחזה נתפס, אבל הצליח לנחש את המילה.',
  'impostor_guess_wrong': 'המתחזה נתפס ולא הצליח לנחש את המילה.',
  'impostor_guess_timeout': 'המתחזה נתפס, אבל הזמן לניחוש נגמר.',
  'impostor_gone': 'המתחזה עזב את המשחק.',
  'not_enough_players': 'נשארו פחות משלושה שחקנים, ולכן המשחק הופסק.',
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
class _ReportableHint extends StatelessWidget {
  const _ReportableHint({
    required this.card,
    required this.playerId,
    required this.nickname,
    required this.hintIndex,
    required this.canReport,
  });

  final Widget card;
  final String playerId;
  final String nickname;
  final int hintIndex;
  final bool canReport;

  @override
  Widget build(BuildContext context) {
    if (!canReport) return card;
    return Row(
      children: [
        Expanded(child: card),
        IconButton(
          tooltip: 'דיווח על הרמז',
          icon: const Icon(Icons.flag_outlined, color: AppColors.muted),
          onPressed: () => _confirm(context),
        ),
      ],
    );
  }

  Future<void> _confirm(BuildContext context) async {
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
    // The hiding is local and holds either way; the report itself may not
    // have reached the server, and saying it did would be a lie.
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
}
