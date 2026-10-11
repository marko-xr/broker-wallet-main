import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_section_card.dart';
import 'package:broker_wallet/src/Views/Widgets/settings_section_header.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
    final contentPrefix = isPrivacy ? 'legalPrivacy' : 'legalTerms';
    final sectionCount = isPrivacy ? 9 : 11;

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
            SettingsSectionCard(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    _isolateEmail(loc.translate('${contentPrefix}Intro')),
                    style: texts.bodyLarge,
                    textAlign: TextAlign.justify,
                  ),
                ),
              ],
            ),
            for (var section = 1; section <= sectionCount; section++) ...[
              const SizedBox(height: 28),
              SettingsSectionHeader(
                title: loc.translate('${contentPrefix}${section}Title'),
              ),
              SettingsSectionCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: isPrivacy || section != 7
                        ? _LegalParagraphs(
                            text: loc.translate('${contentPrefix}${section}Body'),
                          )
                        : _PrivacyReference(
                            text: loc.translate('legalTerms7Body'),
                            reference: loc.translate('legalTermsPrivacyReference'),
                          ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _isolateEmail(String text) => text.replaceAll(
      'brokerwallet@nmodigital.com',
      '\u2066brokerwallet@nmodigital.com\u2069',
    );

class _LegalParagraphs extends StatelessWidget {
  const _LegalParagraphs({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final paragraphs = text.split(RegExp(r'\r?\n\r?\n'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < paragraphs.length; index++) ...[
          if (index > 0) const SizedBox(height: 16),
          Text(
            _isolateEmail(paragraphs[index]),
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.justify,
          ),
        ],
      ],
    );
  }
}

class _PrivacyReference extends StatefulWidget {
  const _PrivacyReference({required this.text, required this.reference});

  final String text;
  final String reference;

  @override
  State<_PrivacyReference> createState() => _PrivacyReferenceState();
}

class _PrivacyReferenceState extends State<_PrivacyReference> {
  late final TapGestureRecognizer _recognizer;

  @override
  void initState() {
    super.initState();
    _recognizer = TapGestureRecognizer()..onTap = () => context.push('/privacy-policy');
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parts = widget.text.split(widget.reference);
    final theme = Theme.of(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: parts.first),
          TextSpan(
            text: widget.reference,
            style: TextStyle(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
            recognizer: _recognizer,
          ),
          TextSpan(text: parts.last),
        ],
      ),
      style: theme.textTheme.bodyLarge,
      textAlign: TextAlign.justify,
    );
  }
}
