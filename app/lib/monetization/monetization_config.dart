/// The remotely configured pricing model (`GET /v1/config`,
/// server/internal/monetization). Prices are not part of it: they come from
/// the stores, localized.
class MonetizationConfig {
  const MonetizationConfig({
    this.freeCategoryIds = const ['food', 'places', 'film_tv'],
    this.categoryPrefix = 'category_',
    this.premiumMonthly = 'premium_monthly',
    this.premiumLifetime = 'premium_lifetime',
    this.purchasesEnabled = true,
    this.adsEnabled = true,
    this.bannerPlacements = BannerPlacement.all,
    this.interstitialEnabled = true,
    this.interstitialMinInterval = Duration.zero,
    this.maxAdContentRating = 'PG',
    this.units = const {},
  });

  /// Reads the server's JSON. Anything missing keeps the built-in default,
  /// which is also what a first launch without a connection uses.
  factory MonetizationConfig.fromJson(Map<String, dynamic> json) {
    const d = MonetizationConfig();
    final products = json['products'] as Map<String, dynamic>? ?? const {};
    final ads = json['ads'] as Map<String, dynamic>? ?? const {};
    final units = ads['units'] as Map<String, dynamic>? ?? const {};
    return MonetizationConfig(
      freeCategoryIds: (json['freeCategoryIds'] as List?)?.cast<String>() ??
          d.freeCategoryIds,
      categoryPrefix: products['categoryPrefix'] as String? ?? d.categoryPrefix,
      premiumMonthly: products['premiumMonthly'] as String? ?? d.premiumMonthly,
      premiumLifetime:
          products['premiumLifetime'] as String? ?? d.premiumLifetime,
      purchasesEnabled: json['purchasesEnabled'] as bool? ?? d.purchasesEnabled,
      adsEnabled: ads['enabled'] as bool? ?? d.adsEnabled,
      bannerPlacements:
          (ads['bannerPlacements'] as List?)?.cast<String>().toSet() ??
              d.bannerPlacements,
      interstitialEnabled:
          ads['interstitialEnabled'] as bool? ?? d.interstitialEnabled,
      interstitialMinInterval: Duration(
        seconds: ads['interstitialMinIntervalSeconds'] as int? ?? 0,
      ),
      maxAdContentRating:
          ads['maxAdContentRating'] as String? ?? d.maxAdContentRating,
      units: {
        for (final e in units.entries)
          e.key: AdUnits.fromJson(e.value as Map<String, dynamic>),
      },
    );
  }

  final List<String> freeCategoryIds;
  final String categoryPrefix;
  final String premiumMonthly;
  final String premiumLifetime;
  final bool purchasesEnabled;
  final bool adsEnabled;
  final Set<String> bannerPlacements;
  final bool interstitialEnabled;
  final Duration interstitialMinInterval;
  final String maxAdContentRating;

  /// AdMob unit ids by platform (`android`, `ios`).
  final Map<String, AdUnits> units;

  Map<String, dynamic> toJson() => {
        'freeCategoryIds': freeCategoryIds,
        'products': {
          'categoryPrefix': categoryPrefix,
          'premiumMonthly': premiumMonthly,
          'premiumLifetime': premiumLifetime,
        },
        'purchasesEnabled': purchasesEnabled,
        'ads': {
          'enabled': adsEnabled,
          'bannerPlacements': bannerPlacements.toList(),
          'interstitialEnabled': interstitialEnabled,
          'interstitialMinIntervalSeconds': interstitialMinInterval.inSeconds,
          'maxAdContentRating': maxAdContentRating,
          'units': {for (final e in units.entries) e.key: e.value.toJson()},
        },
      };

  String categoryProduct(String categoryId) => '$categoryPrefix$categoryId';

  /// The category a product unlocks on its own, or null for Premium.
  String? categoryOf(String productId) =>
      productId.startsWith(categoryPrefix) &&
              productId.length > categoryPrefix.length
          ? productId.substring(categoryPrefix.length)
          : null;
}

class AdUnits {
  const AdUnits({this.banner = '', this.interstitial = ''});

  factory AdUnits.fromJson(Map<String, dynamic> json) => AdUnits(
        banner: json['banner'] as String? ?? '',
        interstitial: json['interstitial'] as String? ?? '',
      );

  final String banner;
  final String interstitial;

  Map<String, String> toJson() =>
      {'banner': banner, 'interstitial': interstitial};
}

/// The non-game screens the design allows a banner on
/// (design/claude/Imposter IL Monetization.dc.html, "כללי פרסומות").
abstract final class BannerPlacement {
  static const home = 'home';
  static const categories = 'categories';
  static const search = 'search';
  static const friends = 'friends';
  static const createRoom = 'create_room';
  static const joinRoom = 'join_room';
  static const lobby = 'lobby';
  static const profile = 'profile';
  static const settings = 'settings';
  static const howToPlay = 'how_to_play';
  static const localPlayers = 'local_players';
  static const localRules = 'local_rules';

  static const all = {
    home, categories, search, friends, createRoom, joinRoom, lobby, //
    profile, settings, howToPlay, localPlayers, localRules,
  };
}
