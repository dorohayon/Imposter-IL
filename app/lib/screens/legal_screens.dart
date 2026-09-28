import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../crash_reporting.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';

/// Bump this value whenever a material Terms/Privacy change requires renewed
/// acknowledgement. The acknowledgement is deliberately device-local: the
/// product has no account system and no legal-consent profile on the server.
const legalVersion = '1.3';
String get legalDate => l10n.legalDate;
const legalAcceptedVersionKey = 'legal.acceptedVersion';

/// Public copies for App Store Connect, Google Play and anyone who wants to
/// read the documents without installing the app. They are built from site/
/// in the repository and published to GitHub Pages (docs/legal.md), so they
/// do not depend on where the game server runs.
const publicSite = 'https://imposteril.github.io';
const privacyPath = '/privacy/';
const termsPath = '/terms/';

Uri publicLegalUrl(String path) => Uri.parse(publicSite).resolve(path);

class LegalGate extends StatefulWidget {
  const LegalGate({required this.child, this.onAccepted, super.key});

  final Widget child;

  /// Called once the current version has just been accepted.
  final VoidCallback? onAccepted;

  @override
  State<LegalGate> createState() => _LegalGateState();
}

class _LegalGateState extends State<LegalGate> {
  bool? _accepted;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _accepted = prefs.getString(legalAcceptedVersionKey) == legalVersion;
    });
  }

  Future<void> _accept() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(legalAcceptedVersionKey, legalVersion);
    unawaited(enableCrashReporting());
    if (!mounted) return;
    setState(() => _accepted = true);
    widget.onAccepted?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_accepted!) return widget.child;
    return LegalConsentScreen(onAccepted: _accept);
  }
}

class LegalConsentScreen extends StatefulWidget {
  const LegalConsentScreen({required this.onAccepted, super.key});

  final Future<void> Function() onAccepted;

  @override
  State<LegalConsentScreen> createState() => _LegalConsentScreenState();
}

class _LegalConsentScreenState extends State<LegalConsentScreen> {
  bool _checked = false;
  bool _busy = false;

  Future<void> _submit() async {
    if (!_checked || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onAccepted();
    } finally {
      // The gate is the way into the app. If saving failed, the button has to
      // come back rather than leave the player stuck on "שומרים...".
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: context.l10n.legalGateTitle,
      showBack: false,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pinned with the button it enables: in the scrolling body it fell
          // below the fold on a small phone, leaving a disabled button with
          // nothing on screen to explain it.
          Material(
            color: AppColors.cream.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(16),
            child: CheckboxListTile(
              value: _checked,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _checked = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppColors.turquoise,
              checkColor: AppColors.night,
              title: Text(
                context.l10n.legalConsent,
                style: TextStyle(fontWeight: FontWeight.w700, height: 1.35),
              ),
            ),
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: _busy ? context.l10n.saving : context.l10n.acceptAndContinue,
            onPressed: _checked && !_busy ? _submit : null,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.verified_user_outlined,
            size: 72,
            color: AppColors.turquoise,
          ),
          const SizedBox(height: 18),
          Text(
            context.l10n.legalGateHeadline,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.legalGateBody,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 22),
          _LegalLink(
            title: context.l10n.termsTitle,
            subtitle: context.l10n.termsSubtitle,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TermsScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _LegalLink(
            title: context.l10n.privacyTitle,
            subtitle: context.l10n.privacySubtitle,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            context.l10n.legalDocsVersion(legalVersion, legalDate),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegalDocument(
      title: context.l10n.termsTitle,
      intro: context.l10n.termsIntro(legalVersion, legalDate),
      sections: [
        _LegalSection(
          context.l10n.terms1Title,
          context.l10n.terms1,
        ),
        _LegalSection(
          context.l10n.terms2Title,
          context.l10n.terms2,
        ),
        _LegalSection(
          context.l10n.terms3Title,
          context.l10n.terms3,
        ),
        _LegalSection(
          context.l10n.terms4Title,
          context.l10n.terms4,
        ),
        _LegalSection(
          context.l10n.terms5Title,
          context.l10n.terms5,
        ),
        _LegalSection(
          context.l10n.terms6Title,
          context.l10n.terms6,
        ),
        _LegalSection(
          context.l10n.terms7Title,
          context.l10n.terms7,
        ),
        _LegalSection(
          context.l10n.terms8Title,
          context.l10n.terms8,
        ),
        _LegalSection(
          context.l10n.terms9Title,
          context.l10n.terms9,
        ),
        _LegalSection(
          context.l10n.terms10Title,
          context.l10n.terms10,
        ),
        _LegalSection(
          context.l10n.terms11Title,
          context.l10n.terms11,
        ),
        _LegalSection(
          context.l10n.terms12Title,
          context.l10n.terms12,
        ),
      ],
      publicPath: termsPath,
    );
  }
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegalDocument(
      title: context.l10n.privacyTitle,
      intro: context.l10n.privacyIntro(legalVersion, legalDate),
      sections: [
        _LegalSection(
          context.l10n.privacy1Title,
          context.l10n.privacy1,
        ),
        _LegalSection(
          context.l10n.privacy2Title,
          context.l10n.privacy2,
        ),
        _LegalSection(
          context.l10n.privacy3Title,
          context.l10n.privacy3,
        ),
        _LegalSection(
          context.l10n.privacy4Title,
          context.l10n.privacy4,
        ),
        _LegalSection(
          context.l10n.privacy5Title,
          context.l10n.privacy5,
        ),
        _LegalSection(
          context.l10n.privacy6Title,
          context.l10n.privacy6,
        ),
        _LegalSection(
          context.l10n.privacy7Title,
          context.l10n.privacy7,
        ),
        _LegalSection(
          context.l10n.privacy8Title,
          context.l10n.privacy8,
        ),
        _LegalSection(
          context.l10n.privacy9Title,
          context.l10n.privacy9,
        ),
        _LegalSection(
          context.l10n.privacy10Title,
          context.l10n.privacy10,
        ),
        _LegalSection(
          context.l10n.privacy11Title,
          context.l10n.privacy11,
        ),
        _LegalSection(
          context.l10n.privacy12Title,
          context.l10n.privacy12,
        ),
        _LegalSection(
          context.l10n.privacy13Title,
          context.l10n.privacy13,
        ),
      ],
      publicPath: privacyPath,
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cream.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        onTap: onTap,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _LegalDocument extends StatelessWidget {
  const _LegalDocument({
    required this.title,
    required this.intro,
    required this.sections,
    required this.publicPath,
  });

  final String title;
  final String intro;
  final List<_LegalSection> sections;
  final String publicPath;

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            intro,
            style: const TextStyle(color: AppColors.muted, height: 1.55),
          ),
          const SizedBox(height: 20),
          for (final section in sections) ...[
            Text(
              section.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(section.body, style: const TextStyle(height: 1.55)),
            const SizedBox(height: 18),
          ],
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cream.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SelectableText(
              context.l10n.legalPublicCopy(publicLegalUrl(publicPath)),
              textDirection: TextDirection.ltr,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalSection {
  const _LegalSection(this.title, this.body);

  final String title;
  final String body;
}
