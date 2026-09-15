import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../demo/prototype_states_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';
import 'online_flow.dart';
import 'private_flow.dart';
import 'secondary_screens.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.nickname,
    required this.avatar,
    super.key,
  });

  final String nickname;
  final String avatar;

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Row(
              textDirection: TextDirection.ltr,
              children: [
                IconButton.filledTonal(
                  tooltip: 'הגדרות',
                  onPressed: () => _open(context, const SettingsScreen()),
                  icon: const Icon(Icons.settings_rounded),
                ),
                const Spacer(),
                IconButton.filledTonal(
                  tooltip: 'פרופיל',
                  onPressed: () => _open(
                    context,
                    ProfileScreen(nickname: nickname, avatar: avatar),
                  ),
                  icon: const Icon(Icons.person_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Illustration('assets/illustrations/home-hero.webp',
                height: 245),
            Text(
              'מי המתחזה?',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displayLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'מוצאים את החשוד לפני שהוא מגלה את המילה',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 17),
            ),
            const SizedBox(height: 26),
            PrimaryButton(
              label: 'משחק ברשת',
              onPressed: () => _open(context, const CategorySelectionScreen()),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'משחק עם חברים',
              secondary: true,
              onPressed: () => _open(context, const FriendsScreen()),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => _open(context, const HowToPlayScreen()),
              icon: const Icon(Icons.help_outline_rounded),
              label: const Text('איך משחקים?',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            if (kDebugMode)
              TextButton(
                onPressed: () => _open(context, const PrototypeStatesScreen()),
                child: const Text('מצבי Prototype (debug)'),
              ),
          ],
        ),
      ),
    );
  }
}
