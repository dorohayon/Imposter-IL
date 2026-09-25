import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/server.dart';

/// The player's connection to the server: guest identity, live WebSocket,
/// and the latest room and game snapshots. Screens read it through
/// [SessionScope] and rebuild when it changes.
class GameSession extends ChangeNotifier {
  GameSession(this.api, {this.reconnectDelay = const Duration(seconds: 2)}) {
    api.onClientTooOld = () {
      if (needsUpdate) return;
      needsUpdate = true;
      _notify();
    };
  }

  final ApiClient api;
  final Duration reconnectDelay;

  static const _tokenKey = 'session.token';
  static const _playerKey = 'session.playerId';
  static const _nicknameKey = 'session.nickname';
  static const _avatarKey = 'session.avatarId';
  static const _winsKey = 'stats.wins';
  static const _lossesKey = 'stats.losses';
  static const _countedKey = 'stats.countedGames';
  static const _vibrationKey = 'settings.vibration';
  static const _reactionsKey = 'settings.showReactions';
  static const _mutedKey = 'moderation.muted';

  String? token;
  String? playerId;
  String? nickname;
  String? avatarId;

  List<Category> categories = const [];
  List<ReactionOption> reactions = const [];
  bool contentLoading = false;
  bool contentLoaded = false;
  String? contentError;

  bool connected = false;

  /// A game the player chose to leave while offline. It remains pending until
  /// the server confirms that this session is no longer in that game.
  String? _pendingGameLeave;
  bool _pendingGameLeaveInFlight = false;

  /// A search cancelled while offline. The server keeps a dropped searcher's
  /// place for 30 seconds, so the cancel is sent again once reconnected.
  bool _pendingSearchCancel = false;
  bool _pendingSearchCancelInFlight = false;

  /// While disconnected: when the server stops holding this player's turn
  /// (docs/decisions.md, 30 seconds), for the reconnecting overlay.
  DateTime? reconnectDeadline;

  // Saved on this device only (docs/decisions.md).
  int wins = 0;
  int losses = 0;
  List<String> _countedGames = [];
  bool vibrationOn = true;
  bool showReactions = true;

  /// Sends this device's purchases to the server again. Set by Monetization;
  /// used when the server refuses a category as locked, which means it has
  /// not seen a purchase the device has.
  Future<void> Function()? resyncEntitlements;

  /// Set by the clue screen so a reaction can pop from the card of whoever
  /// sent it. Only one screen shows reactions, so one slot is enough.
  void Function(String playerId, String reactionId)? onReaction;

  /// Players this device reported. Their hints are hidden here from then on.
  ///
  /// Kept on the device because a player id lasts only as long as a guest
  /// session: there are no accounts, so there is nothing durable to block.
  /// Reports still reach the server, which is what the stores require.
  Set<String> muted = {};

  /// The server lost this session mid-room or mid-game (for example it
  /// restarted). No loss is recorded; screen 29 is shown until dismissed.
  bool sessionLost = false;

  /// The server no longer serves this build. Nothing else works until the
  /// player updates, so this one is not dismissible.
  bool needsUpdate = false;

  String activity = 'none'; // none | matchmaking | room | game
  String? roomId;
  String? gameId;
  RoomView? room;
  GameView? game;
  MatchmakingView? search;

  /// The categories of an online search that found no match, until the
  /// player retries or picks other categories.
  List<String>? noMatchCategories;

  /// Set when the host removed this player, until the screen consumes it.
  bool kicked = false;

  /// Server time minus local time, from the last message's `serverTime`.
  Duration serverOffset = Duration.zero;

  RealtimeChannel? _channel;
  final _pending = <String, Completer<String?>>{};
  int _lastVersion = 0;
  final _random = Random();
  bool _disposed = false;
  bool _loopRunning = false;

  bool get signedIn => token != null;

  DateTime get serverNow => DateTime.now().add(serverOffset);

  /// Loads the saved identity. Content and the connection load in the
  /// background; a session the server no longer knows is recreated.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_tokenKey);
    playerId = prefs.getString(_playerKey);
    nickname = prefs.getString(_nicknameKey);
    avatarId = prefs.getString(_avatarKey);
    wins = prefs.getInt(_winsKey) ?? 0;
    losses = prefs.getInt(_lossesKey) ?? 0;
    _countedGames = prefs.getStringList(_countedKey) ?? [];
    vibrationOn = prefs.getBool(_vibrationKey) ?? true;
    showReactions = prefs.getBool(_reactionsKey) ?? true;
    muted = (prefs.getStringList(_mutedKey) ?? const []).toSet();
    if (signedIn) unawaited(_start());
  }

  /// Creates a guest session. Throws [ApiException] (for example
  /// `invalid_nickname` or `network_error`).
  Future<void> signIn(String nickname, String avatarId) async {
    final json = await api.request(
      'POST',
      '/v1/sessions',
      body: {'nickname': nickname, 'avatarId': avatarId},
    );
    await _saveIdentity(
      json['sessionToken'] as String,
      json['playerId'] as String,
      nickname.trim(),
      avatarId,
    );
    await _start();
  }

  Future<void> _saveIdentity(
    String token,
    String playerId,
    String nickname,
    String avatarId,
  ) async {
    this.token = token;
    this.playerId = playerId;
    this.nickname = nickname;
    this.avatarId = avatarId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_playerKey, playerId);
    await prefs.setString(_nicknameKey, nickname);
    await prefs.setString(_avatarKey, avatarId);
    _notify();
  }

  Future<void> _start() async {
    try {
      await loadContent();
    } on ApiException catch (e) {
      if (e.code == 'session_not_found') {
        try {
          await _replaceLostSession();
        } on ApiException {
          // The content error state already exposes retry to the player.
        }
      }
    }
    unawaited(_connectLoop());
  }

  Future<void> loadContent() async {
    contentLoading = true;
    contentError = null;
    _notify();
    try {
      final results = await Future.wait([
        api.request('GET', '/v1/categories', token: token),
        api.request('GET', '/v1/reactions', token: token),
      ]);
      categories = (results[0]['categories'] as List)
          .cast<Map<String, dynamic>>()
          .map(Category.fromJson)
          .toList();
      reactions = (results[1]['reactions'] as List)
          .cast<Map<String, dynamic>>()
          .map(ReactionOption.fromJson)
          .toList();
      contentLoaded = true;
    } on ApiException catch (e) {
      contentError = e.code;
      rethrow;
    } on Object {
      contentError = 'internal_error';
      rethrow;
    } finally {
      contentLoading = false;
      _notify();
    }
  }

  /// The server no longer knows the token (a restart loses every session).
  /// A new session with the same nickname and avatar replaces it.
  ///
  /// [silently] is for a token another device now holds: nothing failed, so
  /// the server-error screen would be wrong.
  Future<void> _replaceLostSession({bool silently = false}) async {
    if (!silently && activity != 'none') sessionLost = true;
    // A restarted server cannot confirm an old leave and must never turn that
    // infrastructure failure into a local loss.
    _pendingGameLeave = null;
    _pendingGameLeaveInFlight = false;
    _pendingSearchCancel = false;
    _clearActivity();
    final json = await api.request(
      'POST',
      '/v1/sessions',
      body: {'nickname': nickname, 'avatarId': avatarId},
    );
    await _saveIdentity(
      json['sessionToken'] as String,
      json['playerId'] as String,
      nickname!,
      avatarId!,
    );
    await loadContent();
  }

  Future<void> _connectLoop() async {
    if (_loopRunning) return;
    _loopRunning = true;
    var failures = 0;
    while (!_disposed && signedIn) {
      try {
        final channel = await api.connect(token!);
        _channel = channel;
        failures = 0;
        connected = true;
        reconnectDeadline = null;
        _notify();
        await for (final message in channel.messages) {
          _onMessage(message);
        }
        if (channel.closeReason == replacedByNewConnection) {
          // The same token connected from another phone (a backup restored
          // onto a new one). There is no login, so this device simply becomes
          // a new guest with the same nickname and avatar; reconnecting with
          // the old token would only take the connection back and forth.
          _channel = null;
          connected = false;
          _failPending();
          try {
            await _replaceLostSession(silently: true);
          } on ApiException {
            // Unreachable for now; the loop retries with the old token and
            // gets here again if the other device still holds it.
          }
          _notify();
          continue;
        }
      } on Object {
        // Could not connect: check whether the session itself is gone.
        try {
          await api.request('GET', '/v1/categories', token: token);
        } on ApiException catch (e) {
          if (e.code == 'session_not_found') {
            try {
              await _replaceLostSession();
              continue;
            } on ApiException {
              // Still unreachable; retry below.
            }
          }
        }
      }
      _channel = null;
      if (connected) reconnectDeadline = _holdDeadline();
      connected = false;
      _failPending();
      _notify();
      if (_disposed) break;
      // Back off (x1, x2, x4) with jitter, so a restarted server is not hit by
      // every client in the same instant — except while a game holds the
      // player's seat: those 30 seconds are theirs to get back in.
      final backoff = reconnectDeadline != null
          ? reconnectDelay
          : reconnectDelay * (1 << (failures < 2 ? failures : 2));
      failures++;
      await Future<void>.delayed(
        backoff + reconnectDelay * _random.nextDouble(),
      );
    }
    _loopRunning = false;
  }

  /// How long a dropped player has before the drop counts: 30 seconds in any
  /// phase (docs/decisions.md). A hint turn keeps its own clock while they
  /// are away, so during their turn it may be less. A turn that comes up
  /// while offline is not known here.
  DateTime? _holdDeadline() {
    final current = activity == 'game' ? game : null;
    final me = current?.player(playerId);
    if (current == null || me == null || current.phase == 'ended') return null;
    final hold = serverNow.add(const Duration(seconds: 30));
    final turnEnds = current.deadline;
    final myTurn =
        current.phase == 'hints' && current.currentTurnPlayerId == playerId;
    return myTurn && turnEnds != null && turnEnds.isBefore(hold)
        ? turnEnds
        : hold;
  }

  void _onMessage(Map<String, dynamic> message) {
    final serverTime = message['serverTime'] as String?;
    if (serverTime != null) {
      serverOffset = DateTime.parse(serverTime).difference(DateTime.now());
    }
    final payload = message['payload'] as Map<String, dynamic>? ?? const {};
    switch (message['type']) {
      case 'reply':
        final error = message['error'] as Map<String, dynamic>?;
        _pending
            .remove(message['replyTo'])
            ?.complete(error?['code'] as String?);
        return;
      case 'session.state':
        if (_pendingSearchCancel) {
          if (payload['activity'] == 'matchmaking') {
            // Still searching on the server: stay home and cancel it there.
            unawaited(_retryPendingSearchCancel());
            return;
          }
          _pendingSearchCancel = false;
        }
        final outcomeGameId = payload['lastGameId'] as String?;
        final outcome = payload['lastGameOutcome'] as String?;
        if (outcomeGameId != null && outcome != null) {
          _record(outcomeGameId, outcome);
        }
        final leaving = _pendingGameLeave;
        if (leaving != null) {
          if (payload['gameId'] == leaving) {
            // Keep the local UI at home while retrying. The pending id is not
            // cleared until the command is acknowledged, so another dropped
            // connection cannot pull the player back into this game.
            unawaited(_retryPendingGameLeave());
            return;
          }
          _pendingGameLeave = null;
          _pendingGameLeaveInFlight = false;
        }
        final newRoom = payload['roomId'] as String?;
        if (newRoom != roomId) _lastVersion = 0; // versions count per room
        activity = payload['activity'] as String;
        roomId = newRoom;
        gameId = payload['gameId'] as String?;
        if (activity == 'none') room = null;
        if (activity != 'game') game = null;
        if (activity != 'matchmaking') search = null;
      case 'room.state':
        if (!_isNewer(payload)) return;
        room = RoomView.fromJson(payload['room'] as Map<String, dynamic>);
      case 'game.state':
        if (!_isNewer(payload)) return;
        game = GameView.fromJson(payload['game'] as Map<String, dynamic>);
        final me = game!.player(playerId);
        final outcome =
            me?.status == 'removed' ? 'loss' : game!.result?.outcomes[playerId];
        if (outcome != null) _record(game!.id, outcome);
      case 'matchmaking.state':
        if (!_isNewer(payload)) return;
        search = MatchmakingView.fromJson(payload);
      case 'matchmaking.noMatch':
        noMatchCategories =
            (payload['categoryIds'] as List? ?? const []).cast<String>();
      case 'room.kicked':
        kicked = true;
      case 'game.aborted':
        // The server ended the game on its side (a recovered crash, or a
        // shutdown that outlasted draining): screen 29, no loss recorded.
        // The session.state that follows sends the player home, and without
        // this they got there silently, with no word of what happened.
        sessionLost = true;
      case 'game.reaction':
        // The only message that names who reacted; game.state carries counts
        // alone. Nothing to store, so the screen animates it and it is gone.
        onReaction?.call(
          payload['playerId'] as String? ?? '',
          payload['reactionId'] as String? ?? '',
        );
        return;
      default:
        return; // unknown types need no state change
    }
    _notify();
  }

  /// Snapshots with a stateVersion no higher than the last one are stale.
  bool _isNewer(Map<String, dynamic> payload) {
    final version = payload['stateVersion'] as int? ?? 0;
    if (version <= _lastVersion) return false;
    _lastVersion = version;
    return true;
  }

  /// Sends a command and returns its error code, or null on success.
  Future<String?> send(String type, Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null) return Future.value('network_error');
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
    final reply = Completer<String?>();
    _pending[id] = reply;
    channel.send({'v': 1, 'id': id, 'type': type, 'payload': payload});
    return reply.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pending.remove(id);
        return 'network_error';
      },
    );
  }

  void _failPending() {
    for (final reply in _pending.values) {
      reply.complete('network_error');
    }
    _pending.clear();
  }

  /// Creates a private room; the player becomes its host. Throws [ApiException].
  Future<void> createRoom({
    required int maxPlayers,
    required int hintSeconds,
    required List<String> categoryIds,
  }) async {
    final body = {
      'maxPlayers': maxPlayers,
      'hintSeconds': hintSeconds,
      'categoryIds': categoryIds,
    };
    Map<String, dynamic> json;
    try {
      json = await api.request('POST', '/v1/rooms', token: token, body: body);
    } on ApiException catch (e) {
      if (e.code != 'category_locked' || resyncEntitlements == null) rethrow;
      await resyncEntitlements!();
      json = await api.request('POST', '/v1/rooms', token: token, body: body);
    }
    _enterRoom(json['room'] as Map<String, dynamic>);
  }

  /// Joins a room by code. Throws [ApiException].
  Future<void> joinRoom(String code) async {
    final json = await api.request(
      'POST',
      '/v1/rooms/join',
      token: token,
      body: {'code': code},
    );
    _enterRoom(json['room'] as Map<String, dynamic>);
  }

  void _enterRoom(Map<String, dynamic> json) {
    final entered = RoomView.fromJson(json);
    if (entered.id != roomId) _lastVersion = 0;
    activity = 'room';
    roomId = entered.id;
    room = entered;
    game = null;
    _notify();
  }

  /// Leaves the room once the server confirms it. Returns an error code, or
  /// null when the player is out.
  Future<String?> leaveRoom() => _leave('room.leave', 'roomId', roomId);

  /// Leaves the game (and its room) once the server confirms it.
  Future<String?> leaveGame() =>
      _leave('game.leave', 'gameId', gameId ?? game?.id);

  Future<void> _retryPendingSearchCancel() async {
    if (!_pendingSearchCancel || _pendingSearchCancelInFlight || !connected) {
      return;
    }
    _pendingSearchCancelInFlight = true;
    final code = await send('matchmaking.cancel', {});
    _pendingSearchCancelInFlight = false;
    // The server's cancel always succeeds; a network error keeps it pending.
    if (code == null) _pendingSearchCancel = false;
  }

  Future<void> _retryPendingGameLeave() async {
    final id = _pendingGameLeave;
    if (id == null || _pendingGameLeaveInFlight || !connected) return;
    _pendingGameLeaveInFlight = true;
    final code = await send('game.leave', {'gameId': id});
    _pendingGameLeaveInFlight = false;
    if (_pendingGameLeave != id) return;
    if (code == null || code == 'room_not_found' || code == 'game_not_found') {
      _pendingGameLeave = null;
    }
    // A network error deliberately leaves the id pending for the next socket.
    _notify();
  }

  Future<String?> _leave(String type, String key, String? id) async {
    if (type == 'game.leave' && id != null && !connected) {
      // Leaving while offline is immediate locally, then retried after every
      // reconnect until the server confirms it. The authoritative outcome is
      // delivered in session.state, so a stale local snapshot cannot turn a
      // completed win into a loss.
      _pendingGameLeave = id;
      _pendingGameLeaveInFlight = false;
      _clearActivity();
      _notify();
      return null;
    }
    final code = id == null ? null : await send(type, {key: id});
    // The host started the next game while this leave was on its way: the
    // player is in that game now. Show it, where they can still leave, rather
    // than a home screen that leaves an unseen player sitting at the table.
    if (type == 'game.leave' &&
        code == 'game_not_found' &&
        activity == 'game' &&
        gameId != null &&
        gameId != id) {
      return 'room_in_game';
    }
    // Not found means the server no longer has the player there.
    if (code != null && code != 'room_not_found' && code != 'game_not_found') {
      return code;
    }
    _clearActivity();
    _notify();
    return null;
  }

  /// Starts an online search. Returns an error code, or null on success.
  Future<String?> startSearch(List<String> categoryIds) async {
    final retryOf = noMatchCategories;
    noMatchCategories = null;
    activity = 'matchmaking'; // until session.state confirms it
    search = null;
    _notify();
    var code = await send('matchmaking.join', {'categoryIds': categoryIds});
    if (code == 'category_locked' && resyncEntitlements != null) {
      await resyncEntitlements!();
      code = await send('matchmaking.join', {'categoryIds': categoryIds});
    }
    if (code != null) {
      activity = 'none';
      noMatchCategories = retryOf; // keep the no-match screen to try again
      _notify();
    }
    return code;
  }

  /// Cancels the online search once the server confirms it. Without a
  /// connection it is cancelled here at once and again on the server after
  /// reconnecting, since the server holds a dropped searcher's place.
  Future<String?> cancelSearch() async {
    final code = await send('matchmaking.cancel', {});
    if (code != null && connected) return code;
    if (code != null) _pendingSearchCancel = true;
    _clearActivity();
    _notify();
    return null;
  }

  void dismissNoMatch() {
    noMatchCategories = null;
    _notify();
  }

  /// Counts a game's win or loss once. Server errors never reach here, so a
  /// crash records nothing.
  void _record(String gameId, String outcome) {
    // A match that was called off counts for nobody, so nothing is recorded —
    // not even the fact that it happened, in case it resumes as a real one.
    if (outcome == 'none') return;
    if (_countedGames.contains(gameId)) return;
    _countedGames = [..._countedGames, gameId];
    if (_countedGames.length > 50) _countedGames.removeAt(0);
    outcome == 'win' ? wins++ : losses++;
    unawaited(
      SharedPreferences.getInstance().then((prefs) async {
        await prefs.setInt(_winsKey, wins);
        await prefs.setInt(_lossesKey, losses);
        await prefs.setStringList(_countedKey, _countedGames);
      }),
    );
  }

  /// Reports a player for what they wrote and hides their text on this
  /// device. Returns an error code, or null on success.
  Future<String?> reportPlayer(String playerId, {int? hintIndex}) async {
    final code = await send('game.report', {
      'gameId': gameId ?? game?.id,
      'playerId': playerId,
      if (hintIndex != null) 'hintIndex': hintIndex,
    });
    // The mute is this device's own and holds even if the report did not
    // reach the server.
    muted = {...muted, playerId};
    _notify();
    await (await SharedPreferences.getInstance())
        .setStringList(_mutedKey, muted.toList());
    return code;
  }

  /// Whether this player's clues are hidden here: reported from this device,
  /// or reported by enough of the table that the server withholds them.
  bool hides(String playerId) =>
      muted.contains(playerId) || (game?.hiddenForAll(playerId) ?? false);

  /// Forgets every report made on this device, so those hints show again.
  Future<void> clearMuted() async {
    muted = {};
    _notify();
    await (await SharedPreferences.getInstance()).remove(_mutedKey);
  }

  /// Changes the nickname and avatar on the server. Throws [ApiException].
  Future<void> updateProfile(String nickname, String avatarId) async {
    await api.request(
      'PATCH',
      '/v1/sessions/me',
      token: token,
      body: {'nickname': nickname, 'avatarId': avatarId},
    );
    await _saveIdentity(token!, playerId!, nickname.trim(), avatarId);
  }

  Future<void> setVibration(bool on) async {
    vibrationOn = on;
    _notify();
    await (await SharedPreferences.getInstance()).setBool(_vibrationKey, on);
  }

  Future<void> setShowReactions(bool on) async {
    showReactions = on;
    _notify();
    await (await SharedPreferences.getInstance()).setBool(_reactionsKey, on);
  }

  void consumeKicked() {
    kicked = false;
    _clearActivity();
    _notify();
  }

  void dismissSessionLost() {
    sessionLost = false;
    _notify();
  }

  void _clearActivity() {
    activity = 'none';
    roomId = null;
    gameId = null;
    room = null;
    game = null;
    search = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_channel?.close());
    _failPending();
    super.dispose();
  }
}

class SessionScope extends InheritedNotifier<GameSession> {
  const SessionScope({
    required GameSession session,
    required super.child,
    super.key,
  }) : super(notifier: session);

  static GameSession of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;

  /// Reads the session without rebuilding when it changes, for callbacks.
  static GameSession read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SessionScope>()!.notifier!;
}
