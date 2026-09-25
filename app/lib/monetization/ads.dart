import 'dart:async';

import 'package:flutter/foundation.dart';
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

/// Ad diagnostics, in debug builds and TEST_ADS tester builds only. Unit ids,
/// platform and SDK codes and messages; never anything about the player.
void adsLog(String message) {
  if (kDebugMode || const bool.fromEnvironment('TEST_ADS')) {
    debugPrint('[ads] $message');
  }
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
      () {
        adsLog('consent info updated');
        ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (error != null) {
            adsLog('consent form error ${error.errorCode}: ${error.message}');
          }
          done();
        });
      },
      (error) {
        // canRequestAds below still honours consent from an earlier session.
        adsLog('consent info update failed '
            '${error.errorCode}: ${error.message}');
        done();
      },
    );
    await gathered.future;
    final canRequest = await ConsentInformation.instance.canRequestAds();
    adsLog('canRequestAds: $canRequest');
    if (!canRequest) return false;
    // Request settings first, so no ad is ever requested without them.
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(maxAdContentRating: maxAdContentRating),
    );
    final status = await MobileAds.instance.initialize();
    adsLog('MobileAds initialized: ${status.adapterStatuses.entries.map(
          (e) => '${e.key}=${e.value.state.name}',
        ).join(', ')}');
    return true;
  }

  @override
  Future<bool> privacyOptionsRequired() async {
    final status =
        await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
    adsLog('privacy options: ${status.name}');
    return status == PrivacyOptionsRequirementStatus.required;
  }

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
          adsLog('interstitial loaded ($unitId)');
          _interstitial = ad;
          _loadingInterstitial = false;
        },
        onAdFailedToLoad: (error) {
          adsLog('interstitial failed to load ($unitId): ${_describe(error)}');
          _loadingInterstitial = false;
        },
      ),
    );
  }

  @override
  Future<bool> showInterstitial() async {
    final ad = _interstitial;
    if (ad == null) {
      adsLog('interstitial not shown: none loaded');
      return false;
    }
    _interstitial = null;
    final closed = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => adsLog('interstitial shown'),
      onAdDismissedFullScreenContent: (ad) {
        adsLog('interstitial dismissed');
        ad.dispose();
        if (!closed.isCompleted) closed.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        adsLog('interstitial failed to show ${error.code}: ${error.message}');
        ad.dispose();
        if (!closed.isCompleted) closed.complete(false);
      },
    );
    try {
      await ad.show();
    } on Object catch (e) {
      adsLog('interstitial show threw: $e');
      ad.dispose();
      return false;
    }
    return closed.future;
  }
}

String _describe(LoadAdError error) => '${error.code} ${error.domain}: '
    '${error.message} (response ${error.responseInfo?.responseId})';

class _AdMobBanner extends StatefulWidget {
  const _AdMobBanner({required this.unitId});

  final String unitId;

  @override
  State<_AdMobBanner> createState() => _AdMobBannerState();
}

class _AdMobBannerState extends State<_AdMobBanner> {
  /// A failed banner tries again after these, then gives up for this screen:
  /// no fill and a dropped connection are usually short-lived.
  static const _retryDelays = [
    Duration(seconds: 15),
    Duration(seconds: 45),
    Duration(minutes: 2),
  ];

  BannerAd? _ad;
  AdSize? _size;
  bool _loaded = false;
  bool _started = false;
  int _failures = 0;
  Timer? _retry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load(MediaQuery.sizeOf(context).width.truncate());
  }

  Future<void> _load(int width) async {
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (!mounted) return;
    if (size == null) {
      adsLog('banner: no adaptive size for width $width');
      return;
    }
    // The space is taken as soon as the size is known, before the ad
    // arrives, so the screen does not jump when it does.
    setState(() => _size = size);
    final ad = BannerAd(
      size: size,
      adUnitId: widget.unitId,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          adsLog('banner loaded (${widget.unitId}) '
              '${size.width}x${size.height}');
          if (mounted) setState(() => _loaded = true);
        },
        // The reserved space stays empty meanwhile; nothing else changes.
        onAdFailedToLoad: (ad, error) {
          adsLog('banner failed to load (${widget.unitId}): '
              '${_describe(error)}');
          ad.dispose();
          if (!mounted) return;
          _ad = null;
          if (_failures < _retryDelays.length) {
            _retry = Timer(_retryDelays[_failures++], () {
              if (mounted) _load(width);
            });
          }
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _retry?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = _size;
    return SizedBox(
      height: size?.height.toDouble() ?? 60,
      child: size != null && _loaded && _ad != null
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
