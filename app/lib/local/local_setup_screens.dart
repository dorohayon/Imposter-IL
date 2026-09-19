import 'package:flutter/material.dart';

import '../models/player.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';
import 'local_game.dart';
import 'local_screens.dart';
import 'words.g.dart';

/// Screen 03: who is playing. A stepper, a name each, and an avatar each.
class LocalPlayersScreen extends StatefulWidget {
  const LocalPlayersScreen({super.key});

  @override
  State<LocalPlayersScreen> createState() => _LocalPlayersScreenState();
}

class _LocalPlayersScreenState extends State<LocalPlayersScreen> {
  static const _defaultCount = 4;

  final _names = <TextEditingController>[];
  final _avatars = <String>[];

  @override
  void initState() {
    super.initState();
    _setCount(_defaultCount);
  }

  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  void _setCount(int count) {
    while (_names.length < count) {
      final seat = _names.length + 1;
      _names.add(TextEditingController(text: 'שחקן $seat'));
      _avatars.add(
        avatarAssets.firstWhere((avatar) => !_avatars.contains(avatar)),
      );
    }
    while (_names.length > count) {
      _names.removeLast().dispose();
      _avatars.removeLast();
    }
  }

  List<String?> get _problems {
    final trimmed = [for (final c in _names) c.text.trim()];
    return [
      for (final name in trimmed)
        if (name.isEmpty)
          'לכל שחקן צריך להיות שם'
        else if (trimmed.where((other) => other == name).length > 1)
          'לכל שחקן צריך להיות שם שונה'
        else
          null,
    ];
  }

  Future<void> _pickAvatar(int seat) async {
    final taken = {..._avatars}..remove(_avatars[seat]);
    final free = [
      for (final a in avatarAssets)
        if (!taken.contains(a)) a,
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.nightRaised,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              for (final asset in free)
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(asset),
                  child: AvatarView(
                    asset: asset,
                    size: 56,
                    selected: asset == _avatars[seat],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _avatars[seat] = picked);
  }

  @override
  Widget build(BuildContext context) {
    final problems = _problems;
    return GameScaffold(
      title: 'משחק במכשיר אחד',
      bottom: PrimaryButton(
        label: 'המשך להגדרות',
        onPressed: problems.any((problem) => problem != null)
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LocalRulesScreen(
                      players: [
                        for (var i = 0; i < _names.length; i++)
                          LocalPlayer(
                            name: _names[i].text.trim(),
                            avatar: _avatars[i],
                          ),
                      ],
                    ),
                  ),
                ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Illustration('assets/illustrations/local-one-device.webp',
              height: 130),
          const SizedBox(height: 12),
          Text('מי משחק?', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 6),
          const Text(
            'מכשיר אחד עובר בין כולם. הרמזים נאמרים בקול.',
            style: TextStyle(color: AppColors.muted, height: 1.45),
          ),
          const SizedBox(height: 16),
          _Stepper(
            count: _names.length,
            onChanged: (n) => setState(() => _setCount(n)),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < _names.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => _pickAvatar(i),
                    child: AvatarView(asset: _avatars[i], size: 44),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _names[i],
                      textAlign: TextAlign.start,
                      style: const TextStyle(
                        color: AppColors.night,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLength: 18,
                      decoration: InputDecoration(
                        counterText: '',
                        errorText: problems[i],
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'לחיצה על אווטאר מחליפה אותו באחד שלא בשימוש.',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.count, required this.onChanged});

  final int count;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cream.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: count > LocalGame.minPlayers
                ? () => onChanged(count - 1)
                : null,
            icon: const Icon(Icons.remove_rounded),
            tooltip: 'פחות שחקנים',
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '$count שחקנים',
                  maxLines: 1,
                  style: const TextStyle(
                    fontFamily: 'Secular One',
                    fontSize: 21,
                  ),
                ),
                const Text(
                  '${LocalGame.minPlayers}–${LocalGame.maxPlayers}',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: count < LocalGame.maxPlayers
                ? () => onChanged(count + 1)
                : null,
            icon: const Icon(Icons.add_rounded),
            tooltip: 'עוד שחקנים',
          ),
        ],
      ),
    );
  }
}

/// Screen 05: the rules of this match — categories and how long a hint gets.
class LocalRulesScreen extends StatefulWidget {
  const LocalRulesScreen({
    required this.players,
    this.initialCategoryIds,
    this.initialHintSeconds = 30,
    super.key,
  });

  final List<LocalPlayer> players;
  final List<String>? initialCategoryIds;
  final int? initialHintSeconds;

  @override
  State<LocalRulesScreen> createState() => _LocalRulesScreenState();
}

class _LocalRulesScreenState extends State<LocalRulesScreen> {
  /// Null means every category. An empty set is deliberately different: no
  /// category is selected and the match cannot start.
  Set<String>? _categories;
  late int? _hintSeconds;

  static const _times = <int?>[20, 30, 45, 60, null];

  @override
  void initState() {
    super.initState();
    final allIds = {for (final c in localCategories) c.id};
    final initial = widget.initialCategoryIds?.toSet();
    _categories =
        initial == null || initial.containsAll(allIds) ? null : {...initial};
    _hintSeconds = widget.initialHintSeconds;
  }

  List<String> get _chosen => _categories == null
      ? [for (final c in localCategories) c.id]
      : _categories!.toList();

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'הגדרות המשחק',
      bottom: PrimaryButton(
        label: 'מתחילים',
        onPressed: _categories?.isEmpty ?? false
            ? null
            : () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => LocalGameScreen(
                      players: widget.players,
                      categoryIds: _chosen,
                      hintSeconds: _hintSeconds,
                    ),
                  ),
                ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('קטגוריות',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(
                label: 'הכול',
                selected: _categories == null,
                onTap: () => setState(() {
                  _categories = _categories == null ? <String>{} : null;
                }),
              ),
              for (final c in localCategories)
                _Chip(
                  label: c.name,
                  selected: _categories?.contains(c.id) ?? false,
                  onTap: () => setState(() {
                    final next = _categories == null
                        ? <String>{c.id}
                        : {..._categories!};
                    if (!next.remove(c.id)) next.add(c.id);
                    _categories = next;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('זמן לכל רמז',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final seconds in _times)
                _Chip(
                  label: seconds == null ? 'ללא טיימר' : '$seconds',
                  selected: _hintSeconds == seconds,
                  onTap: () => setState(() => _hintSeconds = seconds),
                ),
            ],
          ),
          const SizedBox(height: 20),
          InfoCard(
            label: 'סיכום',
            child: Column(
              children: [
                _SummaryRow('שחקנים', '${widget.players.length}'),
                _SummaryRow(
                  'קטגוריות',
                  _categories == null
                      ? 'הכול'
                      : localCategories
                          .where((c) => _categories!.contains(c.id))
                          .map((c) => c.name)
                          .join(', '),
                ),
                _SummaryRow(
                  'זמן לרמז',
                  _hintSeconds == null ? 'ללא טיימר' : '$_hintSeconds שניות',
                ),
                const _SummaryRow('מתחזים', 'מתחזה אחד'),
                const _SummaryRow('הצבעה', 'הצבעה פרטית במכשיר'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.start,
              style: const TextStyle(color: AppColors.muted),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      backgroundColor: AppColors.cream.withValues(alpha: .07),
      selectedColor: AppColors.yellow,
      labelStyle: TextStyle(
        color: selected ? AppColors.night : AppColors.cream,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.cream.withValues(alpha: .12)),
      ),
    );
  }
}
