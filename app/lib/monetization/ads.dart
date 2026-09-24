import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'monetization_config.dart';

/// The ad network. Tests use a fake; the app uses [AdMobAds].
///
/// Nothing here may block the player: every call returns promptly or runs in
/// the background, and a failure means no ad, never a stuck screen.
abstract interface class AdsGateway {
  /// Asks for consent where the law requires it (Google's UMP, which also
  /// runs Apple's tracking prompt when configured), then starts the SDK.
  /// Returns whether ads may be requested.
  Future<bool> start({required String maxAdContentRating});

  /// Whether the consent rules require a way to change the choice later.
  Future<bool> privacyOptionsRequired();

  Future<void> showPrivacyOptions();

  /// An anchored adaptive banner for the full screen width.
  Widget banner(String unitId);

  Future<void> loadInterstitial(String unitId);

  /// Shows the loaded interstitial and completes once it is closed. Completes
  /// with false at once when none is loaded, so the caller moves on.
  Future<bool> showInterstitial();
}

/// Google's test units: debug builds must never request live ads.
AdUnits testAdUnits(String platform) => platform == 'ios'
    ? const AdUnits(
        banner: 'ca-app-pub-3940256099942544/2435281174',
        interstitial: 'ca-app-pub-3940256099942544/4411468910',
      )
    : const AdUnits(
        banner: 'ca-app-pub-3940256099942544/9214589741',
        interstitial: 'ca-app-pub-3940256099942544/1033173712',
      );

class AdMobAds implements AdsGateway {
  InterstitialAd? _interstitial;
  bool _loadingInterstitial = false;

  @override
  Future<bool> start({required String maxAdContentRating}) async {
    final gathered = Completer<void>();
    void done([Object? _]) {
      if (!gathered.isCompleted) gathered.complete();
    }

    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => ConsentForm.loadAndShowConsentFormIfRequired(done),
      done,
    );
    await gathered.future;
    if (!await ConsentInformation.instance.canRequestAds()) return false;
    await MobileAds.instance.initialize();
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(maxAdContentRating: maxAdContentRating),
    );
    return true;
  }

  @override
  Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  @override
  Future<void> showPrivacyOptions() {
    final closed = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((_) => closed.complete());
    return closed.future;
  }

  @override
  Widget banner(String unitId) => _AdMobBanner(unitId: unitId);

  @override
  Future<void> loadInterstitial(String unitId) async {
    if (_interstitial != null || _loadingInterstitial) return;
    _loadingInterstitial = true;
    await InterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          _loadingInterstitial = false;
        },
        onAdFailedToLoad: (_) => _loadingInterstitial = false,
      ),
    );
  }

  @override
  Future<bool> showInterstitial() async {
    final ad = _interstitial;
    if (ad == null) return false;
    _interstitial = null;
    final closed = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete(false);
      },
    );
    try {
      await ad.show();
    } on Object {
      ad.dispose();
      return false;
    }
    return closed.future;
  }
}

class _AdMobBanner extends StatefulWidget {
  const _AdMobBanner({required this.unitId});

  final String unitId;

  @override
  State<_AdMobBanner> createState() => _AdMobBannerState();
}

class _AdMobBannerState extends State<_AdMobBanner> {
  BannerAd? _ad;
  AdSize? _size;
  bool _loaded = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load(MediaQuery.sizeOf(context).width.truncate());
  }

  Future<void> _load(int width) async {
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (!mounted || size == null) return;
    // The space is taken as soon as the size is known, before the ad
    // arrives, so the screen does not jump when it does.
    setState(() => _size = size);
    final ad = BannerAd(
      size: size,
      adUnitId: widget.unitId,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        // No ad leaves the reserved space empty; nothing else changes.
        onAdFailedToLoad: (ad, _) => ad.dispose(),
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = _size;
    return SizedBox(
      height: size?.height.toDouble() ?? 60,
      child: size != null && _loaded
          ? Center(
              child: SizedBox(
                width: size.width.toDouble(),
                height: size.height.toDouble(),
                child: AdWidget(ad: _ad!),
              ),
            )
          : null,
    );
  }
}
