import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_section_card.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_section_header.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:flutter/material.dart';

enum LegalInformationType { privacyPolicy, termsConditions }

class PrivacyPolicyView extends StatelessWidget {
  const PrivacyPolicyView({super.key});

  @override
  Widget build(BuildContext context) => const LegalInformationView(
        type: LegalInformationType.privacyPolicy,
      );
}

class TermsConditionsView extends StatelessWidget {
  const TermsConditionsView({super.key});

  @override
  Widget build(BuildContext context) => const LegalInformationView(
        type: LegalInformationType.termsConditions,
      );
}

class LegalInformationView extends StatelessWidget {
  const LegalInformationView({super.key, required this.type});

  final LegalInformationType type;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;
    final isPrivacy = type == LegalInformationType.privacyPolicy;
    final title = loc.translate(isPrivacy ? 'privacyPolicy' : 'termsConditions');
    final icon = isPrivacy
        ? Icons.privacy_tip_outlined
        : Icons.description_outlined;

    return Scaffold(
      appBar: AppBar(
        leading: const BackArrowButton(),
        title: Text(title, style: texts.titleLarge),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colors.surface,
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: colors.primary, size: 34),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: texts.titleLarge,
            ),
            const SizedBox(height: 28),
            SettingsSectionHeader(
              title: loc.translate('legalInformationStatus'),
            ),
            SettingsSectionCard(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.translate('legalContentPending'),
                        style: texts.bodyLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        loc.translate('legalContentAvailableBeforeRelease'),
                        style: texts.bodyMedium?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
