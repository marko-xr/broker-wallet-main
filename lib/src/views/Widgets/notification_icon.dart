// lib/src/widgets/notification_icon.dart
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/images.dart';
import 'package:broker_wallet/src/constants/app_colors.dart';
import 'package:broker_wallet/src/viewmodels/notification_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class NotificationIcon extends StatelessWidget {
  final VoidCallback? onPressed;

  const NotificationIcon({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    const badgeColor = AppColors.notificationBadge;
    const onBadge = Colors.white;
    // Very light grey background
    final bgGrey = Color.fromARGB((0.1 * 255).round(), Colors.grey.red,
        Colors.grey.green, Colors.grey.blue);

    return Consumer<NotificationViewModel>(
      builder: (context, vm, _) {
        final unreadCount = vm.unreadCount;
        final badgeLabel = unreadCount > 99 ? '99+' : '$unreadCount';
        final showBadge = unreadCount > 0;

        // The whole 48 dp circle, badge included, is one button: a tap
        // anywhere on it opens the notifications, not only on the bell image.
        return Semantics(
          button: true,
          label: AppLocalizations.of(context).translate('notifications'),
          excludeSemantics: true,
          child: Material(
            key: const ValueKey('notification-icon-button'),
            color: bgGrey,
            shape: const CircleBorder(),
            // No clip: the badge keeps drawing over the circle's edge as
            // before; the ripple stays round through customBorder.
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed ?? () => context.push('/notifications'),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: Image.asset(
                        AppImages.notification,
                        width: 28,
                        height: 28,
                      ),
                    ),
                    if (showBadge)
                      // Unread-count badge: alert red with white digits, at
                      // its original size and place.
                      Positioned(
                        right: 6,
                        top: 4,
                        child: Container(
                          key: const ValueKey('notification-icon-badge'),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            badgeLabel,
                            style: const TextStyle(
                              color: onBadge,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
