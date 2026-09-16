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
            secondary: true,
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
            if (_selected?.contains(c.id) ?? true) c.id, // null is "הכול"
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
    // null is "הכול": every category, shown as that one chip rather than by
    // selecting all of them. A non-null set may be empty, which blocks
    // creating the room — the server needs at least one category.
    final all = _selected == null;
    final selected = _selected ?? const <String>{};
    final loaded = categories.isNotEmpty;

    void toggle(String id) => setState(() {
          // Leaving "הכול" starts a fresh choice of just this category.
          final next = all ? <String>{id} : {...selected};
          if (!all && !next.remove(id)) next.add(id);
          _selected = next;
        });

    return GameScaffold(
      title: 'יצירת חדר',
      bottom: PrimaryButton(
        label: _busy ? 'יוצרים חדר...' : 'יצירת חדר',
        onPressed:
            loaded && !_busy && (all || selected.isNotEmpty) ? _create : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Illustration(
            'assets/illustrations/private-room.webp',
            height: 185,
          ),
          Text(
            'מספר שחקנים מרבי: $players',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          Slider(
            value: players.toDouble(),
            min: 4,
            max: 8,
            divisions: 4,
            label: '$players',
            onChanged: (value) => setState(() => players = value.round()),
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
                  selected: all,
                  onSelected: (_) =>
                      setState(() => _selected = all ? <String>{} : null),
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
            height: 230,
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
        ],
      ),
    );
  }
}
