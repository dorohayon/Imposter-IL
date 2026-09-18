import 'dart:async';

import 'package:imposter_il/data/server.dart';

/// A WebSocket stand-in: records commands, answers each with `ok` unless a
/// type is listed in [errors], and lets tests push server messages.
class FakeChannel implements RealtimeChannel {
  FakeChannel({
    this.autoReply = true,
    this.emitLeaveState = true,
    this.leaveOutcome = 'loss',
  });

  final bool autoReply;
  final bool emitLeaveState;
  final String leaveOutcome;
  final _incoming = StreamController<Map<String, dynamic>>();
  final sent = <Map<String, dynamic>>[];
  final errors = <String, String>{};
  int _version = 0;

  @override
  Stream<Map<String, dynamic>> get messages => _incoming.stream;

  @override
  void send(Map<String, dynamic> message) {
    sent.add(message);
    final code = errors[message['type']];
    if (message['type'] == 'game.leave' && code == null && emitLeaveState) {
      // Like the server: the player is home before the reply arrives.
      scheduleMicrotask(() => event('session.state', {
            'playerId': 'p_me',
            'activity': 'none',
            'roomId': null,
            'lastGameId': message['payload']['gameId'],
            'lastGameOutcome': leaveOutcome,
          }));
    }
    if (!autoReply) return;
    scheduleMicrotask(() => push({
          'v': 1,
          'type': 'reply',
          'replyTo': message['id'],
          'serverTime': DateTime.now().toUtc().toIso8601String(),
          'ok': code == null,
          if (code != null) 'error': {'code': code},
        }));
  }

  @override
  Future<void> close() => _incoming.close();

  void push(Map<String, dynamic> message) {
    if (!_incoming.isClosed) _incoming.add(message);
  }

  void event(String type, Map<String, dynamic> payload) => push({
        'v': 1,
        'type': type,
        'serverTime': DateTime.now().toUtc().toIso8601String(),
        'payload': payload,
      });

  /// Pushes a snapshot with the next stateVersion, or [version] if given.
  void snapshot(String type, String key, Map<String, dynamic> value,
      {int? version}) {
    _version = version ?? _version + 1;
    event(type, {'stateVersion': _version, key: value});
  }

  List<Map<String, dynamic>> commands(String type) => [
        for (final m in sent)
          if (m['type'] == type) m
      ];
}

/// REST stand-in. [responses] maps "METHOD /path" to a JSON map or an
/// [ApiException]; every connect opens a fresh [FakeChannel].
class FakeApi extends ApiClient {
  FakeApi() : super(Uri.parse('http://fake'));

  final requests = <(String, String, Object?)>[];

  /// Tokens the server no longer knows, as after a restart.
  final unknownTokens = <String>{};
  final channels = <FakeChannel>[];
  Object? connectError;
  bool channelAutoReply = true;
  bool channelEmitLeaveState = true;
  String channelLeaveOutcome = 'loss';

  final responses = <String, Object>{
    'POST /v1/sessions': {'playerId': 'p_me', 'sessionToken': 'token-1'},
    'GET /v1/categories': {
      'categories': [
        {'id': 'food', 'name': 'אוכל'},
        {'id': 'animals', 'name': 'חיות'},
        {'id': 'sports', 'name': 'ספורט'},
        {'id': 'professions', 'name': 'מקצועות'},
        {'id': 'places', 'name': 'מקומות'},
        {'id': 'objects', 'name': 'חפצים'},
      ],
    },
    'GET /v1/reactions': {
      'reactions': [
        {'id': 'laugh', 'text': '😂'},
        {'id': 'suspicious', 'text': 'זה מחשיד'},
      ],
    },
  };

  FakeChannel get channel => channels.last;

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    String? token,
    Object? body,
  }) async {
    requests.add((method, path, body));
    if (unknownTokens.contains(token)) {
      throw const ApiException('session_not_found', 401);
    }
    final response = responses['$method $path'];
    if (response is ApiException) {
      // Mirror ApiClient: the real one reports this before it throws.
      if (response.code == 'client_too_old') onClientTooOld?.call();
      throw response;
    }
    if (response == null) throw ApiException('unexpected $method $path');
    return response as Map<String, dynamic>;
  }

  @override
  Future<RealtimeChannel> connect(String token) async {
    if (connectError != null) throw connectError!;
    final channel = FakeChannel(
      autoReply: channelAutoReply,
      emitLeaveState: channelEmitLeaveState,
      leaveOutcome: channelLeaveOutcome,
    );
    channels.add(channel);
    return channel;
  }
}

Map<String, dynamic> player(String id, String nickname,
        {bool connected = true,
        String status = 'active',
        int disconnects = 0,
        bool roleConfirmed = false}) =>
    {
      'playerId': id,
      'nickname': nickname,
      'avatarId': 'avatar-m04-detective-hat',
      'connected': connected,
      'status': status,
      'disconnects': disconnects,
      'roleConfirmed': roleConfirmed,
    };

Map<String, dynamic> roomJson({
  String host = 'p_me',
  List<Map<String, dynamic>>? players,
  String status = 'lobby',
}) =>
    {
      'roomId': 'r_1',
      'code': '482913',
      'status': status,
      'hostPlayerId': host,
      'maxPlayers': 8,
      'hintSeconds': 15,
      'categoryIds': ['food', 'animals'],
      'settingsLocked': false,
      'players': players ?? [player('p_me', 'דור')],
      'hostTransfer': null,
      'hostReconnectDeadline': null,
    };

final _deadline =
    DateTime.now().add(const Duration(seconds: 15)).toUtc().toIso8601String();

Map<String, dynamic> gameJson({
  required String phase,
  int round = 1,
  String role = 'citizen',
  String? turn,
  List<Map<String, dynamic>> hints = const [],
  List<String> candidates = const [],
  Map<String, int> previousVotes = const {},
  String? myVote,
  Map<String, dynamic>? result,
  List<Map<String, dynamic>>? players,
}) =>
    {
      'gameId': 'g_1',
      'round': round,
      'phase': phase,
      'deadline': phase == 'ended' ? null : _deadline,
      'category': 'חיות',
      if (role == 'citizen' || phase == 'ended') 'secretWord': 'פיל',
      'myRole': role,
      'players': players ??
          [
            player('p_me', 'דור'),
            player('p_2', 'נועה'),
            player('p_3', 'יובל'),
            player('p_4', 'מאיה'),
          ],
      'currentTurnPlayerId': turn,
      'awaitingReconnect': false,
      'hints': hints,
      'voteCandidates': candidates,
      'previousVotes': previousVotes,
      'myVote': myVote,
      'result': result,
    };
