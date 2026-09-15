// Typed views of the protocol objects in docs/protocol.md.

DateTime? _time(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

List<Map<String, dynamic>> _list(Object? value) =>
    (value as List? ?? const []).cast<Map<String, dynamic>>();

class Category {
  const Category({required this.id, required this.name});

  factory Category.fromJson(Map<String, dynamic> json) =>
      Category(id: json['id'] as String, name: json['name'] as String);

  final String id;
  final String name;
}

class ReactionOption {
  const ReactionOption({required this.id, required this.text});

  factory ReactionOption.fromJson(Map<String, dynamic> json) =>
      ReactionOption(id: json['id'] as String, text: json['text'] as String);

  final String id;
  final String text;
}

class PlayerInfo {
  const PlayerInfo({
    required this.id,
    required this.nickname,
    required this.avatarId,
    this.connected = true,
    this.status = 'active',
    this.disconnects = 0,
    this.roleConfirmed = false,
  });

  factory PlayerInfo.fromJson(Map<String, dynamic> json) => PlayerInfo(
        id: json['playerId'] as String,
        nickname: json['nickname'] as String? ?? '',
        avatarId: json['avatarId'] as String? ?? '',
        connected: json['connected'] as bool? ?? true,
        status: json['status'] as String? ?? 'active',
        disconnects: json['disconnects'] as int? ?? 0,
        roleConfirmed: json['roleConfirmed'] as bool? ?? false,
      );

  final String id;
  final String nickname;
  final String avatarId;
  final bool connected;
  final String status; // active | left | removed
  final int disconnects;
  final bool roleConfirmed;

  String get avatarAsset => 'assets/avatars/$avatarId.webp';
}

class HostTransfer {
  const HostTransfer({required this.from, required this.to});

  final String from;
  final String to;
}

class RoomView {
  const RoomView({
    required this.id,
    required this.code,
    required this.status,
    required this.hostId,
    required this.maxPlayers,
    required this.hintSeconds,
    required this.categoryIds,
    required this.settingsLocked,
    required this.players,
    this.hostTransfer,
    this.hostReconnectDeadline,
  });

  factory RoomView.fromJson(Map<String, dynamic> json) {
    final transfer = json['hostTransfer'] as Map<String, dynamic>?;
    return RoomView(
      id: json['roomId'] as String,
      code: json['code'] as String,
      status: json['status'] as String,
      hostId: json['hostPlayerId'] as String?,
      maxPlayers: json['maxPlayers'] as int,
      hintSeconds: json['hintSeconds'] as int,
      categoryIds: (json['categoryIds'] as List).cast<String>(),
      settingsLocked: json['settingsLocked'] as bool,
      players: _list(json['players']).map(PlayerInfo.fromJson).toList(),
      hostTransfer: transfer == null
          ? null
          : HostTransfer(
              from: transfer['fromPlayerId'] as String,
              to: transfer['toPlayerId'] as String,
            ),
      hostReconnectDeadline: _time(json['hostReconnectDeadline']),
    );
  }

  final String id;
  final String code;
  final String status; // lobby | in_game
  final String? hostId; // null while waiting for someone to take over
  final int maxPlayers;
  final int hintSeconds;
  final List<String> categoryIds;
  final bool settingsLocked;
  final List<PlayerInfo> players;
  final HostTransfer? hostTransfer;
  final DateTime? hostReconnectDeadline;

  PlayerInfo? player(String? id) {
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }
}

class HintView {
  const HintView({
    required this.playerId,
    required this.text,
    required this.missing,
    required this.reactions,
  });

  factory HintView.fromJson(Map<String, dynamic> json) => HintView(
        playerId: json['playerId'] as String,
        text: json['text'] as String? ?? '',
        missing: json['missing'] as bool? ?? false,
        reactions: (json['reactions'] as Map? ?? const {}).cast<String, int>(),
      );

  final String playerId;
  final String text;
  final bool missing;
  final Map<String, int> reactions;
}

class GameResult {
  const GameResult({
    required this.winner,
    required this.reason,
    required this.impostorId,
    required this.secretWord,
    required this.voteRounds,
    required this.outcomes,
  });

  factory GameResult.fromJson(Map<String, dynamic> json) => GameResult(
        winner: json['winner'] as String?,
        reason: json['reason'] as String,
        impostorId: json['impostorPlayerId'] as String,
        secretWord: json['secretWord'] as String,
        voteRounds: (json['voteRounds'] as List? ?? const [])
            .map((round) => (round as Map).cast<String, String>())
            .toList(),
        outcomes: (json['outcomes'] as Map? ?? const {}).cast<String, String>(),
      );

  final String? winner; // citizens | impostor | null when stopped
  final String reason;
  final String impostorId;
  final String secretWord;
  final List<Map<String, String>> voteRounds;
  final Map<String, String> outcomes;
}

class GameView {
  const GameView({
    required this.id,
    required this.phase,
    required this.deadline,
    required this.category,
    required this.secretWord,
    required this.myRole,
    required this.players,
    required this.currentTurnPlayerId,
    required this.awaitingReconnect,
    required this.hints,
    required this.voteCandidates,
    required this.myVote,
    required this.result,
  });

  factory GameView.fromJson(Map<String, dynamic> json) {
    final result = json['result'] as Map<String, dynamic>?;
    return GameView(
      id: json['gameId'] as String,
      phase: json['phase'] as String,
      deadline: _time(json['deadline']),
      category: json['category'] as String? ?? '',
      secretWord: json['secretWord'] as String?,
      myRole: json['myRole'] as String,
      players: _list(json['players']).map(PlayerInfo.fromJson).toList(),
      currentTurnPlayerId: json['currentTurnPlayerId'] as String?,
      awaitingReconnect: json['awaitingReconnect'] as bool? ?? false,
      hints: _list(json['hints']).map(HintView.fromJson).toList(),
      voteCandidates:
          (json['voteCandidates'] as List? ?? const []).cast<String>(),
      myVote: json['myVote'] as String?,
      result: result == null ? null : GameResult.fromJson(result),
    );
  }

  final String id;
  final String phase;
  final DateTime? deadline;
  final String category;
  final String? secretWord; // absent for the impostor until the end
  final String myRole; // citizen | impostor
  final List<PlayerInfo> players; // turn order
  final String? currentTurnPlayerId;
  final bool awaitingReconnect;
  final List<HintView> hints;
  final List<String> voteCandidates;
  final String? myVote;
  final GameResult? result;

  bool get isImpostor => myRole == 'impostor';

  PlayerInfo? player(String? id) {
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }

  HintView? hintOf(String playerId) {
    for (final h in hints) {
      if (h.playerId == playerId) return h;
    }
    return null;
  }
}

class MatchmakingView {
  const MatchmakingView({
    required this.status,
    required this.categoryIds,
    required this.players,
    required this.targetPlayers,
    required this.maxPlayers,
    required this.deadline,
  });

  factory MatchmakingView.fromJson(Map<String, dynamic> json) =>
      MatchmakingView(
        status: json['status'] as String,
        categoryIds: (json['categoryIds'] as List? ?? const []).cast<String>(),
        players: _list(json['players']).map(PlayerInfo.fromJson).toList(),
        targetPlayers: json['targetPlayers'] as int? ?? 6,
        maxPlayers: json['maxPlayers'] as int? ?? 8,
        deadline: _time(json['deadline']),
      );

  final String status; // searching | waiting_for_more | countdown
  final List<String> categoryIds;
  final List<PlayerInfo> players;
  final int targetPlayers;
  final int maxPlayers;

  /// When "no match" shows while searching, otherwise when the game starts.
  final DateTime? deadline;
}
