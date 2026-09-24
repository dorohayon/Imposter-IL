import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// This build's number: the part after `+` in pubspec.yaml's `version`.
/// CI checks the two agree (.github/workflows/app.yml).
///
/// Sent as `X-Client-Build` on every request. A store release stays installed
/// for years, so the server's MIN_CLIENT_BUILD is the only way to retire a
/// build whose protocol it no longer speaks; without the header there would be
/// no way to tell an old install to update instead of failing strangely.
const clientBuild = 4;

const productionServerUrl = 'https://imposter-eegbs6v5uq-uc.a.run.app';

/// The game server. Override with --dart-define=IMPOSTER_SERVER=https://host.
/// Release builds must work on a physical phone without a build flag, while
/// debug builds keep pointing at the developer machine/emulator by default.
Uri defaultServerUrl({bool releaseMode = kReleaseMode}) {
  const configured = String.fromEnvironment('IMPOSTER_SERVER');
  if (configured.isNotEmpty) return Uri.parse(configured);
  if (releaseMode) return Uri.parse(productionServerUrl);
  // The Android emulator reaches the development machine at 10.0.2.2.
  return Uri.parse(
    Platform.isAndroid ? 'http://10.0.2.2:8080' : 'http://localhost:8080',
  );
}

/// A protocol error code from the server (docs/protocol.md), or
/// `network_error` when the server could not be reached.
class ApiException implements Exception {
  const ApiException(this.code, [this.status = 0]);

  final String code;
  final int status;

  @override
  String toString() => 'ApiException($status $code)';
}

/// REST calls and WebSocket connections to one server.
class ApiClient {
  ApiClient(this.baseUrl);

  final Uri baseUrl;

  /// Called when the server refuses this build (`client_too_old`).
  void Function()? onClientTooOld;

  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    String? token,
    Object? body,
  }) async {
    try {
      final request = await _http.openUrl(method, baseUrl.resolve(path));
      request.headers.set('X-Client-Build', '$clientBuild');
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }
      final response = await request.close().timeout(
            const Duration(seconds: 15),
          );
      final text = await response.transform(utf8.decoder).join();
      final json = text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        final error = json['error'] as Map<String, dynamic>?;
        final code = error?['code'] as String? ?? 'internal_error';
        if (code == 'client_too_old') onClientTooOld?.call();
        throw ApiException(code, response.statusCode);
      }
      return json;
    } on ApiException {
      rethrow;
    } on Object {
      throw const ApiException('network_error');
    }
  }

  Future<RealtimeChannel> connect(String token) async {
    final url = baseUrl.replace(
      scheme: baseUrl.scheme == 'https' ? 'wss' : 'ws',
      path: '/v1/ws',
    );
    final socket = await WebSocket.connect(
      url.toString(),
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer $token',
        'X-Client-Build': '$clientBuild',
      },
    ).timeout(const Duration(seconds: 10));
    return _WebSocketChannel(socket);
  }
}

/// One WebSocket connection carrying protocol envelopes as JSON maps.
abstract interface class RealtimeChannel {
  /// Incoming messages; the stream ends when the connection closes.
  Stream<Map<String, dynamic>> get messages;

  void send(Map<String, dynamic> message);

  Future<void> close();
}

class _WebSocketChannel implements RealtimeChannel {
  _WebSocketChannel(this._socket);

  final WebSocket _socket;

  @override
  Stream<Map<String, dynamic>> get messages => _socket
      .where((data) => data is String)
      .map((data) => jsonDecode(data as String) as Map<String, dynamic>);

  @override
  void send(Map<String, dynamic> message) => _socket.add(jsonEncode(message));

  @override
  Future<void> close() => _socket.close();
}
