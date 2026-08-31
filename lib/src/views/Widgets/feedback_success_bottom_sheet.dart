import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

class FeedbackSuccessBottomSheet extends StatelessWidget {
  const FeedbackSuccessBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;
    final loc = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Close button
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 0, top: 0, bottom: 0),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow.withValues(alpha: 0.06),
                      blurRadius: 3,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 20,
                    color: colors.primary,
                  ),
                  onPressed: () => Navigator.pop(context),
                  splashRadius: 24,
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ),

          const SizedBox(height: 25), // Reduced from 20

          // SVG Illustration
          SvgPicture.asset(
            SvgIcon.sharingFeedback,
            width: 250,
            height: 200,
          ),

          const SizedBox(height: 15), // Reduced from 25

          // Success message
          Text(
            loc.translate('thankYouForFeedback'),
            textAlign: TextAlign.center,
            style: texts.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),

          const SizedBox(height: 25), // Reduced from 40

          // Done button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onPressed: () {
                Navigator.pop(context); // Close bottom sheet
                if (context.canPop()) {
                  context.pop(); // Go back to profile
                } else {
                  context.go('/profile');
                }
              },
              child: Text(
                loc.translate('done'),
                style: texts.labelLarge?.copyWith(
                  color: colors.onPrimary,
                ),
              ),
            ),
          ),

          const SizedBox(
              height: 45), // Increased from 30 to maintain total height
        ],
      ),
    );
  }
}
