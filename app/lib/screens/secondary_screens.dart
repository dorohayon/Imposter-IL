import 'package:flutter/material.dart';

import '../demo/demo_countdown.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';
import 'online_flow.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen(
      {required this.nickname, required this.avatar, super.key});

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
          // Disabled until editing and saving the identity are implemented.
          const TextButton(onPressed: null, child: Text('עריכת פרטים — בקרוב')),
          const SizedBox(height: 24),
          Row(
            children: const [
              Expanded(
                  child: _StatCard(
                      value: '0',
                      label: 'ניצחונות',
                      color: AppColors.turquoise)),
              SizedBox(width: 12),
              Expanded(
                  child: _StatCard(
                      value: '0', label: 'הפסדים', color: AppColors.coral)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.value, required this.label, required this.color});

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
            Text(value,
                style: TextStyle(
                    fontSize: 40, fontWeight: FontWeight.w900, color: color)),
            Text(label,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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

typedef _Action = ({String label, VoidCallback onPressed});

/// System states that only the server can trigger. Until the client is
/// connected they are opened from the debug-only prototype states list.
/// The join error is shown inline on [JoinRoomScreen] (screen 23).
enum SystemStateType {
  noCategoryMatch,
  reconnecting,
  removed,
  stopped,
  serverError
}

class SystemStateScreen extends StatelessWidget {
  const SystemStateScreen({required this.type, super.key});

  final SystemStateType type;

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.of(context);
    void home() => navigator.popUntil((route) => route.isFirst);
    void replace(Widget screen) => navigator.pushReplacement(
          MaterialPageRoute<void>(builder: (_) => screen),
        );

    final ({
      String title,
      String body,
      String image,
      _Action? primary,
      _Action? secondary,
    }) data = switch (type) {
      SystemStateType.noCategoryMatch => (
          title: 'לא נמצא משחק מתאים',
          body: 'אפשר לבחור קטגוריות אחרות או לנסות שוב.',
          image: 'assets/illustrations/no-category-match.webp',
          primary: (
            label: 'בחירת קטגוריות מחדש',
            onPressed: () => replace(const CategorySelectionScreen()),
          ),
          secondary: (
            label: 'ניסיון נוסף',
            onPressed: () => replace(const MatchmakingScreen()),
          ),
        ),
      SystemStateType.reconnecting => (
          title: 'מתחברים מחדש',
          body: 'מנסים להחזיר אותך למשחק. ניתוק 2 מתוך 3.',
          image: 'assets/illustrations/connection-error.webp',
          primary: null,
          secondary: null,
        ),
      SystemStateType.removed => (
          title: 'הוצאת מהמשחק',
          body: 'זה היה הניתוק השלישי ונרשם הפסד.',
          image: 'assets/illustrations/connection-error.webp',
          primary: (label: 'חזרה למסך הבית', onPressed: home),
          secondary: null,
        ),
      SystemStateType.stopped => (
          title: 'המשחק הופסק',
          body: 'לא נשארו מספיק שחקנים כדי להמשיך.',
          image: 'assets/illustrations/connection-error.webp',
          primary: (label: 'חזרה למסך הבית', onPressed: home),
          secondary: null,
        ),
      SystemStateType.serverError => (
          title: 'משהו השתבש',
          body: 'המשחק הופסק עקב תקלה בחיבור לשרת. לא נרשם הפסד.',
          image: 'assets/illustrations/connection-error.webp',
          // Demo: retrying just closes the error.
          primary: (label: 'ניסיון נוסף', onPressed: () => navigator.pop()),
          secondary: (label: 'חזרה למסך הבית', onPressed: home),
        ),
    };
    final primary = data.primary;
    final secondary = data.secondary;

    return GameScaffold(
      title: data.title,
      timer: type == SystemStateType.reconnecting
          // Demo: the reconnect succeeds when the countdown ends.
          ? DemoCountdown(seconds: 30, onDone: () => navigator.pop())
          : null,
      onExit: type == SystemStateType.reconnecting ? home : null,
      showBack: false,
      bottom: primary == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PrimaryButton(
                  label: primary.label,
                  onPressed: primary.onPressed,
                ),
                if (secondary != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: secondary.onPressed,
                    child: Text(secondary.label),
                  ),
                ],
              ],
            ),
      child: Column(
        children: [
          Illustration(data.image, height: 260),
          Text(
            data.title,
            style: Theme.of(context).textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            data.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 17,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
