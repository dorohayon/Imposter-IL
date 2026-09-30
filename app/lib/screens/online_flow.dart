import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../monetization/monetization.dart';
import '../monetization/monetization_config.dart';
import '../monetization/purchase_sheet.dart';
import '../state/game_session.dart';
import '../state/sounds.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';
import 'live_room.dart';
import 'private_flow.dart';
import 'secondary_screens.dart';

const _allId = '';

String searchErrorMessage(String code) => switch (code) {
      'already_in_activity' => l10n.errAlreadyInActivity,
      'content_unavailable' => l10n.errContentUnavailable,
      'category_locked' => lockedCategoryMessage,
      _ => connectionMessage(code),
    };

/// The server refused a category this device believes it owns, and a fresh
/// sync did not help.
String get lockedCategoryMessage => l10n.errCategoryLocked;

/// "אפשר לבחור כמה קטגוריות", with how many are open (design 04).
String categoryHint(Monetization m, Iterable<String> ids) {
  final base = l10n.canPickSeveral;
  if (m.premium) return base;
  final open = m.unlocked(ids).length;
  final onlyFree = ids.where(m.isUnlocked).every(m.isFree);
  return '$base · ${onlyFree ? l10n.openFreeCount(open) : l10n.openCount(open)}';
}

/// Online play: choose categories, then search on the server.
class CategorySelectionScreen extends StatefulWidget {
  const CategorySelectionScreen({super.key});

  @override
  State<CategorySelectionScreen> createState() =>
      _CategorySelectionScreenState();
}

class _CategorySelectionScreenState extends State<CategorySelectionScreen> {
  Set<String>? _selected; // null: every category
  bool _busy = false;

  Future<void> _search(List<String> ids) async {
    final session = SessionScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final code = await session.startSearch(ids);
    if (!mounted) return;
    setState(() => _busy = false);
    if (code != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(searchErrorMessage(code))),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LiveRoomScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final money = MonetizationScope.of(context);
    final categories = session.categories;
    if (categories.isEmpty &&
        (session.contentError != null || session.contentLoaded)) {
      return ServerErrorScreen(
        onRetry: () async {
          try {
            await SessionScope.read(context).loadContent();
          } on Object {
            // The screen stays visible so the player can retry or go home.
          }
        },
        onHome: () => Navigator.of(context).popUntil((route) => route.isFirst),
      );
    }
    final allIds = [for (final c in categories) c.id];
    // null is "הכול": every open category, shown as that one tile rather than
    // by lighting all of them up. A non-null set is an explicit choice and may
    // be empty, which disables the search button. A category that locked
    // again meanwhile (a subscription ended) drops out of the choice.
    final all = _selected == null;
    final selected = {...?_selected}
      ..removeWhere((id) => !money.isUnlocked(id));

    void toggle(String id) => setState(() {
          if (id == _allId) {
            _selected = all ? <String>{} : null;
            return;
          }
          // Leaving "הכול" starts a fresh choice of just this category.
          final next = all ? <String>{id} : {...selected};
          if (!all && !next.remove(id)) next.add(id);
          _selected = next;
        });

    final tiles = [
      (id: _allId, name: context.l10n.all),
      for (final c in money.openFirst(categories, (c) => c.id))
        (id: c.id, name: c.name),
    ];

    return GameScaffold(
      title: context.l10n.chooseCategories,
      bannerPlacement: BannerPlacement.categories,
      bottom: PrimaryButton(
        label: _busy ? context.l10n.searchingGame : context.l10n.searchGame,
        // Nothing chosen means nothing to search for.
        onPressed: categories.isEmpty || _busy || (!all && selected.isEmpty)
            ? null
            : () => _search([
                  for (final id in allIds)
                    if (all ? money.isUnlocked(id) : selected.contains(id)) id,
                ]),
      ),
      child: categories.isEmpty
          ? Padding(
              padding: EdgeInsets.only(top: 180),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: AppColors.yellow),
                    SizedBox(height: 18),
                    Text(
                      context.l10n.loadingCategories,
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        categoryHint(money, allIds),
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 14),
                      ),
                    ),
                    if (money.premium) const PremiumBadge(),
                  ],
                ),
                const SizedBox(height: 14),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: tiles.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    // A row for the corner marks, then two lines of name.
                    mainAxisExtent: 108,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) {
                    final tile = tiles[index];
                    final locked =
                        tile.id != _allId && !money.isUnlocked(tile.id);
                    if (locked) {
                      return LockedCategoryTile(
                        name: tile.name,
                        onTap: () => openLockedCategory(
                          context,
                          categoryId: tile.id,
                          categoryName: tile.name,
                          // "הכול" already includes it once it opens.
                          onSelect: () {
                            if (!all) toggle(tile.id);
                          },
                        ),
                      );
                    }
                    final isSelected =
                        tile.id == _allId ? all : selected.contains(tile.id);
                    final purchased = !isSelected && money.isPurchased(tile.id);
                    return Semantics(
                      selected: isSelected,
                      button: true,
                      child: InkWell(
                        onTap: withClick(() => toggle(tile.id)),
                        borderRadius: BorderRadius.circular(18),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.yellow
                                : AppColors.nightSoft,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.yellow
                                  : const Color(0xFF4A4860),
                              width: 2,
                            ),
                          ),
                          child: _TileBody(
                            name: tile.name,
                            color:
                                isSelected ? AppColors.night : AppColors.cream,
                            start: isSelected
                                ? const _SelectedCategoryCheck()
                                : purchased
                                    ? const _PurchasedTag()
                                    : null,
                            end: tile.id == _allId
                                ? Text(
                                    money.premium
                                        ? context.l10n.allCategories
                                        : context.l10n.allOpenCategories,
                                    textAlign: TextAlign.end,
                                    maxLines: 2,
                                    style: TextStyle(
                                      color: isSelected
                                          ? AppColors.night
                                              .withValues(alpha: .7)
                                          : AppColors.muted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  )
                                : Icon(
                                    categoryIcon(tile.id),
                                    size: 24,
                                    color: isSelected
                                        ? AppColors.night
                                        : AppColors.turquoise,
                                  ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }
}

/// "פרימיום", next to the category hint for Premium players (design 04).
class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.yellow.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.yellow.withValues(alpha: .5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 12, color: AppColors.yellow),
          SizedBox(width: 5),
          Text(
            context.l10n.premium,
            style: TextStyle(
              color: AppColors.yellow,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// An open category's icon on its tile.
IconData categoryIcon(String id) => switch (id) {
      'food' => Icons.restaurant_rounded,
      'animals' => Icons.pets_rounded,
      'home' => Icons.chair_rounded,
      'school_students' => Icons.school_rounded,
      'work_office' => Icons.work_rounded,
      'technology_digital' => Icons.devices_rounded,
      'travel_vacation' => Icons.flight_rounded,
      'places' => Icons.public_rounded,
      'dating_relationships' => Icons.favorite_rounded,
      'nightlife' => Icons.nightlife_rounded,
      'fashion_grooming' => Icons.checkroom_rounded,
      'gaming' => Icons.sports_esports_rounded,
      'music' => Icons.music_note_rounded,
      'nostalgia' => Icons.history_rounded,
      'internet_culture' => Icons.alternate_email_rounded,
      'superheroes_fantasy' => Icons.auto_awesome_rounded,
      'israeli_slang' => Icons.record_voice_over_rounded,
      'idf_service' => Icons.military_tech_rounded,
      'film_tv' => Icons.movie_rounded,
      'sports' => Icons.sports_soccer_rounded,
      'nature_weather' => Icons.landscape_rounded,
      'transportation' => Icons.directions_car_rounded,
      'hobbies_free_time' => Icons.palette_rounded,
      _ => Icons.category_rounded,
    };

/// A category's name on its tile: a name of several words breaks before its
/// last word, so every tile holds its name on the same lines and the bottom
/// line sits in the same place ("מקצועות" / "ועבודה").
String categoryTileName(String name) {
  final i = name.lastIndexOf(' ');
  return i < 0 ? name : '${name.substring(0, i)}\n${name.substring(i + 1)}';
}

/// A category tile's inside: a row for the corner marks, the name under it.
/// Nothing is drawn over the name, in any language.
class _TileBody extends StatelessWidget {
  const _TileBody({
    required this.name,
    required this.color,
    this.start,
    this.end,
  });

  /// Shown with a break before its last word, as the design does
  /// (categoryTileName), or wrapped where it falls when that does not fit.
  final String name;
  final Color color;
  final Widget? start;
  final Widget? end;

  static const _markRow = 28.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // At least the row's height, and more for "All unlocked categories"
        // on two lines, which a fixed height cut at the bottom. The name sits
        // at the tile's bottom, so it stays in line with the other tiles.
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _markRow),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (start case final mark?) mark,
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.topEnd,
                  heightFactor: 1,
                  child: end,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final (text, size) = _fit(context, box);
              return Align(
                alignment: AlignmentDirectional.bottomStart,
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontFamily: 'Secular One',
                    fontSize: size,
                    height: 1.1,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// The largest size, 20 down to 13, at which the name keeps to two lines,
  /// fits the height and breaks no word in the middle: the design's break
  /// first, then the natural one.
  (String, double) _fit(BuildContext context, BoxConstraints box) {
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    for (var size = 20.0; size > 13; size -= 1) {
      // Measured as drawn: the theme's text style under the name's own.
      TextPainter paint(String text, {int? lines}) => TextPainter(
            text: TextSpan(
              text: text,
              style: DefaultTextStyle.of(context).style.merge(TextStyle(
                  fontFamily: 'Secular One', fontSize: size, height: 1.1)),
            ),
            textDirection: direction,
            textScaler: scaler,
            maxLines: lines,
          );
      final wordsFit = name
          .split(RegExp(r'\s+'))
          .every((w) => (paint(w)..layout()).width <= box.maxWidth);
      if (!wordsFit) continue;
      for (final text in {categoryTileName(name), name}) {
        final whole = paint(text, lines: 2)..layout(maxWidth: box.maxWidth);
        if (!whole.didExceedMaxLines && whole.height <= box.maxHeight) {
          return (text, size);
        }
      }
    }
    return (name, 13);
  }
}

/// A category that is visible but locked: a lock and a dimmed name. Tapping
/// it opens the purchase popup (design 04).
class LockedCategoryTile extends StatelessWidget {
  const LockedCategoryTile({
    required this.name,
    required this.onTap,
    super.key,
  });

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.lockedTapToOpen(name),
      excludeSemantics: true,
      child: InkWell(
        onTap: withClick(onTap),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: AppColors.cream.withValues(alpha: .035),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.cream.withValues(alpha: .1),
              width: 2,
            ),
          ),
          child: _TileBody(
            name: name,
            color: AppColors.cream.withValues(alpha: .62),
            end: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.yellow.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: AppColors.yellow.withValues(alpha: .45),
                ),
              ),
              child: const Icon(Icons.lock_rounded,
                  color: AppColors.yellow, size: 15),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedCategoryCheck extends StatelessWidget {
  const _SelectedCategoryCheck();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.night,
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Icon(Icons.check_rounded, size: 14, color: AppColors.yellow),
    );
  }
}

class _PurchasedTag extends StatelessWidget {
  const _PurchasedTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.turquoise.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.turquoise.withValues(alpha: .4)),
      ),
      child: Text(
        context.l10n.purchasedTag,
        style: TextStyle(
          color: Color(0xFF8FF3E6),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
