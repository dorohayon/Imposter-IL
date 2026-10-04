// Store screenshots, rendered from the real app (docs/store-assets.md). Not
// part of the normal run: STORE_ASSETS=1 flutter test test/store
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;

import '../support/helpers.dart';
import 'panel.dart';
import 'scenes.dart';

final _run = Platform.environment['STORE_ASSETS'] == '1';

/// What each screenshot says, in order. A word in brackets is in yellow.
const _captions = {
  'he': [
    ('1_home', 'תפסו את [המתחזה]', 'משחק הרמזים שבו כולם חשודים'),
    ('2_role', 'מילה סודית אחת.\n[מתחזה אחד.]', 'המתחזה יודע רק את הקטגוריה'),
    ('3_clues', 'מילה אחת.\n[רמז אחד.]', 'לא ברור מדי, לא מעורפל מדי'),
    ('4_vote', '[הצביעו]\nמי המתחזה', 'חשדו, הגיבו והחליטו יחד'),
    ('5_result', 'חשפו את\n[המבלף]', 'נתפס? למתחזה נשאר ניחוש אחד'),
    (
      '6_categories',
      '[אינספור מילים]\nמכל תחום',
      'ברשת, בחדר פרטי או בטלפון אחד'
    ),
  ],
  'en': [
    (
      '1_home',
      'Catch the\n[imposter]',
      'The clue game where everyone’s a suspect'
    ),
    (
      '2_role',
      'One secret word.\n[One imposter.]',
      'The imposter only knows the category'
    ),
    ('3_clues', 'One word.\n[One clue.]', 'Not too obvious, not too vague'),
    (
      '4_vote',
      '[Vote out]\nthe imposter',
      'Suspect, react and decide together'
    ),
    (
      '5_result',
      'Unmask the\n[bluffer]',
      'Caught? The imposter gets one last guess'
    ),
    (
      '6_categories',
      '[Endless words]\nfrom every topic',
      'Online, in a private room or on one phone'
    ),
  ],
};

/// The sizes each store wants: the App Store's 6.9" iPhone, and Google
/// Play's 9:16 phone at the size it features.
const _targets = {
  'appstore': Size(1320, 2868),
  'googleplay': Size(1080, 1920),
};

/// Renders [panel] at [size] pixels to [path].png.
Future<void> _render(WidgetTester tester, Widget panel, Size size,
    List<Uint8List> images, String path) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = FakeViewPadding.zero;
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(key: key, child: panel));
  await tester.runAsync(() async {
    for (final bytes in images) {
      await precacheImage(MemoryImage(bytes), key.currentContext!);
    }
  });
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    // A PNG. The screenshots then go to JPEG, which has no alpha channel, as
    // the App Store requires (docs/store-assets.md): converting from in here
    // hung the test now and then. Play's icon stays a PNG, alpha and all.
    File('$path.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// The 6.9" iPhone the App Store asks for: 440×956 points at 3x.
const appStorePhone = Size(440, 956);

void main() {
  for (final lang in storeLangs) {
    testWidgets('raw screens: ${lang.code}', skip: !_run, (tester) async {
      await loadRealFonts();
      await loadEmojiFont();
      final (api, _) = await startStoreApp(tester, lang, appStorePhone, 3);
      final folder = 'store/raw/${lang.code}';
      clearScreenshots(folder);
      final l = lang.l10n;

      await saveScreenshot(tester, folder, '1_home');

      await tapText(tester, l.onlineGame);
      await tapText(tester, l.quickGame);
      await saveScreenshot(tester, folder, '6_categories');
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .popUntil((r) => r.isFirst);
      await tester.pumpAndSettle();

      final channel = await enterStoreGame(tester, api);
      channel.snapshot('game.state', 'game', storeGame(lang, 'role_reveal'));
      await settle(tester);
      await saveScreenshot(tester, folder, '2_role');
      channel.snapshot('game.state', 'game',
          storeGame(lang, 'role_reveal', role: 'impostor'));
      await settle(tester);
      await saveScreenshot(tester, folder, '2_role_impostor');

      channel.snapshot(
          'game.state',
          'game',
          storeGame(lang, 'hints',
              turn: lang.players[4].$1,
              hints: 4,
              reactions: {
                1: {'good_hint': 2},
                3: {'suspicious': 3, 'eyes': 2},
              }));
      await settle(tester);
      await saveScreenshot(tester, folder, '3_clues');

      channel.snapshot('game.state', 'game', storeGame(lang, 'voting'));
      await settle(tester);
      await tapLive(tester, lang.players[3].$2);
      await saveScreenshot(tester, folder, '4_vote');

      channel.snapshot('game.state', 'game',
          storeGame(lang, 'ended', result: citizensWon(lang)));
      await settle(tester);
      await saveScreenshot(tester, folder, '5_result');

      // The panels, from the captures just made.
      Uint8List raw(String name) =>
          File('build/screenshots/$folder/$name.png').readAsBytesSync();
      for (final MapEntry(key: store, value: size) in _targets.entries) {
        final out = 'build/store/$store/${lang.code}';
        final dir = Directory(out);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
        for (final (i, (name, title, subtitle))
            in _captions[lang.code]!.indexed) {
          final screens = [
            raw(name),
            if (name == '2_role') raw('2_role_impostor'),
          ];
          await _render(
            tester,
            StorePanel(
              size: size,
              title: title,
              subtitle: subtitle,
              screens: screens,
              rtl: lang.code == 'he',
            ),
            size,
            screens,
            '$out/${(i + 1).toString().padLeft(2, '0')}_${name.substring(2)}',
          );
        }
      }

      // Google Play's feature graphic, and its 512px icon (once).
      final icon = File('branding/icon.png').readAsBytesSync();
      final hero =
          File('assets/illustrations/home-hero.webp').readAsBytesSync();
      await _render(
        tester,
        FeatureGraphic(
          name: lang.code == 'he' ? 'מי המתחזה?' : 'Imposter:\nWord Bluff',
          tagline: lang.code == 'he'
              ? 'משחק הרמזים שבו כולם חשודים'
              : 'The clue game where\neveryone’s a suspect',
          rtl: lang.code == 'he',
          icon: icon,
          hero: hero,
        ),
        const Size(1024, 500),
        [icon, hero],
        'build/store/googleplay/${lang.code}/feature_graphic',
      );
      if (lang.code == 'en') {
        await _render(
          tester,
          Image.memory(icon,
              width: 512, height: 512, filterQuality: FilterQuality.high),
          const Size(512, 512),
          [icon],
          'build/store/googleplay/icon_512',
        );
      }
    });
  }
}
