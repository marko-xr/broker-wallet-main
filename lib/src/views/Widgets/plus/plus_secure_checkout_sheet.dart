import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/localization/plus_localization.dart';
import 'package:broker_wallet/src/data/models/subscription/subscription_ui_models.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_presentation.dart';
import 'package:broker_wallet/src/views/Widgets/plus/plus_widgets.dart';

/// "Secure checkout": the Broker Wallet-owned pause between the purchase
/// review and the store's own purchase sheet.
///
/// It exists so the user knows, before anything starts, that the next thing
/// they see belongs to Google Play or the App Store, that the payment details
/// are theirs to enter there, and that Broker Wallet never sees or stores them.
/// It is not the store's sheet and does not imitate it: there is no card, no
/// payment field and no price breakdown here, only the explanation and the
/// choice to continue.
///
/// [show] resolves to true only when the user chose to continue, which is the
/// caller's cue to begin the purchase. In debug builds the purchase that
/// follows is the preview path, and [isPreview] says so on the sheet.
class PlusSecureCheckoutSheet extends StatelessWidget {
  const PlusSecureCheckoutSheet({
    super.key,
    required this.store,
    this.isPreview = false,
  });

  final PlusStore store;

  /// True while the plans are development preview data: nothing real happens.
  final bool isPreview;

  static Future<bool> show(
    BuildContext context, {
    required PlusStore store,
    bool isPreview = false,
  }) async {
    final proceed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PlusSecureCheckoutSheet(
        store: store,
        isPreview: isPreview,
      ),
    );
    return proceed ?? false;
  }

  String _handlingKey() {
    switch (store) {
      case PlusStore.googlePlay:
        return 'plusCheckoutNoteGoogle';
      case PlusStore.appStore:
        return 'plusCheckoutNoteApple';
      case PlusStore.unknown:
        return 'plusCheckoutNoteGeneric';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final storeName = plusStoreName(l10n, store);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Center(
                child: PlusIconBadge(
                  icon: Icons.lock_outline_rounded,
                  size: 64,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.translate('plusCheckoutTitle'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.plusText('plusCheckoutBody', {'store': storeName}),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.onSurface,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.translate(_handlingKey()),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.8),
                  height: 1.45,
                ),
              ),
              if (isPreview) ...[
                const SizedBox(height: 16),
                const PlusPreviewBanner(),
              ],
              const SizedBox(height: 20),
              PlusPrimaryButton(
                label: l10n.plusText('plusContinueToStore', {
                  'store': storeName,
                }),
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: colors.onSurface.withValues(alpha: 0.75),
                ),
                child: Text(
                  l10n.translate('notNow'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
