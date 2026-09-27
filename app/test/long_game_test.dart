// A long match at its worst: the most players, the longest names and hints
// the rules allow, ten rounds deep, on the narrowest phone (320px) at the
// normal and a large system font. Any overflow fails the test.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:imposter_il/local/local_game.dart';
import 'package:imposter_il/local/local_screens.dart';
import 'package:imposter_il/models/player.dart';
import 'package:imposter_il/widgets/game_ui.dart';

import 'support/fake_server.dart';
import 'support/helpers.dart';

/// 18 characters, the longest nickname the server accepts.
String _name(int i) => 'אלכסנדרה-פטרושקוב$i';

/// 25 characters, the longest hint the server accepts, one word.
String _hint(int round, int player) =>
    'אנטידיסאסטבלישמנטרי${round.toString().padLeft(2, '0')}$player'
        .padRight(25, 'ה')
        .substring(0, 25);

const _rounds = 10;
const _ids = ['p_me', 'p_2', 'p_3', 'p_4', 'p_5', 'p_6', 'p_7', 'p_8'];

/// Three voted out along the way, one on a bad connection.
List<Map<String, dynamic>> _players() => [
      for (final (i, id) in _ids.indexed)
        player(
          id,
          _name(i + 1),
          status: const {'p_6', 'p_7', 'p_8'}.contains(id)
              ? 'eliminated'
              : 'active',
          connected: id != 'p_5',
          disconnects: id == 'p_5' ? 2 : 0,
        ),
    ];

/// The round each watcher was voted out in.
const _outIn = {'p_6': 3, 'p_7': 5, 'p_8': 7};

/// Every round's hints; the watchers stopped at the round they went out in,
/// and one turn in three rounds passed with nothing said.
List<Map<String, dynamic>> _hints({int upTo = _rounds}) => [
      for (var round = 1; round <= upTo; round++)
        for (final (i, id) in _ids.indexed)
          if (round <= (_outIn[id] ?? _rounds))
            {
              'playerId': id,
              'text': round % 3 == 0 && id == 'p_4' ? '' : _hint(round, i),
              'round': round,
              'missing': round % 3 == 0 && id == 'p_4',
              'reactions': {'laugh': 3, 'thinking': 2, 'eyes': 1},
            },
    ];

Map<String, dynamic> _result() => {
      'winner': 'citizens',
      'reason': 'impostor_guess_wrong',
      'impostorPlayerId': 'p_4',
      'secretWord': 'פיל',
      'voteRounds': [
        for (var round = 1; round <= _rounds; round++)
          {for (final id in _ids.take(5)) id: 'p_4'},
      ],
      'abstentions': [for (var round = 1; round <= _rounds; round++) 1],
      'outcomes': {for (final id in _ids) id: id == 'p_4' ? 'loss' : 'win'},
    };

/// Each screen of round ten, as the server would send it.
final _screens = <String, Map<String, dynamic> Function()>{
  'hints': () => gameJson(
        phase: 'hints',
        round: _rounds,
        turn: 'p_3',
        players: _players(),
        hints: _hints(upTo: _rounds - 1),
      ),
  'voting': () => gameJson(
        phase: 'voting',
        round: _rounds,
        players: _players(),
        hints: _hints(),
        candidates: ['p_me', 'p_2', 'p_3', 'p_4', 'p_5'],
      ),
  'runoff': () => gameJson(
        phase: 'runoff_voting',
        round: _rounds,
        players: _players(),
        hints: _hints(),
        candidates: ['p_2', 'p_3', 'p_4'],
        previousVotes: {'p_2': 2, 'p_3': 2, 'p_4': 2},
      ),
  'impostor guess': () => gameJson(
        phase: 'impostor_guess',
        role: 'impostor',
        round: _rounds,
        players: _players(),
        hints: _hints(),
      ),
  'elimination': () => gameJson(
        phase: 'elimination_reveal',
        round: _rounds,
        players: _players(),
        hints: _hints(),
        eliminatedPlayerId: 'p_8',
      ),
  'second tie': () => gameJson(
        phase: 'elimination_reveal',
        round: _rounds,
        players: _players(),
        hints: _hints(),
        candidates: ['p_2', 'p_3', 'p_4'],
        previousVotes: {'p_2': 1, 'p_3': 1, 'p_4': 1},
      ),
  'result': () => gameJson(
        phase: 'ended',
        round: _rounds,
        players: _players(),
        hints: _hints(),
        result: _result(),
      ),
};

/// One device at its fullest: twelve players, eight of them voted out over
/// eight rounds, round ten with four still at the table.
Map<String, dynamic> _local(String phase) => {
      'players': [
        for (var i = 0; i < 12; i++)
          {
            'name': _name(i + 1),
            'avatar': avatarAssets[i % avatarAssets.length],
            'eliminated': i >= 4,
          },
      ],
      'categoryIds': ['food'],
      'hintSeconds': 60,
      'secretWord': 'פיצה',
      'category': 'אוכל ושתייה',
      'impostor': 3,
      'phase': phase,
      'round': _rounds,
      'seat': 0,
      'turnOrder': [2, 0, 3, 1],
      'secondsRemaining': 41,
      'missedHintSeats': <int>[],
      'votes': <String, int>{},
      'runoffCandidates': phase == 'runoff' ? [0, 1, 2] : <int>[],
      'tiedVotes': 1,
      'tieCandidates': [0, 1, 2],
      'previousVotes': {'0': 1, '1': 1, '2': 1},
      'lastEliminated': 11,
      'submittedGuess': phase == 'ended' ? 'אנטידיסאסטבלישמנטריאניזם' : null,
      'eliminations': [
        for (var i = 4; i < 12; i++) [i, i - 3],
      ],
      'outcome': phase == 'ended' ? 'citizensWin' : null,
      'endReason': phase == 'ended' ? 'impostorGuessWrong' : null,
    };

/// What proves each phase is the screen under test.
final _expected = {
  'ready': 'סיבוב נוסף',
  'hints': 'התור של',
  'voteTransition': 'אל תגלו למי הצבעתם',
  'voting': 'מי המתחזה?',
  'tie': 'יש תיקו',
  'tieAgain': 'שוב יש תיקו',
  'runoff': 'יש תיקו',
  'elimination': '${_name(12)} הודח/ה',
  'guess': 'נתפסת',
  'ended': 'האזרחים ניצחו!',
};

/// Phases that open behind the privacy screen, and its button.
const _privatePhases = {'voting', 'runoff', 'guess'};

void main() {
  for (final scale in [1.0, 1.3, 1.5]) {
    group('one device, 12 players, round $_rounds, font x$scale', () {
      for (final phase in [
        'ready',
        'hints',
        'voteTransition',
        'voting',
        'tie',
        'tieAgain',
        'runoff',
        'elimination',
        'guess',
        'ended',
      ]) {
        testWidgets(phase, (tester) async {
          await loadRealFonts();
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await startAtHome(tester);
          final game = localGameFromJson(_local(phase))!;
          tester.state<NavigatorState>(find.byType(Navigator).first).push(
                MaterialPageRoute<void>(
                  builder: (_) => LocalGameScreen(resumed: game),
                ),
              );
          await settle(tester);
          if (_privatePhases.contains(phase)) {
            // "It's me": the ballot or the guess, not just the hand-over.
            await tester.tap(find.byType(PrimaryButton).last);
            await settle(tester);
          }
          expect(find.textContaining(_expected[phase]!), findsWidgets);
          expect(find.textContaining('העבירו את המכשיר'), findsNothing);
          await tester.drag(
              find.byType(Scrollable).first, const Offset(0, -3000));
          await settle(tester);
        });
      }
    });
    group('online, round $_rounds, font x$scale', () {
      for (final MapEntry(key: screen, value: build) in _screens.entries) {
        testWidgets(screen, (tester) async {
          await loadRealFonts();
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final api = FakeApi();
          await startAtHome(tester, api);
          await openCreatedRoom(tester, api);
          api.channel.event('session.state', {
            'playerId': 'p_me',
            'activity': 'game',
            'roomId': 'r_1',
            'gameId': 'g_1',
          });
          api.channel.snapshot('game.state', 'game', build());
          await settle(tester);
          _expectNoHintCut(tester);
          // Scrolled to the end too: what is below the fold lays out as well.
          await tester.drag(
              find.byType(Scrollable).first, const Offset(0, -3000));
          await settle(tester);

          if (screen == 'hints') {
            // All ten rounds of one player, from their card.
            await tester.drag(
                find.byType(Scrollable).first, const Offset(0, 3000));
            await settle(tester);
            await tester.tap(find.text(_name(2)).first);
            await settle(tester);
            expect(find.text('הרמזים של ${_name(2)}'), findsOneWidget);
            await tester.drag(
                find.byType(Scrollable).last, const Offset(0, -3000));
            await settle(tester);
          }
        });
      }
    });
  }
}

/// A hint is the evidence the table votes on: none may end in "…".
void _expectNoHintCut(WidgetTester tester) {
  final hints = {for (final h in _hints()) h['text'] as String}..remove('');
  for (final paragraph
      in tester.renderObjectList<RenderParagraph>(find.byType(RichText))) {
    final text = paragraph.text.toPlainText();
    if (hints.any(text.contains)) {
      expect(paragraph.didExceedMaxLines, isFalse, reason: 'cut: $text');
    }
  }
}
