import '../models/player.dart';

// Prototype-only content for the online flow, which has no server support yet
// (matchmaking). Private rooms use the real server. Category names follow the
// approved first batch in server/internal/content; nothing else is product data.

const demoCategories = [
  'הכול',
  'אוכל',
  'חיות',
  'ספורט',
  'מקצועות',
  'מקומות',
  'חפצים',
];
const demoCategory = 'אוכל';
const demoWord = 'בננה';

/// How long another demo player "takes" to send a hint, and the pause before
/// the demo moves from the last hint to voting.
const demoTurnDelay = Duration(seconds: 3);

/// Demo turn order. [DemoGame.me] picks which of these is the current player;
/// that player's scripted hint is ignored and replaced by what they type.
const demoPlayers = <Player>[
  Player(
    nickname: 'נועם',
    avatar: 'assets/avatars/avatar-f01-notebook.webp',
    hint: 'קיץ',
    isHost: true,
  ),
  Player(
    nickname: 'יובל',
    avatar: 'assets/avatars/avatar-m02-binoculars.webp',
    hint: 'מתוק',
  ),
  Player(
    nickname: 'מאיה',
    avatar: 'assets/avatars/avatar-f02-camera.webp',
    hint: 'צהוב',
  ),
  Player(
    nickname: 'אורי',
    avatar: 'assets/avatars/avatar-m04-detective-hat.webp',
    hint: 'קליפה',
  ),
  Player(
    nickname: 'דנה',
    avatar: 'assets/avatars/avatar-f04-map.webp',
    hint: 'קוף',
  ),
  Player(
    nickname: 'רועי',
    avatar: 'assets/avatars/avatar-m05-badge.webp',
    hint: 'קינוח',
  ),
];

const demoOnlineMe = 'מאיה';

/// The scripted game a prototype flow walks through.
class DemoGame {
  const DemoGame({
    required this.me,
    this.isImpostor = false,
    this.hintSeconds = 15,
  });

  final String me;
  final bool isImpostor;
  final int hintSeconds;

  /// The demo impostor is יובל unless the current player is the impostor.
  String get impostor => isImpostor ? me : 'יובל';

  /// Roster in turn order, with the current player marked and without a hint.
  List<Player> get players => [
        for (final player in demoPlayers)
          player.nickname == me
              ? Player(
                  nickname: player.nickname,
                  avatar: player.avatar,
                  isMe: true,
                  isHost: player.isHost,
                )
              : player,
      ];
}

/// Selecting "הכול" clears the rest; clearing everything falls back to "הכול".
void toggleCategory(Set<String> selected, String name) {
  if (name == demoCategories.first) {
    selected
      ..clear()
      ..add(name);
    return;
  }
  selected.remove(demoCategories.first);
  if (!selected.remove(name)) selected.add(name);
  if (selected.isEmpty) selected.add(demoCategories.first);
}
