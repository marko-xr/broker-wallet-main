import 'package:broker_wallet/src/constants/constants.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:broker_wallet/src/services/quota_service.dart';
import 'package:broker_wallet/src/common/utils/app_notifier.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

/// Helper class to show quota-related dialogs and handle quota checks
/// FREE PLAN LIMIT: 3 items per section
class QuotaHelper {
  /// Check if user can add an item to a section (FREE = 3 items limit)
  /// Returns true if allowed, false if quota exceeded (and shows dialog)
  /// For toolkit, use toolName to customize the message (e.g., 'Scanner', 'Signature')
  static Future<bool> checkAndWarnQuota({
    required BuildContext context,
    required String uid,
    required String section,
    String?
        toolName, // Optional: for toolkit features like "Scanner", "Signature", etc.
  }) async {
    const freeLimit = 3; // FREE users can add 3 items per section

    try {
      // Get user's plan and current count
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (!userDoc.exists) return true; // Allow if user doc doesn't exist yet

      final data = userDoc.data() as Map<String, dynamic>;
      final plan = data['plan'] as String? ?? 'free';

      // Premium users have no limits
      if (plan != 'free') return true;

      // FREE users: Check LIFETIME created quota (not current count)
      // This prevents deleting items to add new ones
      final lifetimeCreated =
          data['lifetimeCreated'] as Map<String, dynamic>? ?? {};
      final lifetimeCount = lifetimeCreated[section] as int? ?? 0;

      if (lifetimeCount >= freeLimit) {
        if (context.mounted) {
          await _showQuotaExceededDialog(
            context,
            section,
            lifetimeCount,
            freeLimit,
            toolName: toolName,
          );
        }
        return false;
      }

      return true;
    } catch (e) {
      return true; // Fail open for better UX
    }
  }

  /// Translate section or toolkit name to localized version
  static String _translateName(AppLocalizations localization, String name) {
    // Convert to lowercase for case-insensitive matching
    final lowerName = name.toLowerCase();

    // Map of section/toolkit names to translation keys
    final Map<String, String> nameMap = {
      // Sections
      'requests': 'requests',
      'offers': 'offers',
      'owners': 'owners',
      'offices': 'offices',
      'brokers': 'brokers',
      'watchmen': 'watchmen',
      'quotations': 'quotations',
      // Toolkit names
      'scanner': 'scanner',
      'signature': 'signature',
      'image to pdf': 'convertImagesToPdf',
      'imagetopdf': 'convertImagesToPdf',
      'combine pdf': 'combinePdfs',
      'combinepdf': 'combinePdfs',
      'combinepdfs': 'combinePdfs',
    };

    // Try to find matching translation key
    final translationKey = nameMap[lowerName];
    if (translationKey != null) {
      return localization.translate(translationKey);
    }

    // If no match found, return original name
    return name;
  }

  /// Show dialog when quota is exceeded
  static Future<void> _showQuotaExceededDialog(
    BuildContext context,
    String section,
    int currentCount,
    int limit, {
    String? toolName,
  }) async {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final localization = AppLocalizations.of(context);

    // Translate section/toolkit name
    final translatedName = toolName != null
        ? _translateName(localization, toolName)
        : _translateName(localization, section);

    // Customize message based on section
    String message;
    if (toolName != null) {
      // Toolkit message
      message = localization
          .translate('quotaToolkitMessage')
          .replaceAll('{count}', '$currentCount')
          .replaceAll('{toolName}', translatedName)
          .replaceAll('{limit}', '$limit');
    } else {
      // Regular section message
      message = localization
          .translate('quotaSectionMessage')
          .replaceAll('{count}', '$currentCount')
          .replaceAll('{section}', translatedName)
          .replaceAll('{limit}', '$limit');
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.lock,
          color: colors.error,
          size: 48,
        ),
        title: Text(localization.translate('freePlanLimitReached')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.workspace_premium,
                          color: colors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        localization.translate('upgradeToPremium'),
                        style: theme.textTheme.titleSmall!.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                      '✓ ${localization.translate('unlimitedItemsInAllSections')}'),
                  Text('✓ ${localization.translate('prioritySupport')}'),
                  Text('✓ ${localization.translate('advancedAnalytics')}'),
                  const SizedBox(height: 8),
                  Text(
                    localization.translate('premiumPricing'),
                    style: theme.textTheme.labelLarge!.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localization.translate('notNow')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/subscription');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
            ),
            child: Text(
              localization.translate('upgradeNow'),
              style: AppTextStyles.buttonText.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// Add import for Firestore
  static final _firestore = FirebaseFirestore.instance;

  /// Show a banner at the top of add screens warning about remaining quota
  static Widget buildQuotaWarningBanner({
    required BuildContext context,
    required String uid,
    required String section,
  }) {
    return StreamBuilder<Map<String, int>>(
      stream: QuotaService().countsStream(uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final counts = snapshot.data!;
        final currentCount = counts[section] ?? 0;
        const limit = 5;
        final remaining = limit - currentCount;

        // Only show for free users approaching limit
        if (remaining > 2 || remaining <= 0) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final colors = theme.colorScheme;

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: remaining == 1
                ? colors.error.withValues(alpha: 0.1)
                : Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: remaining == 1 ? colors.error : Colors.orange,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                remaining == 1 ? Icons.warning : Icons.info,
                color: remaining == 1 ? colors.error : Colors.orange,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      remaining == 1
                          ? '⚠️ Last slot remaining!'
                          : '⚠️ $remaining slots remaining',
                      style: theme.textTheme.titleSmall!.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Upgrade to Premium for unlimited items',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => context.push('/subscription'),
                child: const Text('Upgrade'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Show a success message after adding an item
  static void showSuccessMessage(BuildContext context, String section) {
    AppNotifier.show(context, 'Item added to $section successfully!',
        isError: false, duration: const Duration(seconds: 2));
  }

  /// Show an error message
  static void showErrorMessage(BuildContext context, String message) {
    AppNotifier.show(context, message, isError: true);
  }
}
