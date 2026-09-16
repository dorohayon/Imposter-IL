import 'package:flutter/material.dart';

import '../state/game_session.dart';
import 'live_room.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';
import 'online_flow.dart';
import 'private_flow.dart';
import 'secondary_screens.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  /// Reopens the live screen when the server says the player is still in a
  /// room, search or game, for example after the app restarted mid-game.
  void _returnToActivity(BuildContext context) {
    bool shouldOpen() =>
        SessionScope.read(context).activity != 'none' &&
        (ModalRoute.of(context)?.isCurrent ?? false);
    if (!shouldOpen()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted && shouldOpen()) {
        _open(context, const LiveRoomScreen());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    SessionScope.of(context); // rebuild when the activity changes
    _returnToActivity(context);
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
                  onPressed: () => _open(context, const ProfileScreen()),
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
              'משחק חקירה חברתי בעברית',
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
              variant: ButtonVariant.secondary,
              onPressed: () => _open(context, const FriendsScreen()),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => _open(context, const HowToPlayScreen()),
              icon: const Icon(Icons.help_outline_rounded),
              label: const Text('איך משחקים?',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
