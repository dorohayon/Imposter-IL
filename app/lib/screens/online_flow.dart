import 'package:flutter/material.dart';

import '../models/player.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';
import 'game_flow.dart';

class CategorySelectionScreen extends StatefulWidget {
  const CategorySelectionScreen({super.key});

  @override
  State<CategorySelectionScreen> createState() => _CategorySelectionScreenState();
}

class _CategorySelectionScreenState extends State<CategorySelectionScreen> {
  static const categories = <({String name, IconData icon})>[
    (name: 'הכול', icon: Icons.auto_awesome_rounded),
    (name: 'אוכל', icon: Icons.restaurant_rounded),
    (name: 'חיות', icon: Icons.pets_rounded),
    (name: 'ספורט', icon: Icons.sports_soccer_rounded),
    (name: 'מקומות', icon: Icons.public_rounded),
    (name: 'מקצועות', icon: Icons.work_rounded),
  ];
  final selected = <String>{'הכול'};

  void _toggle(String name) {
    setState(() {
      if (name == 'הכול') {
        selected
          ..clear()
          ..add('הכול');
      } else {
        selected.remove('הכול');
        selected.contains(name) ? selected.remove(name) : selected.add(name);
        if (selected.isEmpty) selected.add('הכול');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('בחירת קטגוריות'),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: PrimaryButton(
          label: 'חפש משחק',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const MatchmakingScreen()),
          ),
        ),
      ),
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          itemCount: categories.length + 1,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 178,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
          ),
          itemBuilder: (context, index) {
            if (index == 0) {
              return const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'אפשר לבחור כמה קטגוריות',
                  style: TextStyle(color: AppColors.muted, fontSize: 17),
                ),
              );
            }
            final category = categories[index - 1];
            final isSelected = selected.contains(category.name);
            return Semantics(
              selected: isSelected,
              button: true,
              child: InkWell(
                onTap: () => _toggle(category.name),
                borderRadius: BorderRadius.circular(26),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.yellow : AppColors.nightSoft,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: isSelected ? AppColors.yellow : const Color(0xFF4A4860),
                      width: 2,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: Icon(
                          isSelected ? Icons.check_circle_rounded : category.icon,
                          color: isSelected ? AppColors.night : AppColors.turquoise,
                          size: 36,
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Text(
                          category.name,
                          style: TextStyle(
                            color: isSelected ? AppColors.night : AppColors.cream,
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

class MatchmakingScreen extends StatelessWidget {
  const MatchmakingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'מחפשים שחקנים',
      onExit: () => Navigator.of(context).pop(),
      bottom: PrimaryButton(
        label: 'ביטול',
        secondary: true,
        onPressed: () => Navigator.of(context).pop(),
      ),
      child: Column(
        children: [
          const Illustration('assets/illustrations/matchmaking-team.webp', height: 180),
          Text('6 מתוך 8', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 6),
          const Text(
            'מצאנו שישה! מחכים עד 30 שניות לעוד שני שחקנים',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 16),
          ),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 8,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisExtent: 112,
              mainAxisSpacing: 12,
              crossAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              if (index >= demoPlayers.length) {
                return Column(
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF5C586E), width: 2),
                      ),
                      child: const Icon(Icons.search_rounded, color: AppColors.muted),
                    ),
                    const SizedBox(height: 7),
                    const Text('מחפשים...', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                );
              }
              final player = demoPlayers[index];
              return Column(
                children: [
                  AvatarView(asset: player.avatar, size: 68),
                  const SizedBox(height: 7),
                  Text(player.nickname, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'התחלת משחק',
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(builder: (_) => const RoleRevealScreen(isImpostor: false)),
            ),
          ),
        ],
      ),
    );
  }
}
