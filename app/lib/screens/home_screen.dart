import 'package:flutter/material.dart';

import '../monetization/ad_banner.dart';
import '../monetization/monetization.dart';
import '../monetization/monetization_config.dart';
import '../state/game_session.dart';
import 'live_room.dart';
import 'onboarding_screen.dart';
import '../theme/app_theme.dart';
import '../local/local_game.dart';
import '../local/local_screens.dart';
import '../local/local_setup_screens.dart';
import '../local/online_choice_screen.dart';
import '../local/local_store.dart';
import '../widgets/game_ui.dart';
import 'secondary_screens.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  LocalGame? _savedLocalGame;

  @override
  void initState() {
    super.initState();
    _loadSavedLocalGame();
    // Home is the first screen after the legal gate and onboarding, so the
    // ad consent form (UMP) never covers either of them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) MonetizationScope.read(context).startAds();
    });
  }

  Future<void> _loadSavedLocalGame() async {
    final saved = await LocalStore.load();
    if (saved?.phase == LocalPhase.ended) {
      await LocalStore.clear();
      if (mounted) setState(() => _savedLocalGame = null);
      return;
    }
    if (mounted) setState(() => _savedLocalGame = saved);
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _openOnline(
    BuildContext context,
    GameSession session,
  ) async {
    if (!session.signedIn) {
      final signedIn = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(builder: (_) => const OnboardingScreen()),
      );
      if (signedIn != true || !context.mounted) return;
    }
    _open(context, const OnlineChoiceScreen());
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
    final session = SessionScope.of(context);
    _returnToActivity(context);
    final page = DecoratedBox(
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
        // Only when there is a banner: an empty bottom bar would still take
        // the bottom inset away from the buttons.
        bottomNavigationBar: AdBanner.shows(context, BannerPlacement.home)
            ? const AdBanner(BannerPlacement.home)
            : null,
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
                            style: IconButton.styleFrom(
                              side: BorderSide(
                                color: AppColors.cream.withValues(alpha: .16),
                              ),
                            ),
                            onPressed: () =>
                                _open(context, const SettingsScreen()),
                            icon: const Icon(Icons.settings_rounded, size: 21),
                          ),
                          const Spacer(),
                          IconButton.filledTonal(
                            tooltip: 'פרופיל',
                            style: IconButton.styleFrom(
                              side: BorderSide(
                                color: AppColors.cream.withValues(alpha: .16),
                              ),
                            ),
                            onPressed: () => _open(
                              context,
                              session.signedIn
                                  ? const ProfileScreen()
                                  : const OnboardingScreen(),
                            ),
                            icon: const Icon(Icons.person_rounded, size: 21),
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
                        icon: Icons.language_rounded,
                        onPressed: () => _openOnline(context, session),
                      ),
                      const SizedBox(height: 12),
                      PrimaryButton(
                        label: 'משחק במכשיר אחד',
                        icon: Icons.smartphone_rounded,
                        variant: ButtonVariant.secondary,
                        onPressed: () =>
                            _open(context, const LocalPlayersScreen()),
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
    final saved = _savedLocalGame;
    if (saved == null) return page;
    return Stack(
      children: [
        page,
        const ModalBarrier(color: Color(0xB8090818), dismissible: false),
        SafeArea(
          minimum: const EdgeInsets.all(20),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: AppColors.cream,
              borderRadius: BorderRadius.circular(28),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'להמשיך את המשחק?',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(color: AppColors.night),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'סיבוב ${saved.round} נשמר במכשיר · ${saved.players.length} שחקנים',
                      style: const TextStyle(color: Color(0xFF625E70)),
                    ),
                    const SizedBox(height: 14),
                    PrimaryButton(
                      label: 'המשך משחק',
                      onPressed: () {
                        setState(() => _savedLocalGame = null);
                        _open(context, LocalGameScreen(resumed: saved));
                      },
                    ),
                    const SizedBox(height: 8),
                    PrimaryButton(
                      label: 'מחיקת המשחק',
                      variant: ButtonVariant.danger,
                      onPressed: () async {
                        await LocalStore.clear();
                        if (mounted) {
                          setState(() => _savedLocalGame = null);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
