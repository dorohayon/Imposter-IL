import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/server.dart';
import '../l10n/l10n.dart';
import '../models/player.dart';
import '../state/game_session.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ProfileForm(
          title: context.l10n.whoAreYou,
          subtitle: context.l10n.onboardingSubtitle,
          submitLabel: context.l10n.continueLabel,
          busyLabel: context.l10n.connecting,
          onSubmit: (nickname, avatarId) async {
            await SessionScope.read(context).signIn(nickname, avatarId);
            if (!context.mounted) return;
            Navigator.of(context).pop(true);
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
      title: context.l10n.editDetails,
      child: ProfileForm(
        scrollable: false,
        initialNickname: session.nickname ?? '',
        initialAvatarId: session.avatarId,
        submitLabel: context.l10n.save,
        busyLabel: context.l10n.saving,
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

String get _nicknameLengthMessage => l10n.nicknameRule;

/// Matches the server's UTF-8 rune limit without splitting a visible
/// grapheme (for example an emoji sequence) at the boundary.
class _RuneLengthFormatter extends TextInputFormatter {
  const _RuneLengthFormatter(this.maxRunes);

  final int maxRunes;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.runes.length <= maxRunes) return newValue;
    final out = StringBuffer();
    var runes = 0;
    for (final grapheme in newValue.text.characters) {
      final next = grapheme.runes.length;
      if (runes + next > maxRunes) break;
      out.write(grapheme);
      runes += next;
    }
    final text = out.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

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
    final length = value.runes.length;
    if (length < 2 || length > maxNicknameLength) {
      setState(() => _error = _nicknameLengthMessage);
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
          'invalid_nickname' => _nicknameLengthMessage,
          'nickname_blocked' => context.l10n.nicknameBlocked,
          _ => context.l10n.errNetwork,
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
      Text(
        context.l10n.yourNickname,
        style: TextStyle(
          color: AppColors.muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _nickname,
        inputFormatters: const [_RuneLengthFormatter(maxNicknameLength)],
        textAlign: TextAlign.start,
        style: const TextStyle(
          color: AppColors.night,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          hintText: context.l10n.nicknameExample,
          helperText: context.l10n.nicknameLength(maxNicknameLength),
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: 8),
      Text(
        context.l10n.chooseAvatar,
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
          label: context.l10n.avatarN(index + 1),
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
