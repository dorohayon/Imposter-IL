import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../monetization/monetization.dart';
import '../monetization/monetization_config.dart';
import '../state/game_session.dart';
import '../state/sounds.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';
import 'legal_screens.dart';
import 'onboarding_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return GameScaffold(
      title: context.l10n.myProfile,
      bannerPlacement: BannerPlacement.profile,
      child: Column(
        children: [
          AvatarView(
            asset: 'assets/avatars/${session.avatarId}.webp',
            size: 138,
            selected: true,
          ),
          const SizedBox(height: 14),
          Text(
            session.nickname ?? '',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ProfileEditScreen(),
              ),
            ),
            icon: const Icon(Icons.edit_rounded),
            label: Text(context.l10n.editNicknameAvatar),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  value: '${session.wins}',
                  label: context.l10n.wins,
                  color: AppColors.turquoise,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  value: '${session.losses}',
                  label: context.l10n.losses,
                  color: AppColors.coral,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// Support address shown in settings and required by the stores alongside
/// reporting (App Store review guideline 1.2). Empty hides the row.
///
/// MUST be filled in before submission — see docs/production-architecture-review.md.
const supportEmail = 'imposteril36@gmail.com';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final money = MonetizationScope.of(context);
    return GameScaffold(
      title: context.l10n.settings,
      bannerPlacement: BannerPlacement.settings,
      child: Column(
        children: [
          _SettingsRow(
            title: context.l10n.sounds,
            value: session.soundsOn,
            onChanged: session.setSounds,
          ),
          const SizedBox(height: 10),
          _SettingsRow(
            title: context.l10n.vibration,
            value: session.vibrationOn,
            onChanged: session.setVibration,
          ),
          const SizedBox(height: 10),
          _SettingsRow(
            title: context.l10n.showReactions,
            value: session.showReactions,
            onChanged: session.setShowReactions,
          ),
          const SizedBox(height: 10),
          _LinkRow(
            title: context.l10n.language,
            value: session.languageOverride == null
                ? '${context.l10n.phoneLanguage} · ${context.l10n.languageName}'
                : context.l10n.languageName,
            onTap: () => _chooseLanguage(context),
          ),
          const SizedBox(height: 20),
          _LinkRow(
            title: context.l10n.termsTitle,
            value: context.l10n.versionN(legalVersion),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TermsScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _LinkRow(
            title: context.l10n.privacyTitle,
            value: context.l10n.versionN(legalVersion),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()),
            ),
          ),
          const SizedBox(height: 10),
          const _RestoreRow(),
          // Subscribers manage and cancel in the store; this takes them there.
          if (money.monthlyActive) ...[
            const SizedBox(height: 10),
            _LinkRow(
              title: context.l10n.manageSubscription,
              value: context.l10n.premiumMonthly,
              onTap: () => openSubscriptions(money.config.premiumMonthly),
            ),
          ],
          // Required by Google's consent rules where they apply (EEA, UK):
          // a way back to the ad privacy choice.
          if (money.privacyOptionsRequired) ...[
            const SizedBox(height: 10),
            _LinkRow(
              title: context.l10n.adPrivacy,
              value: '',
              onTap: money.showPrivacyOptions,
            ),
          ],
          const SizedBox(height: 36),
          Text(
            context.l10n.appVersion,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          if (supportEmail.isNotEmpty) ...[
            const SizedBox(height: 10),
            ListTile(
              onTap: withClick(() => _emailSupport(context)),
              // The same end as the rows above (see _LinkRow).
              contentPadding:
                  const EdgeInsetsDirectional.only(start: 16, end: 12),
              tileColor: AppColors.cream.withValues(alpha: .06),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              leading: const Icon(Icons.mail_outline_rounded,
                  color: AppColors.yellow),
              title: Text(context.l10n.contact),
              subtitle: Text(supportEmail),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: AppColors.muted),
            ),
          ],
          if (session.muted.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(context.l10n.reportedPlayers),
              subtitle:
                  Text(context.l10n.hiddenPlayersCount(session.muted.length)),
              trailing: TextButton(
                onPressed: session.clearMuted,
                child: Text(context.l10n.clear),
              ),
            ),
        ],
      ),
    );
  }
}

/// The store's own subscription page: where a subscriber changes or cancels.
/// Opens the store app, or its web page if the app is missing.
Future<bool> Function(Uri) openExternal =
    (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

Future<void> openSubscriptions(String productId) => openExternal(
      Platform.isIOS
          ? Uri.parse('https://apps.apple.com/account/subscriptions')
          : Uri.https('play.google.com', '/store/account/subscriptions', {
              'sku': productId,
              'package': 'com.imposteril.app',
            }),
    );

/// Opens the mail app on a message to support. A phone without one gets the
/// address copied instead, so the tap is never a dead end.
Future<void> _emailSupport(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final copied = context.l10n.emailCopied;
  var opened = false;
  try {
    opened = await openExternal(Uri(scheme: 'mailto', path: supportEmail));
  } on Object {
    opened = false;
  }
  if (opened) return;
  await Clipboard.setData(const ClipboardData(text: supportEmail));
  messenger.showSnackBar(SnackBar(content: Text(copied)));
}

/// Restore outside the purchase popup: a player on a new phone whose
/// Premium hides every lock has no locked category to tap.
class _RestoreRow extends StatefulWidget {
  const _RestoreRow();

  @override
  State<_RestoreRow> createState() => _RestoreRowState();
}

class _RestoreRowState extends State<_RestoreRow> {
  bool _busy = false;

  Future<void> _restore() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final result = await MonetizationScope.read(context).restoreAll();
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(
      content: Text(switch (result) {
        RestoreResult.found => context.l10n.purchasesRestored,
        RestoreResult.none => context.l10n.noPurchasesFound,
        RestoreResult.failed => context.l10n.restoreFailed,
      }),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final money = MonetizationScope.of(context);
    return _LinkRow(
      title: _busy
          ? context.l10n.restoringPurchases
          : context.l10n.restorePurchases,
      value: money.premium ? context.l10n.premium : '',
      onTap: _busy ? null : _restore,
    );
  }
}

/// The phone's language, then every language the app has, each in its own
/// name: a new ARB file adds its row by itself.
Future<void> _chooseLanguage(BuildContext context) async {
  final session = SessionScope.read(context);
  final choice = await showModalBottomSheet<(String?,)>(
    context: context,
    backgroundColor: AppColors.nightSoft,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final code in [
            null,
            for (final l in AppLocalizations.supportedLocales) l.languageCode,
          ])
            ListTile(
              minTileHeight: 56,
              title: Text(
                code == null
                    ? sheet.l10n.phoneLanguage
                    : lookupAppLocalizations(Locale(code)).languageName,
              ),
              trailing: session.languageOverride == code
                  ? const Icon(Icons.check_rounded, color: AppColors.yellow)
                  : null,
              onTap: () => Navigator.of(sheet).pop((code,)),
            ),
        ],
      ),
    ),
  );
  if (choice != null) await session.setLanguage(choice.$1);
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    required this.value,
    this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cream.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: withClick(onChanged == null ? null : () => onChanged!(!value)),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Expanded: a longer language must wrap at 320 px.
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.cream,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IgnorePointer(
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.title, required this.value, this.onTap});

  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cream.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: withClick(onTap),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          // 12 at the end, not 16: a chevron's stroke sits further inside its
          // box than a switch's track, and this lines the two up.
          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 12, 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.cream,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // The value by the chevron, at the row's end. A Flexible here
              // took half the row, which put the value mid-row and wrapped
              // "Restore purchases" into two lines.
              if (value.isNotEmpty) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  static List<String> get steps => [
        l10n.howStep1,
        l10n.howStep2,
        l10n.citizenTip2,
        l10n.howStep4,
        l10n.howStep5,
        l10n.howStep6,
      ];

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: context.l10n.howToPlay,
      bannerPlacement: BannerPlacement.howToPlay,
      accent: const Color(0xFF2A2455),
      bottom: PrimaryButton(
        label: context.l10n.gotIt,
        onPressed: () => Navigator.of(context).pop(),
      ),
      child: Column(
        children: [
          ...List.generate(steps.length, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: StepCard(
                number: index + 1,
                text: steps[index],
                purple: index == steps.length - 1,
              ),
            );
          }),
          const Illustration(
            'assets/illustrations/how-to-play.webp',
            height: 110,
          ),
        ],
      ),
    );
  }
}

/// Shown when the server refuses this build (`client_too_old`). Nothing else
/// is reachable: an old install whose protocol the server dropped can only
/// update, so this screen has no way back.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: context.l10n.updateNeeded,
      showBack: false,
      child: Column(
        children: [
          const SizedBox(height: 12),
          const Illustration('assets/illustrations/connection-error.webp'),
          const SizedBox(height: 20),
          Text(
            context.l10n.newVersion,
            style: Theme.of(context).textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.versionUnsupported,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// The approved connection-error design, used both when initial content
/// cannot load and when an active game is aborted by the server.
class ServerErrorScreen extends StatelessWidget {
  const ServerErrorScreen({
    required this.onRetry,
    required this.onHome,
    this.gameStopped = false,
    super.key,
  });

  final VoidCallback onRetry;
  final VoidCallback onHome;
  final bool gameStopped;

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: '',
      showBack: false,
      showHeader: false,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryButton(label: context.l10n.tryAgain, onPressed: onRetry),
          const SizedBox(height: 8),
          PrimaryButton(
            label: context.l10n.backToHome,
            variant: ButtonVariant.secondary,
            onPressed: onHome,
          ),
        ],
      ),
      child: Column(
        children: [
          const Illustration(
            'assets/illustrations/connection-error.webp',
            height: 170,
          ),
          Text(
            context.l10n.somethingWrong,
            style: Theme.of(context).textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            gameStopped
                ? context.l10n.serverFaultStopped
                : context.l10n.serverUnavailable,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 17,
              height: 1.45,
            ),
          ),
          if (gameStopped) ...[
            const SizedBox(height: 16),
            StatusBanner(text: context.l10n.noLossRecorded, positive: true),
          ],
        ],
      ),
    );
  }
}
