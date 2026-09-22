import 'package:flutter/material.dart';

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'שני מצבים, אותו משחק. אפשר להצטרף לשחקנים אחרים או לפתוח חדר לחברים.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.45),
          ),
          const SizedBox(height: 18),
          _ModeCard(
            illustration: 'assets/illustrations/matchmaking-team.webp',
            title: 'משחק מהיר',
            description: 'בוחרים קטגוריות ומצטרפים לשחקנים ברשת',
            notes: const ['4–8 שחקנים'],
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CategorySelectionScreen(),
              ),
            ),
          ),
          const SizedBox(height: 12),
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
    return Material(
      color: AppColors.cream.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Illustration(illustration, height: 84),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Secular One',
                        fontSize: 21,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final note in notes)
                      Text(
                        '· $note',
                        style: const TextStyle(
                          color: AppColors.yellow,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
