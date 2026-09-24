import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/server.dart';
import '../monetization/monetization.dart';
import '../monetization/monetization_config.dart';
import '../monetization/purchase_sheet.dart';
import '../state/game_session.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';
import 'live_room.dart';

// Private rooms run against the real server (docs/protocol.md).

String connectionMessage(String code) => switch (code) {
      'network_error' => 'אין חיבור לשרת. בדקו את החיבור ונסו שוב.',
      'category_locked' =>
        'אחת הקטגוריות נעולה. אפשר לשחזר רכישות מחלון הפתיחה של הקטגוריה.',
      _ => 'משהו השתבש. נסו שוב בעוד רגע.',
    };

class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'משחק עם חברים',
      bannerPlacement: BannerPlacement.friends,
      child: Column(
        children: [
          const Illustration(
            'assets/illustrations/private-room.webp',
            height: 180,
          ),
          const SizedBox(height: 14),
          _FriendsChoiceCard(
            title: 'יצירת חדר',
            description: 'בוחרים הגדרות, מקבלים קוד ומשתפים עם החברים.',
            icon: Icons.add_home_work_rounded,
            onPressed: () => _open(context, const CreateRoomScreen()),
          ),
          const SizedBox(height: 12),
          _FriendsChoiceCard(
            title: 'הצטרפות לחדר',
            description: 'יש לכם קוד בן שש ספרות? מזינים ונכנסים.',
            icon: Icons.login_rounded,
            onPressed: () => _open(context, const JoinRoomScreen()),
          ),
          const SizedBox(height: 18),
          const Text(
            'המשחק מתאים ל־4 עד 8 שחקנים',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _FriendsChoiceCard extends StatelessWidget {
  const _FriendsChoiceCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.onPressed,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cream,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.yellow,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: AppColors.night),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.night,
                        fontFamily: 'Secular One',
                        fontSize: 21,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: TextStyle(
                        color: AppColors.night.withValues(alpha: .68),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.night),
            ],
          ),
        ),
      ),
    );
  }
}

// The live room replaces create/join, so back from the room leaves it instead
// of reopening a form for a room that already exists.
void _openRoom(BuildContext context) => Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const LiveRoomScreen()),
    );

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  int players = 8;
  int hintSeconds = 60;
  Set<String>? _selected; // null until the categories load: all of them
  bool _busy = false;

  Future<void> _create() async {
    final session = SessionScope.read(context);
    final money = MonetizationScope.read(context);
    setState(() => _busy = true);
    try {
      await session.createRoom(
        maxPlayers: players,
        hintSeconds: hintSeconds,
        categoryIds: [
          for (final c in session.categories)
            // null is "הכול": every category the host has open.
            if (money.isUnlocked(c.id) && (_selected?.contains(c.id) ?? true))
              c.id,
        ],
      );
      if (mounted) _openRoom(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(connectionMessage(e.code))));
    }
  }

  Future<void> _retryCategories() async {
    try {
      await SessionScope.read(context).loadContent();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(connectionMessage(e.code))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = SessionScope.of(context).categories;
    final money = MonetizationScope.of(context);
    // null is "הכול": every open category, shown as that one chip rather than
    // by selecting all of them. A non-null set may be empty, which blocks
    // creating the room — the server needs at least one category. The host's
    // purchases decide what the room may use; guests need none.
    final all = _selected == null;
    final selected = {...?_selected}
      ..removeWhere((id) => !money.isUnlocked(id));
    final loaded = categories.isNotEmpty;

    void toggle(String id) => setState(() {
          // Leaving "הכול" starts a fresh choice of just this category.
          final next = all ? <String>{id} : {...selected};
          if (!all && !next.remove(id)) next.add(id);
          _selected = next;
        });

    return GameScaffold(
      title: 'יצירת חדר',
      bannerPlacement: BannerPlacement.createRoom,
      bottom: PrimaryButton(
        label: _busy ? 'יוצרים חדר...' : 'יצירת חדר',
        onPressed:
            loaded && !_busy && (all || selected.isNotEmpty) ? _create : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'לאחר יצירת החדר, לא יהיה ניתן לשנות את ההגדרות.',
            style: TextStyle(color: AppColors.muted, height: 1.45),
          ),
          const SizedBox(height: 18),
          const Text(
            'מספר שחקנים מרבי',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _OptionRow<int>(
            values: const [4, 5, 6, 7, 8],
            selected: players,
            label: (value) => '$value',
            onSelected: (value) => setState(() => players = value),
          ),
          const SizedBox(height: 18),
          const Text(
            'זמן לרמז',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _OptionRow<int>(
            values: const [30, 60, 90],
            selected: hintSeconds,
            label: (value) => '$value שניות',
            onSelected: (value) => setState(() => hintSeconds = value),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Text(
                'קטגוריות',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 10),
              if (loaded && !money.premium)
                Expanded(
                  child: Text(
                    categoryCount(money, [for (final c in categories) c.id]),
                    textAlign: TextAlign.end,
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!loaded)
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'טוענים קטגוריות...',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ),
                TextButton(
                  onPressed: _retryCategories,
                  child: const Text('ניסיון נוסף'),
                ),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('הכול'),
                  selected: all,
                  onSelected: (_) =>
                      setState(() => _selected = all ? <String>{} : null),
                ),
                for (final c in categories)
                  if (money.isUnlocked(c.id))
                    FilterChip(
                      label: Text(c.name),
                      selected: selected.contains(c.id),
                      onSelected: (_) => toggle(c.id),
                    )
                  else
                    LockedChip(
                      label: c.name,
                      onTap: () => openLockedCategory(
                        context,
                        categoryId: c.id,
                        categoryName: c.name,
                        onSelect: () {
                          if (!all) toggle(c.id);
                        },
                      ),
                    ),
              ],
            ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.yellow.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.yellow.withValues(alpha: .4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_clock_rounded,
                    color: AppColors.yellow, size: 20),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'אחרי ששחקן נוסף יצטרף, אי אפשר יהיה לשנות את ההגדרות.',
                    style: TextStyle(color: Color(0xFFFFF0C2), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionRow<T> extends StatelessWidget {
  const _OptionRow({
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final value in values) ...[
          Expanded(
            child: Semantics(
              selected: value == selected,
              button: true,
              child: InkWell(
                onTap: () => onSelected(value),
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == selected
                        ? AppColors.yellow
                        : AppColors.cream.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: value == selected
                          ? AppColors.yellow
                          : AppColors.cream.withValues(alpha: .14),
                    ),
                  ),
                  child: Text(
                    label(value),
                    style: TextStyle(
                      color:
                          value == selected ? AppColors.night : AppColors.cream,
                      fontWeight: FontWeight.w700,
                      fontSize: values.length > 3 ? 16 : 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (value != values.last) const SizedBox(width: 7),
        ],
      ],
    );
  }
}

class JoinRoomScreen extends StatefulWidget {
  /// Filled in when the player arrived from an invitation link, so the only
  /// thing left to do is confirm.
  const JoinRoomScreen({this.code, super.key});

  final String? code;

  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  late final code = TextEditingController(text: widget.code ?? '');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      await SessionScope.read(context).joinRoom(code.text);
      if (mounted) _openRoom(context);
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = switch (e.code) {
          'invalid_room_code' => 'קוד החדר צריך להיות בן שש ספרות',
          'room_not_found' =>
            'החדר לא נמצא או שאינו זמין. בדקו את הקוד עם מי שפתח את החדר.',
          'room_unavailable' => 'החדר מלא או שהמשחק כבר התחיל.',
          'already_in_activity' => 'כבר הצטרפתם למשחק אחר.',
          _ => connectionMessage(e.code),
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = code.text.length == 6 && !_busy;
    return GameScaffold(
      title: 'הצטרפות לחדר',
      bannerPlacement: BannerPlacement.joinRoom,
      bottom: PrimaryButton(
        label: _error == null ? 'הצטרפות' : 'ניסיון נוסף',
        onPressed: ready ? _join : null,
      ),
      child: Column(
        children: [
          const Text(
            'הזינו את קוד החדר בן שש הספרות שקיבלתם.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 15),
          ),
          const SizedBox(height: 22),
          _CodeBoxes(
            controller: code,
            error: _error != null,
            onChanged: () => setState(() => _error = null),
            onSubmitted: () {
              if (ready) _join();
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            StatusBanner(text: _error!, positive: false),
          ],
          const SizedBox(height: 18),
          _Keypad(
            onDigit: (digit) {
              if (code.text.length < 6) {
                setState(() {
                  _error = null;
                  final text = code.text + digit;
                  code.value = TextEditingValue(
                    text: text,
                    selection: TextSelection.collapsed(offset: text.length),
                  );
                });
              }
            },
            onDelete: code.text.isEmpty
                ? null
                : () => setState(() {
                      _error = null;
                      code.text = code.text.substring(0, code.text.length - 1);
                    }),
          ),
        ],
      ),
    );
  }
}

class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({
    required this.controller,
    required this.error,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool error;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final digits = controller.text.padRight(6).characters.toList();
    return SizedBox(
      height: 72,
      child: Stack(
        children: [
          Row(
            textDirection: TextDirection.ltr,
            children: [
              for (var index = 0; index < 6; index++) ...[
                Expanded(
                  child: Container(
                    height: 70,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.cream,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: error ? AppColors.coral : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Text(
                      digits[index].trim(),
                      style: const TextStyle(
                        color: AppColors.night,
                        fontFamily: 'Secular One',
                        fontSize: 28,
                      ),
                    ),
                  ),
                ),
                if (index < 5) const SizedBox(width: 7),
              ],
            ],
          ),
          Positioned.fill(
            child: Opacity(
              opacity: .01,
              child: TextField(
                controller: controller,
                readOnly: true,
                canRequestFocus: false,
                showCursor: false,
                enableInteractiveSelection: false,
                maxLength: 6,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  counterText: '',
                ),
                onChanged: (_) => onChanged(),
                onSubmitted: (_) => onSubmitted(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Digits for the six-digit room code, so the code can be typed without the
/// system keyboard covering the screen.
class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onDelete});

  final void Function(String digit) onDigit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    Widget key(String label, VoidCallback? onTap) => SizedBox(
          height: 52,
          child: OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.cream,
              side: BorderSide(color: AppColors.cream.withValues(alpha: 0.25)),
              padding: EdgeInsets.zero,
            ),
            child: Text(
              label,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
        );
    return Directionality(
      // Phone dialpads are not mirrored with the surrounding language.
      textDirection: TextDirection.ltr,
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.65,
        children: [
          for (final digit in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
            key(digit, () => onDigit(digit)),
          const SizedBox.shrink(),
          key('0', () => onDigit('0')),
          key('מחיקה', onDelete),
        ],
      ),
    );
  }
}
