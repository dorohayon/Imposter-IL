import 'package:flutter/material.dart';

import '../models/player.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';

class RoleRevealScreen extends StatelessWidget {
  const RoleRevealScreen({required this.isImpostor, super.key});

  final bool isImpostor;

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'המשימה שלך',
      timer: 10,
      onExit: () => Navigator.of(context).popUntil((route) => route.isFirst),
      bottom: PrimaryButton(
        label: 'הבנתי',
        onPressed: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const HintRoundScreen()),
        ),
      ),
      child: Column(
        children: [
          Illustration(
            isImpostor
                ? 'assets/illustrations/role-impostor.webp'
                : 'assets/illustrations/role-citizen.webp',
            height: 245,
          ),
          const Text('קטגוריה: אוכל', style: TextStyle(color: AppColors.turquoise, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text(
            isImpostor ? 'אתה המתחזה' : 'המילה שלך',
            style: Theme.of(context).textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: isImpostor ? AppColors.purple : AppColors.cream,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              isImpostor ? 'המילה נשארת סודית' : 'בננה',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isImpostor ? AppColors.cream : AppColors.night,
                fontSize: 32,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isImpostor
                ? 'נסה להשתלב, להבין את הרמזים ולגלות את המילה.'
                : 'תן רמז של מילה אחת בלי לחשוף את המילה הסודית.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 17, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class HintRoundScreen extends StatefulWidget {
  const HintRoundScreen({super.key});

  @override
  State<HintRoundScreen> createState() => _HintRoundScreenState();
}

class _HintRoundScreenState extends State<HintRoundScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _submitted = false;
  final _reactions = <String>[];

  static const reactionOptions = ['😂', '🤔', '🔥', 'חשוד מאוד', 'רמז טוב!', 'לא הבנתי'];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final hint = _controller.text.trim();
    final words = hint.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
    if (hint.isEmpty) {
      setState(() => _error = 'צריך לכתוב רמז');
    } else if (words.length != 1) {
      setState(() => _error = 'הרמז חייב להיות מילה אחת');
    } else if (hint.contains('בננה')) {
      setState(() => _error = 'אסור לחשוף את המילה הסודית');
    } else if (demoPlayers.any((player) => player.hint == hint)) {
      setState(() => _error = 'כבר השתמשו ברמז הזה');
    } else {
      setState(() {
        _error = null;
        _submitted = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'קטגוריה: אוכל',
      timer: 15,
      onExit: () => Navigator.of(context).popUntil((route) => route.isFirst),
      bottom: _submitted
          ? PrimaryButton(
              label: 'להצבעה',
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(builder: (_) => const VotingScreen()),
              ),
            )
          : PrimaryButton(label: 'שליחת רמז', onPressed: _submit),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _showSecretWord(context),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('הצגת המילה'),
            ),
          ),
          const SizedBox(height: 4),
          if (!_submitted) ...[
            Text('התור שלך', style: Theme.of(context).textTheme.headlineLarge, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            const Text('רמז אחד, מילה אחת', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLength: 25,
              autofocus: true,
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppColors.night, fontSize: 21, fontWeight: FontWeight.w800),
              decoration: InputDecoration(
                hintText: 'הרמז שלי',
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
          ] else ...[
            const AvatarView(asset: 'assets/avatars/avatar-m02-binoculars.webp', size: 92),
            const SizedBox(height: 10),
            Text('יובל כותב רמז...', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 22),
          const Text('הרמזים שנחשפו', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          ...demoPlayers.take(3).map(
            (player) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PlayerCard(player: player),
            ),
          ),
          const SizedBox(height: 10),
          const Text('תגובות לרמז האחרון', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: reactionOptions.map((reaction) {
              final count = _reactions.where((value) => value == reaction).length;
              return ActionChip(
                onPressed: () => setState(() => _reactions.add(reaction)),
                avatar: count == 0 ? null : CircleAvatar(child: Text('$count')),
                label: Text(reaction),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _showSecretWord(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cream,
      showDragHandle: true,
      builder: (context) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('המילה שלך', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              SizedBox(height: 10),
              Text('בננה', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: AppColors.night)),
            ],
          ),
        ),
      ),
    );
  }
}

class VotingScreen extends StatefulWidget {
  const VotingScreen({this.isRevote = false, super.key});

  final bool isRevote;

  @override
  State<VotingScreen> createState() => _VotingScreenState();
}

class _VotingScreenState extends State<VotingScreen> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final candidates = widget.isRevote ? demoPlayers.sublist(1, 3) : demoPlayers;
    return GameScaffold(
      title: widget.isRevote ? 'הצבעה חוזרת' : 'מי המתחזה?',
      timer: widget.isRevote ? 15 : 20,
      onExit: () => Navigator.of(context).popUntil((route) => route.isFirst),
      bottom: PrimaryButton(
        label: 'אישור הצבעה',
        onPressed: _selected == null
            ? null
            : () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(builder: (_) => const ImpostorGuessScreen()),
                ),
      ),
      child: Column(
        children: [
          const Illustration('assets/illustrations/voting.webp', height: 150),
          if (widget.isRevote)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'תיקו נוסף מעניק ניצחון למתחזה',
                style: TextStyle(color: AppColors.coral, fontWeight: FontWeight.w800),
              ),
            ),
          ...List.generate(candidates.length, (index) {
            final player = candidates[index];
            final isMe = player.isMe;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PlayerCard(
                player: player,
                enabled: !isMe,
                selected: _selected == index,
                onTap: () => setState(() => _selected = index),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class ImpostorGuessScreen extends StatefulWidget {
  const ImpostorGuessScreen({super.key});

  @override
  State<ImpostorGuessScreen> createState() => _ImpostorGuessScreenState();
}

class _ImpostorGuessScreenState extends State<ImpostorGuessScreen> {
  final _guess = TextEditingController();

  @override
  void dispose() {
    _guess.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'הזדמנות אחרונה',
      timer: 15,
      onExit: () => Navigator.of(context).popUntil((route) => route.isFirst),
      bottom: PrimaryButton(
        label: 'שליחת ניחוש',
        onPressed: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const ResultScreen(citizensWon: true)),
        ),
      ),
      child: Column(
        children: [
          const Illustration('assets/illustrations/role-impostor.webp', height: 230),
          Text('המתחזה עדיין יכול לנצח', style: Theme.of(context).textTheme.headlineLarge, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          const Text('מה הייתה המילה הסודית?', style: TextStyle(color: AppColors.muted, fontSize: 17)),
          const SizedBox(height: 20),
          TextField(
            controller: _guess,
            textAlign: TextAlign.right,
            style: const TextStyle(color: AppColors.night, fontSize: 20, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(hintText: 'הניחוש שלי'),
          ),
        ],
      ),
    );
  }
}

class ResultScreen extends StatelessWidget {
  const ResultScreen({required this.citizensWon, super.key});

  final bool citizensWon;

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'תוצאות המשחק',
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(
            label: 'משחק נוסף',
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('חזרה למסך הבית'),
          ),
        ],
      ),
      child: Column(
        children: [
          Illustration(
            citizensWon
                ? 'assets/illustrations/result-citizens-win.webp'
                : 'assets/illustrations/result-impostor-win.webp',
            height: 250,
          ),
          Text(
            citizensWon ? 'האזרחים ניצחו!' : 'המתחזה ניצח!',
            style: Theme.of(context).textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            citizensWon ? 'המתחזה נתפס ולא ניחש את המילה' : 'המתחזה הצליח לגלות את המילה',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 17),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: const [
                  ListTile(title: Text('המתחזה'), trailing: Text('יובל', style: TextStyle(fontWeight: FontWeight.w900))),
                  Divider(),
                  ListTile(title: Text('המילה'), trailing: Text('בננה', style: TextStyle(fontWeight: FontWeight.w900))),
                  Divider(),
                  ListTile(title: Text('חלוקת הקולות'), trailing: Text('יובל — 4')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
