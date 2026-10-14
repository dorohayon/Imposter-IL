
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';

/// The documents' version, shown with them and in Settings. Players agree
/// to the current Terms when they choose a nickname (OnboardingScreen).
const legalVersion = '1.4';
String get legalDate => l10n.legalDate;

/// Public copies for App Store Connect, Google Play and anyone who wants to
/// read the documents without installing the app. They are built from site/
/// in the repository and published to GitHub Pages (docs/legal.md), so they
/// do not depend on where the game server runs.
const publicSite = 'https://imposteril.github.io';
const privacyPath = '/privacy/';
const termsPath = '/terms/';

Uri publicLegalUrl(String path) => Uri.parse(publicSite).resolve(path);

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
