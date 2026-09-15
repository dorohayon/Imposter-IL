import 'package:flutter/material.dart';

import '../screens/game_flow.dart';
import '../screens/secondary_screens.dart';
import '../widgets/game_ui.dart';
import 'demo_data.dart';

/// Debug-only index of states that a real game reaches through the server
/// (roles, ties, disconnects, errors). The home screen links here only in
/// debug builds; delete it once those states are driven by the server.
class PrototypeStatesScreen extends StatelessWidget {
  const PrototypeStatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const impostorGame = DemoGame(me: demoOnlineMe, isImpostor: true);
    const citizenGame = DemoGame(me: demoOnlineMe);
    final entries = <(String, Widget)>[
      ('משחק כמתחזה', const RoleRevealScreen(game: impostorGame)),
      (
        'הצבעה חוזרת',
        VotingScreen(
          game: citizenGame,
          players: citizenGame.players,
          isRevote: true,
        ),
      ),
      (
        'לא נמצא משחק מתאים',
        const SystemStateScreen(type: SystemStateType.noCategoryMatch),
      ),
      (
        'חיבור מחדש',
        const SystemStateScreen(type: SystemStateType.reconnecting),
      ),
      (
        'הוצאה לאחר הניתוק השלישי',
        const SystemStateScreen(type: SystemStateType.removed),
      ),
      (
        'המשחק הופסק — מחסור בשחקנים',
        const SystemStateScreen(type: SystemStateType.stopped),
      ),
      (
        'תקלה בשרת',
        const SystemStateScreen(type: SystemStateType.serverError),
      ),
    ];

    return GameScaffold(
      title: 'מצבי Prototype',
      child: Column(
        children: [
          for (final (label, screen) in entries)
            Card(
              child: ListTile(
                title: Text(label),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => screen),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
