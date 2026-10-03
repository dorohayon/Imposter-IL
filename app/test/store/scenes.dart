// The app as the store shows it: a believable game, in each language, driven
// through the real screens against the fake server. Shared by the screenshots
// and the preview video (store_test.dart, docs/store-assets.md).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/l10n/l10n.dart';
import 'package:imposter_il/local/words.g.dart';
import 'package:imposter_il/screens/live_room.dart';
import 'package:imposter_il/state/game_session.dart';

import '../support/fake_server.dart';
import '../support/helpers.dart';

/// One language's cast and game.
class StoreLang {
  const StoreLang({
    required this.code,
    required this.players,
    required this.word,
    required this.hints,
    required this.reactions,
  });

  final String code;

  /// (id, nickname, avatar). The first is the player holding the phone; the
  /// fourth is the impostor.
  final List<(String, String, String)> players;
  final String word;

  /// One clue per player in turn order, the impostor's vague on purpose.
  final List<String> hints;

  /// The four structured messages, after the six shared emoji.
  final List<Map<String, String>> reactions;

  TextDirection get direction =>
      code == 'he' ? TextDirection.rtl : TextDirection.ltr;
  AppLocalizations get l10n => lookupAppLocalizations(Locale(code));
  String get category => localCategoriesFor(code).first.name; // Food & Drink
  String get impostorId => players[3].$1;
}

const _avatars = [
  'avatar-f01-notebook',
  'avatar-m04-detective-hat',
  'avatar-f03-headphones',
  'avatar-m02-binoculars',
  'avatar-f05-fingerprint-kit',
  'avatar-m06-magnifying-glass',
];

final storeLangs = [
  StoreLang(
    code: 'he',
    players: [
      for (final (i, name)
          in ['דנה', 'יואב', 'נועה', 'איתי', 'מאיה', 'עומר'].indexed)
        (i == 0 ? 'p_me' : 'p_${i + 1}', name, _avatars[i]),
    ],
    word: 'פיצה',
    hints: ['גבינה', 'משולש', 'תנור', 'ארוחה', 'משלוח', 'איטליה'],
    reactions: const [
      {'id': 'good_hint', 'text': 'רמז טוב!'},
      {'id': 'suspicious', 'text': 'זה מחשיד'},
      {'id': 'not_convinced', 'text': 'לא השתכנעתי'},
      {'id': 'what_connection', 'text': 'מה הקשר?'},
    ],
  ),
  StoreLang(
    code: 'en',
    players: [
      for (final (i, name)
          in ['Dana', 'Josh', 'Mia', 'Ethan', 'Lily', 'Noah'].indexed)
        (i == 0 ? 'p_me' : 'p_${i + 1}', name, _avatars[i]),
    ],
    word: 'Pizza',
    hints: ['Cheese', 'Slice', 'Oven', 'Dinner', 'Delivery', 'Italy'],
    reactions: const [
      {'id': 'good_hint', 'text': 'Good hint!'},
      {'id': 'suspicious', 'text': 'Suspicious…'},
      {'id': 'not_convinced', 'text': 'Not convinced'},
      {'id': 'what_connection', 'text': 'Huh? How?'},
    ],
  ),
];

const _emoji = [
  {'id': 'laugh', 'text': '😂'},
  {'id': 'thinking', 'text': '🤔'},
  {'id': 'eyes', 'text': '👀'},
  {'id': 'surprised', 'text': '😮'},
  {'id': 'applause', 'text': '👏'},
  {'id': 'eye_roll', 'text': '🙄'},
];

/// The phone the store pictures: [logical] points at [ratio], with the status
/// bar and home indicator a modern iPhone keeps clear.
Future<void> setPhone(WidgetTester tester, Size logical, double ratio) async {
  tester.view.devicePixelRatio = ratio;
  tester.view.physicalSize = logical * ratio;
  tester.view.padding = FakeViewPadding(top: 59 * ratio, bottom: 34 * ratio);
  addTearDown(tester.view.reset);
  await tester.pumpAndSettle();
}

/// The app at home, signed in as the first player, in [lang].
Future<(FakeApi, GameSession)> startStoreApp(
    WidgetTester tester, StoreLang lang, Size logical, double ratio) async {
  final api = FakeApi();
  api.responses['GET /v1/categories'] = {
    'categories': [
      for (final c in localCategoriesFor(lang.code))
        {'id': c.id, 'name': c.name},
    ],
  };
  api.responses['GET /v1/reactions'] = {
    'reactions': [..._emoji, ...lang.reactions],
  };
  final me = lang.players.first;
  final session = await startApp(tester, api, saved: {
    'session.token': 'token-1',
    'session.playerId': 'p_me',
    'session.nickname': me.$2,
    'session.avatarId': me.$3,
    'stats.wins': 17,
    'stats.losses': 6,
    'settings.language': lang.code,
  });
  await setPhone(tester, logical, ratio);
  return (api, session);
}

List<Map<String, dynamic>> _players(StoreLang lang,
        {String? eliminated, bool confirmed = true}) =>
    [
      for (final (id, name, avatar) in lang.players)
        player(id, name,
            status: id == eliminated ? 'eliminated' : 'active',
            roleConfirmed: confirmed)
          ..['avatarId'] = avatar,
    ];

/// A game snapshot in [lang]: its category, word and cast.
Map<String, dynamic> storeGame(
  StoreLang lang,
  String phase, {
  String role = 'citizen',
  String? turn,
  int hints = 0,
  Map<int, Map<String, int>> reactions = const {},
  String? myVote,
  Map<String, dynamic>? result,
  DateTime? deadline,
}) {
  final order = lang.players;
  return gameJson(
    phase: phase,
    role: role,
    turn: turn,
    players: _players(lang, confirmed: phase != 'role_reveal'),
    candidates: [for (final p in order) p.$1],
    myVote: myVote,
    result: result,
    hints: [
      for (var i = 0; i < hints; i++)
        {
          'playerId': order[i].$1,
          'text': lang.hints[i],
          'missing': false,
          'reactions': reactions[i] ?? const <String, int>{},
        },
    ],
  )
    ..['category'] = lang.category
    ..['secretWord'] = role == 'impostor' && phase != 'ended' ? null : lang.word
    ..['deadline'] = phase == 'ended'
        ? null
        : (deadline ?? DateTime.now().add(const Duration(seconds: 42)))
            .toUtc()
            .toIso8601String();
}

/// The citizens caught the impostor, who then missed the word.
Map<String, dynamic> citizensWon(StoreLang lang) => {
      'winner': 'citizens',
      'reason': 'impostor_guess_wrong',
      'impostorPlayerId': lang.impostorId,
      'secretWord': lang.word,
      'voteRounds': [
        {
          for (final p in lang.players)
            if (p.$1 != lang.impostorId) p.$1: lang.impostorId,
          lang.impostorId: lang.players[1].$1,
        },
      ],
      'abstentions': [0],
      'outcomes': {
        for (final p in lang.players)
          p.$1: p.$1 == lang.impostorId ? 'loss' : 'win',
      },
    };

/// Opens the live game screen over home, as a found game does.
Future<FakeChannel> enterStoreGame(WidgetTester tester, FakeApi api) async {
  tester
      .state<NavigatorState>(find.byType(Navigator).first)
      .push(MaterialPageRoute<void>(builder: (_) => const LiveRoomScreen()));
  await tester.pump();
  api.channel.event('session.state', {
    'playerId': 'p_me',
    'activity': 'game',
    'roomId': 'r_pub',
    'gameId': 'g_1',
  });
  return api.channel;
}

/// The colour emoji the theme falls back to (lib/theme/app_theme.dart), from
/// the Mac running the render: reactions are emoji.
Future<void> loadEmojiFont() async {
  final font = File('/System/Library/Fonts/Apple Color Emoji.ttc');
  if (!font.existsSync()) return;
  await (FontLoader('Apple Color Emoji')
        ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync()))))
      .load();
}
