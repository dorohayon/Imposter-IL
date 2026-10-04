// The App Store preview (and Google Play's YouTube video): a scripted game on
// the real app, 25 seconds at 886×1920 and 30 fps, rendered frame by frame to
// build/store/video/<language>/ with the moments its sounds play
// (docs/store-assets.md). STORE_ASSETS=1 flutter test test/store/video_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/main.dart';
import 'package:imposter_il/screens/legal_screens.dart';
import 'package:imposter_il/state/game_session.dart';
import 'package:imposter_il/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_monetization.dart';
import '../support/fake_server.dart';
import '../support/helpers.dart';
import 'panel.dart';
import 'scenes.dart';

final _run = Platform.environment['STORE_ASSETS'] == '1';

const _fps = 30;

/// The app's own size inside the preview: the frame is 443×960 points at 2x,
/// 886×1920 pixels, and the app is drawn smaller under the caption.
const _view = Size(443, 960);

const _captions = {
  'he': (
    home: 'משחק הרמזים\nשבו [כולם חשודים]',
    word: 'כולם מקבלים\n[מילה סודית]',
    impostor: '[חוץ מהמתחזה]',
    clues: 'רמז במילה אחת.\n[מי מבלף?]',
    vote: '[הצביעו] מי המתחזה',
    result: 'תפסו אותו\n[לפני שינחש]',
  ),
  'en': (
    home: 'The clue game where\n[everyone’s a suspect]',
    word: 'Everyone gets\nthe [secret word]',
    impostor: '[Except the imposter]',
    clues: 'One-word clues.\n[Who\'s bluffing?]',
    vote: '[Vote out] the imposter',
    result: 'Catch them\n[before they guess]',
  ),
};

/// The preview's frame: the brand's night, the caption, and the app under it.
class _Frame extends StatelessWidget {
  const _Frame({required this.caption, required this.rtl, required this.app});

  final ValueNotifier<String?> caption;
  final bool rtl;
  final Widget app;

  @override
  Widget build(BuildContext context) {
    const captionHeight = 150.0;
    final appHeight = _view.height - captionHeight - 18;
    final appWidth = appHeight * _view.width / _view.height;
    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: StoreBackground(
        mirror: rtl,
        child: Stack(
          children: [
            Positioned(
              top: 12,
              left: 20,
              right: 20,
              height: captionHeight - 12,
              child: Center(
                child: ValueListenableBuilder(
                  valueListenable: caption,
                  builder: (context, text, _) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: Text.rich(
                      TextSpan(children: highlighted(text ?? '')),
                      key: ValueKey(text),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Secular One',
                        fontSize: 31,
                        height: 1.15,
                        color: AppColors.cream,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: captionHeight,
              left: (_view.width - appWidth) / 2,
              width: appWidth,
              height: appHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(34),
                  border: Border.all(color: const Color(0xFF4A4868), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.purple.withValues(alpha: .3),
                      blurRadius: 40,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: FittedBox(
                    child: SizedBox.fromSize(size: _view, child: app),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  for (final lang in storeLangs) {
    testWidgets('preview video: ${lang.code}',
        skip: !_run,
        timeout: const Timeout(Duration(minutes: 30)), (tester) async {
      await loadRealFonts();
      await loadEmojiFont();
      final l = lang.l10n;
      final say = _captions[lang.code]!;
      final out = Directory('build/store/video/${lang.code}');
      if (out.existsSync()) out.deleteSync(recursive: true);
      out.createSync(recursive: true);

      // As startApp, inside the preview's frame.
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = _view * 2;
      tester.view.padding = const FakeViewPadding(top: 59 * 2, bottom: 34 * 2);
      addTearDown(tester.view.reset);
      final api = FakeApi();
      api.responses['GET /v1/reactions'] = {
        'reactions': [
          {'id': 'laugh', 'text': '😂'},
          {'id': 'eyes', 'text': '👀'},
          ...lang.reactions,
        ],
      };
      final me = lang.players.first;
      SharedPreferences.setMockInitialValues({
        legalAcceptedVersionKey: legalVersion,
        'session.token': 'token-1',
        'session.playerId': 'p_me',
        'session.nickname': me.$2,
        'session.avatarId': me.$3,
        'settings.language': lang.code,
      });
      final session =
          GameSession(api, reconnectDelay: const Duration(milliseconds: 50));
      addTearDown(session.dispose);
      final monetization = fakeMonetization(api);
      addTearDown(monetization.dispose);
      await session.restore();
      await monetization.start();
      monetization.attach(session);
      final caption = ValueNotifier<String?>(null);
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: _Frame(
          caption: caption,
          rtl: lang.code == 'he',
          app: ImposterApp(session: session, monetization: monetization),
        ),
      ));
      await tester.pumpAndSettle();

      // Video time: frame n is n/30 s, and the server's clock follows it, so
      // every timer on screen counts down at the video's pace.
      final start = DateTime.now();
      var frame = 0;
      Duration at(num seconds) =>
          Duration(microseconds: (seconds * 1e6).round());
      DateTime clock(num seconds) => start.add(at(seconds));
      double now() => frame / _fps;
      final sounds = <Map<String, Object>>[];
      void sound(String file, {double? until}) => sounds
          .add({'t': now(), 'file': file, if (until != null) 'until': until});

      Future<void> images() async {
        await tester.runAsync(() async {
          for (final e in find.byType(Image).evaluate()) {
            await precacheImage((e.widget as Image).image, e);
          }
        });
      }

      Future<void> hold(double seconds) async {
        await images();
        final end = frame + (seconds * _fps).round();
        while (frame < end) {
          frame++;
          session.serverOffset = clock(now()).difference(DateTime.now());
          await tester.pump(at(1 / _fps));
          await tester.runAsync(() async {
            final boundary = key.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            File('${out.path}/frame_${frame.toString().padLeft(4, '0')}.png')
                .writeAsBytesSync(png!.buffer.asUint8List());
          });
        }
      }

      // 0. Home, long enough to read, then the game slides in.
      caption.value = say.home;
      await hold(2.2);
      final channel = await enterStoreGame(tester, api);
      var hints = 0;
      void board(String turn,
              {Map<int, Map<String, int>> reactions = const {}}) =>
          channel.snapshot(
              'game.state',
              'game',
              storeGame(lang, 'hints',
                  turn: turn,
                  hints: hints,
                  reactions: reactions,
                  deadline: clock(now() + 45)));
      void react(int hint, String from, String id) {
        channel.event('game.reaction', {
          'gameId': 'g_1',
          'hintIndex': hint,
          'reactionId': id,
          'playerId': from,
        });
        sound('reaction');
      }

      // 1. Everyone's card, then the impostor's.
      channel.snapshot('game.state', 'game',
          storeGame(lang, 'role_reveal', deadline: clock(20)));
      caption.value = say.word;
      sound('reveal');
      await hold(2.8);
      channel.snapshot(
          'game.state',
          'game',
          storeGame(lang, 'role_reveal',
              role: 'impostor', deadline: clock(20)));
      caption.value = say.impostor;
      sound('reveal');
      await hold(2.5);

      // 2. The clues, mine first: typed, sent, then the table's, one by one.
      caption.value = say.clues;
      board('p_me');
      await hold(.6);
      final mine = lang.hints.first;
      for (var i = 1; i <= mine.length; i++) {
        await tester.enterText(find.byType(TextField), mine.substring(0, i));
        await hold(.12);
      }
      await hold(.3);
      await tester.tap(find.text(l.send).last);
      hints = 1;
      board(lang.players[1].$1);
      sound('hint');
      await hold(1.0);
      for (final i in [1, 2, 3, 4, 5]) {
        hints = i + 1;
        board(i + 1 < lang.players.length ? lang.players[i + 1].$1 : 'p_me',
            reactions: {
              if (hints > 2) 1: {'good_hint': 2},
              if (hints > 4) 3: {'eyes': 2, 'suspicious': 1},
            });
        sound('hint');
        await hold(.55);
        if (i == 1) react(1, lang.players[2].$1, 'good_hint');
        if (i == 3) {
          react(3, lang.players[4].$1, 'eyes');
          await hold(.35);
          react(3, lang.players[1].$1, 'suspicious');
        }
        await hold(i == 3 ? .5 : .85);
      }

      // 3. "Time to vote", its sound going round until the vote opens.
      channel.snapshot('game.state', 'game',
          storeGame(lang, 'pre_voting', hints: 6, deadline: clock(now() + 2)));
      caption.value = null;
      sound('vote_start', until: now() + 2);
      await hold(2.0);

      // 4. The vote: pick the impostor, confirm, and the clock runs out.
      final deadline = now() + 5.5;
      channel.snapshot('game.state', 'game',
          storeGame(lang, 'voting', hints: 6, deadline: clock(deadline)));
      caption.value = say.vote;
      sounds.add({'t': deadline - 5, 'file': 'countdown'});
      await hold(1.1);
      await tester.tap(find.text(lang.players[3].$2).last);
      await hold(1.0);
      await tester.tap(find.text(l.confirmVote).last);
      channel.snapshot(
          'game.state',
          'game',
          storeGame(lang, 'voting',
              hints: 6, myVote: lang.impostorId, deadline: clock(deadline)));
      await hold(deadline - now());

      // 5. The citizens win.
      channel.snapshot('game.state', 'game',
          storeGame(lang, 'ended', hints: 6, result: citizensWon(lang)));
      caption.value = say.result;
      sound('win');
      await hold(3.5);

      File('${out.path}/sounds.json').writeAsStringSync(jsonEncode({
        'fps': _fps,
        'frames': frame,
        'sounds': sounds,
      }));
    });
  }
}
