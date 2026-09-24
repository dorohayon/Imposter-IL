import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:imposter_il/data/server.dart';
import 'package:imposter_il/monetization/ads.dart';
import 'package:imposter_il/monetization/monetization.dart';
import 'package:imposter_il/monetization/store.dart';

const lifetime = 'premium_lifetime';
const monthly = 'premium_monthly';

/// The App Store / Play stand-in. [owned] is what the store account holds;
/// a restore replays it, a successful buy adds to it.
class FakeStore implements StoreGateway {
  FakeStore({Set<String> owned = const {}, this.platform = 'android'})
      : owned = {...owned};

  @override
  final String platform;
  Set<String> owned;
  bool available = true;
  bool restoreFails = false;
  bool productsFail = false;

  /// What the next buy reports; null leaves the purchase hanging.
  StoreStatus? outcome = StoreStatus.purchased;
  bool refuseBuy = false;

  /// Verification data per product, for example a StoreKit JWS.
  final proofs = <String, String>{};
  final prices = <String, String>{
    for (final id in ['sports', 'professions', 'objects', 'food'])
      'category_$id': '9.90 ₪',
    monthly: '14.90 ₪',
    lifetime: '59.90 ₪',
  };
  final bought = <String>[];
  final completed = <String>[];
  var restores = 0;

  final _updates = StreamController<List<StorePurchase>>.broadcast();

  @override
  Stream<List<StorePurchase>> get purchases => _updates.stream;

  StorePurchase purchase(String id, StoreStatus status) => StorePurchase(
        productId: id,
        status: status,
        verificationData: proofs[id] ?? 'token-$id',
      );

  void emit(List<StorePurchase> list) => _updates.add(list);

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<Map<String, StoreProduct>> products(Set<String> ids) async {
    if (productsFail) throw StateError('offline');
    return {
      for (final id in ids)
        if (prices[id] case final price?)
          id: StoreProduct(id: id, price: price),
    };
  }

  @override
  Future<bool> buy(String productId) async {
    bought.add(productId);
    if (refuseBuy) return false;
    final status = outcome;
    if (status != null) {
      scheduleMicrotask(() {
        if (status == StoreStatus.purchased) owned.add(productId);
        emit([purchase(productId, status)]);
      });
    }
    return true;
  }

  @override
  Future<void> restore() async {
    restores++;
    if (restoreFails) throw StateError('offline');
    emit([for (final id in owned) purchase(id, StoreStatus.restored)]);
  }

  @override
  Future<void> complete(StorePurchase purchase) async =>
      completed.add(purchase.productId);
}

class FakeAds implements AdsGateway {
  bool canRequest = true;
  bool privacyRequired = false;
  bool loaded = false;
  bool showThrows = false;
  int started = 0;
  int shown = 0;
  final loads = <String>[];

  /// Set to hold the interstitial open until [close] is called.
  Completer<bool>? open;
  bool holdOpen = false;

  @override
  Future<bool> start({required String maxAdContentRating}) async {
    started++;
    return canRequest;
  }

  @override
  Future<bool> privacyOptionsRequired() async => privacyRequired;

  @override
  Future<void> showPrivacyOptions() async {}

  @override
  Widget banner(String unitId) =>
      const SizedBox(key: ValueKey('ad-banner'), height: 60);

  @override
  Future<void> loadInterstitial(String unitId) async {
    loads.add(unitId);
    loaded = true;
  }

  @override
  Future<bool> showInterstitial() async {
    if (showThrows) throw StateError('ad crashed');
    if (!loaded) return false;
    loaded = false;
    shown++;
    if (!holdOpen) return true;
    return (open = Completer<bool>()).future;
  }

  void close() => open?.complete(true);
}

Monetization fakeMonetization(
  ApiClient api, {
  FakeStore? store,
  FakeAds? ads,
  DateTime Function()? clock,
}) =>
    Monetization(
      store: store ?? FakeStore(owned: {lifetime}),
      ads: ads ?? FakeAds(),
      api: api,
      clock: clock,
      useTestAds: true,
      settle: Duration.zero,
    );

/// A StoreKit 2 signed transaction as the app sees it. Only the payload
/// matters on the device; the server checks the signature.
String storeKitJws(String productId, {DateTime? expires, DateTime? signedAt}) {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return [
    part({'alg': 'ES256'}),
    part({
      'productId': productId,
      if (expires != null) 'expiresDate': expires.millisecondsSinceEpoch,
      if (signedAt != null) 'signedDate': signedAt.millisecondsSinceEpoch,
    }),
    'sig',
  ].join('.');
}
