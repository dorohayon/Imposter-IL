import 'package:flutter/material.dart';

import 'crash_reporting.dart';
import 'data/invite.dart';
import 'data/server.dart';
import 'l10n/l10n.dart';
import 'monetization/ads.dart';
import 'monetization/monetization.dart';
import 'monetization/store.dart';
import 'screens/home_screen.dart';
import 'screens/private_flow.dart';
import 'screens/secondary_screens.dart';
import 'state/game_session.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await startCrashReporting();
  logInfo('app', 'start: build $clientBuild, ${defaultServerUrl().host}');
  final api = ApiClient(defaultServerUrl());
  final session = GameSession(api);
  final monetization =
      Monetization(store: PluginStore(), ads: AdMobAds(), api: api);
  await session.restore(
    phoneLocales: WidgetsBinding.instance.platformDispatcher.locales,
  );
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
    // Launched straight into the background: no change will arrive to say so,
    // and the connection opened while the session was restored.
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
      widget.session.setBackground(true);
    }
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
    logDebug('app', state.name);
    if (state == AppLifecycleState.paused) widget.session.setBackground(true);
    if (state == AppLifecycleState.resumed) {
      widget.session.setBackground(false);
      widget.monetization.resumed();
    }
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation info) async =>
      _openInvite(info.uri.toString());

  void _joinRoom(String code) => _navigator.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => JoinRoomScreen(code: code)),
      );

  bool _openInvite(String? route) {
    final code = roomCodeFromLink(route);
    if (code != null) logInfo('app', 'invite link');
    // Nothing is pushed over onboarding: a player id only exists once it is
    // behind us, and with it the Terms agreed there. Without one the
    // invitation page still shows the code to type.
    if (code == null || widget.session.playerId == null) return false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _joinRoom(code));
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
        child: ValueListenableBuilder(
          valueListenable: widget.session.languageChoice,
          builder: (context, languageChoice, _) => MaterialApp(
            navigatorKey: _navigator,
            navigatorObservers: [_ScreenLog()],
            // In Hebrew the trailing "?" is a neutral character, so in the LTR
            // task switcher it would sit on the wrong side; app_he.arb pins it
            // with \u200f (RLM).
            onGenerateTitle: (context) => context.l10n.appTitle,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark,
            // The phone's language, or the one chosen in Settings; a language
            // the app does not have yet falls back to English
            // (docs/localization.md). Layout direction follows it.
            locale: switch (languageChoice) {
              final code? => Locale(code),
              null => null,
            },
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            localeListResolutionCallback: (locales, _) =>
                resolveLocale(locales),
            // builder wraps the Navigator, so an unsupported build is covered
            // wherever the player happens to be — home is not enough, since
            // client_too_old can arrive while they are deep in a pushed route.
            builder: (context, child) {
              final session = SessionScope.of(context);
              currentL10n = context.l10n;
              session.languageResolved(
                  Localizations.localeOf(context).languageCode);
              return session.needsUpdate
                  ? const UpdateRequiredScreen()
                  : child!;
            },
            home: const _Start(),
          ),
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

/// Logs every screen opened and closed, so a report shows where the player
/// was. Routes carry no names, so a page is named after its screen widget.
class _ScreenLog extends NavigatorObserver {
  // ponytail: builds the page's widget a second time to read its type; every
  // builder only constructs a widget. Give routes RouteSettings names if one
  // ever does more.
  String _name(Route<dynamic>? route) => switch (route) {
        null => 'none',
        Route(settings: RouteSettings(name: final name?)) => name,
        final MaterialPageRoute<dynamic> page =>
          '${page.builder(navigator!.context).runtimeType}',
        _ => '${route.runtimeType}',
      };

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      logInfo('nav', 'open ${_name(route)}');

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      logInfo('nav', 'close ${_name(route)} -> ${_name(previousRoute)}');

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      logInfo('nav', 'remove ${_name(route)}');

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      logInfo('nav', 'replace ${_name(oldRoute)} -> ${_name(newRoute)}');
}
