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
  GameSession(this.api, {this.reconnectDelay = const Duration(seconds: 2)});

  final ApiClient api;
  final Duration reconnectDelay;

  static const _tokenKey = 'session.token';
  static const _playerKey = 'session.playerId';
  static const _nicknameKey = 'session.nickname';
  static const _avatarKey = 'session.avatarId';

  String? token;
  String? playerId;
  String? nickname;
  String? avatarId;

  List<Category> categories = const [];
  List<ReactionOption> reactions = const [];

  bool connected = false;

  /// The server lost this session mid-room or mid-game (for example it
  /// restarted). No loss is recorded; screen 29 is shown until dismissed.
  bool sessionLost = false;

  String activity = 'none'; // none | room | game
  String? roomId;
  String? gameId;
  RoomView? room;
  GameView? game;

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
      if (e.code == 'session_not_found') await _replaceLostSession();
    }
    unawaited(_connectLoop());
  }

  Future<void> loadContent() async {
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
    _notify();
  }

  /// The server no longer knows the token (a restart loses every session).
  /// A new session with the same nickname and avatar replaces it.
  Future<void> _replaceLostSession() async {
    if (activity != 'none') sessionLost = true;
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
    while (!_disposed && signedIn) {
      try {
        final channel = await api.connect(token!);
        _channel = channel;
        connected = true;
        _notify();
        await for (final message in channel.messages) {
          _onMessage(message);
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
      connected = false;
      _failPending();
      _notify();
      if (_disposed) break;
      await Future<void>.delayed(reconnectDelay);
    }
    _loopRunning = false;
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
        final newRoom = payload['roomId'] as String?;
        if (newRoom != roomId) _lastVersion = 0; // versions count per room
        activity = payload['activity'] as String;
        roomId = newRoom;
        gameId = payload['gameId'] as String?;
        if (activity == 'none') room = null;
        if (activity != 'game') game = null;
      case 'room.state':
        if (!_isNewer(payload)) return;
        room = RoomView.fromJson(payload['room'] as Map<String, dynamic>);
      case 'game.state':
        if (!_isNewer(payload)) return;
        game = GameView.fromJson(payload['game'] as Map<String, dynamic>);
      case 'room.kicked':
        kicked = true;
      default:
        return; // game.reaction and unknown types need no state change
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
    final json = await api.request(
      'POST',
      '/v1/rooms',
      token: token,
      body: {
        'maxPlayers': maxPlayers,
        'hintSeconds': hintSeconds,
        'categoryIds': categoryIds,
      },
    );
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

  Future<String?> leaveRoom() async {
    final id = roomId;
    _clearActivity();
    _notify();
    return id == null ? null : send('room.leave', {'roomId': id});
  }

  Future<String?> leaveGame() async {
    final id = gameId ?? game?.id;
    _clearActivity();
    _notify();
    return id == null ? null : send('game.leave', {'gameId': id});
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
