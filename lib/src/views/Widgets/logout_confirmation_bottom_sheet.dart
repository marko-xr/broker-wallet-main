import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

class LogoutConfirmationBottomSheet extends StatelessWidget {
  final Future<void> Function()? onLogout;

  const LogoutConfirmationBottomSheet({
    super.key,
    this.onLogout,
  });

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

          const SizedBox(height: 5),

          // SVG Illustration
          SvgPicture.asset(
            SvgIcon.confirmLogout,
            width: 200,
            height: 180,
          ),

          const SizedBox(height: 15),

          // Confirmation message
          Text(
            loc.translate('logoutConfirmation'),
            textAlign: TextAlign.center,
            style: texts.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),

          const SizedBox(height: 25),

          // Logout button
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
              onPressed: () async {
                // Close the bottom sheet immediately
                Navigator.of(context).pop();

                // Call the logout callback
                final callback = onLogout;
                if (callback != null) {
                  await callback();
                }
              },
              child: Text(
                loc.translate('yesLogOut'),
                style: texts.labelLarge?.copyWith(
                  color: colors.onPrimary,
                ),
              ),
            ),
          ),

          const SizedBox(height: 45),
        ],
      ),
    );
  }
}
