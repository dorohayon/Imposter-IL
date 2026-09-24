import 'package:flutter/material.dart';

import 'monetization.dart';

/// The adaptive banner strip at the bottom of a non-game screen
/// (design "כללי פרסומות"). Below the primary button, never over content; the
/// space is kept while the ad loads and stays empty if none comes. Premium
/// players get nothing at all, not even the space.
class AdBanner extends StatelessWidget {
  const AdBanner(this.placement, {super.key});

  final String placement;

  /// Whether [placement] shows a banner for this player right now.
  static bool shows(BuildContext context, String placement) =>
      MonetizationScope.maybeOf(context)?.bannerUnit(placement) != null;

  @override
  Widget build(BuildContext context) {
    final monetization = MonetizationScope.maybeOf(context);
    final unit = monetization?.bannerUnit(placement);
    if (monetization == null || unit == null) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: 'פרסומת',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF0C0B1F),
          border: Border(
            top: BorderSide(
                color: const Color(0xFFFFF8E7).withValues(alpha: .1)),
          ),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 14),
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: monetization.adsReady
                ? monetization.ads.banner(unit)
                : const SizedBox(height: 60, width: double.infinity),
          ),
        ),
      ),
    );
  }
}
