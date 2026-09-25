import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/invite.dart';
import 'data/server.dart';
import 'monetization/ads.dart';
import 'monetization/monetization.dart';
import 'monetization/store.dart';
import 'screens/home_screen.dart';
import 'screens/private_flow.dart';
import 'screens/legal_screens.dart';
import 'screens/secondary_screens.dart';
import 'state/game_session.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient(defaultServerUrl());
  final session = GameSession(api);
  final monetization =
      Monetization(store: PluginStore(), ads: AdMobAds(), api: api);
  await session.restore();
  await monetization.start();
  monetization.attach(session);
  runApp(ImposterApp(session: session, monetization: monetization));
}

class ImposterApp extends StatefulWidget {
  const ImposterApp({
    required this.session,
    required this.monetization,
    super.key,
  });

  final GameSession session;
  final Monetization monetization;

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
  /// Back in the foreground, the store may have renewed, refunded or
  /// expired something meanwhile.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.monetization.resumed();
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation info) async =>
      _openInvite(info.uri.toString());

  /// An invitation that arrived while new Terms were still to be accepted.
  String? _pendingInvite;

  void _joinRoom(String code) => _navigator.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => JoinRoomScreen(code: code)),
      );

  void _openPendingInvite() {
    final code = _pendingInvite;
    _pendingInvite = null;
    if (code != null) _joinRoom(code);
  }

  bool _openInvite(String? route) {
    final code = roomCodeFromLink(route);
    // Nothing is pushed over onboarding or the legal gate: a player id only
    // exists once both are behind us, so this cannot smuggle anyone past
    // consent. Without one the invitation page still shows the code to type.
    if (code == null || widget.session.playerId == null) return false;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // A returning player has an id but may still owe the re-acceptance of
      // new Terms; the gate is below this route, so check it here too, and
      // keep the invitation for when they accept.
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(legalAcceptedVersionKey) != legalVersion) {
        _pendingInvite = code;
        return;
      }
      _joinRoom(code);
    });
    // A warm link arrives with no frame pending; without one the push waits
    // for whatever next repaints the screen.
    WidgetsBinding.instance.scheduleFrame();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return MonetizationScope(
      monetization: widget.monetization,
      child: SessionScope(
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
          home:
              LegalGate(onAccepted: _openPendingInvite, child: const _Start()),
        ),
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
