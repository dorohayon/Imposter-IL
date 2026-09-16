import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/server.dart';
import '../state/game_session.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';
import 'live_room.dart';

// Private rooms run against the real server (docs/protocol.md).

String connectionMessage(String code) => switch (code) {
      'network_error' => 'אין חיבור לשרת. בדקו את החיבור ונסו שוב.',
      _ => 'משהו השתבש. נסו שוב.',
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
      child: Column(
        children: [
          const Illustration(
            'assets/illustrations/private-room.webp',
            height: 270,
          ),
          PrimaryButton(
            label: 'יצירת חדר',
            onPressed: () => _open(context, const CreateRoomScreen()),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'הצטרפות לחדר',
            variant: ButtonVariant.secondary,
            onPressed: () => _open(context, const JoinRoomScreen()),
          ),
        ],
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
  int hintSeconds = 15;
  Set<String>? _selected; // null until the categories load: all of them
  bool _busy = false;

  Future<void> _create() async {
    final session = SessionScope.read(context);
    setState(() => _busy = true);
    try {
      await session.createRoom(
        maxPlayers: players,
        hintSeconds: hintSeconds,
        categoryIds: [
          for (final c in session.categories)
            if (_selected?.contains(c.id) ?? true) c.id,
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
    final allIds = {for (final c in categories) c.id};
    final selected = _selected ?? allIds;
    final loaded = categories.isNotEmpty;

    void toggle(String id) => setState(() {
          final next = {...selected};
          if (!next.remove(id)) next.add(id);
          if (next.isNotEmpty) _selected = next; // keep at least one
        });

    return GameScaffold(
      title: 'יצירת חדר',
      bottom: PrimaryButton(
        label: _busy ? 'יוצרים חדר...' : 'יצירת חדר',
        onPressed: loaded && !_busy ? _create : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Illustration(
            'assets/illustrations/private-room.webp',
            height: 185,
          ),
          const Text(
            'מספר שחקנים מרבי',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 4, label: Text('4')),
              ButtonSegment(value: 5, label: Text('5')),
              ButtonSegment(value: 6, label: Text('6')),
              ButtonSegment(value: 7, label: Text('7')),
              ButtonSegment(value: 8, label: Text('8')),
            ],
            selected: {players},
            onSelectionChanged: (value) =>
                setState(() => players = value.first),
          ),
          const SizedBox(height: 18),
          const Text(
            'זמן לרמז',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 10, label: Text('10 שניות')),
              ButtonSegment(value: 15, label: Text('15 שניות')),
              ButtonSegment(value: 20, label: Text('20 שניות')),
            ],
            selected: {hintSeconds},
            onSelectionChanged: (value) =>
                setState(() => hintSeconds = value.first),
          ),
          const SizedBox(height: 22),
          const Text(
            'קטגוריות',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
                  selected: selected.length == allIds.length,
                  onSelected: (_) => setState(() => _selected = allIds),
                ),
                for (final c in categories)
                  FilterChip(
                    label: Text(c.name),
                    selected: selected.contains(c.id),
                    onSelected: (_) => toggle(c.id),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class JoinRoomScreen extends StatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  final code = TextEditingController();
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
          'room_not_found' => 'החדר לא נמצא. בדקו את הקוד ונסו שוב.',
          'room_unavailable' => 'החדר מלא או שמשחק כבר מתנהל בו',
          'already_in_activity' => 'אתם עדיין במשחק אחר',
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
      bottom: PrimaryButton(
        label: _error == null ? 'הצטרפות' : 'ניסיון נוסף',
        onPressed: ready ? _join : null,
      ),
      child: Column(
        children: [
          Illustration(
            _error == null
                ? 'assets/illustrations/private-room.webp'
                : 'assets/illustrations/connection-error.webp',
            height: 150,
          ),
          const Text(
            'הכניסו את קוד החדר שקיבלתם',
            style: TextStyle(color: AppColors.muted, fontSize: 17),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: code,
            maxLength: 6,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.night,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
            ),
            decoration: InputDecoration(hintText: '000000', errorText: _error),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) {
              if (ready) _join();
            },
          ),
          const SizedBox(height: 6),
          _Keypad(
            onDigit: (digit) {
              if (code.text.length < 6) {
                setState(() {
                  _error = null;
                  code.text += digit;
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

/// Digits for the six-digit room code, so the code can be typed without the
/// system keyboard covering the screen.
class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onDelete});

  final void Function(String digit) onDigit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    Widget key(String label, VoidCallback? onTap) => SizedBox(
          width: 84,
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
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final digit in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'])
          key(digit, () => onDigit(digit)),
        key('מחיקה', onDelete),
      ],
    );
  }
}
