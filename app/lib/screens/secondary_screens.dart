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
            label: const Text('עריכת כינוי ואווטאר'),
          ),
          const SizedBox(height: 20),
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
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cream.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'אין במשחק ניקוד. רק מספר הניצחונות וההפסדים נשמר במכשיר הזה.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.4),
            ),
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
          const _SettingsRow(
            title: 'צלילים',
            value: false,
            enabled: false,
            note: 'בקרוב',
          ),
          const SizedBox(height: 10),
          _SettingsRow(
            title: 'רטט',
            value: session.vibrationOn,
            onChanged: session.setVibration,
          ),
          const SizedBox(height: 10),
          _SettingsRow(
            title: 'הצגת תגובות',
            value: session.showReactions,
            onChanged: session.setShowReactions,
          ),
          const SizedBox(height: 10),
          const _LinkRow(title: 'שפה', value: 'עברית'),
          const SizedBox(height: 20),
          const _LinkRow(title: 'תנאי שימוש', value: 'בקרוב', enabled: false),
          const SizedBox(height: 10),
          const _LinkRow(
            title: 'מדיניות פרטיות',
            value: 'בקרוב',
            enabled: false,
          ),
          const SizedBox(height: 36),
          const Text(
            'מי המתחזה? · גרסה 1.0',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    required this.value,
    this.onChanged,
    this.enabled = true,
    this.note,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cream.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: enabled && onChanged != null ? () => onChanged!(!value) : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: enabled ? AppColors.cream : AppColors.muted,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (note != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        note!,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ],
                ),
              ),
              IgnorePointer(
                child: Switch(
                  value: value,
                  onChanged: enabled ? onChanged : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow(
      {required this.title, required this.value, this.enabled = true});

  final String title;
  final String value;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.cream.withValues(alpha: enabled ? .06 : .035),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: enabled ? AppColors.cream : AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(value, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_left_rounded, color: AppColors.muted),
        ],
      ),
    );
  }
}

class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  static const steps = [
    'כולם מקבלים את אותה מילה סודית — חוץ מהמתחזה, שרואה רק את הקטגוריה.',
    'כל שחקן כותב בתורו רמז של מילה אחת. לכל תור יש 15 שניות.',
    'אפשר להגיב לרמזים באמצעות אימוג׳ים והודעות מוכנות.',
    'בסוף הסבב מצביעים מי המתחזה. יש 20 שניות להצביע.',
    'אם המתחזה נתפס, יש לו 15 שניות לנחש את המילה ולנצח בכל זאת.',
  ];

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'איך משחקים?',
      accent: const Color(0xFF2A2455),
      bottom: PrimaryButton(
        label: 'הבנתי',
        onPressed: () => Navigator.of(context).pop(),
      ),
      child: Column(
        children: [
          ...List.generate(steps.length, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: StepCard(
                number: index + 1,
                text: steps[index],
                purple: index == steps.length - 1,
              ),
            );
          }),
          const Illustration('assets/illustrations/how-to-play.webp',
              height: 110),
        ],
      ),
    );
  }
}
