import 'package:flutter_test/flutter_test.dart';
import 'package:imposter_il/data/server.dart';
import 'package:imposter_il/monetization/monetization.dart';
import 'package:imposter_il/monetization/monetization_config.dart';
import 'package:imposter_il/monetization/store.dart';
import 'package:imposter_il/state/game_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_monetization.dart';
import 'support/fake_server.dart';

Future<Monetization> started({
  FakeStore? store,
  FakeAds? ads,
  FakeApi? api,
  DateTime Function()? clock,
}) async {
  final m = fakeMonetization(api ?? FakeApi(),
      store: store ?? FakeStore(), ads: ads, clock: clock);
  addTearDown(m.dispose);
  await m.start();
  await m.refresh();
  return m;
}

/// Lets queued stream deliveries and microtasks run.
Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('entitlements', () {
    test('three configured categories are free and the rest locked', () async {
      final m = await started();
      for (final id in ['food', 'animals', 'places']) {
        expect(m.isUnlocked(id), isTrue, reason: id);
      }
      for (final id in ['sports', 'professions', 'objects']) {
        expect(m.isUnlocked(id), isFalse, reason: id);
      }
      expect(m.premium, isFalse);
      expect(m.showsAds, isTrue);
    });

    test('the free list comes from the server', () async {
      final api = FakeApi();
      (api.responses['GET /v1/config']! as Map)['monetization']
          ['freeCategoryIds'] = ['sports'];
      final m = await started(api: api);
      await flush();
      expect(m.isUnlocked('sports'), isTrue);
      expect(m.isUnlocked('food'), isFalse);
    });

    test('a category purchase unlocks that category and keeps ads', () async {
      final m = await started(store: FakeStore(owned: {'category_sports'}));
      expect(m.isUnlocked('sports'), isTrue);
      expect(m.isPurchased('sports'), isTrue);
      expect(m.isUnlocked('objects'), isFalse);
      expect(m.premium, isFalse);
      expect(m.showsAds, isTrue);
      expect(m.bannerUnit(BannerPlacement.home), isNotNull);
    });

    test('lifetime Premium unlocks everything and removes every ad', () async {
      final m = await started(store: FakeStore(owned: {lifetime}));
      expect(m.premium, isTrue);
      expect(m.isUnlocked('objects'), isTrue);
      expect(m.isPurchased('objects'), isFalse);
      expect(m.showsAds, isFalse);
      for (final placement in BannerPlacement.all) {
        expect(m.bannerUnit(placement), isNull, reason: placement);
      }
    });

    test('a refund takes the category away at the next store answer', () async {
      final store = FakeStore(owned: {'category_sports'});
      final m = await started(store: store);
      expect(m.isUnlocked('sports'), isTrue);

      store.owned.clear(); // refunded: the store no longer lists it
      await m.refresh();
      expect(m.isUnlocked('sports'), isFalse);
    });

    test('monthly Premium lasts until the signed period ends', () async {
      var now = DateTime(2026, 9, 23);
      final store = FakeStore(owned: {monthly}, platform: 'ios')
        ..proofs[monthly] =
            storeKitJws(monthly, expires: DateTime(2026, 10, 23));
      final m = await started(store: store, clock: () => now);
      expect(m.premium, isTrue);
      expect(m.premiumUntil, DateTime(2026, 10, 23));
      expect(m.showsAds, isFalse);

      // Offline past the period: it lapses even without the store's word.
      now = DateTime(2026, 10, 24);
      store.available = false;
      await m.refresh();
      expect(m.premium, isFalse);
      expect(m.isUnlocked('sports'), isFalse);
      expect(m.showsAds, isTrue);
    });

    test('a cancelled subscription is gone once the store stops listing it',
        () async {
      final store = FakeStore(owned: {monthly});
      final m = await started(store: store);
      expect(m.premium, isTrue);
      store.owned.remove(monthly); // cancelled and the period ran out
      await m.refresh();
      expect(m.premium, isFalse);
      expect(m.premiumUntil, isNull);
    });

    test('Play gives no expiry, so a listed subscription holds for a grace',
        () async {
      final now = DateTime(2026, 9, 23);
      final m =
          await started(store: FakeStore(owned: {monthly}), clock: () => now);
      expect(m.premiumUntil, now.add(Monetization.undatedGrace));
    });

    test('the server can date a Play subscription', () async {
      final api = FakeApi()
        ..responses['POST /v1/entitlements'] = {
          'entitlements': {
            'premium': true,
            'premiumUntil': '2026-10-20T00:00:00Z'
          },
        };
      final session = GameSession(api);
      session.token = 'token-1';
      final m = await started(store: FakeStore(owned: {monthly}), api: api);
      m.attach(session);
      await m.syncServer(force: true);
      expect(m.premiumUntil, DateTime.utc(2026, 10, 20));
    });

    test('offline, the last answer is kept and survives a restart', () async {
      final store = FakeStore(owned: {'category_sports', lifetime});
      await started(store: store);

      final offline = FakeStore()..available = false;
      final m = await started(store: offline);
      expect(m.isUnlocked('sports'), isTrue);
      expect(m.premium, isTrue);

      final broken = FakeStore()..restoreFails = true;
      final again = await started(store: broken);
      expect(again.premium, isTrue, reason: 'a failed restore changes nothing');
    });

    test('a renewal the store delivers on its own extends Premium', () async {
      final store = FakeStore();
      final m = await started(store: store);
      store.emit([store.purchase(monthly, StoreStatus.purchased)]);
      await flush();
      expect(m.premium, isTrue);
      expect(store.completed, contains(monthly));
    });
  });

  group('purchase popup', () {
    test('prices are the store\'s own', () async {
      final m = await started();
      await m.loadProducts('sports');
      expect(m.products['category_sports']?.price, '9.90 ₪');
      expect(m.products[monthly]?.price, '14.90 ₪');
      expect(m.products[lifetime]?.price, '59.90 ₪');
      expect(m.productsFailed, isFalse);
    });

    test('prices that cannot load are a state, not a crash', () async {
      final m = await started(store: FakeStore()..productsFail = true);
      await m.loadProducts('sports');
      expect(m.productsFailed, isTrue);
      expect(m.productsLoading, isFalse);

      final offline = await started(store: FakeStore()..available = false);
      await offline.loadProducts('sports');
      expect(offline.productsFailed, isTrue);
    });

    test('buying a category unlocks it and finishes the transaction', () async {
      final store = FakeStore();
      final m = await started(store: store);
      m.openPopup();
      await m.buy('category_sports');
      await flush();
      expect(m.step, PurchaseStep.purchased);
      expect(m.flowProduct, 'category_sports');
      expect(m.isUnlocked('sports'), isTrue);
      expect(store.completed, contains('category_sports'));
    });

    test('cancel, error and a refused start charge nothing', () async {
      final store = FakeStore();
      final m = await started(store: store);
      for (final (outcome, step) in [
        (StoreStatus.canceled, PurchaseStep.cancelled),
        (StoreStatus.error, PurchaseStep.failed),
      ]) {
        m.openPopup();
        store.outcome = outcome;
        await m.buy('category_sports');
        await flush();
        expect(m.step, step);
        expect(m.isUnlocked('sports'), isFalse);
      }
      m.openPopup();
      store.refuseBuy = true;
      await m.buy('category_sports');
      expect(m.step, PurchaseStep.failed);
    });

    test('a pending payment opens nothing and is not finished', () async {
      final store = FakeStore()..outcome = StoreStatus.pending;
      final m = await started(store: store);
      m.openPopup();
      await m.buy(lifetime);
      await flush();
      expect(m.step, PurchaseStep.pending);
      expect(m.premium, isFalse);
      expect(store.completed, isNot(contains(lifetime)));

      // Approved later: the store delivers it.
      store.emit([store.purchase(lifetime, StoreStatus.purchased)]);
      await flush();
      expect(m.step, PurchaseStep.purchased);
      expect(m.premium, isTrue);
    });

    test('buying is off when the remote config says so', () async {
      final api = FakeApi();
      (api.responses['GET /v1/config']! as Map)['monetization']
          ['purchasesEnabled'] = false;
      final store = FakeStore();
      final m = await started(store: store, api: api);
      await flush();
      await m.buy('category_sports');
      expect(store.bought, isEmpty);
    });

    test('restore reports what came back', () async {
      final store = FakeStore();
      final m = await started(store: store);

      await m.restoreFor('sports');
      expect(m.step, PurchaseStep.restoreNone);

      store.owned.add('category_objects');
      await m.restoreFor('sports');
      expect(m.step, PurchaseStep.restoredOther);

      store.owned.add('category_sports');
      await m.restoreFor('sports');
      expect(m.step, PurchaseStep.restored);

      store.restoreFails = true;
      await m.restoreFor('sports');
      expect(m.step, PurchaseStep.restoreFailed);
      expect(m.isUnlocked('sports'), isTrue, reason: 'kept after a failure');

      expect(await m.restoreAll(), RestoreResult.failed);
      store.restoreFails = false;
      expect(await m.restoreAll(), RestoreResult.found);
      store.owned.clear();
      expect(await m.restoreAll(), RestoreResult.none);
    });
  });

  group('server', () {
    test('the store proofs reach the server, once per change', () async {
      final api = FakeApi();
      final store = FakeStore(owned: {'category_sports'});
      final session = GameSession(api);
      addTearDown(session.dispose);
      session.token = 'token-1';
      final m = await started(store: store, api: api);
      m.attach(session);
      await flush();
      final posts = api.requests.where((r) => r.$2 == '/v1/entitlements');
      expect(posts, isNotEmpty);
      expect((posts.last.$3! as Map)['purchases'], [
        {
          'platform': 'android',
          'productId': 'category_sports',
          'verificationData': 'token-category_sports',
        },
      ]);

      final before = posts.length;
      // Notifications without a new token or a new purchase send nothing.
      session.notifyListeners();
      session.notifyListeners();
      await flush();
      expect(
          api.requests.where((r) => r.$2 == '/v1/entitlements').length, before);
    });

    test('a resume that finds the same purchases sends nothing', () async {
      final api = FakeApi();
      final store =
          FakeStore(owned: {'category_sports', monthly}, platform: 'ios');
      final session = GameSession(api);
      addTearDown(session.dispose);
      session.token = 'token-1';
      var signed = 0;
      // StoreKit signs the same transaction again on every restore.
      String jws() => storeKitJws(monthly,
          expires: DateTime(2030), signedAt: DateTime(2026, 9, 1 + signed++));
      store.proofs[monthly] = jws();
      final m = await started(store: store, api: api);
      m.attach(session);
      await flush();
      int posts() =>
          api.requests.where((r) => r.$2 == '/v1/entitlements').length;
      final before = posts();
      expect(before, greaterThan(0));

      for (var i = 0; i < 5; i++) {
        store.proofs[monthly] = jws();
        m.resumed();
        await flush();
        await m.refresh();
        await flush();
      }
      expect(posts(), before, reason: 'nothing the server decides on changed');

      // A real change is sent, once.
      store.owned.add('category_objects');
      await m.refresh();
      await flush();
      expect(posts(), before + 1);
    });

    test('a Play renewal keeps its token and is re-verified near the end',
        () async {
      var clock = DateTime.utc(2026, 9, 24, 12);
      final firstEnd = DateTime.utc(2026, 10, 24, 12);
      final api = FakeApi()
        ..responses['POST /v1/entitlements'] = {
          'entitlements': {
            'premium': true,
            'premiumUntil': firstEnd.toIso8601String()
          },
        };
      final store = FakeStore(owned: {monthly}); // Android: one token for good
      final session = GameSession(api);
      addTearDown(session.dispose);
      session.token = 'token-1';
      final m = await started(store: store, api: api, clock: () => clock);
      m.attach(session);
      await flush();
      int posts() =>
          api.requests.where((r) => r.$2 == '/v1/entitlements').length;
      final before = posts();
      expect(m.premiumUntil, firstEnd);

      // Mid-period resumes send nothing.
      clock = clock.add(const Duration(days: 10));
      await m.refresh();
      await flush();
      expect(posts(), before);

      // Hours before the period the server knows ends, the same token goes
      // again, and Google's later expiry comes back.
      final renewedEnd = firstEnd.add(const Duration(days: 30));
      api.responses['POST /v1/entitlements'] = {
        'entitlements': {
          'premium': true,
          'premiumUntil': renewedEnd.toIso8601String()
        },
      };
      clock = firstEnd.subtract(const Duration(hours: 12));
      await m.refresh();
      await flush();
      expect(posts(), before + 1);
      expect(m.premiumUntil, renewedEnd);
      expect(m.premium, isTrue);
    });

    test('near a renewal, resuming again and again asks at most hourly',
        () async {
      final end = DateTime.utc(2026, 10, 24, 12);
      var clock = end.subtract(const Duration(hours: 20));
      final api = FakeApi()
        ..responses['POST /v1/entitlements'] = {
          'entitlements': {
            'premium': true,
            'premiumUntil': end.toIso8601String()
          },
        };
      final session = GameSession(api);
      addTearDown(session.dispose);
      session.token = 'token-1';
      final m = await started(
          store: FakeStore(owned: {monthly}), api: api, clock: () => clock);
      m.attach(session);
      await flush();
      int posts() =>
          api.requests.where((r) => r.$2 == '/v1/entitlements').length;
      final before = posts();
      // Google has not renewed yet, so the server keeps the same end.
      for (var i = 0; i < 10; i++) {
        clock = clock.add(const Duration(minutes: 3));
        await m.refresh();
        await flush();
      }
      expect(posts(), before, reason: 'ten resumes inside the hour');
      clock = clock.add(const Duration(hours: 1));
      await m.refresh();
      await flush();
      expect(posts(), before + 1);
    });

    test('an undated subscription is re-sent at most every few hours',
        () async {
      var clock = DateTime.utc(2026, 9, 24, 12);
      final api = FakeApi(); // the server dates nothing (no Google verifier)
      final session = GameSession(api);
      addTearDown(session.dispose);
      session.token = 'token-1';
      final m = await started(
          store: FakeStore(owned: {monthly}), api: api, clock: () => clock);
      m.attach(session);
      await flush();
      int posts() =>
          api.requests.where((r) => r.$2 == '/v1/entitlements').length;
      final before = posts();
      for (var i = 0; i < 5; i++) {
        clock = clock.add(const Duration(minutes: 10));
        await m.refresh();
        await flush();
      }
      expect(posts(), before);
      clock = clock.add(const Duration(hours: 6));
      await m.refresh();
      await flush();
      expect(posts(), before + 1);
    });

    test('a failing server is not retried on every session change', () async {
      final api = FakeApi()
        ..responses['POST /v1/entitlements'] =
            const ApiException('network_error');
      final session = GameSession(api);
      addTearDown(session.dispose);
      session.token = 'token-1';
      final m = await started(api: api);
      m.attach(session);
      await flush();
      final attempts =
          api.requests.where((r) => r.$2 == '/v1/entitlements').length;
      for (var i = 0; i < 20; i++) {
        session.notifyListeners();
      }
      await flush();
      expect(api.requests.where((r) => r.$2 == '/v1/entitlements').length,
          attempts);
    });

    test('a locked answer re-syncs once and retries the search', () async {
      final api = FakeApi();
      final session = GameSession(api);
      addTearDown(session.dispose);
      var resyncs = 0;
      session.resyncEntitlements = () async => resyncs++;
      await session.restore();
      await session.signIn('דור', 'avatar-m04-detective-hat');
      await flush();
      api.channel.errors['matchmaking.join'] = 'category_locked';
      final code = await session.startSearch(['sports']);
      expect(resyncs, 1);
      expect(code, 'category_locked');
      expect(api.channel.commands('matchmaking.join'), hasLength(2));
    });

    test('a locked room re-syncs once and tries again', () async {
      final api = FakeApi()
        ..responses['POST /v1/rooms'] = const ApiException('category_locked');
      final session = GameSession(api);
      addTearDown(session.dispose);
      var resyncs = 0;
      session.resyncEntitlements = () async {
        resyncs++;
        api.responses['POST /v1/rooms'] = {'room': roomJson()};
      };
      session.token = 'token-1';
      await session
          .createRoom(maxPlayers: 4, hintSeconds: 60, categoryIds: ['sports']);
      expect(resyncs, 1);
      expect(session.roomId, 'r_1');
    });
  });

  group('ads', () {
    test('ads start only for players who see them', () async {
      final ads = FakeAds();
      final m = await started(store: FakeStore(owned: {lifetime}), ads: ads);
      await m.startAds();
      expect(ads.started, 0);

      final freeAds = FakeAds();
      final free = await started(ads: freeAds);
      await free.startAds();
      expect(freeAds.started, 1);
      expect(free.adsReady, isTrue);
      expect(freeAds.loads, isNotEmpty, reason: 'interstitial preloaded');
    });

    test('no consent means no ads, and nothing waits on them', () async {
      final ads = FakeAds()..canRequest = false;
      final m = await started(ads: ads);
      await m.startAds();
      expect(m.adsReady, isFalse);
      await m.afterCompletedMatch(); // returns at once
      expect(ads.shown, 0);
    });

    test('an interstitial after a completed match, within the interval',
        () async {
      var now = DateTime(2026, 9, 23, 12);
      final api = FakeApi();
      (api.responses['GET /v1/config']! as Map)['monetization']['ads']
          ['interstitialMinIntervalSeconds'] = 120;
      final ads = FakeAds();
      final m = await started(ads: ads, api: api, clock: () => now);
      await flush();
      await m.startAds();

      await m.afterCompletedMatch();
      expect(ads.shown, 1);
      now = now.add(const Duration(seconds: 60));
      await m.afterCompletedMatch();
      expect(ads.shown, 1, reason: 'inside the interval');
      now = now.add(const Duration(seconds: 61));
      await m.afterCompletedMatch();
      expect(ads.shown, 2);
    });

    test('a failed or missing interstitial never blocks', () async {
      final ads = FakeAds();
      final m = await started(ads: ads);
      await m.startAds();
      ads.loaded = false;
      await m.afterCompletedMatch();
      expect(ads.shown, 0);
      ads
        ..loaded = true
        ..showThrows = true;
      await m.afterCompletedMatch(); // completes without throwing
    });

    test('Premium bought mid-session ends ads at once', () async {
      final store = FakeStore();
      final ads = FakeAds();
      final m = await started(store: store, ads: ads);
      await m.startAds();
      expect(m.bannerUnit(BannerPlacement.settings), isNotNull);
      await m.buy(monthly);
      await flush();
      expect(m.bannerUnit(BannerPlacement.settings), isNull);
      await m.afterCompletedMatch();
      expect(ads.shown, 0);
    });

    test('remote config controls placements and can turn ads off', () async {
      final api = FakeApi();
      final ads = (api.responses['GET /v1/config']! as Map)['monetization']
          ['ads'] as Map;
      ads['bannerPlacements'] = ['home'];
      final m = await started(api: api);
      await flush();
      expect(m.bannerUnit(BannerPlacement.home), isNotNull);
      expect(m.bannerUnit(BannerPlacement.settings), isNull);

      ads['enabled'] = false;
      final off = await started(api: api);
      await flush();
      expect(off.bannerUnit(BannerPlacement.home), isNull);
    });

    test('a release build without unit ids shows no ads', () async {
      final m = Monetization(
        store: FakeStore(),
        ads: FakeAds(),
        api: FakeApi(),
        useTestAds: false,
        settle: Duration.zero,
      );
      addTearDown(m.dispose);
      await m.start();
      await flush();
      expect(m.bannerUnit(BannerPlacement.home), isNull);
    });
  });

  test('the config survives a round trip and fills gaps with defaults', () {
    const config = MonetizationConfig(
      freeCategoryIds: ['sports'],
      interstitialMinInterval: Duration(seconds: 30),
      units: {'ios': AdUnits(banner: 'b', interstitial: 'i')},
    );
    final back = MonetizationConfig.fromJson(config.toJson());
    expect(back.freeCategoryIds, ['sports']);
    expect(back.interstitialMinInterval, const Duration(seconds: 30));
    expect(back.units['ios']?.banner, 'b');
    expect(MonetizationConfig.fromJson({}).freeCategoryIds,
        ['food', 'animals', 'places']);
    expect(config.categoryOf('category_sports'), 'sports');
    expect(config.categoryOf('premium_monthly'), isNull);
    expect(config.categoryOf('category_'), isNull);
  });
}
