import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_platform_policy.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// DESIGN REVIEW ONLY. The owner's proposed iPhone sheet saying Plus is activated
/// in a browser.
///
/// App Store guideline 3.1.1(a) does not allow this call to action on the UAE
/// storefront without an entitlement Broker Wallet does not have. It is reachable
/// only from the debug preview gallery, its text lives here rather than in the
/// shipped language files, and no server or remote value can enable it.
class IosWebActivationPreviewSheet extends StatelessWidget {
  const IosWebActivationPreviewSheet({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode ||
        !SubscriptionPlatformPolicy.canShowIosWebActivationPreview()) {
      return const SizedBox.shrink();
    }
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SubNotice(
              icon: Icons.block_rounded,
              tone: SubTone.attention,
              text: arabic
                  ? 'معاينة تصميم فقط. لا تظهر في نسخة App Store.'
                  : 'Design preview only. Never shown in an App Store build.',
            ),
            SubMessage(
              icon: Icons.language_rounded,
              title: arabic
                  ? 'فعّل Plus عبر المتصفح'
                  : 'Activate Plus in your browser',
              body: arabic
                  ? 'يمكن تفعيل Broker Wallet Plus من حسابك عبر المتصفح، ثم يظهر هنا تلقائيًا.'
                  : 'Broker Wallet Plus can be activated from your account in a browser, then appears here automatically.',
            ),
            SubSecondaryButton(
              label: arabic ? 'إغلاق' : 'Close',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
