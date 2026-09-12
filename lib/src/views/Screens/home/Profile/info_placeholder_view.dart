// lib/src/views/Screens/home/Profile/info_placeholder_view.dart
//
// Reusable, production-quality "not available yet" destination for
// Profile/Settings rows that exist in the information architecture but
// whose real implementation (legal content, support content, backend
// logic) is deferred to a later checkpoint. This screen never invents
// policy, legal, or contact content — it only communicates honestly that
// the destination is coming.
import 'package:flutter/material.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/info_placeholder_args.dart';

class InfoPlaceholderView extends StatelessWidget {
  final InfoPlaceholderArgs args;

  const InfoPlaceholderView({super.key, required this.args});

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
        title: Text(args.title, style: texts.titleLarge),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colors.surface,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(args.icon, color: colors.primary, size: 40),
                ),
                const SizedBox(height: 24),
                Text(
                  args.message,
                  textAlign: TextAlign.center,
                  style: texts.bodyLarge?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.primary,
                      side: BorderSide(color: colors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Text(loc.translate('ok')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
