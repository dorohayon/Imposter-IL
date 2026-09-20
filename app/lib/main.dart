import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/invite.dart';
import 'data/server.dart';
import 'screens/home_screen.dart';
import 'screens/private_flow.dart';
import 'screens/legal_screens.dart';
import 'screens/secondary_screens.dart';
import 'state/game_session.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = GameSession(ApiClient(defaultServerUrl()));
  await session.restore();
  runApp(ImposterApp(session: session));
}

class ImposterApp extends StatefulWidget {
  const ImposterApp({required this.session, super.key});

  final GameSession session;

  @override
  State<ImposterApp> createState() => _ImposterAppState();
}

class _ImposterAppState extends State<ImposterApp> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The link that launched the app, if it was launched by one.
    _openInvite(WidgetsBinding.instance.platformDispatcher.defaultRouteName);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A link that arrives while the app is already open. The platform delivers
  /// both this and the launch route as plain route strings, which is why no
  /// plugin is involved.
  @override
  Future<bool> didPushRouteInformation(RouteInformation info) async =>
      _openInvite(info.uri.toString());

  bool _openInvite(String? route) {
    final code = roomCodeFromLink(route);
    // Nothing is pushed over onboarding or the legal gate: a player id only
    // exists once both are behind us, so this cannot smuggle anyone past
    // consent. Without one the invitation page still shows the code to type.
    if (code == null || widget.session.playerId == null) return false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigator.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => JoinRoomScreen(code: code)),
      );
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      session: widget.session,
      child: MaterialApp(
        navigatorKey: _navigator,
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

/// Local play does not need a server identity, so Home is also the offline
/// entry point. Online/profile actions ask for onboarding when there is no
/// guest session yet.
class _Start extends StatelessWidget {
  const _Start();

  @override
  Widget build(BuildContext context) {
    SessionScope.of(context);
    return const HomeScreen();
  }
}
