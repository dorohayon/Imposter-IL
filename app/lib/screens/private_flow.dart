import 'package:flutter/material.dart';

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
          const Illustration('assets/illustrations/private-room.webp',
              height: 270),
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

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  int players = 8;
  int hintSeconds = 15;

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'יצירת חדר',
      bottom: PrimaryButton(
        label: 'יצירת חדר',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PrivateLobbyScreen()),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Illustration('assets/illustrations/private-room.webp',
              height: 185),
          Text('מספר שחקנים מרבי: $players',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Slider(
            value: players.toDouble(),
            min: 4,
            max: 8,
            divisions: 4,
            label: '$players',
            onChanged: (value) => setState(() => players = value.round()),
          ),
          const SizedBox(height: 18),
          const Text('זמן לרמז',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
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
          const Text('קטגוריות',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('הכול'), avatar: Icon(Icons.check_rounded)),
              Chip(label: Text('אוכל')),
              Chip(label: Text('חיות')),
              Chip(label: Text('ספורט')),
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

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'הצטרפות לחדר',
      bottom: PrimaryButton(
        label: 'הצטרפות',
        onPressed: code.text.length == 6
            ? () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const PrivateLobbyScreen(isHost: false)),
                )
            : null,
      ),
      child: Column(
        children: [
          const Illustration('assets/illustrations/private-room.webp',
              height: 230),
          const Text('הכניסו את קוד החדר שקיבלתם',
              style: TextStyle(color: AppColors.muted, fontSize: 17)),
          const SizedBox(height: 18),
          TextField(
            controller: code,
            maxLength: 6,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.night,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: 8),
            decoration: const InputDecoration(hintText: '000000'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }
}

class PrivateLobbyScreen extends StatelessWidget {
  const PrivateLobbyScreen({this.isHost = true, super.key});

  final bool isHost;

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'החדר של נועם',
      bottom: PrimaryButton(
        label: 'התחלת משחק',
        onPressed: demoPlayers.length >= 4 && isHost
            ? () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) =>
                          const RoleRevealScreen(isImpostor: false)),
                )
            : null,
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
                        Text('קוד החדר',
                            style: TextStyle(color: AppColors.muted)),
                        Text('482731',
                            style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 3)),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'שיתוף הקוד',
                    onPressed: () {},
                    icon: const Icon(Icons.ios_share_rounded),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerRight,
            child: Text('6 מתוך 8 שחקנים',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 8),
          ...demoPlayers.map(
            (player) => Card(
              child: ListTile(
                leading: AvatarView(asset: player.avatar, size: 52),
                title: Text(player.nickname,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: player.isMe ? const Text('מנהל החדר') : null,
                trailing: isHost && !player.isMe
                    ? IconButton(
                        tooltip: 'הסרת שחקן',
                        onPressed: () {},
                        icon: const Icon(Icons.person_remove_rounded,
                            color: AppColors.coral),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(child: Text('קטגוריות: הכול')),
                  Text('15 שניות לרמז'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
