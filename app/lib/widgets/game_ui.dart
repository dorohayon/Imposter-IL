import 'package:flutter/material.dart';

import '../models/player.dart';
import '../theme/app_theme.dart';

/// The button styles of the design system (design/claude/design-system.md).
enum ButtonVariant { primary, secondary, confirm, danger }

class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.variant = ButtonVariant.primary,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonVariant variant;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  static const _sink = 6.0; // how far a filled button drops when pressed
  static const _shadow = 8.0;

  bool _pressed = false;

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
    };
    final drop = shadow != null && _pressed ? _sink : 0.0;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTapDown: enabled ? (_) => _setPressed(true) : null,
          onTapUp: enabled ? (_) => _setPressed(false) : null,
          onTapCancel: enabled ? () => _setPressed(false) : null,
          onTap: widget.onPressed,
          child: SizedBox(
            width: double.infinity,
            height: 58 + (shadow == null ? 0 : _shadow),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 70),
              height: 58,
              margin: EdgeInsets.only(top: drop),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: enabled
                    ? background
                    : (shadow == null
                        ? Colors.transparent
                        : const Color(0xFF3A3850)),
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
              child: Text(
                widget.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  // Readable disabled text (WCAG AA on the disabled background).
                  color: enabled ? foreground : AppColors.muted,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TimerBadge extends StatelessWidget {
  const TimerBadge({required this.seconds, this.color, super.key});

  final int seconds;

  /// Defaults to yellow, and to coral in the last seconds.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ring = color ?? (seconds <= 5 ? AppColors.coral : AppColors.yellow);
    return Semantics(
      label: '$seconds שניות',
      child: Container(
        width: 54,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ring.withValues(alpha: 0.14),
          border: Border.all(color: ring, width: 4),
        ),
        child: Text(
          '$seconds',
          style: TextStyle(
            color: ring,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
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
    super.key,
  });

  final String title;
  final Widget child;

  /// Shown top-left inside a circle, usually a [TimerBadge].
  final Widget? timer;

  /// In-game exit, top-right. Without it, a back button takes the slot
  /// whenever the route can pop, so no screen depends on a swipe gesture.
  final VoidCallback? onExit;
  final Widget? bottom;
  final bool showBack;

  /// Replaces the default pop, for screens that must tell the server first.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return Scaffold(
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: bottom!,
            ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                textDirection: TextDirection.ltr,
                children: [
                  SizedBox(width: 54, height: 54, child: timer),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  SizedBox(
                    width: 54,
                    height: 54,
                    child: onExit != null
                        ? IconButton.filledTonal(
                            tooltip: 'יציאה',
                            onPressed: onExit,
                            icon: const Icon(Icons.close_rounded),
                          )
                        : showBack && canPop
                            ? BackButton(onPressed: onBack)
                            : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AvatarView extends StatelessWidget {
  const AvatarView({
    required this.asset,
    this.size = 64,
    this.selected = false,
    this.disconnected = false,
    super.key,
  });

  final String asset;
  final double size;
  final bool selected;
  final bool disconnected;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: disconnected ? .45 : 1,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.cream,
          border: Border.all(
            color: selected ? AppColors.yellow : const Color(0xFF555169),
            width: selected ? 4 : 2,
          ),
        ),
        child: ClipOval(child: Image.asset(asset, fit: BoxFit.cover)),
      ),
    );
  }
}

class PlayerCard extends StatelessWidget {
  const PlayerCard({
    required this.player,
    this.selected = false,
    this.enabled = true,
    this.note,
    this.onTap,
    super.key,
  });

  final Player player;

  /// An extra line under the hint, such as why a row cannot be picked.
  final String? note;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected ? AppColors.yellow.withValues(alpha: .14) : null,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              AvatarView(
                asset: player.avatar,
                selected: selected,
                disconnected: player.isDisconnected,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(player.nickname,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    if (player.hint != null)
                      Text(
                        player.hint!.isEmpty
                            ? 'לא נשלח רמז'
                            : 'הרמז: ${player.hint}',
                        style: TextStyle(
                          color: player.hint!.isEmpty
                              ? AppColors.coral
                              : AppColors.muted,
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
                  ],
                ),
              ),
              if (player.isMe)
                const Chip(label: Text('אני'))
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
