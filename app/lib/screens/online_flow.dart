import 'package:flutter/material.dart';

import '../monetization/monetization.dart';
import '../monetization/monetization_config.dart';
import '../monetization/purchase_sheet.dart';
import '../state/game_session.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';
import 'live_room.dart';
import 'private_flow.dart';
import 'secondary_screens.dart';

const _categoryIcons = {
  'food': Icons.restaurant_rounded,
  'home': Icons.home_rounded,
  'school_students': Icons.school_rounded,
  'work_office': Icons.work_rounded,
  'technology_digital': Icons.devices_rounded,
  'travel_vacation': Icons.flight_takeoff_rounded,
  'places': Icons.public_rounded,
  'dating_relationships': Icons.favorite_rounded,
  'nightlife': Icons.nightlife_rounded,
  'weddings_events': Icons.celebration_rounded,
  'fashion_grooming': Icons.checkroom_rounded,
  'gaming': Icons.sports_esports_rounded,
  'music': Icons.music_note_rounded,
  'nostalgia': Icons.history_rounded,
  'israeli_slang': Icons.forum_rounded,
  'idf_service': Icons.military_tech_rounded,
  'film_tv': Icons.movie_rounded,
  'sports': Icons.fitness_center_rounded,
};

const _allId = '';

String searchErrorMessage(String code) => switch (code) {
      'already_in_activity' => 'כבר הצטרפתם למשחק או לחדר אחר.',
      'content_unavailable' => 'אי אפשר להתחיל משחק כרגע. נסו שוב בעוד רגע.',
      'category_locked' => lockedCategoryMessage,
      _ => connectionMessage(code),
    };

/// The server refused a category this device believes it owns, and a fresh
/// sync did not help.
const lockedCategoryMessage =
    'אחת הקטגוריות נעולה. אפשר לשחזר רכישות מחלון הפתיחה של הקטגוריה.';

/// "אפשר לבחור כמה קטגוריות", with how many are open (design 04).
String categoryHint(Monetization m, Iterable<String> ids) {
  const base = 'אפשר לבחור כמה קטגוריות';
  if (m.premium) return base;
  final open = m.unlocked(ids).length;
  final onlyFree = ids.where(m.isUnlocked).every(m.isFree);
  return '$base · $open ${onlyFree ? 'פתוחות בחינם' : 'פתוחות'}';
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
      (id: _allId, name: 'הכול', icon: Icons.auto_awesome_rounded),
      for (final c in categories)
        (
          id: c.id,
          name: c.name,
          icon: _categoryIcons[c.id] ?? Icons.category_rounded,
        ),
    ];

    return GameScaffold(
      title: 'בחירת קטגוריות',
      bannerPlacement: BannerPlacement.categories,
      bottom: PrimaryButton(
        label: _busy ? 'מחפשים משחק...' : 'חפש משחק',
        // Nothing chosen means nothing to search for.
        onPressed: categories.isEmpty || _busy || (!all && selected.isEmpty)
            ? null
            : () => _search([
                  for (final id in allIds)
                    if (all ? money.isUnlocked(id) : selected.contains(id)) id,
                ]),
      ),
      child: categories.isEmpty
          ? const Padding(
              padding: EdgeInsets.only(top: 180),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: AppColors.yellow),
                    SizedBox(height: 18),
                    Text(
                      'טוענים את הקטגוריות...',
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
                    mainAxisExtent: 92,
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
                        onTap: () => toggle(tile.id),
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
                          child: Stack(
                            children: [
                              if (purchased)
                                const Align(
                                  alignment: AlignmentDirectional.topStart,
                                  child: _PurchasedTag(),
                                ),
                              if (tile.id == _allId)
                                Align(
                                  alignment: AlignmentDirectional.bottomEnd,
                                  child: Text(
                                    money.premium
                                        ? 'כל הקטגוריות'
                                        : 'כל הפתוחות',
                                    style: TextStyle(
                                      color: isSelected
                                          ? AppColors.night
                                              .withValues(alpha: .7)
                                          : AppColors.muted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              Align(
                                alignment: AlignmentDirectional.topEnd,
                                child: Icon(
                                  isSelected
                                      ? Icons.check_circle_rounded
                                      : tile.icon,
                                  color: isSelected
                                      ? AppColors.night
                                      : AppColors.turquoise,
                                  size: 24,
                                ),
                              ),
                              Align(
                                alignment: AlignmentDirectional.bottomStart,
                                child: Text(
                                  tile.name,
                                  style: TextStyle(
                                    color: isSelected
                                        ? AppColors.night
                                        : AppColors.cream,
                                    fontFamily: 'Secular One',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
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
      child: const Text(
        'פרימיום',
        style: TextStyle(
          color: AppColors.yellow,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// A category that is visible but locked: a lock, a dimmed name and
/// "לפתיחה". Tapping it opens the purchase popup (design 04).
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
      label: '$name — נעולה, לחצו לפתיחה',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
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
          child: Stack(
            children: [
              Align(
                alignment: AlignmentDirectional.topEnd,
                child: Container(
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
              Align(
                alignment: AlignmentDirectional.bottomStart,
                child: Text(
                  name,
                  style: TextStyle(
                    color: AppColors.cream.withValues(alpha: .62),
                    fontFamily: 'Secular One',
                    fontSize: 20,
                  ),
                ),
              ),
              const Align(
                alignment: AlignmentDirectional.bottomEnd,
                child: Text(
                  'לפתיחה',
                  style: TextStyle(
                    color: AppColors.yellow,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
      child: const Text(
        '✓ נרכשה',
        style: TextStyle(
          color: Color(0xFF8FF3E6),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
