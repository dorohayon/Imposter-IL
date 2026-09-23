import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/server.dart';
import '../state/game_session.dart';
import 'ads.dart';
import 'monetization_config.dart';
import 'store.dart';

/// Where the purchase popup is (design P01–P12).
enum PurchaseStep {
  choose,
  processing,
  pending,
  cancelled,
  failed,
  restoring,
  restoreNone,
  restoreFailed,
  restoredOther,
  purchased,
  restored,
}

enum RestoreResult { found, none, failed }

/// Categories, Premium and ads (docs/monetization.md).
///
/// The store is the source of truth for what this device owns: at launch and
/// on every resume the app asks it again, silently, and replaces what it had.
/// That is how refunds, lapsed and cancelled subscriptions reach the app. The
/// last answer is kept on the device, so offline play keeps what was paid for.
/// The same proofs go to the server, which enforces the online side.
class Monetization extends ChangeNotifier {
  Monetization({
    required this.store,
    required this.ads,
    required this.api,
    DateTime Function()? clock,
    this.useTestAds = !kReleaseMode,
    this.settle = const Duration(milliseconds: 400),
  }) : _clock = clock ?? DateTime.now;

  final StoreGateway store;
  final AdsGateway ads;
  final ApiClient api;

  /// Debug builds always request Google's test ads.
  final bool useTestAds;

  /// How long to wait after a restore for its purchases to arrive: the plugin
  /// delivers them on the purchase stream, not as the call's result.
  final Duration settle;
  final DateTime Function() _clock;

  static const _configKey = 'monetization.config';
  static const _categoriesKey = 'monetization.categories';
  static const _lifetimeKey = 'monetization.lifetime';
  static const _premiumUntilKey = 'monetization.premiumUntil';
  static const _interstitialKey = 'monetization.lastInterstitial';

  /// A subscription the store says is current but did not date (Play) stays
  /// open this long offline, until the next answer from the store.
  static const undatedGrace = Duration(days: 7);

  MonetizationConfig config = const MonetizationConfig();
  Set<String> ownedCategories = {};
  bool lifetime = false;

  /// When monthly Premium lapses on this device, or null without one.
  DateTime? premiumUntil;

  Map<String, StoreProduct> products = const {};
  bool productsLoading = false;
  bool productsFailed = false;

  bool adsReady = false;
  bool privacyOptionsRequired = false;
  DateTime? _lastInterstitial;
  bool _adsStarting = false;

  /// Home has been reached, so ads may start as soon as they can: the config
  /// with the unit ids may arrive later, or Premium may lapse.
  bool _adsWanted = false;

  PurchaseStep step = PurchaseStep.choose;
  String? _flowProduct;

  /// The product the popup is buying or just bought.
  String? get flowProduct => _flowProduct;

  /// What the premium success screen says about a subscription the player
  /// still pays for after buying lifetime.
  bool monthlyBeforePurchase = false;

  /// The latest purchase the store reported for each product this device
  /// owns: the proofs the server verifies.
  final _proofs = <String, StorePurchase>{};
  Map<String, StorePurchase>? _collecting;
  Future<bool>? _refreshing;
  StreamSubscription<List<StorePurchase>>? _purchases;

  String? Function()? _token;
  String? _attachedToken;
  String? _syncedToken;
  bool _proofsChanged = false;
  Future<void> _syncChain = Future.value();
  Future<void>? _queuedSync;
  bool _queuedForce = false;
  bool _disposed = false;

  DateTime get now => _clock();

  /// Premium: every category, the Premium features and no ads.
  bool get premium => lifetime || monthlyActive;
  bool get monthlyActive => premiumUntil?.isAfter(now) ?? false;

  bool isFree(String categoryId) => config.freeCategoryIds.contains(categoryId);

  bool isUnlocked(String categoryId) =>
      premium || isFree(categoryId) || ownedCategories.contains(categoryId);

  /// Bought on its own, for the "נרכשה" tag. Premium makes that moot.
  bool isPurchased(String categoryId) =>
      !premium && !isFree(categoryId) && ownedCategories.contains(categoryId);

  List<String> unlocked(Iterable<String> categoryIds) => [
        for (final id in categoryIds)
          if (isUnlocked(id)) id
      ];

  // ---- lifecycle -----------------------------------------------------------

  /// Reads the device's last answer, then asks the server and the store in
  /// the background. Nothing here waits on the network.
  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_configKey);
    if (cached != null) {
      try {
        config = MonetizationConfig.fromJson(
            jsonDecode(cached) as Map<String, dynamic>);
      } on Object {
        await prefs.remove(_configKey);
      }
    }
    ownedCategories = (prefs.getStringList(_categoriesKey) ?? const []).toSet();
    lifetime = prefs.getBool(_lifetimeKey) ?? false;
    premiumUntil = DateTime.tryParse(prefs.getString(_premiumUntilKey) ?? '');
    _lastInterstitial =
        DateTime.tryParse(prefs.getString(_interstitialKey) ?? '');
    _purchases = store.purchases.listen(_onPurchases);
    _notify();
    unawaited(_loadConfig());
    unawaited(refresh());
  }

  /// The app came back to the foreground: a renewal, refund or remote change
  /// may have happened meanwhile.
  void resumed() {
    unawaited(_loadConfig());
    unawaited(refresh());
  }

  /// Sends proofs whenever the session's token changes (a new or replaced
  /// guest session), and lets the session re-sync when the server says a
  /// category is locked.
  void attach(GameSession session) {
    _token = () => session.token;
    session.resyncEntitlements = () => syncServer(force: true);
    void tokenChanged() {
      if (session.token == _attachedToken) return;
      _attachedToken = session.token;
      // A store answer on its way syncs by itself once it lands.
      if (_attachedToken != null && _refreshing == null) {
        unawaited(syncServer(force: true));
      }
    }

    session.addListener(tokenChanged);
    tokenChanged();
  }

  Future<void> _loadConfig() async {
    try {
      final json = await api.request('GET', '/v1/config');
      final raw = json['monetization'] as Map<String, dynamic>;
      config = MonetizationConfig.fromJson(raw);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_configKey, jsonEncode(config.toJson()));
      _notify();
      if (_adsWanted) unawaited(startAds());
      _preloadInterstitial();
    } on Object {
      // The cached or built-in model stays; nothing is blocked on this.
    }
  }

  // ---- entitlements ------------------------------------------------------

  /// Asks the store what this account owns now. Returns whether it answered;
  /// when it did not (offline, signed out of the store), the device keeps its
  /// last answer.
  Future<bool> refresh() => _refreshing ??= _refresh().whenComplete(() {
        _refreshing = null;
      });

  Future<bool> _refresh() async {
    try {
      if (!await store.isAvailable()) return false;
      final found = _collecting = {};
      await store.restore();
      // Zero (tests) still lets the stream deliver: it is a microtask away.
      await (settle > Duration.zero
          ? Future<void>.delayed(settle)
          : Future<void>.value());
      _collecting = null;
      _replaceWith(found);
      return true;
    } on Object {
      _collecting = null;
      return false;
    }
  }

  void _onPurchases(List<StorePurchase> list) {
    for (final p in list) {
      final inFlow = p.productId == _flowProduct &&
          (step == PurchaseStep.processing || step == PurchaseStep.pending);
      switch (p.status) {
        case StoreStatus.purchased || StoreStatus.restored:
          _collecting?[p.productId] = p;
          // A new purchase, or a renewal the store delivered by itself.
          _grant(p);
          if (inFlow) step = PurchaseStep.purchased;
        case StoreStatus.pending:
          // Ask to Buy or a slow payment method: nothing opens until paid.
          if (inFlow) step = PurchaseStep.pending;
        case StoreStatus.canceled:
          if (inFlow) step = PurchaseStep.cancelled;
        case StoreStatus.error:
          if (inFlow) step = PurchaseStep.failed;
      }
      // Delivered locally before acknowledging: Play refunds a purchase not
      // acknowledged in three days, so this cannot wait on our server.
      if (p.status != StoreStatus.pending) {
        unawaited(store.complete(p).catchError((Object _) {}));
      }
    }
    unawaited(_persist());
    _notify();
    unawaited(syncServer());
  }

  void _grant(StorePurchase p) {
    _proofs[p.productId] = p;
    _proofsChanged = true;
    if (p.productId == config.premiumLifetime) {
      lifetime = true;
    } else if (p.productId == config.premiumMonthly) {
      final until = _currentUntil(p);
      if (premiumUntil == null || until.isAfter(premiumUntil!)) {
        premiumUntil = until;
      }
    } else if (config.categoryOf(p.productId) case final id?) {
      ownedCategories = {...ownedCategories, id};
    }
  }

  /// Everything the store listed, and nothing else: a refunded category or a
  /// lapsed subscription is simply no longer there.
  void _replaceWith(Map<String, StorePurchase> found) {
    _proofs
      ..clear()
      ..addAll(found);
    _proofsChanged = true;
    ownedCategories = {
      for (final id in found.keys)
        if (config.categoryOf(id) case final category?) category,
    };
    lifetime = found.containsKey(config.premiumLifetime);
    final monthly = found[config.premiumMonthly];
    premiumUntil = monthly == null ? null : _currentUntil(monthly);
    unawaited(_persist());
    _notify();
    unawaited(syncServer());
    if (_adsWanted) unawaited(startAds());
  }

  /// A subscription the store lists as current is open now. StoreKit dates it
  /// in the signed transaction; a date already past (billing grace) or no
  /// date at all (Play) keeps it open for [undatedGrace].
  DateTime _currentUntil(StorePurchase p) {
    final expires = _jwsExpiry(p.verificationData);
    return expires != null && expires.isAfter(now)
        ? expires
        : now.add(undatedGrace);
  }

  /// StoreKit already verified the transaction on the device; this only
  /// reads the period's end. The server does the verifying.
  static DateTime? _jwsExpiry(String jws) {
    final parts = jws.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      final ms = payload['expiresDate'];
      return ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    } on Object {
      return null;
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_categoriesKey, ownedCategories.toList());
    await prefs.setBool(_lifetimeKey, lifetime);
    final until = premiumUntil;
    if (until == null) {
      await prefs.remove(_premiumUntilKey);
    } else {
      await prefs.setString(_premiumUntilKey, until.toIso8601String());
    }
  }

  /// Sends the store's proofs to the server, which checks them with Apple or
  /// Google and enforces categories online. Failing is harmless: the server
  /// only refuses a locked category when enforcement is on, and the session
  /// re-syncs then.
  ///
  /// One request at a time, and at most one waiting behind it: calls made
  /// meanwhile join the waiting one, which reads the proofs when it starts,
  /// so it sends whatever changed.
  Future<void> syncServer({bool force = false}) {
    _queuedForce = _queuedForce || force;
    return _queuedSync ??= _syncChain = _syncChain.then((_) {
      final forced = _queuedForce;
      _queuedSync = null;
      _queuedForce = false;
      return _sync(forced);
    });
  }

  Future<void> _sync(bool force) async {
    final token = _token?.call();
    if (token == null) return;
    if (!force && token == _syncedToken && !_proofsChanged) return;
    final sentChanges = _proofsChanged;
    _proofsChanged = false;
    try {
      final json = await api.request(
        'POST',
        '/v1/entitlements',
        token: token,
        body: {
          'purchases': [
            for (final p in _proofs.values)
              {
                'platform': store.platform,
                'productId': p.productId,
                'verificationData': p.verificationData,
              },
          ],
        },
      );
      _syncedToken = token;
      // Play gives the app no expiry; the server's check does.
      final ent = json['entitlements'] as Map<String, dynamic>? ?? const {};
      final until = DateTime.tryParse(ent['premiumUntil'] as String? ?? '');
      if (until != null && _proofs.containsKey(config.premiumMonthly)) {
        premiumUntil = until;
        unawaited(_persist());
        _notify();
      }
    } on Object {
      _proofsChanged = _proofsChanged || sentChanges;
    }
  }

  // ---- the purchase popup ----------------------------------------------

  bool get busy =>
      step == PurchaseStep.processing || step == PurchaseStep.restoring;

  /// The three products the popup offers for [categoryId].
  List<String> offerFor(String categoryId) => [
        config.categoryProduct(categoryId),
        config.premiumMonthly,
        config.premiumLifetime,
      ];

  void openPopup() {
    step = PurchaseStep.choose;
    _flowProduct = null;
    monthlyBeforePurchase = monthlyActive;
  }

  Future<void> loadProducts(String categoryId) async {
    final ids = offerFor(categoryId).toSet();
    if (ids.every(products.containsKey)) return;
    productsLoading = true;
    productsFailed = false;
    _notify();
    try {
      if (!await store.isAvailable()) throw StateError('store unavailable');
      products = {...products, ...await store.products(ids)};
      productsFailed = !ids.any(products.containsKey);
    } on Object {
      productsFailed = true;
    } finally {
      productsLoading = false;
      _notify();
    }
  }

  Future<void> buy(String productId) async {
    if (busy || !config.purchasesEnabled) return;
    _flowProduct = productId;
    monthlyBeforePurchase = monthlyActive;
    step = PurchaseStep.processing;
    _notify();
    bool started;
    try {
      started = await store.buy(productId);
    } on Object {
      started = false;
    }
    if (!started && step == PurchaseStep.processing) {
      step = PurchaseStep.failed;
      _notify();
    }
  }

  /// Restore from the popup: the result depends on whether the category the
  /// player tapped came back (P10–P12).
  Future<void> restoreFor(String categoryId) async {
    if (busy) return;
    step = PurchaseStep.restoring;
    _notify();
    final answered = await refresh();
    step = !answered
        ? PurchaseStep.restoreFailed
        : isUnlocked(categoryId)
            ? PurchaseStep.restored
            : _proofs.isEmpty
                ? PurchaseStep.restoreNone
                : PurchaseStep.restoredOther;
    _notify();
  }

  /// Restore from Settings.
  Future<RestoreResult> restoreAll() async {
    if (!await refresh()) return RestoreResult.failed;
    return _proofs.isEmpty ? RestoreResult.none : RestoreResult.found;
  }

  /// Leaves a notice step for the plain choice, once the player picks again.
  void backToChoice() {
    if (busy) return;
    step = PurchaseStep.choose;
    _notify();
  }

  // ---- ads -----------------------------------------------------------------

  /// Free players, and players who bought single categories, see ads.
  bool get showsAds => !premium && config.adsEnabled;

  AdUnits? get _units =>
      useTestAds ? testAdUnits(store.platform) : config.units[store.platform];

  /// The banner unit for a screen, or null when that screen shows none.
  String? bannerUnit(String placement) {
    if (!showsAds || !config.bannerPlacements.contains(placement)) return null;
    final unit = _units?.banner ?? '';
    return unit.isEmpty ? null : unit;
  }

  /// Consent, then the SDK. Started from the home screen, so the consent
  /// form never covers the legal gate or onboarding.
  Future<void> startAds() async {
    _adsWanted = true;
    final units = _units;
    if (_adsStarting || adsReady || !showsAds || units == null) return;
    if (units.banner.isEmpty && units.interstitial.isEmpty) return;
    _adsStarting = true;
    try {
      adsReady = await ads.start(maxAdContentRating: config.maxAdContentRating);
      privacyOptionsRequired = await ads.privacyOptionsRequired();
      _notify();
      _preloadInterstitial();
    } on Object {
      adsReady = false;
    } finally {
      _adsStarting = false;
    }
  }

  void _preloadInterstitial() {
    if (!adsReady || !showsAds || !config.interstitialEnabled) return;
    final unit = _units?.interstitial ?? '';
    if (unit.isEmpty) return;
    unawaited(ads.loadInterstitial(unit).catchError((Object _) {}));
  }

  /// Called once a finished match's full result has been seen and the player
  /// chose to go on. Shows an interstitial and completes when it closes — or
  /// at once, for Premium, without a loaded ad, or inside the interval.
  Future<void> afterCompletedMatch() async {
    if (!adsReady || !showsAds || !config.interstitialEnabled) return;
    final last = _lastInterstitial;
    if (last != null && now.difference(last) < config.interstitialMinInterval) {
      return;
    }
    var shown = false;
    try {
      shown = await ads.showInterstitial();
    } on Object {
      shown = false;
    }
    if (shown) {
      _lastInterstitial = now;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_interstitialKey, now.toIso8601String());
    }
    _preloadInterstitial();
  }

  Future<void> showPrivacyOptions() async {
    try {
      await ads.showPrivacyOptions();
    } on Object {
      // Nothing to change if the form cannot open.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_purchases?.cancel());
    super.dispose();
  }
}

class MonetizationScope extends InheritedNotifier<Monetization> {
  const MonetizationScope({
    required Monetization monetization,
    required super.child,
    super.key,
  }) : super(notifier: monetization);

  static Monetization of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<MonetizationScope>()!
      .notifier!;

  /// For screens that also run outside the app shell (tests pump the
  /// one-device match on its own).
  static Monetization? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MonetizationScope>()?.notifier;

  /// [maybeOf] for callbacks, without rebuilding.
  static Monetization? maybeRead(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MonetizationScope>()?.notifier;

  /// Without rebuilding, for callbacks.
  static Monetization read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MonetizationScope>()!.notifier!;
}
