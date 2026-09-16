import 'package:flutter/material.dart';

import '../state/game_session.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';
import 'onboarding_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return GameScaffold(
      title: 'הפרופיל שלי',
      child: Column(
        children: [
          AvatarView(
            asset: 'assets/avatars/${session.avatarId}.webp',
            size: 138,
            selected: true,
          ),
          const SizedBox(height: 14),
          Text(
            session.nickname ?? '',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ProfileEditScreen(),
              ),
            ),
            icon: const Icon(Icons.edit_rounded),
            label: const Text('עריכת פרטים'),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  value: '${session.wins}',
                  label: 'ניצחונות',
                  color: AppColors.turquoise,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  value: '${session.losses}',
                  label: 'הפסדים',
                  color: AppColors.coral,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'הניצחונות וההפסדים נשמרים במכשיר הזה',
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return GameScaffold(
      title: 'הגדרות',
      child: Column(
        children: [
          // No sound files exist yet (docs/decisions.md).
          const SwitchListTile(
            title: Text('צלילים'),
            subtitle: Text('בקרוב'),
            secondary: Icon(Icons.volume_up_rounded),
            value: false,
            onChanged: null,
          ),
          SwitchListTile(
            title: const Text('רטט'),
            subtitle:
                const Text('כשהתור שלך מגיע, כשמשחק מתחיל וכשמתחילה הצבעה'),
            secondary: const Icon(Icons.vibration_rounded),
            value: session.vibrationOn,
            onChanged: session.setVibration,
          ),
          SwitchListTile(
            title: const Text('הצגת תגובות'),
            subtitle: const Text('אימוג׳ים והודעות מובנות'),
            secondary: const Icon(Icons.emoji_emotions_rounded),
            value: session.showReactions,
            onChanged: session.setShowReactions,
          ),
          const Divider(height: 36),
          const ListTile(
            leading: Icon(Icons.language_rounded),
            title: Text('שפה'),
            trailing: Text('עברית'),
          ),
          // Disabled until the documents exist (TASKS.md, P2).
          const ListTile(
            enabled: false,
            leading: Icon(Icons.description_outlined),
            title: Text('תנאי שימוש'),
            subtitle: Text('בקרוב'),
          ),
          const ListTile(
            enabled: false,
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('מדיניות פרטיות'),
            subtitle: Text('בקרוב'),
          ),
        ],
      ),
    );
  }
}

class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  static const steps = [
    (
      'כולם מקבלים מילה',
      'חוץ מהמתחזה, שרואה רק את הקטגוריה.',
      Icons.visibility_rounded
    ),
    ('כותבים רמז בתור', 'כל רמז הוא מילה אחת בלבד.', Icons.edit_note_rounded),
    (
      'מגיבים לרמזים',
      'אפשר לשלוח אימוג׳ים והודעות מובנות.',
      Icons.emoji_emotions_rounded
    ),
    ('מצביעים', 'מי לדעתכם הוא המתחזה?', Icons.how_to_vote_rounded),
    (
      'הזדמנות אחרונה',
      'אם נתפס, המתחזה יכול לנחש את המילה ולנצח.',
      Icons.psychology_rounded
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'איך משחקים?',
      child: Column(
        children: [
          const Illustration('assets/illustrations/how-to-play.webp',
              height: 210),
          ...List.generate(steps.length, (index) {
            final step = steps[index];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.yellow,
                  foregroundColor: AppColors.night,
                  child: Text('${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
                title: Text(step.$1,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text(step.$2),
                trailing: Icon(step.$3, color: AppColors.turquoise),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Shown when the server refuses this build (`client_too_old`). Nothing else
/// is reachable: an old install whose protocol the server dropped can only
/// update, so this screen has no way back.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'צריך לעדכן',
      showBack: false,
      child: Column(
        children: [
          const SizedBox(height: 12),
          const Illustration('assets/illustrations/connection-error.webp'),
          const SizedBox(height: 20),
          Text(
            'יש גרסה חדשה של המשחק',
            style: Theme.of(context).textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'הגרסה שמותקנת אצלכם כבר לא נתמכת.\n'
            'עדכנו את האפליקציה בחנות כדי להמשיך לשחק.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}
