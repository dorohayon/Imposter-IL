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
          // The design frame is a fixed 390x844 whose content reaches the
          // bottom. On a taller phone a plain list stacks everything at the
          // top and leaves the slack below, so the height is filled instead:
          // the header stays up, the buttons stay down, and the slack goes
          // around the hero. It still scrolls if the content does not fit.
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 26),
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(minHeight: constraints.maxHeight - 34),
                // Spacer needs a definite height, which a scroll view alone
                // does not give.
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        textDirection: TextDirection.ltr,
                        children: [
                          IconButton.filledTonal(
                            tooltip: 'הגדרות',
                            onPressed: () =>
                                _open(context, const SettingsScreen()),
                            icon: const Icon(Icons.settings_rounded),
                          ),
                          const Spacer(),
                          IconButton.filledTonal(
                            tooltip: 'פרופיל',
                            onPressed: () =>
                                _open(context, const ProfileScreen()),
                            icon: const Icon(Icons.person_rounded),
                          ),
                        ],
                      ),
                      const Spacer(),
                      const Illustration('assets/illustrations/home-hero.webp',
                          height: 196),
                      Text(
                        'מי המתחזה?',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.displayLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'כולם יודעים את המילה. חוץ מאחד.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.yellow,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
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
                        onPressed: () =>
                            _open(context, const HowToPlayScreen()),
                        variant: ButtonVariant.quiet,
                        label: 'איך משחקים?',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
