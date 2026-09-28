import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../screens/legal_screens.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';
import 'monetization.dart';

// The purchase popup: one bottom sheet over the category picker, no store
// screen (design/claude/Imposter IL Monetization.dc.html, P01–P12).

/// Opens the popup for a locked category. Completes with true when the
/// player unlocked that category on its own and chose to play it.
Future<bool> showPurchaseSheet(
  BuildContext context, {
  required String categoryId,
  required String categoryName,
}) async {
  final monetization = MonetizationScope.read(context);
  monetization.openPopup();
  unawaited(monetization.loadProducts(categoryId));
  final chosen = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    // Dragging would close it mid-payment; the close button is always there
    // otherwise.
    enableDrag: false,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xBD080716),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height -
          (MediaQuery.sizeOf(context).height < 844 ? 40 : 60),
    ),
    builder: (_) => _PurchaseSheet(id: categoryId, name: categoryName),
  );
  return chosen ?? false;
}

/// Opens the popup and, if the player chose to, selects the category.
Future<void> openLockedCategory(
  BuildContext context, {
  required String categoryId,
  required String categoryName,
  required VoidCallback onSelect,
}) async {
  final chosen = await showPurchaseSheet(context,
      categoryId: categoryId, categoryName: categoryName);
  // The picker may have gone meanwhile; the purchase itself is kept either way.
  if (chosen && context.mounted) onSelect();
}

/// "3 פתוחות בחינם", next to a category chip list (design L05).
String categoryCount(Monetization m, Iterable<String> ids) {
  final open = m.unlocked(ids);
  return open.every(m.isFree)
      ? l10n.openFreeCount(open.length)
      : l10n.openCount(open.length);
}

/// A locked category in a chip list: a lock and a dimmed name. Tapping it
/// opens the purchase popup.
class LockedChip extends StatelessWidget {
  const LockedChip({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.lockedTapToOpen(label),
      excludeSemantics: true,
      child: ActionChip(
        avatar:
            const Icon(Icons.lock_rounded, size: 16, color: AppColors.yellow),
        label: Text(label),
        onPressed: onTap,
        backgroundColor: AppColors.cream.withValues(alpha: .035),
        labelStyle: TextStyle(
          color: AppColors.cream.withValues(alpha: .62),
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.cream.withValues(alpha: .1)),
        ),
      ),
    );
  }
}

class _PurchaseSheet extends StatefulWidget {
  const _PurchaseSheet({required this.id, required this.name});

  final String id;
  final String name;

  @override
  State<_PurchaseSheet> createState() => _PurchaseSheetState();
}

const _sheetColor = Color(0xFF1E1C3B);

/// The rewarded-ad option, listed first; not a store product.
const _adOption = 'rewarded_ad';

const _soft = Color(0xB8FFF8E7); // cream at ~72%

class _PurchaseSheetState extends State<_PurchaseSheet> {
  String? _selected;

  /// Keeps the rewarded cooldown's minutes current while the popup is open.
  late final Timer _tick =
      Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _tick;
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = MonetizationScope.of(context);
    final offer = m.offerFor(widget.id);
    final adOffered = m.rewardOffered;
    final available = [
      if (adOffered && m.rewardCooldownLeft == null) _adOption,
      for (final id in offer)
        if (m.products.containsKey(id)) id,
    ];
    final step = m.step;
    final loading = m.productsLoading;
    final pricesFailed = !loading && m.productsFailed;
    // The first option is chosen for them: the ad, else the category they
    // tapped or the first product the store sells. Prices that failed keep
    // a product chosen, so their retry button shows.
    final selected = available.contains(_selected)
        ? _selected!
        : pricesFailed
            ? offer.first
            : available.firstOrNull ?? offer.first;
    final succeeded = step == PurchaseStep.purchased ||
        step == PurchaseStep.restored ||
        step == PurchaseStep.rewarded;

    return PopScope(
      canPop: !m.busy,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _sheetColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: AppColors.cream.withValues(alpha: .14)),
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x73000000),
                blurRadius: 50,
                offset: Offset(0, -20)),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.cream.withValues(alpha: .25),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
                  child: succeeded
                      ? _success(m, step)
                      : _choose(m, offer, available, adOffered, selected,
                          loading, pricesFailed),
                ),
              ),
              _footer(m, selected, succeeded, loading, pricesFailed,
                  available.isNotEmpty),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choose(
    Monetization m,
    List<String> offer,
    List<String> available,
    bool adOffered,
    String selected,
    bool loading,
    bool pricesFailed,
  ) {
    final notice = switch (m.step) {
      PurchaseStep.rewardRefused => _Notice.warning(
          context.l10n.rewardRefused(widget.name) +
              (m.rewardCooldownLeft == null
                  ? ''
                  : context.l10n
                      .watchAgainInSentence(_duration(m.rewardCooldownLeft!)))),
      PurchaseStep.adFailed =>
        _Notice.warning(context.l10n.adFailed(widget.name)),
      _ when pricesFailed && m.productsMissing =>
        _Notice.error(context.l10n.purchasesUnavailableLater),
      _ when pricesFailed => _Notice.error(context.l10n.pricesFailed),
      PurchaseStep.cancelled => _Notice.warning(context.l10n.purchaseCancelled),
      PurchaseStep.failed => _Notice.error(context.l10n.purchaseFailed),
      PurchaseStep.pending =>
        _Notice.warning(context.l10n.purchasePending(widget.name)),
      PurchaseStep.restoreNone => _Notice.info(context.l10n.noPurchasesFound),
      PurchaseStep.restoredOther =>
        _Notice.info(context.l10n.restoredOther(widget.name)),
      PurchaseStep.restoreFailed => _Notice.error(context.l10n.restoreFailed),
      _ when !m.config.purchasesEnabled =>
        _Notice.warning(context.l10n.purchasesUnavailableRestore),
      _ => null,
    };
    final disabled = m.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CloseButton(
              onPressed: disabled ? null : () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                children: [
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_rounded,
                          color: AppColors.yellow, size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          context.l10n.categoryLockedTitle(widget.name),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Secular One',
                            fontSize: 21,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.chooseHowToUnlock,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _soft, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 52),
          ],
        ),
        if (notice != null) ...[const SizedBox(height: 10), notice],
        const SizedBox(height: 10),
        if (adOffered) ...[
          _adChoice(m, selected == _adOption, disabled),
          const SizedBox(height: 9),
        ],
        for (final id
            in loading ? offer : available.where((id) => id != _adOption)) ...[
          _Option(
            title: _title(m, id),
            description: _description(m, id),
            price: m.products[id]?.price,
            priceNote: id == m.config.premiumMonthly
                ? context.l10n.perMonth
                : context.l10n.oneTimePayment,
            loading: loading,
            selected: !loading && id == selected,
            enabled: !disabled && !loading,
            onTap: () => setState(() => _selected = id),
          ),
          const SizedBox(height: 9),
        ],
      ],
    );
  }

  Widget _adChoice(Monetization m, bool selected, bool disabled) {
    final wait = m.rewardCooldownLeft;
    return _Option(
      title: context.l10n.watchAd,
      description: wait == null
          ? context.l10n.adUnlocksNextGame(widget.name)
          : context.l10n.watchAgainIn(_duration(wait)),
      price: context.l10n.free,
      priceNote: context.l10n.oneGame,
      loading: false,
      selected: selected && wait == null,
      enabled: !disabled && wait == null,
      onTap: () => setState(() => _selected = _adOption),
    );
  }

  /// "3 שע׳ ו־12 דק׳", rounded up to the minute.
  static String _duration(Duration d) {
    final minutes = (d.inSeconds / 60).ceil();
    final h = minutes ~/ 60, min = minutes % 60;
    return [
      if (h > 0) l10n.durationHours(h),
      if (min > 0 || h == 0) l10n.durationMinutes(min)
    ].join(l10n.durationAnd);
  }

  String _title(Monetization m, String id) => id == m.config.premiumMonthly
      ? context.l10n.premiumMonthly
      : id == m.config.premiumLifetime
          ? context.l10n.premiumLifetime
          : context.l10n.onlyCategory(widget.name);

  String _description(Monetization m, String id) =>
      id == m.config.premiumMonthly
          ? context.l10n.premiumMonthlyDesc
          : id == m.config.premiumLifetime
              ? context.l10n.premiumLifetimeDesc
              : context.l10n.categoryForeverDesc;

  Widget _success(Monetization m, PurchaseStep step) {
    final product = m.flowProduct;
    final premium = step == PurchaseStep.purchased &&
        (product == m.config.premiumMonthly ||
            product == m.config.premiumLifetime);
    final (title, body) = step == PurchaseStep.restored
        ? (
            context.l10n.purchasesRestoredTitle,
            context.l10n.categoryOpenAgain(widget.name)
          )
        : step == PurchaseStep.rewarded
            ? (
                context.l10n.categoryOpenNextGame(widget.name),
                context.l10n.thanksForWatching,
              )
            : premium
                ? (
                    context.l10n.welcomePremium,
                    product == m.config.premiumMonthly
                        ? context.l10n.monthlyActive
                        : m.monthlyBeforePurchase
                            ? context.l10n.lifetimeWithMonthly
                            : context.l10n.lifetimeUnlocked,
                  )
                : (
                    context.l10n.categoryUnlocked(widget.name),
                    context.l10n.categoryYoursForever,
                  );
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: premium ? AppColors.yellow : AppColors.turquoise,
              boxShadow: [
                BoxShadow(
                  color: (premium ? AppColors.yellow : AppColors.turquoise)
                      .withValues(alpha: .35),
                  blurRadius: 26,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(
              Icons.check_rounded,
              size: 40,
              color: premium ? AppColors.night : const Color(0xFF0E2B2A),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Secular One', fontSize: 26),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.cream.withValues(alpha: .75),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
          if (premium) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.cream.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  _Included(context.l10n.allCategoriesOpen),
                  SizedBox(height: 10),
                  _Included(context.l10n.premiumFeaturesActive),
                  SizedBox(height: 10),
                  _Included(context.l10n.noBannersNoAds),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _footer(
    Monetization m,
    String selected,
    bool succeeded,
    bool loading,
    bool pricesFailed,
    bool anyProduct,
  ) {
    final price = m.products[selected]?.price ?? '';
    // Isolated so the currency sign stays with its number inside Hebrew.
    final p = '\u2066$price\u2069';
    final isCategory = selected != m.config.premiumMonthly &&
        selected != m.config.premiumLifetime;

    final Widget child;
    if (succeeded) {
      final product = m.flowProduct;
      final categoryBought = m.step == PurchaseStep.purchased &&
          product == m.config.categoryProduct(widget.id);
      final premium = m.step == PurchaseStep.purchased && !categoryBought;
      final pick = categoryBought || m.step == PurchaseStep.rewarded;
      child = PrimaryButton(
        label: m.step == PurchaseStep.restored
            ? context.l10n.close
            : premium
                ? context.l10n.startPlaying
                : context.l10n.chooseCategoryN(widget.name),
        onPressed: () => Navigator.of(context).pop(pick),
      );
    } else if (selected == _adOption) {
      final watching = m.step == PurchaseStep.watchingAd;
      child = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrimaryButton(
            label: watching ? context.l10n.loadingAd : context.l10n.watchAd,
            // Busy restoring too: the restore link shows that state.
            onPressed: m.busy ? null : () => m.watchAdFor(widget.id),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.adDisclosure(widget.name),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.cream.withValues(alpha: .66),
              fontSize: 12,
              height: 1.5,
            ),
          ),
          // Restore and the legal links stay one tap away, as for a purchase.
          _links(m),
        ],
      );
    } else {
      final (label, onPressed) = switch (m.step) {
        _ when loading => (context.l10n.loadingPrices, null),
        _ when pricesFailed => (
            context.l10n.tryAgain,
            () => unawaited(m.loadProducts(widget.id)),
          ),
        PurchaseStep.processing => (context.l10n.connectingStore, null),
        PurchaseStep.restoring => (_ctaFor(m, selected, p), null),
        PurchaseStep.failed => (context.l10n.tryAgain, () => m.buy(selected)),
        _ => (_ctaFor(m, selected, p), () => m.buy(selected)),
      };
      final canBuy = m.config.purchasesEnabled && anyProduct;
      final disclosure = loading
          ? context.l10n.pricesInStoreCurrency
          : m.step == PurchaseStep.processing
              ? context.l10n.continueInStore
              : !anyProduct
                  ? ''
                  : selected == m.config.premiumMonthly
                      ? context.l10n.subscriptionDisclosure(p)
                      : isCategory
                          ? context.l10n
                              .categoryPurchaseDisclosure(p, widget.name)
                          : context.l10n.premiumPurchaseDisclosure(p);
      child = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrimaryButton(
            label: label,
            onPressed: pricesFailed || canBuy ? onPressed : null,
          ),
          if (disclosure.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              disclosure,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.cream.withValues(alpha: .66),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
          _links(m),
        ],
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.cream.withValues(alpha: .08)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: child,
    );
  }

  Widget _links(Monetization m) => Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 14,
        children: [
          TextButton(
            onPressed: m.busy ? null : () => m.restoreFor(widget.id),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.turquoise,
              minimumSize: const Size(44, 44),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.underline,
              ),
            ),
            child: Text(m.step == PurchaseStep.restoring
                ? context.l10n.restoringPurchases
                : context.l10n.restorePurchases),
          ),
          _Link(context.l10n.termsTitle, () => const TermsScreen()),
          _Link(context.l10n.privacyTitle, () => const PrivacyScreen()),
        ],
      );

  String _ctaFor(Monetization m, String selected, String p) =>
      selected == m.config.premiumMonthly
          ? context.l10n.joinPremium
          : context.l10n.buyPrice(p);
}

class _Option extends StatelessWidget {
  const _Option({
    required this.title,
    required this.description,
    required this.price,
    required this.priceNote,
    required this.loading,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String description;
  final String? price;
  final String priceNote;
  final bool loading;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 844;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: enabled,
      button: true,
      child: Opacity(
        opacity: enabled || loading || selected ? 1 : .5,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14,
              vertical: compact ? 11 : 13,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.yellow.withValues(alpha: .12)
                  : AppColors.cream.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? AppColors.yellow
                    : AppColors.cream.withValues(alpha: .14),
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? AppColors.yellow : null,
                    border: selected
                        ? null
                        : Border.all(
                            color: AppColors.cream.withValues(alpha: .35),
                            width: 2,
                          ),
                  ),
                  child: selected
                      ? Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: AppColors.night,
                            shape: BoxShape.circle,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Secular One',
                          fontSize: 17,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: const TextStyle(
                          color: _soft,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (loading)
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _Skeleton(width: 58, height: 16, alpha: .14),
                      SizedBox(height: 6),
                      _Skeleton(width: 40, height: 10, alpha: .08),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      LtrText(
                        price ?? '',
                        style: TextStyle(
                          fontFamily: 'Secular One',
                          fontSize: 18,
                          color: selected ? AppColors.yellow : AppColors.cream,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        priceNote,
                        style: TextStyle(
                          color: AppColors.cream.withValues(alpha: .6),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({
    required this.width,
    required this.height,
    required this.alpha,
  });

  final double width;
  final double height;
  final double alpha;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.cream.withValues(alpha: alpha),
          borderRadius: BorderRadius.circular(6),
        ),
      );
}

/// A status line in the popup: coral for failures, yellow for warnings,
/// turquoise for information. Each carries its own sign, not just a color.
class _Notice extends StatelessWidget {
  const _Notice.error(this.text)
      : color = AppColors.coral,
        ink = const Color(0xFF3B1214),
        textColor = const Color(0xFFFFD9D9),
        sign = '!',
        alert = true;
  const _Notice.warning(this.text)
      : color = AppColors.yellow,
        ink = AppColors.night,
        textColor = const Color(0xFFFFF0C2),
        sign = '!',
        alert = false;
  const _Notice.info(this.text)
      : color = AppColors.turquoise,
        ink = const Color(0xFF0E2B2A),
        textColor = const Color(0xFFCFF7F1),
        sign = 'i',
        alert = false;

  final String text;
  final Color color;
  final Color ink;
  final Color textColor;
  final String sign;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: alert ? .14 : .12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Text(
                sign,
                style: TextStyle(
                  color: ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Included extends StatelessWidget {
  const _Included(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: AppColors.turquoise,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded,
              size: 15, color: Color(0xFF0E2B2A)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? .35 : 1,
      child: Material(
        color: AppColors.cream.withValues(alpha: .08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.cream.withValues(alpha: .16)),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.close_rounded,
                size: 18,
                color: AppColors.cream,
                semanticLabel: context.l10n.close),
          ),
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.label, this.screen);

  final String label;
  final Widget Function() screen;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => screen()),
      ),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.cream.withValues(alpha: .7),
        minimumSize: const Size(44, 44),
        textStyle: const TextStyle(fontSize: 12),
      ),
      child: Text(label),
    );
  }
}
