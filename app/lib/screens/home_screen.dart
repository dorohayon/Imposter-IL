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
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -1.05),
          radius: 1.05,
          colors: [Color(0xFF2A2455), AppColors.night],
          stops: [0, .62],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 26),
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
              const SizedBox(height: 8),
              const Illustration('assets/illustrations/home-hero.webp',
                  height: 196),
              Text(
                'מי המתחזה?',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'משחק חקירה חברתי בעברית',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.yellow,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                label: 'משחק ברשת',
                onPressed: () =>
                    _open(context, const CategorySelectionScreen()),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'משחק עם חברים',
                variant: ButtonVariant.secondary,
                onPressed: () => _open(context, const FriendsScreen()),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                onPressed: () => _open(context, const HowToPlayScreen()),
                variant: ButtonVariant.quiet,
                label: 'איך משחקים?',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
