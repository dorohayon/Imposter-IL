import 'package:flutter/material.dart';

import '../models/player.dart';
import '../theme/app_theme.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.secondary = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: secondary
          ? OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.cream,
                side: const BorderSide(color: AppColors.yellow, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
            )
          : FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.yellow,
                foregroundColor: AppColors.night,
                disabledBackgroundColor: const Color(0xFF65606A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900)),
            ),
    );
  }
}

class TimerBadge extends StatelessWidget {
  const TimerBadge(
      {required this.seconds, this.color = AppColors.yellow, super.key});

  final int seconds;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$seconds שניות',
      child: Container(
        width: 54,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))
          ],
        ),
        child: Text(
          '$seconds',
          style: const TextStyle(
            color: AppColors.night,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
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
    this.onTap,
    super.key,
  });

  final Player player;
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
                        style: const TextStyle(color: AppColors.muted),
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
