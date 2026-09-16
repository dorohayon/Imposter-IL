import 'package:flutter/material.dart';

import '../state/game_session.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';
import 'live_room.dart';
import 'private_flow.dart';
import 'secondary_screens.dart';

const _categoryIcons = {
  'food': Icons.restaurant_rounded,
  'animals': Icons.pets_rounded,
  'sports': Icons.sports_soccer_rounded,
  'professions': Icons.work_rounded,
  'places': Icons.public_rounded,
  'objects': Icons.umbrella_rounded,
};

const _allId = '';

String searchErrorMessage(String code) => switch (code) {
      'already_in_activity' => 'כבר הצטרפתם למשחק או לחדר אחר.',
      'content_unavailable' => 'אי אפשר להתחיל משחק כרגע. נסו שוב בעוד רגע.',
      _ => connectionMessage(code),
    };

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
        onHome: () => Navigator.of(context).pop(),
      );
    }
    final allIds = [for (final c in categories) c.id];
    // null is "הכול": every category, shown as that one tile rather than by
    // lighting all of them up. A non-null set is an explicit choice and may be
    // empty, which disables the search button.
    final all = _selected == null;
    final selected = _selected ?? const <String>{};

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
      bottom: PrimaryButton(
        label: _busy ? 'מחפשים משחק...' : 'חפש משחק',
        // Nothing chosen means nothing to search for.
        onPressed: categories.isEmpty || _busy || (!all && selected.isEmpty)
            ? null
            : () => _search([
                  for (final id in allIds)
                    if (all || selected.contains(id)) id,
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
                const Text(
                  'אפשר לבחור כמה קטגוריות',
                  style: TextStyle(color: AppColors.muted, fontSize: 14),
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
                    final isSelected =
                        tile.id == _allId ? all : selected.contains(tile.id);
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
