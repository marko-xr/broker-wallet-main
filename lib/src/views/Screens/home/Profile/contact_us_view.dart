import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactUsView extends StatelessWidget {
  const ContactUsView({super.key});

  static const supportEmail = 'brokerwallet@nmodigital.com';
  static const supportSubject = 'Broker Wallet Support';

  Future<void> _emailSupport(BuildContext context) async {
    final uri = Uri.parse(
      'mailto:$supportEmail?subject=${Uri.encodeComponent(supportSubject)}',
    );

    try {
      if (await canLaunchUrl(uri) &&
          await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // A missing mail handler can throw on some platforms.
    }

    if (context.mounted) await _copyEmail(context, fromFallback: true);
  }

  Future<void> _copyEmail(
    BuildContext context, {
    bool fromFallback = false,
  }) async {
    final loc = AppLocalizations.of(context);
    String message;
    try {
      await Clipboard.setData(const ClipboardData(text: supportEmail));
      message = loc.translate(
        fromFallback ? 'contactFallbackCopied' : 'contactEmailCopied',
      );
    } catch (_) {
      message = loc.translate('contactEmailUnavailable');
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        leading: const BackArrowButton(),
        title: Text(loc.translate('contactUs'), style: texts.titleLarge),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colors.surface,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.mail_outline_rounded,
                    color: colors.primary,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                loc.translate('contactBrandName'),
                textAlign: TextAlign.center,
                style: texts.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                loc.translate('contactBrandByline'),
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: texts.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                loc.translate('contactHowCanWeHelp'),
                style: texts.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                loc.translate('contactSupportDescription'),
                style: texts.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Card(
                color: colors.surfaceContainerLow,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        loc.translate('contactEmailLabel'),
                        style: texts.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        supportEmail,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.start,
                        style: texts.bodyMedium?.copyWith(
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton.icon(
                          onPressed: () => _copyEmail(context),
                          icon: const Icon(Icons.copy_outlined),
                          label: Text(loc.translate('contactCopyEmail')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => _emailSupport(context),
                  child: Text(loc.translate('emailSupport')),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      loc.translate('contactSecurityNote'),
                      style: texts.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
