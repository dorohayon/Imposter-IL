import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../demo/demo_data.dart';
import '../models/player.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';
import 'game_flow.dart';

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

// The lobby replaces create/join so that back from the lobby leaves the room
// instead of reopening a form for a room that already exists.
void _openLobby(BuildContext context, PrivateLobbyScreen lobby) =>
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => lobby),
    );

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  int players = 8;
  int hintSeconds = 15;
  final categories = <String>{demoCategories.first};

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'יצירת חדר',
      bottom: PrimaryButton(
        label: 'יצירת חדר',
        onPressed: () => _openLobby(
          context,
          PrivateLobbyScreen(
            me: demoHostMe,
            maxPlayers: players,
            hintSeconds: hintSeconds,
            categories: [
              for (final name in demoCategories)
                if (categories.contains(name)) name,
            ],
          ),
        ),
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in demoCategories)
                FilterChip(
                  label: Text(name),
                  selected: categories.contains(name),
                  onSelected: (_) =>
                      setState(() => toggleCategory(categories, name)),
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

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  void _join() {
    // Demo: only the demo room exists. The server answers room_not_found or
    // room_unavailable for everything else (docs/protocol.md).
    if (code.text != demoRoomCode) {
      setState(() => _error = 'החדר לא נמצא או שאינו זמין כרגע');
      return;
    }
    _openLobby(context, const PrivateLobbyScreen(me: demoJoinerMe));
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'הצטרפות לחדר',
      bottom: PrimaryButton(
        label: _error == null ? 'הצטרפות' : 'ניסיון נוסף',
        onPressed: code.text.length == 6 ? _join : null,
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
            decoration: InputDecoration(
              hintText: '000000',
              errorText: _error,
              helperText: kDebugMode ? 'קוד חדר להדגמה: $demoRoomCode' : null,
              helperStyle: const TextStyle(color: AppColors.muted),
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) {
              if (code.text.length == 6) _join();
            },
          ),
        ],
      ),
    );
  }
}

class PrivateLobbyScreen extends StatefulWidget {
  const PrivateLobbyScreen({
    required this.me,
    this.maxPlayers = 8,
    this.hintSeconds = 15,
    this.categories = const ['הכול'],
    super.key,
  });

  /// Demo nickname of the current player; the host is fixed by the demo data.
  final String me;
  final int maxPlayers;
  final int hintSeconds;
  final List<String> categories;

  @override
  State<PrivateLobbyScreen> createState() => _PrivateLobbyScreenState();
}

class _PrivateLobbyScreenState extends State<PrivateLobbyScreen> {
  late final List<Player> _players =
      DemoGame(me: widget.me).players.take(widget.maxPlayers).toList();

  Player get _host => _players.firstWhere((player) => player.isHost);
  bool get _iAmHost => _host.isMe;
  bool get _canStart => _iAmHost && _players.length >= 4;

  void _start() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoleRevealScreen(
          game: DemoGame(
            me: widget.me,
            hintSeconds: widget.hintSeconds,
            roster: List.of(_players),
          ),
        ),
      ),
    );
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(const ClipboardData(text: demoRoomCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('קוד החדר הועתק')));
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'החדר של ${_host.nickname}',
      bottom: PrimaryButton(
        label: _iAmHost ? 'התחלת משחק' : 'רק מנהל החדר יכול להתחיל',
        onPressed: _canStart ? _start : null,
      ),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'קוד החדר',
                          style: TextStyle(color: AppColors.muted),
                        ),
                        Text(
                          demoRoomCode,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'העתקת הקוד',
                    onPressed: _copyCode,
                    icon: const Icon(Icons.copy_rounded),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              '${_players.length} מתוך ${widget.maxPlayers} שחקנים',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          if (_iAmHost && _players.length < 4)
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'צריך לפחות 4 שחקנים כדי להתחיל',
                style: TextStyle(
                  color: AppColors.coral,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 8),
          for (final player in _players)
            Card(
              child: ListTile(
                leading: AvatarView(asset: player.avatar, size: 52),
                title: Text(
                  player.nickname,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: player.isHost || player.isMe
                    ? Text(
                        [
                          if (player.isHost) 'מנהל החדר',
                          if (player.isMe) 'אני',
                        ].join(' · '),
                      )
                    : null,
                trailing: _iAmHost && !player.isMe
                    ? IconButton(
                        tooltip: 'הסרת ${player.nickname}',
                        onPressed: () =>
                            setState(() => _players.remove(player)),
                        icon: const Icon(
                          Icons.person_remove_rounded,
                          color: AppColors.coral,
                        ),
                      )
                    : null,
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                children: [
                  Text('קטגוריות: ${widget.categories.join(', ')}'),
                  Text('${widget.hintSeconds} שניות לרמז'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
