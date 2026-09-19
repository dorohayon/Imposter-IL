import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_game.dart';

/// Where a one-device match in progress lives between app launches.
///
/// The phone is the whole game: there is no server holding a copy, so a match
/// that is not written down is a match that is lost when somebody's phone
/// rings. Written after every move, and read back on the home screen so the
/// table can carry on.
class LocalStore {
  static const _key = 'local.game';

  /// The match in progress, or null if there is none to carry on.
  static Future<LocalGame?> load({Random? rng}) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved == null) return null;
    try {
      final game = localGameFromJson(
        jsonDecode(saved) as Map<String, dynamic>,
        rng: rng,
      );
      if (game == null) await prefs.remove(_key);
      return game;
    } on Object {
      await prefs.remove(_key);
      return null;
    }
  }

  static Future<void> save(LocalGame game) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(game.toJson()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
