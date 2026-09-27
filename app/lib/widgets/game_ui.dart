import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/player.dart';
import '../monetization/ad_banner.dart';
import '../theme/app_theme.dart';

/// The button styles of the design system (design/claude/design-system.md).
enum ButtonVariant { primary, secondary, confirm, danger, quiet }

class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.variant = ButtonVariant.primary,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final IconData? icon;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  static const _sink = 6.0; // how far a filled button drops when pressed
  static const _shadow = 8.0;

  bool _pressed = false;
  final _focusNode = FocusNode(debugLabel: 'PrimaryButton');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    // Filled buttons sit on a solid shadow and sink into it when pressed;
    // outlined ones have no shadow to sink into.
    final (background, foreground, shadow, border) = switch (widget.variant) {
      ButtonVariant.primary => (
          _pressed ? const Color(0xFFF0B400) : AppColors.yellow,
          AppColors.night,
          const Color(0xFFD9A900),
          null,
        ),
      ButtonVariant.confirm => (
          _pressed ? const Color(0xFF22B3A1) : AppColors.turquoise,
          const Color(0xFF0E2B2A),
          const Color(0xFF17A395),
          null,
        ),
      ButtonVariant.secondary => (
          Colors.transparent,
          AppColors.turquoise,
          null,
          AppColors.turquoise,
        ),
      ButtonVariant.danger => (
          Colors.transparent,
          const Color(0xFFFF9B9B),
          null,
          AppColors.coral.withValues(alpha: 0.7),
        ),
      ButtonVariant.quiet => (
          AppColors.cream.withValues(alpha: .08),
          AppColors.cream,
          null,
          null,
        ),
    };
    final drop = shadow != null && _pressed ? _sink : 0.0;
    final contentColor = enabled
        ? foreground
        : widget.variant == ButtonVariant.primary
            ? AppColors.night.withValues(alpha: .45)
            : AppColors.muted;
    final contentStyle = TextStyle(
      color: contentColor,
      fontFamily: widget.variant == ButtonVariant.danger ||
              widget.variant == ButtonVariant.quiet
          ? 'Rubik'
          : 'Secular One',
      fontSize: widget.variant == ButtonVariant.danger ||
              widget.variant == ButtonVariant.quiet
          ? 16
          : 22,
      fontWeight: widget.variant == ButtonVariant.danger ||
              widget.variant == ButtonVariant.quiet
          ? FontWeight.w600
          : FontWeight.w400,
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      onTap: enabled ? widget.onPressed : null,
      child: ExcludeSemantics(
        // InkWell supplies focus traversal plus Enter/Space activation for
        // keyboards and switch-access devices. The parent Semantics node is
        // still the single spoken button.
        child: InkWell(
          focusNode: _focusNode,
          canRequestFocus: enabled,
          onHighlightChanged: enabled ? _setPressed : null,
          onTap: widget.onPressed,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: double.infinity,
            height: 60 + (shadow == null ? 0 : _shadow),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 70),
              height: 60,
              margin: EdgeInsets.only(top: drop),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: enabled
                    ? background
                    : widget.variant == ButtonVariant.primary
                        ? AppColors.yellow.withValues(alpha: .30)
                        : widget.variant == ButtonVariant.confirm
                            ? AppColors.turquoise.withValues(alpha: .26)
                            : AppColors.cream.withValues(alpha: .05),
                borderRadius: BorderRadius.circular(18),
                border: border == null
                    ? null
                    : Border.all(
                        color: enabled ? border : AppColors.muted,
                        width: 2,
                      ),
                boxShadow: shadow == null || !enabled
                    ? null
                    : [
                        BoxShadow(
                          color: shadow,
                          offset: Offset(0, _shadow - drop),
                        ),
                      ],
              ),
              child: widget.icon == null
                  ? Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      style: contentStyle,
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(widget.icon, size: 22, color: contentColor),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            widget.label,
                            textAlign: TextAlign.center,
                            style: contentStyle,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Text whose visual order must stay left-to-right inside the Hebrew UI.
///
/// Use this for codes and numeric expressions that contain neutral separators
/// (spaces, slashes, punctuation). Without an explicit direction, Unicode
/// bidi can reverse their visible runs in an RTL paragraph.
class LtrText extends StatelessWidget {
  const LtrText(
    this.data, {
    this.style,
    this.textAlign,
    this.semanticsLabel,
    super.key,
  });

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Text(
          data,
          style: style,
          textAlign: textAlign,
          semanticsLabel: semanticsLabel,
        ),
      );
}

class TimerBadge extends StatelessWidget {
  const TimerBadge({
    required this.seconds,
    this.color,
    this.remaining,
    this.size = 52,
    this.label,
    super.key,
  });

  final int seconds;

  /// Shown instead of the seconds, for a wait long enough to read as a clock
  /// ("1:42") rather than a count.
  final String? label;

  /// Defaults to yellow, and to coral in the last seconds.
  final Color? color;

  /// Fraction of the phase still to run, 1 at the start and 0 at the deadline.
  /// The filled wedge drains with it, so the time left reads at a glance
  /// without counting digits. Null keeps the circle evenly filled.
  final double? remaining;

  final double size;

  @override
  Widget build(BuildContext context) {
    final ring = color ?? (seconds <= 5 ? AppColors.coral : AppColors.yellow);
    return Semantics(
      label: '$seconds שניות',
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _TimerDial(
            ring: ring,
            remaining: remaining?.clamp(0.0, 1.0) ?? 1,
            stroke: size / 13,
          ),
          child: Center(
            child: Text(
              label ?? '$seconds',
              style: TextStyle(
                color: ring,
                fontSize: size * (label == null ? .38 : .28),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The timer circle. The coloured ring itself is what drains: it runs
/// clockwise from the top and shortens as the phase runs out, leaving a faint
/// track behind it, so the time left reads as a shrinking arc rather than a
/// number to be parsed.
class _TimerDial extends CustomPainter {
  const _TimerDial({
    required this.ring,
    required this.remaining,
    required this.stroke,
  });

  final Color ring;
  final double remaining;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = (Offset.zero & size).center;
    final radius = size.width / 2 - stroke / 2;
    final circle = Rect.fromCircle(center: centre, radius: radius);

    // The track the ring leaves behind, so the circle keeps its shape.
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = ring.withValues(alpha: .16),
    );
    if (remaining <= 0) return;
    canvas.drawArc(
      circle,
      -math.pi / 2,
      2 * math.pi * remaining,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = ring,
    );
  }

  @override
  bool shouldRepaint(_TimerDial old) =>
      old.remaining != remaining || old.ring != ring || old.stroke != stroke;
}

/// A short status line with an icon, in one of the system banner colors.
class StatusBanner extends StatelessWidget {
  const StatusBanner({required this.text, required this.positive, super.key});

  final String text;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final color = positive ? AppColors.turquoise : AppColors.coral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            positive ? Icons.check_circle_rounded : Icons.error_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class GameScaffold extends StatelessWidget {
  const GameScaffold({
    required this.title,
    required this.child,
    this.timer,
    this.onExit,
    this.bottom,
    this.showBack = true,
    this.onBack,
    this.accent,
    this.contentPadding = const EdgeInsets.fromLTRB(24, 12, 24, 28),
    this.showHeader = true,
    this.titleLabel,
    this.scrollable = true,
    this.bannerPlacement,
    super.key,
  });

  final String title;
  final Widget child;

  /// The ad banner strip under the primary button, on the non-game screens
  /// the design allows one (BannerPlacement). Nothing for Premium players.
  final String? bannerPlacement;

  /// A small line above the title, such as the clue screen's "קטגוריה".
  final String? titleLabel;

  /// Screens that scroll a list under something pinned take the body as it is,
  /// instead of putting the whole page in one scroll view.
  final bool scrollable;

  /// Shown top-left inside a circle, usually a [TimerBadge].
  final Widget? timer;

  /// In-game exit, top-right. Without it, a back button takes the slot
  /// whenever the route can pop, so no screen depends on a swipe gesture.
  final VoidCallback? onExit;
  final Widget? bottom;
  final bool showBack;
  final Color? accent;
  final EdgeInsetsGeometry contentPadding;
  final bool showHeader;

  /// Replaces the default pop, for screens that must tell the server first.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final banner =
        bannerPlacement != null && AdBanner.shows(context, bannerPlacement!);
    final scaffold = Scaffold(
      // Transparent only when the DecoratedBox below paints the accent
      // gradient. Without that, nothing paints behind the scaffold and the
      // screen goes black as soon as the route transition disposes whatever
      // was underneath.
      backgroundColor: accent == null ? AppColors.night : Colors.transparent,
      bottomNavigationBar: bottom == null && !banner
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (bottom != null)
                  SafeArea(
                    // The banner takes the bottom inset, 16px below the button.
                    bottom: !banner,
                    minimum: EdgeInsets.fromLTRB(24, 8, 24, banner ? 16 : 22),
                    child: bottom!,
                  ),
                if (banner) AdBanner(bannerPlacement!),
              ],
            ),
      body: SafeArea(
        child: Column(
          children: [
            if (showHeader)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 8),
                child: Row(
                  textDirection: TextDirection.ltr,
                  children: [
                    SizedBox(width: 54, height: 54, child: timer),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (titleLabel != null)
                            Text(
                              titleLabel!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 54,
                      height: 54,
                      child: onExit != null
                          ? IconButton.filledTonal(
                              tooltip: 'יציאה',
                              onPressed: onExit,
                              icon: const Icon(Icons.close_rounded, size: 22),
                            )
                          : showBack && canPop
                              ? BackButton(onPressed: onBack)
                              : null,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: scrollable
                  ? SingleChildScrollView(
                      padding: contentPadding,
                      child: child,
                    )
                  : Padding(padding: contentPadding, child: child),
            ),
          ],
        ),
      ),
    );
    if (accent == null) return scaffold;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -1.05),
          radius: 1.05,
          colors: [accent!, AppColors.night],
          stops: const [0, .62],
        ),
      ),
      child: scaffold,
    );
  }
}

class AvatarView extends StatelessWidget {
  const AvatarView({
    required this.asset,
    this.size = 64,
    this.selected = false,
    this.disconnected = false,
    this.eliminated = false,
    super.key,
  });

  final String asset;
  final double size;
  final bool selected;
  final bool disconnected;
  final bool eliminated;

  @override
  Widget build(BuildContext context) {
    final dimmed = disconnected || eliminated;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: dimmed ? .45 : 1,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.nightSoft,
                border: Border.all(
                  color: selected ? AppColors.yellow : Colors.transparent,
                  width: selected ? 4 : 0,
                ),
              ),
              child: ClipOval(
                child: eliminated
                    ? ColorFiltered(
                        colorFilter: const ColorFilter.mode(
                          Colors.grey,
                          BlendMode.saturation,
                        ),
                        child: Image.asset(asset, fit: BoxFit.cover),
                      )
                    : Image.asset(asset, fit: BoxFit.cover),
              ),
            ),
          ),
          if (disconnected)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _DashedCirclePainter()),
              ),
            ),
          if (selected)
            PositionedDirectional(
              end: -2,
              bottom: -2,
              child: Container(
                width: size * .34,
                height: size * .34,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.yellow,
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: size * .22,
                  color: AppColors.night,
                ),
              ),
            ),
          if (disconnected && !selected)
            PositionedDirectional(
              end: -2,
              bottom: -2,
              child: Container(
                width: size * .36,
                height: size * .36,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.coral,
                ),
                child: Icon(
                  Icons.wifi_off_rounded,
                  size: size * .21,
                  color: AppColors.night,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.coral
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final rect = Offset.zero & size;
    const dash = .22;
    const gap = .12;
    for (var angle = 0.0; angle < math.pi * 2; angle += dash + gap) {
      canvas.drawArc(rect.deflate(2), angle, dash, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PlayerCard extends StatelessWidget {
  const PlayerCard({
    required this.player,
    this.selected = false,
    this.enabled = true,
    this.note,
    this.secondaryNote,
    this.onTap,
    super.key,
  });

  final Player player;

  /// An extra line under the hint, such as why a row cannot be picked.
  final String? note;
  final String? secondaryNote;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected ? AppColors.yellow.withValues(alpha: .12) : null,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            // A card with ten rounds of hints is tall; the face stays at its top.
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AvatarView(
                asset: player.avatar,
                size: 48,
                selected: selected,
                disconnected: player.isDisconnected,
                eliminated: player.isEliminated,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.nickname,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (player.hint != null)
                      Text(
                        player.hint!.isEmpty ? 'לא נשלח רמז' : player.hint!,
                        style: TextStyle(
                          color: player.hint!.isEmpty
                              ? AppColors.coral
                              : AppColors.cream,
                          fontFamily: 'Secular One',
                          fontSize: 19,
                        ),
                      ),
                    if (note != null)
                      Text(
                        note!,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    if (secondaryNote != null)
                      Text(
                        secondaryNote!,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              if (player.isMe)
                const Chip(label: Text('אתם'))
              else if (!enabled)
                const Icon(Icons.block_rounded, color: AppColors.muted)
              else if (selected)
                const Icon(Icons.check_circle_rounded, color: AppColors.yellow),
            ],
          ),
        ),
      ),
    );
  }
}

class Illustration extends StatelessWidget {
  const Illustration(this.asset, {this.height = 210, super.key});

  final String asset;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(asset, height: height, fit: BoxFit.contain);
  }
}

/// A compact label/value surface used throughout the Claude design.
class InfoCard extends StatelessWidget {
  const InfoCard({
    required this.label,
    required this.child,
    this.light = false,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final String label;
  final Widget child;
  final bool light;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final foreground = light ? AppColors.night : AppColors.cream;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: light ? AppColors.cream : AppColors.cream.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(20),
        border: light
            ? null
            : Border.all(color: AppColors.cream.withValues(alpha: .10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: foreground.withValues(alpha: .62),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          DefaultTextStyle.merge(
              style: TextStyle(color: foreground), child: child),
        ],
      ),
    );
  }
}

/// Screen 17 / online elimination_reveal: who was voted out before the next
/// hint round. Shared by local pass-and-play and network games.
class EliminationRevealContent extends StatelessWidget {
  const EliminationRevealContent({
    required this.eliminatedName,
    required this.eliminatedAvatar,
    required this.roleLine,
    required this.remaining,
    super.key,
  });

  final String eliminatedName;
  final String eliminatedAvatar;
  final String roleLine;
  final List<(String name, String avatar)> remaining;

  @override
  Widget build(BuildContext context) {
    // Design L17.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.nightSoft,
              border: Border.all(
                color: AppColors.cream.withValues(alpha: .3),
                width: 4,
              ),
            ),
            child: ClipOval(
              child: Opacity(
                opacity: .55,
                child: ColorFiltered(
                  colorFilter: const ColorFilter.matrix(_grayscale85),
                  child: Image.asset(eliminatedAvatar, fit: BoxFit.cover),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '$eliminatedName הודח/ה',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Secular One',
            fontSize: 36,
            height: 1.1,
            color: AppColors.cream,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.cream,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              Text(
                'התפקיד',
                style: TextStyle(
                  color: AppColors.night.withValues(alpha: .55),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: AppColors.turquoise,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 18, color: AppColors.night),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      roleLine,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Secular One',
                        fontSize: 26,
                        height: 1.1,
                        color: AppColors.night,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                  height: 1, color: AppColors.night.withValues(alpha: .12)),
              const SizedBox(height: 12),
              Text(
                'המילה נשארת סודית — המשחק ממשיך.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.night.withValues(alpha: .7),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'נשארו במשחק',
          style: TextStyle(
            color: AppColors.cream.withValues(alpha: .5),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        // Equal tiles, up to four a row: a phone of twelve still fits.
        LayoutBuilder(
          builder: (context, constraints) {
            final perRow = remaining.length.clamp(1, 4);
            final width = (constraints.maxWidth - 8 * (perRow - 1)) / perRow;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (name, avatar) in remaining)
                  Container(
                    width: width,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.cream.withValues(alpha: .07),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        AvatarView(asset: avatar, size: 40),
                        const SizedBox(height: 7),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.cream,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// CSS grayscale(.85).
const _grayscale85 = <double>[
  0.3307, 0.6079, 0.0614, 0, 0, //
  0.1807, 0.7579, 0.0614, 0, 0, //
  0.1807, 0.6079, 0.2114, 0, 0, //
  0, 0, 0, 1, 0,
];

class StepCard extends StatelessWidget {
  const StepCard(
      {required this.number,
      required this.text,
      this.purple = false,
      super.key});

  final int number;
  final String text;
  final bool purple;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: purple ? AppColors.purple : AppColors.yellow,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              '$number',
              style: TextStyle(
                color: purple ? AppColors.cream : AppColors.night,
                fontFamily: 'Secular One',
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.night,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The dots after "כותב/ת רמז", counting up and starting over: `.` `..` `...`.
/// A fixed width, so the text beside them does not shift as they come and go.
class TypingDots extends StatefulWidget {
  const TypingDots({required this.colour, super.key});

  final Color colour;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final _run = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      child: AnimatedBuilder(
        animation: _run,
        builder: (context, _) => Text(
          '.' * (1 + (_run.value * 3).floor().clamp(0, 2)),
          style: TextStyle(
            color: widget.colour,
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// The hint that just landed, shown where the eye already is and lit for a
/// moment so it is noticed.
///
/// This replaces an earlier attempt that froze the screen for three seconds
/// before a turn: a pause costs the player time and still hides the hint the
/// instant it ends. Showing it, unmissably, costs nothing.
class LastHintCard extends StatelessWidget {
  const LastHintCard({
    required this.nickname,
    required this.avatar,
    required this.hint,
    required this.highlight,
    super.key,
  });

  final String nickname;
  final String avatar;
  final String hint;

  /// Fades from lit to resting. Keyed on the hint so a new one lights again.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(hint),
      tween: Tween(begin: highlight ? 1 : 0, end: 0),
      duration: const Duration(milliseconds: 2600),
      curve: Curves.easeOut,
      builder: (context, lit, child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: Color.lerp(AppColors.cream.withValues(alpha: .05),
              AppColors.turquoise.withValues(alpha: .18), lit),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Color.lerp(AppColors.cream.withValues(alpha: .10),
                AppColors.turquoise, lit)!,
          ),
        ),
        child: child,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'הרמז הקודם · $nickname',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.cream,
                    fontFamily: 'Secular One',
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          AvatarView(asset: avatar, size: 40),
        ],
      ),
    );
  }
}

/// The purple card on the hints screen: whose turn it is, and what they are
/// doing — writing, or the word they just wrote.
///
/// One card for both so it does not change shape or style mid-round: only its
/// second line swaps.
class TurnCard extends StatelessWidget {
  const TurnCard({
    required this.title,
    required this.avatar,
    required this.subtitle,
    this.disconnected = false,
    super.key,
  });

  final String title;
  final String avatar;

  /// The second line: the typing indicator, or the hint just written.
  final Widget subtitle;
  final bool disconnected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: .26),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.purple.withValues(alpha: .55)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.cream,
                    fontFamily: 'Secular One',
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 4),
                subtitle,
              ],
            ),
          ),
          const SizedBox(width: 12),
          AvatarView(asset: avatar, size: 56, disconnected: disconnected),
        ],
      ),
    );
  }
}

/// Floats a reaction off the top of the screen from [anchor], the way the
/// design's `om-bubble` keyframes do: it pops at the card it belongs to,
/// drifts sideways as it climbs, and fades out on the way up. It goes into the
/// root overlay so nothing on the screen clips it.
///
/// [seed] varies the drift, so a burst of reactions fans out instead of rising
/// in one column.
void floatReaction(
  BuildContext context,
  String text, {
  required GlobalKey anchor,
  int seed = 0,
}) {
  final box = anchor.currentContext?.findRenderObject() as RenderBox?;
  final overlay = Overlay.maybeOf(context);
  if (overlay == null || box == null || !box.hasSize) return;
  final origin = box.localToGlobal(Offset(box.size.width / 2, 0));
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ReactionBubble(
      text: text,
      origin: origin,
      drift: (seed.isEven ? 1 : -1) * (30 + (seed % 3) * 16),
      onDone: entry.remove,
    ),
  );
  // The caller is usually a snapshot landing mid-build, and inserting into the
  // overlay marks it dirty, so wait for the frame to finish.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (overlay.mounted) overlay.insert(entry);
  });
}

class _ReactionBubble extends StatefulWidget {
  const _ReactionBubble({
    required this.text,
    required this.origin,
    required this.drift,
    required this.onDone,
  });

  final String text;
  final Offset origin; // Global, the top centre of the card it rises from.
  final double drift;
  final VoidCallback onDone;

  @override
  State<_ReactionBubble> createState() => _ReactionBubbleState();
}

class _ReactionBubbleState extends State<_ReactionBubble>
    with SingleTickerProviderStateMixin {
  // The om-bubble keyframes, read straight off the prototype: the stops as
  // fractions of the six seconds, and what each channel is worth at each one.
  static const _stops = [0.0, .06, .12, .30, .50, .70, .88, 1.0];
  static const _rise = [
    4.0,
    -14.0,
    -40.0,
    -150.0,
    -270.0,
    -380.0,
    -470.0,
    -530.0
  ];
  static const _fade = [0.0, 1.0, 1.0, .95, .8, .55, .22, 0.0];
  static const _scale = [.6, 1.04, 1.0, 1.0, .99, .97, .94, .9];
  static const _sway = [0.0, 0.0, 0.0, .7, -.4, .8, .2, .5];

  late final _run = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )
    ..addStatusListener((status) {
      // Removing the entry tears this widget down, so leave the frame first.
      if (status == AnimationStatus.completed) {
        WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
      }
    })
    ..forward();

  static double _at(List<double> channel, double t) {
    for (var i = 1; i < _stops.length; i++) {
      if (t <= _stops[i]) {
        final progress = (t - _stops[i - 1]) / (_stops[i] - _stops[i - 1]);
        return channel[i - 1] + (channel[i] - channel[i - 1]) * progress;
      }
    }
    return channel.last;
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Emoji get the bigger, tighter pill; the structured messages are text.
    final emoji = !RegExp(r'[֐-׿]').hasMatch(widget.text);
    return Positioned(
      left: widget.origin.dx,
      top: widget.origin.dy,
      child: IgnorePointer(
        child: FractionalTranslation(
          translation: const Offset(-.5, 0),
          child: AnimatedBuilder(
            animation: _run,
            builder: (context, child) => Transform.translate(
              offset: Offset(
                widget.drift * _at(_sway, _run.value),
                _at(_rise, _run.value),
              ),
              child: Transform.scale(
                scale: _at(_scale, _run.value),
                child: Opacity(
                  opacity: _at(_fade, _run.value).clamp(0.0, 1.0),
                  child: child,
                ),
              ),
            ),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: emoji ? 14 : 15,
                vertical: emoji ? 7 : 9,
              ),
              decoration: BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x660A081E),
                    blurRadius: 22,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Text(
                widget.text,
                softWrap: false,
                style: TextStyle(
                  color: AppColors.night,
                  fontSize: emoji ? 24 : 14,
                  fontWeight: emoji ? FontWeight.w400 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Which hint-and-vote round the table is in. Shown from the second one, since
/// a match that ends in one round never had rounds to count.
class RoundBadge extends StatelessWidget {
  const RoundBadge({required this.round, super.key});

  final int round;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.purple.withValues(alpha: .22),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.purple.withValues(alpha: .6)),
        ),
        child: Text(
          'סבב $round',
          style: const TextStyle(
            color: Color(0xFFD9C8FF),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Shown to a player the table voted out: they keep watching and reacting, and
/// they still win or lose with their side.
class SpectatorNote extends StatelessWidget {
  const SpectatorNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.coral.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.coral.withValues(alpha: .42)),
      ),
      child: const Column(
        children: [
          Icon(Icons.visibility_outlined, color: AppColors.coral, size: 26),
          SizedBox(height: 8),
          Text(
            'הודחתם מהמשחק',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Secular One',
              fontSize: 19,
              color: Color(0xFFFFD9D9),
            ),
          ),
          SizedBox(height: 4),
          Text(
            'אתם ממשיכים לצפות ולהגיב, בלי רמזים והצבעות. '
            'התוצאה שלכם היא של הקבוצה שלכם.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFFFD9D9), height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Separates one round's hints from the next on a board that keeps them all.
class RoundDivider extends StatelessWidget {
  const RoundDivider({required this.round, super.key});

  final int round;

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Container(
        height: 1,
        color: AppColors.cream.withValues(alpha: .14),
      ),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'סבב $round',
            style: TextStyle(
              color: AppColors.cream.withValues(alpha: .55),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        line,
      ],
    );
  }
}

/// The round's category, as a pill. Shared by the online and one-device role
/// reveals so the same screen reads the same way in both.
class CategoryPill extends StatelessWidget {
  const CategoryPill({required this.category, super.key});

  final String category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: .22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.purple.withValues(alpha: .6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'קטגוריה',
            style: TextStyle(color: Color(0xFFD9C8FF), fontSize: 13),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              category,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFC4B0FF),
                fontFamily: 'Secular One',
                fontSize: 17,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The word card on a role reveal: the word itself for a citizen, and four
/// masked tiles for the impostor, who is told what they are rather than shown
/// nothing at all.
///
/// Shared, because the same card was drawn twice — once online and once for
/// the one-device game — and the two drifted apart.
class SecretWordCard extends StatelessWidget {
  const SecretWordCard({required this.word, required this.impostor, super.key});

  /// The secret word. Ignored when [impostor] is true, and never read from
  /// there, so an impostor's card cannot show it by accident.
  final String? word;
  final bool impostor;

  @override
  Widget build(BuildContext context) {
    return InfoCard(
      label: 'המילה הסודית',
      light: !impostor,
      child: impostor
          // Not a row of letter boxes. Four of them said the word was four
          // letters long, which is a clue nobody meant to give — and the
          // impostor would count them. One covered card says hidden without
          // saying how much.
          ? Column(
              children: [
                Container(
                  height: 62,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.night.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.cream.withValues(alpha: .10),
                    ),
                  ),
                  child: Icon(
                    Icons.visibility_off_rounded,
                    size: 30,
                    color: AppColors.cream.withValues(alpha: .45),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'המילה לא מוצגת לכם — רק הקטגוריה.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, height: 1.45),
                ),
              ],
            )
          : Text(
              word ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.night,
                fontFamily: 'Secular One',
                fontSize: 38,
              ),
            ),
    );
  }
}

/// The beat between the last hint and the vote (screen 11א).
///
/// Shared by the online and one-device games, which drew it twice and drifted:
/// one had a large dial in the middle of the screen, the other a small badge
/// in the corner, and the headings were different sizes. The countdown itself
/// is passed in, because online counts down to a deadline the server set and
/// the one-device game counts its own seconds.
class ToVotingView extends StatelessWidget {
  const ToVotingView({
    required this.countdown,
    required this.note,
    this.onExit,
    this.bottom,
    this.footnote = 'מסך ההצבעה נפתח אוטומטית',
    super.key,
  });

  /// The dial, already counting.
  final Widget countdown;

  /// The line under the heading. The only thing the two games say
  /// differently: online is deciding, one device is passing the phone around.
  final String note;
  final VoidCallback? onExit;
  final Widget? bottom;
  final String footnote;

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: '',
      onExit: onExit,
      accent: const Color(0xFF3A3470),
      bottom: bottom,
      child: Column(
        children: [
          const SizedBox(height: 4),
          const Illustration(
            'assets/illustrations/pre-vote-transition.webp',
            height: 190,
          ),
          const SizedBox(height: 18),
          const Text(
            'כל הרמזים נשלחו',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'עוברים להצבעה',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displayLarge,
          ),
          const SizedBox(height: 10),
          Text(
            note,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 26),
          countdown,
          const SizedBox(height: 14),
          Text(
            footnote,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Design 15ב/15ג: a tie, before the runoff or after a runoff that tied as
/// well. Shared by pass-and-play and network games.
class TieAnnouncementContent extends StatelessWidget {
  const TieAnnouncementContent({
    required this.subtitle,
    required this.explanation,
    required this.candidates,
    this.footnote,
    super.key,
  });

  final String subtitle;
  final String explanation;

  /// Who tied: name, avatar, and a line under them such as the vote count.
  final List<(String name, String avatar, String? note)> candidates;
  final String? footnote;

  /// The explanation's first sentence, which the design sets in bold.
  String get _lead {
    final end = explanation.indexOf('.');
    return end < 0 ? explanation : explanation.substring(0, end + 1);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Illustration(
          'assets/illustrations/tie-announcement.webp',
          height: 190,
        ),
        const SizedBox(height: 14),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, fontSize: 15),
        ),
        const SizedBox(height: 16),
        // Wrapped rather than a row: a tie can be between more than two, and
        // the design says never to crop a name or show only the first pair.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final (name, avatar, note) in candidates)
              SizedBox(
                width: 96,
                child: Column(
                  children: [
                    AvatarView(asset: avatar, size: 66),
                    const SizedBox(height: 8),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (note != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        note,
                        style: const TextStyle(
                          color: AppColors.yellow,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
          decoration: BoxDecoration(
            color: AppColors.coral.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.coral.withValues(alpha: .47)),
          ),
          // Design 15ב/15ג: the scales inline, the first sentence in bold
          // pink, the rest in cream.
          child: Text.rich(
            TextSpan(
              style: const TextStyle(
                color: AppColors.cream,
                fontSize: 15,
                height: 1.55,
              ),
              children: [
                const WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(end: 7),
                    child: Icon(
                      Icons.balance_rounded,
                      color: AppColors.yellow,
                      size: 18,
                    ),
                  ),
                ),
                TextSpan(
                  text: _lead,
                  style: const TextStyle(
                    color: Color(0xFFFFB7B7),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: explanation.substring(_lead.length)),
              ],
            ),
          ),
        ),
        if (footnote case final line?) ...[
          const SizedBox(height: 12),
          Text(
            line,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
      ],
    );
  }
}

/// Designs 15/16 (online) and L20/L21 (one device): the end of a match, one
/// layout for both. [children] are the mode's own sections under the card:
/// the vote breakdown online, who was voted out and a note on one device.
class GameResultContent extends StatelessWidget {
  const GameResultContent({
    required this.winner,
    required this.title,
    required this.reason,
    required this.impostorName,
    required this.impostorAvatar,
    required this.secretWord,
    required this.impostorLabel,
    this.guess,
    this.rounds,
    this.cardLabel,
    this.above,
    this.children = const [],
    super.key,
  });

  /// The line over the impostor's name: "המתחזה היה" online, "המתחזה" on
  /// one device.
  final String impostorLabel;

  /// A heading over the card, such as "איך זה נגמר".
  final String? cardLabel;

  /// Between the reason and the card, such as what the match recorded.
  final Widget? above;

  /// 'citizens', 'impostor', or null for a match that was stopped.
  final String? winner;
  final String title;
  final String reason;
  final String impostorName;
  final String impostorAvatar;
  final String secretWord;
  final String? guess;
  final int? rounds;
  final List<Widget> children;

  /// The accent behind the screen, for [GameScaffold.accent].
  static Color? accentFor(String? winner) => switch (winner) {
        'citizens' => const Color(0xFF14514A),
        'impostor' => const Color(0xFF4A2A8C),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final label = TextStyle(
      color: AppColors.night.withValues(alpha: .55),
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );
    Widget line(String name, Widget value) => Row(
          children: [
            Text(name, style: label),
            const SizedBox(width: 12),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: value,
              ),
            ),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Image.asset(
            switch (winner) {
              'citizens' => 'assets/illustrations/result-citizens-win.webp',
              'impostor' => 'assets/illustrations/result-impostor-win.webp',
              _ => 'assets/illustrations/connection-error.webp',
            },
            width: 132,
            height: 132,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Secular One',
            fontSize: 34,
            height: 1.1,
            color: switch (winner) {
              'citizens' => AppColors.turquoise,
              'impostor' => AppColors.yellow,
              _ => AppColors.cream,
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          reason,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.cream.withValues(alpha: .75),
            fontSize: 15,
            height: 1.5,
          ),
        ),
        if (above case final above?) ...[
          const SizedBox(height: 10),
          above,
        ],
        const SizedBox(height: 14),
        if (cardLabel case final label?) ...[
          ResultSectionLabel(label),
          const SizedBox(height: 8),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cream,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.purple, width: 3),
                    ),
                    child: AvatarView(asset: impostorAvatar, size: 46),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(impostorLabel,
                            style: label.copyWith(fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          impostorName,
                          style: const TextStyle(
                            fontFamily: 'Secular One',
                            fontSize: 22,
                            height: 1.15,
                            color: AppColors.night,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                  height: 1, color: AppColors.night.withValues(alpha: .12)),
              const SizedBox(height: 12),
              line(
                'המילה הייתה',
                Text(
                  secretWord,
                  style: const TextStyle(
                    fontFamily: 'Secular One',
                    fontSize: 26,
                    height: 1,
                    color: AppColors.night,
                  ),
                ),
              ),
              if (guess case final guess?) ...[
                const SizedBox(height: 12),
                line(
                  'הניחוש',
                  Text(
                    guess,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: Color(0xFFC4413F),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              if (rounds case final rounds?) ...[
                const SizedBox(height: 12),
                line(
                  'סבבים',
                  Text(
                    '$rounds',
                    style: const TextStyle(
                      color: AppColors.night,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        for (final child in children) ...[
          const SizedBox(height: 14),
          child,
        ],
      ],
    );
  }
}

/// A section heading under the result card.
class ResultSectionLabel extends StatelessWidget {
  const ResultSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          color: AppColors.cream.withValues(alpha: .6),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      );
}

/// Design 15/16: the last vote, one bar per player out of the whole table.
class ResultVoteBars extends StatelessWidget {
  const ResultVoteBars({required this.rows, required this.of, super.key});

  /// Name, votes and the bar's colour, in the order shown.
  final List<(String name, int votes, Color color)> rows;
  final int of;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ResultSectionLabel('חלוקת הקולות'),
        for (final (name, votes, color) in rows) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 58,
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.cream,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 22,
                    color: AppColors.cream.withValues(alpha: .1),
                    alignment: AlignmentDirectional.centerStart,
                    child: FractionallySizedBox(
                      widthFactor: of == 0 ? 0 : (votes / of).clamp(0, 1),
                      heightFactor: 1,
                      child: ColoredBox(color: color),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$votes',
                style: const TextStyle(
                  color: AppColors.cream,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A tinted note with an icon, as under results and eliminations.
class ResultNote extends StatelessWidget {
  const ResultNote({
    required this.text,
    required this.icon,
    required this.color,
    super.key,
  });

  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.cream.withValues(alpha: .76),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "משחק נוסף" over "חזרה למסך הבית", the end of every match (design 15).
class ResultButtons extends StatelessWidget {
  const ResultButtons({
    required this.onAgain,
    required this.onHome,
    super.key,
  });

  final VoidCallback? onAgain;
  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(label: 'משחק נוסף', onPressed: onAgain),
        const SizedBox(height: 12),
        SizedBox(
          height: 54,
          child: OutlinedButton(
            onPressed: onHome,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.cream,
              side: BorderSide(
                color: AppColors.cream.withValues(alpha: .28),
                width: 2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Rubik',
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            child: const Text('חזרה למסך הבית'),
          ),
        ),
      ],
    );
  }
}
