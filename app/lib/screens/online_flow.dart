import 'package:flutter/material.dart';

import '../state/game_session.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';
import 'live_room.dart';
import 'private_flow.dart';

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
      'already_in_activity' => 'אתם עדיין במשחק או בחדר אחר',
      'content_unavailable' => 'השרת עדיין לא מוכן להתחלת משחקים',
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
    final categories = SessionScope.of(context).categories;
    final allIds = [for (final c in categories) c.id];
    final selected = _selected ?? allIds.toSet();

    void toggle(String id) => setState(() {
          if (id == _allId) {
            _selected = null;
            return;
          }
          final next = {...selected};
          if (!next.remove(id)) next.add(id);
          if (next.isNotEmpty) _selected = next; // keep at least one
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('בחירת קטגוריות'),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: PrimaryButton(
          label: _busy ? 'מתחילים חיפוש...' : 'חפש משחק',
          onPressed: categories.isEmpty || _busy
              ? null
              : () => _search([
                    for (final id in allIds)
                      if (selected.contains(id)) id,
                  ]),
        ),
      ),
      body: SafeArea(
        child: categories.isEmpty
            ? const Center(
                child: Text(
                  'טוענים קטגוריות...',
                  style: TextStyle(color: AppColors.muted),
                ),
              )
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                itemCount: tiles.length + 1,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 178,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                ),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return const Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'אפשר לבחור כמה קטגוריות',
                        style: TextStyle(color: AppColors.muted, fontSize: 17),
                      ),
                    );
                  }
                  final tile = tiles[index - 1];
                  final isSelected = tile.id == _allId
                      ? selected.length == allIds.length
                      : selected.contains(tile.id);
                  return Semantics(
                    selected: isSelected,
                    button: true,
                    child: InkWell(
                      onTap: () => toggle(tile.id),
                      borderRadius: BorderRadius.circular(26),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.yellow
                              : AppColors.nightSoft,
                          borderRadius: BorderRadius.circular(26),
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
                                size: 36,
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
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
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
      ),
    );
  }
}
