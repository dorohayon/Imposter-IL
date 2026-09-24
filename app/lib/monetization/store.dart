import 'dart:async';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';

/// What happened to a purchase, as the store reports it.
enum StoreStatus { purchased, restored, pending, canceled, error }

/// A product with the store's localized price, for example `9.90 ₪`.
class StoreProduct {
  const StoreProduct({required this.id, required this.price});

  final String id;
  final String price;
}

class StorePurchase {
  const StorePurchase({
    required this.productId,
    required this.status,
    this.verificationData = '',
    this.handle,
  });

  final String productId;
  final StoreStatus status;

  /// What the server verifies: StoreKit 2's signed transaction (JWS) on iOS,
  /// the purchase token on Android.
  final String verificationData;

  /// The plugin's own object, needed to finish the transaction.
  final Object? handle;
}

/// The App Store or Google Play. Tests use a fake; the app uses [PluginStore].
abstract interface class StoreGateway {
  /// `ios` or `android`, as the server's verifiers are keyed.
  String get platform;

  /// Every purchase update: new purchases, restores, renewals the store
  /// delivers on its own, cancellations and errors.
  Stream<List<StorePurchase>> get purchases;

  Future<bool> isAvailable();

  /// The products the store knows, with localized prices. Unknown ids are
  /// left out.
  Future<Map<String, StoreProduct>> products(Set<String> ids);

  /// Starts a purchase. The result arrives on [purchases]; false means the
  /// store refused to start one.
  Future<bool> buy(String productId);

  /// Replays what this store account owns now as `restored`, without any
  /// sign-in prompt: StoreKit 2's current entitlements and Play's active
  /// purchases, which already leave out refunds and lapsed periods.
  Future<void> restore();

  /// Finishes (iOS) or acknowledges (Android) a delivered purchase. Play
  /// refunds one that is not acknowledged within three days.
  Future<void> complete(StorePurchase purchase);
}

class PluginStore implements StoreGateway {
  PluginStore() {
    // Subscribing at launch is what the plugin asks for: a purchase finished
    // while the app was closed is delivered here. The store lives as long as
    // the app, so the subscription is never cancelled.
    _iap.purchaseStream.listen(
      (list) => _updates.add([for (final p in list) _convert(p)]),
      onError: (Object _) {},
    );
  }

  final _iap = InAppPurchase.instance;
  final _updates = StreamController<List<StorePurchase>>.broadcast();
  final _details = <String, ProductDetails>{};

  @override
  String get platform => Platform.isIOS ? 'ios' : 'android';

  @override
  Stream<List<StorePurchase>> get purchases => _updates.stream;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Future<Map<String, StoreProduct>> products(Set<String> ids) async {
    final response = await _iap.queryProductDetails(ids);
    if (response.error != null && response.productDetails.isEmpty) {
      throw StateError(response.error!.message);
    }
    final out = <String, StoreProduct>{};
    // ponytail: Play lists one entry per subscription offer; with only a base
    // plan configured the first is the one. Pick by offer id if intro offers
    // are ever added.
    for (final d in response.productDetails) {
      if (out.containsKey(d.id)) continue;
      _details[d.id] = d;
      out[d.id] = StoreProduct(id: d.id, price: d.price);
    }
    return out;
  }

  @override
  Future<bool> buy(String productId) async {
    final details = _details[productId];
    if (details == null) return false;
    try {
      // Subscriptions are bought as non-consumables in this plugin too.
      return await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: details),
      );
    } on Object {
      return false;
    }
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  @override
  Future<void> complete(StorePurchase purchase) async {
    final details = purchase.handle;
    if (details is PurchaseDetails && details.pendingCompletePurchase) {
      await _iap.completePurchase(details);
    }
  }

  StorePurchase _convert(PurchaseDetails p) => StorePurchase(
        productId: p.productID,
        status: switch (p.status) {
          PurchaseStatus.purchased => StoreStatus.purchased,
          PurchaseStatus.restored => StoreStatus.restored,
          PurchaseStatus.pending => StoreStatus.pending,
          PurchaseStatus.canceled => StoreStatus.canceled,
          PurchaseStatus.error => StoreStatus.error,
        },
        verificationData: p.verificationData.serverVerificationData,
        handle: p,
      );
}
