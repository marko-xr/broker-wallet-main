// lib/src/widgets/notification_icon.dart
import 'package:broker_wallet/src/common/utils/images.dart';
import 'package:broker_wallet/src/viewmodels/notification_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class NotificationIcon extends StatelessWidget {
  final VoidCallback? onPressed;

  const NotificationIcon({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    // Very light grey background
    final bgGrey = Color.fromARGB((0.1 * 255).round(), Colors.grey.red,
        Colors.grey.green, Colors.grey.blue);

    return Consumer<NotificationViewModel>(
      builder: (context, vm, _) {
        final unreadCount = vm.unreadCount;
        final badgeLabel = unreadCount > 99 ? '99+' : '$unreadCount';
        final showBadge = unreadCount > 0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: bgGrey,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: onPressed ?? () => context.push('/notifications'),
                iconSize: 28,
                padding: EdgeInsets.zero,
                icon: Image.asset(
                  AppImages.notification,
                  width: 28,
                  height: 28,
                ),
              ),
            ),
            if (showBadge)
              Positioned(
                right: 6,
                top: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badgeLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
