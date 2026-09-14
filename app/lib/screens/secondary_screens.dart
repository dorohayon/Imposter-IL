import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({required this.nickname, required this.avatar, super.key});

  final String nickname;
  final String avatar;

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'הפרופיל שלי',
      child: Column(
        children: [
          AvatarView(asset: avatar, size: 138, selected: true),
          const SizedBox(height: 14),
          Text(nickname, style: Theme.of(context).textTheme.headlineLarge),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.edit_rounded),
            label: const Text('עריכת פרטים'),
          ),
          const SizedBox(height: 24),
          Row(
            children: const [
              Expanded(child: _StatCard(value: '0', label: 'ניצחונות', color: AppColors.turquoise)),
              SizedBox(width: 12),
              Expanded(child: _StatCard(value: '0', label: 'הפסדים', color: AppColors.coral)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label, required this.color});

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
            Text(value, style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: color)),
            Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool sounds = true;
  bool vibration = true;
  bool reactions = true;

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'הגדרות',
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('צלילים'),
            secondary: const Icon(Icons.volume_up_rounded),
            value: sounds,
            onChanged: (value) => setState(() => sounds = value),
          ),
          SwitchListTile(
            title: const Text('רטט'),
            secondary: const Icon(Icons.vibration_rounded),
            value: vibration,
            onChanged: (value) => setState(() => vibration = value),
          ),
          SwitchListTile(
            title: const Text('הצגת תגובות'),
            subtitle: const Text('אימוג׳ים והודעות מובנות'),
            secondary: const Icon(Icons.emoji_emotions_rounded),
            value: reactions,
            onChanged: (value) => setState(() => reactions = value),
          ),
          const Divider(height: 36),
          const ListTile(
            leading: Icon(Icons.language_rounded),
            title: Text('שפה'),
            trailing: Text('עברית'),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('תנאי שימוש'),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('מדיניות פרטיות'),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  static const steps = [
    ('כולם מקבלים מילה', 'חוץ מהמתחזה, שרואה רק את הקטגוריה.', Icons.visibility_rounded),
    ('כותבים רמז בתור', 'כל רמז הוא מילה אחת בלבד.', Icons.edit_note_rounded),
    ('מגיבים לרמזים', 'אפשר לשלוח אימוג׳ים והודעות מובנות.', Icons.emoji_emotions_rounded),
    ('מצביעים', 'מי לדעתכם הוא המתחזה?', Icons.how_to_vote_rounded),
    ('הזדמנות אחרונה', 'אם נתפס, המתחזה יכול לנחש את המילה ולנצח.', Icons.psychology_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'איך משחקים?',
      child: Column(
        children: [
          const Illustration('assets/illustrations/how-to-play.webp', height: 210),
          ...List.generate(steps.length, (index) {
            final step = steps[index];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.yellow,
                  foregroundColor: AppColors.night,
                  child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
                title: Text(step.$1, style: const TextStyle(fontWeight: FontWeight.w900)),
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

enum SystemStateType { noCategoryMatch, reconnecting, removed, stopped, joinError, serverError }

class SystemStateScreen extends StatelessWidget {
  const SystemStateScreen({required this.type, super.key});

  final SystemStateType type;

  @override
  Widget build(BuildContext context) {
    final data = switch (type) {
      SystemStateType.noCategoryMatch => (
          title: 'לא נמצא משחק מתאים',
          body: 'אפשר לבחור קטגוריות אחרות או לנסות שוב.',
          image: 'assets/illustrations/no-category-match.webp',
          action: 'בחירת קטגוריות מחדש',
        ),
      SystemStateType.reconnecting => (
          title: 'מתחברים מחדש',
          body: 'מנסים להחזיר אותך למשחק. ניתוק 2 מתוך 3.',
          image: 'assets/illustrations/connection-error.webp',
          action: 'המשך המתנה',
        ),
      SystemStateType.removed => (
          title: 'הוצאת מהמשחק',
          body: 'זה היה הניתוק השלישי ונרשם הפסד.',
          image: 'assets/illustrations/connection-error.webp',
          action: 'חזרה למסך הבית',
        ),
      SystemStateType.stopped => (
          title: 'המשחק הופסק',
          body: 'לא נשארו מספיק שחקנים כדי להמשיך.',
          image: 'assets/illustrations/connection-error.webp',
          action: 'חזרה למסך הבית',
        ),
      SystemStateType.joinError => (
          title: 'לא הצלחנו להצטרף',
          body: 'החדר לא נמצא או שאינו זמין כרגע.',
          image: 'assets/illustrations/private-room.webp',
          action: 'ניסיון נוסף',
        ),
      SystemStateType.serverError => (
          title: 'משהו השתבש',
          body: 'המשחק הופסק עקב תקלה בשרת. לא נרשם הפסד.',
          image: 'assets/illustrations/connection-error.webp',
          action: 'ניסיון נוסף',
        ),
    };

    return GameScaffold(
      title: data.title,
      timer: type == SystemStateType.reconnecting ? 30 : null,
      bottom: PrimaryButton(label: data.action, onPressed: () => Navigator.of(context).pop()),
      child: Column(
        children: [
          Illustration(data.image, height: 260),
          Text(data.title, style: Theme.of(context).textTheme.headlineLarge, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(data.body, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 17, height: 1.45)),
        ],
      ),
    );
  }
}
