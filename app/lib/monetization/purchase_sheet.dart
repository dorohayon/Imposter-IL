import 'dart:async';

import 'package:flutter/material.dart';

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
  return '${open.length} ${open.every(m.isFree) ? 'פתוחות בחינם' : 'פתוחות'}';
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
      label: '$label — נעולה, לחצו לפתיחה',
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
const _soft = Color(0xB8FFF8E7); // cream at ~72%

class _PurchaseSheetState extends State<_PurchaseSheet> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final m = MonetizationScope.of(context);
    final offer = m.offerFor(widget.id);
    final available = [
      for (final id in offer)
        if (m.products.containsKey(id)) id,
    ];
    // The first option is chosen for them: the category they tapped, or the
    // first product the store actually sells.
    final selected = available.contains(_selected)
        ? _selected!
        : available.isEmpty
            ? offer.first
            : available.first;
    final step = m.step;
    final loading = m.productsLoading;
    final pricesFailed = !loading && m.productsFailed;
    final succeeded =
        step == PurchaseStep.purchased || step == PurchaseStep.restored;

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
                      : _choose(
                          m, offer, available, selected, loading, pricesFailed),
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
    String selected,
    bool loading,
    bool pricesFailed,
  ) {
    final notice = switch (m.step) {
      _ when pricesFailed => const _Notice.error(
          'לא הצלחנו לטעון את המחירים מהחנות. בדקו את החיבור לאינטרנט ונסו שוב.'),
      PurchaseStep.cancelled =>
        const _Notice.warning('הרכישה בוטלה. לא בוצע חיוב.'),
      PurchaseStep.failed => const _Notice.error(
          'הרכישה לא הושלמה ולא בוצע חיוב. בדקו את החיבור לאינטרנט ונסו שוב.'),
      PurchaseStep.pending => _Notice.warning(
          'הרכישה ממתינה לאישור. ״${widget.name}״ תיפתח ברגע שהתשלום יאושר.'),
      PurchaseStep.restoreNone =>
        const _Notice.info('לא נמצאו רכישות קודמות בחשבון החנות הזה.'),
      PurchaseStep.restoredOther =>
        _Notice.info('הרכישות שוחזרו, אבל ״${widget.name}״ לא נמצאה ביניהן.'),
      PurchaseStep.restoreFailed => const _Notice.error(
          'השחזור לא הושלם. בדקו את החיבור לאינטרנט ונסו שוב.'),
      _ when !m.config.purchasesEnabled => const _Notice.warning(
          'הרכישות אינן זמינות כרגע. אפשר לשחזר רכישות קודמות.'),
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
                          '״${widget.name}״ נעולה',
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
                  const Text(
                    'בחרו איך לפתוח אותה',
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
        for (final id in loading ? offer : available) ...[
          _Option(
            title: _title(m, id),
            description: _description(m, id),
            price: m.products[id]?.price,
            priceNote: id == m.config.premiumMonthly ? 'לחודש' : 'תשלום אחד',
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

  String _title(Monetization m, String id) => id == m.config.premiumMonthly
      ? 'פרימיום חודשי'
      : id == m.config.premiumLifetime
          ? 'פרימיום לכל החיים'
          : 'רק ״${widget.name}״';

  String _description(Monetization m, String id) => id ==
          m.config.premiumMonthly
      ? 'כל הקטגוריות ותכונות הפרימיום, בלי פרסומות — כל עוד המנוי פעיל'
      : id == m.config.premiumLifetime
          ? 'כל הקטגוריות, גם אלה שיתווספו בעתיד, ותכונות הפרימיום. בלי פרסומות לתמיד'
          : 'פתוחה לתמיד · הפרסומות נשארות';

  Widget _success(Monetization m, PurchaseStep step) {
    final product = m.flowProduct;
    final premium = step == PurchaseStep.purchased &&
        (product == m.config.premiumMonthly ||
            product == m.config.premiumLifetime);
    final (title, body) = step == PurchaseStep.restored
        ? ('הרכישות שוחזרו', '״${widget.name}״ פתוחה שוב במכשיר הזה.')
        : premium
            ? (
                'ברוכים הבאים לפרימיום',
                product == m.config.premiumMonthly
                    ? 'המנוי החודשי פעיל. אפשר לנהל או לבטל אותו בהגדרות המנויים בחנות.'
                    : m.monthlyBeforePurchase
                        ? 'הכול פתוח לתמיד — כולל קטגוריות שיתווספו בעתיד. המנוי החודשי שלכם עדיין פעיל; אפשר לבטל אותו בהגדרות המנויים בחנות.'
                        : 'הכול פתוח לתמיד — כולל קטגוריות שיתווספו בעתיד.',
              )
            : (
                '״${widget.name}״ נפתחה!',
                'הקטגוריה שלכם לתמיד. הפרסומות ממשיכות להופיע.',
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
              child: const Column(
                children: [
                  _Included('כל הקטגוריות פתוחות'),
                  SizedBox(height: 10),
                  _Included('תכונות הפרימיום פעילות'),
                  SizedBox(height: 10),
                  _Included('בלי באנרים ובלי מודעות במסך מלא'),
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
      child = PrimaryButton(
        label: m.step == PurchaseStep.restored
            ? 'סגירה'
            : premium
                ? 'מתחילים לשחק'
                : 'בוחרים ב״${widget.name}״',
        onPressed: () => Navigator.of(context).pop(categoryBought),
      );
    } else {
      final (label, onPressed) = switch (m.step) {
        _ when loading => ('טוענים מחירים…', null),
        _ when pricesFailed => (
            'ניסיון נוסף',
            () => unawaited(m.loadProducts(widget.id)),
          ),
        PurchaseStep.processing => ('מתחברים לחנות…', null),
        PurchaseStep.restoring => (_ctaFor(m, selected, p), null),
        PurchaseStep.failed => ('ניסיון נוסף', () => m.buy(selected)),
        _ => (_ctaFor(m, selected, p), () => m.buy(selected)),
      };
      final canBuy = m.config.purchasesEnabled && anyProduct;
      final disclosure = loading
          ? 'המחירים מוצגים במטבע של חשבון החנות שלכם.'
          : m.step == PurchaseStep.processing
              ? 'ממשיכים בחלון התשלום של החנות. אין לסגור את האפליקציה.'
              : !anyProduct
                  ? ''
                  : selected == m.config.premiumMonthly
                      ? 'המנוי מתחדש אוטומטית ב־$p בכל חודש עד לביטול. אפשר לבטל בכל עת בהגדרות המנויים בחנות, לפחות 24 שעות לפני מועד החידוש.'
                      : isCategory
                          ? 'תשלום אחד של $p דרך החנות. ״${widget.name}״ נשארת פתוחה לתמיד; הפרסומות ממשיכות להופיע.'
                          : 'תשלום אחד של $p דרך החנות. בלי מנוי ובלי חיובים נוספים.';
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
          Wrap(
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
                    ? 'משחזרים רכישות…'
                    : 'שחזור רכישות'),
              ),
              _Link('תנאי שימוש', () => const TermsScreen()),
              _Link('מדיניות פרטיות', () => const PrivacyScreen()),
            ],
          ),
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

  String _ctaFor(Monetization m, String selected, String p) =>
      selected == m.config.premiumMonthly ? 'הצטרפות לפרימיום' : 'קנייה · $p';
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
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.close_rounded,
                size: 18, color: AppColors.cream, semanticLabel: 'סגירה'),
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
