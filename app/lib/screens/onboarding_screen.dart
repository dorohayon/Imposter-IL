import 'package:flutter/material.dart';

import '../data/server.dart';
import '../models/player.dart';
import '../state/game_session.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nickname = TextEditingController();
  int _selectedAvatar = 0;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final value = _nickname.text.trim();
    if (value.characters.length < 2) {
      setState(() => _error = 'צריך לבחור כינוי של לפחות 2 תווים');
      return;
    }
    setState(() => _busy = true);
    try {
      await SessionScope.read(context)
          .signIn(value, avatarIdOf(avatarAssets[_selectedAvatar]));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      );
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = switch (e.code) {
          'invalid_nickname' => 'צריך לבחור כינוי של לפחות 2 תווים',
          'nickname_blocked' => 'הכינוי הזה לא מתאים. נסו כינוי אחר.',
          _ => 'אין חיבור לשרת. בדקו את החיבור ונסו שוב.',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
          children: [
            Text('בואו נכיר',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 8),
            const Text('בחרו כינוי ודמות בלשית',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 17)),
            const SizedBox(height: 24),
            Center(
                child: AvatarView(
                    asset: avatarAssets[_selectedAvatar],
                    size: 132,
                    selected: true)),
            const SizedBox(height: 24),
            TextField(
              controller: _nickname,
              maxLength: 18,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: AppColors.night,
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: 'הכינוי שלי',
                errorText: _error,
                prefixIcon:
                    const Icon(Icons.edit_rounded, color: AppColors.night),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _continue(),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: avatarAssets.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemBuilder: (context, index) => GestureDetector(
                onTap: () => setState(() => _selectedAvatar = index),
                child: AvatarView(
                  asset: avatarAssets[index],
                  selected: index == _selectedAvatar,
                ),
              ),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: _busy ? 'מתחברים...' : 'ממשיכים',
              onPressed: _busy ? null : _continue,
            ),
          ],
        ),
      ),
    );
  }
}
