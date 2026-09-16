import 'package:flutter/material.dart';

import '../data/server.dart';
import '../models/player.dart';
import '../state/game_session.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ProfileForm(
          title: 'מי אתם במשחק?',
          subtitle: 'בוחרים כינוי ואווטאר ומתחילים. בלי הרשמה.',
          submitLabel: 'ממשיכים',
          busyLabel: 'מתחברים...',
          onSubmit: (nickname, avatarId) async {
            await SessionScope.read(context).signIn(nickname, avatarId);
            if (!context.mounted) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
            );
          },
        ),
      ),
    );
  }
}

/// Changes the nickname and avatar of the current guest.
class ProfileEditScreen extends StatelessWidget {
  const ProfileEditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.read(context);
    return GameScaffold(
      title: 'עריכת פרטים',
      child: ProfileForm(
        scrollable: false,
        initialNickname: session.nickname ?? '',
        initialAvatarId: session.avatarId,
        submitLabel: 'שמירה',
        busyLabel: 'שומרים...',
        onSubmit: (nickname, avatarId) async {
          await session.updateProfile(nickname, avatarId);
          if (context.mounted) Navigator.of(context).pop();
        },
      ),
    );
  }
}

/// The server's nickname bounds (docs/decisions.md).
const maxNicknameLength = 18;

/// A nickname field and the 12 avatars. [onSubmit] may throw [ApiException].
class ProfileForm extends StatefulWidget {
  const ProfileForm({
    required this.submitLabel,
    required this.busyLabel,
    required this.onSubmit,
    this.title,
    this.subtitle,
    this.initialNickname = '',
    this.initialAvatarId,
    this.scrollable = true,
    super.key,
  });

  final String? title;
  final String? subtitle;
  final String initialNickname;
  final String? initialAvatarId;
  final String submitLabel;
  final String busyLabel;
  final bool scrollable;
  final Future<void> Function(String nickname, String avatarId) onSubmit;

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  late final _nickname = TextEditingController(text: widget.initialNickname);
  late int _selectedAvatar = () {
    final index = avatarAssets
        .indexWhere((asset) => avatarIdOf(asset) == widget.initialAvatarId);
    return index < 0 ? 0 : index;
  }();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _nickname.text.trim();
    if (value.characters.length < 2) {
      setState(() => _error = 'בחרו כינוי של לפחות 2 תווים.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onSubmit(value, avatarIdOf(avatarAssets[_selectedAvatar]));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e.code) {
          'invalid_nickname' => 'בחרו כינוי באורך 2–18 תווים.',
          'nickname_blocked' => 'הכינוי הזה לא מתאים למשחק. בחרו כינוי אחר.',
          _ => 'אין חיבור לשרת. בדקו את החיבור ונסו שוב.',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = [
      if (widget.title != null)
        Text(
          widget.title!,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
      if (widget.subtitle != null) ...[
        const SizedBox(height: 8),
        Text(
          widget.subtitle!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, fontSize: 14),
        ),
      ],
      const SizedBox(height: 20),
      Center(
        child: AvatarView(
          asset: avatarAssets[_selectedAvatar],
          size: 132,
          selected: true,
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'הכינוי שלכם',
        style: TextStyle(
          color: AppColors.muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _nickname,
        maxLength: maxNicknameLength,
        textAlign: TextAlign.start,
        style: const TextStyle(
          color: AppColors.night,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          hintText: 'למשל: דורון',
          helperText: '2–$maxNicknameLength תווים',
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: 8),
      const Text(
        'בחירת אווטאר',
        style: TextStyle(
          color: AppColors.muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 10),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: avatarAssets.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemBuilder: (context, index) => Semantics(
          button: true,
          selected: index == _selectedAvatar,
          label: 'דמות ${index + 1}',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => setState(() => _selectedAvatar = index),
            child: AvatarView(
              asset: avatarAssets[index],
              selected: index == _selectedAvatar,
            ),
          ),
        ),
      ),
      const SizedBox(height: 22),
      PrimaryButton(
        label: _busy ? widget.busyLabel : widget.submitLabel,
        onPressed: _busy ? null : _submit,
      ),
    ];
    if (!widget.scrollable) return Column(children: children);
    return ListView(
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 28),
      children: children,
    );
  }
}
