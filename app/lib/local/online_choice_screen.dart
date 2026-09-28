import 'package:flutter/material.dart';

import '../monetization/monetization_config.dart';
import '../screens/online_flow.dart';
import '../screens/private_flow.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';

/// Screen 02: the two ways to play over a network, which used to sit side by
/// side on the home screen. The home screen has a third way now — one device —
/// so the online pair moved behind one door.
class OnlineChoiceScreen extends StatelessWidget {
  const OnlineChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'משחק ברשת',
      bannerPlacement: BannerPlacement.onlineChoice,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'שני מצבים, אותו משחק. אפשר להצטרף לשחקנים אחרים או לפתוח חדר לחברים.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.cream.withValues(alpha: .62),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          _ModeCard(
            illustration: 'assets/illustrations/matchmaking-team.webp',
            title: 'משחק מהיר',
            description: 'בוחרים קטגוריות ומצטרפים לשחקנים ברשת.',
            notes: const ['4–8 שחקנים'],
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CategorySelectionScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ModeCard(
            illustration: 'assets/illustrations/private-room.webp',
            title: 'חדר פרטי',
            description: 'יוצרים חדר ושולחים קוד, או מצטרפים לחדר קיים.',
            notes: const ['4–8 שחקנים', 'אתם קובעים מתי מתחילים'],
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const FriendsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.illustration,
    required this.title,
    required this.description,
    required this.notes,
    required this.onTap,
  });

  final String illustration;
  final String title;
  final String description;
  final List<String> notes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(26);
    return Material(
      color: AppColors.cream.withValues(alpha: .06),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: AppColors.cream.withValues(alpha: .14),
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 86,
                    height: 86,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.cream.withValues(alpha: .07),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Image.asset(illustration, width: 78, height: 78),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontFamily: 'Secular One',
                            fontSize: 26,
                            height: 1.1,
                            color: AppColors.cream,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: TextStyle(
                            color: AppColors.cream.withValues(alpha: .7),
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final note in notes)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.cream.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        note,
                        style: TextStyle(
                          color: AppColors.cream.withValues(alpha: .7),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
