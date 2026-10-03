// The store's frame around a real screen: the brand's night, a headline, and
// a generic phone, mirrored for Hebrew (docs/store-assets.md).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:imposter_il/theme/app_theme.dart';

/// A headline with one stretch in yellow, written as `before [yellow] after`.
List<TextSpan> highlighted(String text) {
  final parts = text.split(RegExp(r'[\[\]]'));
  return [
    for (final (i, part) in parts.indexed)
      TextSpan(
        text: part,
        style: i.isOdd ? const TextStyle(color: AppColors.yellow) : null,
      ),
  ];
}

/// The night sky every panel sits on: deep navy, a violet glow behind the
/// headline and a warm one low down.
class StoreBackground extends StatelessWidget {
  const StoreBackground({required this.child, this.mirror = false, super.key});

  final Widget child;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    final x = mirror ? -1.0 : 1.0;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B1840), AppColors.night, Color(0xFF100F24)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Glow(Alignment(-.7 * x, -.85),
              AppColors.purple.withValues(alpha: .42), 1.1),
          _Glow(Alignment(.9 * x, .55), AppColors.yellow.withValues(alpha: .13),
              .9),
          _Glow(Alignment(-.9 * x, .95),
              AppColors.turquoise.withValues(alpha: .10), .8),
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow(this.at, this.color, this.radius);

  final Alignment at;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: at,
            radius: radius,
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      );
}

/// A phone with no maker's marks, the status bar on the side the language
/// puts it. [width] is the whole device; [screen] a capture at 440 points.
class StorePhone extends StatelessWidget {
  const StorePhone({
    required this.screen,
    required this.width,
    required this.rtl,
    super.key,
  });

  final Uint8List screen;
  final double width;
  final bool rtl;

  static const screenAspect = 956 / 440;

  @override
  Widget build(BuildContext context) {
    final bezel = width * .028;
    final inner = width - 2 * bezel;
    final radius = width * .135;
    final unit = inner / 440; // one point of the phone's screen
    return Container(
      width: width,
      height: inner * screenAspect + 2 * bezel,
      padding: EdgeInsets.all(bezel),
      decoration: BoxDecoration(
        color: const Color(0xFF07060F),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFF4A4868), width: width * .006),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .55),
            blurRadius: width * .09,
            offset: Offset(0, width * .04),
          ),
          BoxShadow(
            color: AppColors.purple.withValues(alpha: .25),
            blurRadius: width * .16,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - bezel),
        child: Stack(
          children: [
            Image.memory(screen,
                width: inner,
                fit: BoxFit.fitWidth,
                filterQuality: FilterQuality.high),
            // The status bar, in the 59 points the app keeps clear.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 59 * unit,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 34 * unit),
                child: Directionality(
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  child: Row(
                    children: [
                      Text(
                        '9:41',
                        style: TextStyle(
                          fontFamily: 'Rubik',
                          fontWeight: FontWeight.w600,
                          fontSize: 17 * unit,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.signal_cellular_alt_rounded,
                          size: 18 * unit, color: Colors.white),
                      SizedBox(width: 5 * unit),
                      Icon(Icons.wifi_rounded,
                          size: 18 * unit, color: Colors.white),
                      SizedBox(width: 5 * unit),
                      Transform.rotate(
                        angle: math.pi / 2 * (rtl ? -1 : 1),
                        child: Icon(Icons.battery_full_rounded,
                            size: 20 * unit, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // The front camera: a plain punch hole.
            Positioned(
              top: 18 * unit,
              left: inner / 2 - 6 * unit,
              child: Container(
                width: 12 * unit,
                height: 12 * unit,
                decoration: const BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One store screenshot: the headline, its line, and the phone (or two).
class StorePanel extends StatelessWidget {
  const StorePanel({
    required this.size,
    required this.title,
    required this.subtitle,
    required this.screens,
    required this.rtl,
    super.key,
  });

  final Size size;
  final String title;
  final String subtitle;

  /// One screen, or two fanned out (the second behind).
  final List<Uint8List> screens;
  final bool rtl;

  @override
  Widget build(BuildContext context) {
    final w = size.width;
    final h = size.height;
    final tall = h / w > 2;
    final titleSize = w * (tall ? .088 : .074);
    final top = h * (tall ? .075 : .055);
    final textBlock = top + titleSize * 2.4 + w * .1;
    final phoneWidth = math.min(
      w * (screens.length > 1 ? .56 : .78),
      (h - textBlock - h * .03) / (StorePhone.screenAspect * .944 + .056),
    );
    final dir = rtl ? TextDirection.rtl : TextDirection.ltr;
    final side = rtl ? -1.0 : 1.0;
    return Directionality(
      textDirection: dir,
      child: SizedBox.fromSize(
        size: size,
        child: StoreBackground(
          mirror: rtl,
          child: Stack(
            children: [
              Positioned(
                top: top,
                left: w * .07,
                right: w * .07,
                child: Column(
                  children: [
                    Text.rich(
                      TextSpan(children: highlighted(title)),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Secular One',
                        fontSize: titleSize,
                        height: 1.12,
                        color: AppColors.cream,
                        shadows: const [
                          Shadow(
                              color: Color(0x66000000),
                              blurRadius: 18,
                              offset: Offset(0, 4)),
                        ],
                      ),
                    ),
                    SizedBox(height: titleSize * .32),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Rubik',
                        fontWeight: FontWeight.w500,
                        fontSize: titleSize * .42,
                        height: 1.3,
                        color: AppColors.cream.withValues(alpha: .78),
                      ),
                    ),
                  ],
                ),
              ),
              if (screens.length > 1)
                // The second phone, behind and to the far side, tilted away:
                // both screens read in full.
                Positioned(
                  bottom: h * .085,
                  left: (w - phoneWidth * .95) / 2 + side * w * .2,
                  child: Transform.rotate(
                    angle: side * .1,
                    child: StorePhone(
                        screen: screens[1], width: phoneWidth * .95, rtl: rtl),
                  ),
                ),
              Positioned(
                bottom: h * .03,
                left: (w - phoneWidth) / 2 -
                    (screens.length > 1 ? side * w * .2 : 0),
                child: Transform.rotate(
                  angle: screens.length > 1 ? -side * .06 : 0,
                  child: StorePhone(
                      screen: screens[0], width: phoneWidth, rtl: rtl),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Google Play's feature graphic, 1024×500: the name and a line on the
/// reading side, the cast on the other. The middle stays light, where Play
/// lays its play button over a promo video.
class FeatureGraphic extends StatelessWidget {
  const FeatureGraphic({
    required this.name,
    required this.tagline,
    required this.rtl,
    required this.icon,
    required this.hero,
    super.key,
  });

  /// The app icon and the home screen's cast (branding/icon.png,
  /// assets/illustrations/home-hero.webp).
  final Uint8List icon;
  final Uint8List hero;
  final String name;
  final String tagline;
  final bool rtl;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: SizedBox(
        width: 1024,
        height: 500,
        child: StoreBackground(
          mirror: rtl,
          child: Stack(
            children: [
              PositionedDirectional(
                start: 64,
                top: 0,
                bottom: 0,
                width: 470,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(26),
                      child: Image.memory(icon,
                          width: 112,
                          height: 112,
                          filterQuality: FilterQuality.high),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      name,
                      style: const TextStyle(
                        fontFamily: 'Secular One',
                        fontSize: 58,
                        height: 1.05,
                        color: AppColors.cream,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tagline,
                      style: const TextStyle(
                        fontFamily: 'Rubik',
                        fontWeight: FontWeight.w600,
                        fontSize: 28,
                        color: AppColors.yellow,
                      ),
                    ),
                  ],
                ),
              ),
              PositionedDirectional(
                end: 30,
                bottom: -10,
                height: 490,
                child: Image.memory(hero, filterQuality: FilterQuality.high),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
