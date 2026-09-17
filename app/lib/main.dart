import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/server.dart';
import 'screens/home_screen.dart';
import 'screens/legal_screens.dart';
import 'screens/onboarding_screen.dart';
import 'screens/secondary_screens.dart';
import 'state/game_session.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = GameSession(ApiClient(defaultServerUrl()));
  await session.restore();
  runApp(ImposterApp(session: session));
}

class ImposterApp extends StatelessWidget {
  const ImposterApp({required this.session, super.key});

  final GameSession session;

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      session: session,
      child: MaterialApp(
        // The trailing "?" is a neutral character, so in the LTR context of the
        // task switcher it would sit on the wrong side. \u200f (RLM) pins it.
        title: 'מי המתחזה?\u200f',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        // Hebrew everywhere: RTL layout and Hebrew text in built-in widgets.
        locale: const Locale('he'),
        supportedLocales: const [Locale('he')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // builder wraps the Navigator, so an unsupported build is covered
        // wherever the player happens to be — home is not enough, since
        // client_too_old can arrive while they are deep in a pushed route.
        builder: (context, child) => SessionScope.of(context).needsUpdate
            ? const UpdateRequiredScreen()
            : child!,
        // Legal acknowledgement is outside onboarding: no guest session and no
        // user-written nickname reaches the server before the current Terms are
        // accepted. Bumping legalVersion gates returning installs as well.
        home: const LegalGate(child: _Start()),
      ),
    );
  }
}

/// Picks the first screen, below [SessionScope] so it follows the session
/// rather than the state it had at launch.
class _Start extends StatelessWidget {
  const _Start();

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return session.signedIn ? const HomeScreen() : const OnboardingScreen();
  }
}
