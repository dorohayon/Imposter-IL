import 'package:flutter/material.dart';

import 'data/server.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
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
        title: 'מי המתחזה?',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: session.signedIn ? const HomeScreen() : const OnboardingScreen(),
      ),
    );
  }
}
