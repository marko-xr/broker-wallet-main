import 'package:broker_wallet/src/data/models/notification_model.dart';
import 'package:broker_wallet/src/viewmodels/notification_viewmodel.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class NotificationsListView extends StatefulWidget {
  const NotificationsListView({super.key});

  @override
  State<NotificationsListView> createState() => _NotificationsListViewState();
}

class _NotificationsListViewState extends State<NotificationsListView> {
  Future<void> _onRefresh(NotificationViewModel vm) async {
    await vm.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationViewModel>(
      builder: (context, vm, _) {
        return Scaffold(
          appBar: AppBar(
            title:
                Text(AppLocalizations.of(context).translate('notifications')),
            actions: [
              if (vm.unreadCount > 0)
                TextButton(
                  onPressed: vm.markAllAsRead,
                  child: Text(
                      AppLocalizations.of(context).translate('markAllRead')),
                ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () => _onRefresh(vm),
            child: vm.isLoading
                ? const Center(child: CircularProgressIndicator())
                : vm.isEmpty
                    ? _EmptyState(onRefresh: () => _onRefresh(vm))
                    : NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification.metrics.pixels >=
                              notification.metrics.maxScrollExtent - 200) {
                            vm.loadMore();
                          }
                          return false;
                        },
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          itemCount: vm.notifications.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final notification = vm.notifications[index];
                            return _NotificationTile(
                              notification: notification,
                              onTap: () =>
                                  _handleTap(context, vm, notification),
                              onDismissed: () =>
                                  vm.deleteNotification(notification.id),
                            );
                          },
                        ),
                      ),
          ),
        );
      },
    );
  }

  void _handleTap(
    BuildContext context,
    NotificationViewModel vm,
    NotificationModel notification,
  ) {
    vm.markAsRead(notification.id);

    // Handle navigation based on notification category
    switch (notification.category) {
      case NotificationCategory.match:
        // Navigate to match details view showing both request and offer
        if (notification.requestId != null && notification.offerId != null) {
          context.push(
            '/match-details',
            extra: {
              'requestId': notification.requestId,
              'offerId': notification.offerId,
              'matchScore': notification.matchScore,
            },
          );
          return;
        }
        break;

      case NotificationCategory.reminder:
        // Navigate to specific item detail
        if (notification.offerId != null) {
          context.push('/offers-details-by-id/${notification.offerId}');
          return;
        }
        if (notification.requestId != null) {
          context.push('/requested-details-by-id/${notification.requestId}');
          return;
        }
        break;

      case NotificationCategory.plan:
        // Navigate to subscription/plan page
        context.push('/my-plan');
        return;

      case NotificationCategory.system:
        // System notifications may have a custom action route or just show info
        final route = notification.actionRoute ?? notification.data['route'];
        if (route is String && route.isNotEmpty) {
          context.push(route, extra: notification.data);
          return;
        }
        // Default: open app store for update (handled by data['storeUrl'])
        final storeUrl = notification.data['storeUrl'] as String?;
        if (storeUrl != null) {
          // Will be handled by url_launcher in the app
          return;
        }
        break;
    }

    // Fallback: use actionRoute or data['route'] if available
    final route = notification.actionRoute ?? notification.data['route'];
    if (route is String && route.isNotEmpty) {
      context.push(route, extra: notification.data);
    }
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
    required this.onDismissed,
  });

  final NotificationModel notification;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  IconData get _leadingIcon {
    switch (notification.category) {
      case NotificationCategory.match:
        return Icons.handshake;
      case NotificationCategory.reminder:
        return Icons.alarm;
      case NotificationCategory.plan:
        return Icons.workspace_premium;
      case NotificationCategory.system:
        return Icons.system_update;
    }
  }

  Color _statusColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return notification.isRead ? scheme.outline : scheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = Text(
      notification.body,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    final relativeTimeStr = _relativeTime(notification.createdAt);
    final timeLabel = Text(
      _formatTimeLabel(context, relativeTimeStr),
      style: Theme.of(context).textTheme.labelSmall,
    );

    final tile = ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: _statusColor(context).withValues(alpha: 0.12),
        child: Icon(
          _leadingIcon,
          color: _statusColor(context),
        ),
      ),
      title: Text(
        notification.title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight:
                  notification.isRead ? FontWeight.w500 : FontWeight.bold,
            ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          subtitle,
          const SizedBox(height: 6),
          timeLabel,
        ],
      ),
      tileColor: notification.isRead
          ? Theme.of(context).colorScheme.surface
          : Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    );

    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDismissed(),
      child: tile,
    );
  }

  String _relativeTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inSeconds.abs() < 60) {
      return 'justNow'; // Will be translated in the widget
    }
    if (diff.inMinutes.abs() < 60) {
      final minutes = diff.inMinutes.abs();
      return '$minutes minAgo'; // Will be translated in the widget
    }
    if (diff.inHours.abs() < 24) {
      final hours = diff.inHours.abs();
      return '$hours hAgo'; // Will be translated in the widget
    }
    if (diff.inDays == 0) {
      return 'today'; // Will be translated in the widget
    }

    return DateFormat.yMMMd().add_jm().format(date);
  }

  String _formatTimeLabel(BuildContext context, String relativeTimeStr) {
    // If it contains a number, it's a time with number (e.g., "5 minAgo" or "3 hAgo")
    if (relativeTimeStr.contains(' ')) {
      final parts = relativeTimeStr.split(' ');
      if (parts.length == 2) {
        final number = parts[0];
        final key = parts[1];
        return '$number ${AppLocalizations.of(context).translate(key)}';
      }
    }

    // Otherwise it's a simple key like "justNow", "today", or a formatted date
    if (relativeTimeStr.contains(':') || relativeTimeStr.contains('/')) {
      // It's a formatted date, return as is
      return relativeTimeStr;
    }

    // It's a translation key
    return AppLocalizations.of(context).translate(relativeTimeStr);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        Icon(
          Icons.notifications_active_outlined,
          size: 64,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 16),
        Text(
          AppLocalizations.of(context).translate('youAreAllCaughtUp'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          AppLocalizations.of(context).translate('newMatchesWillAppear'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        Center(
          child: FilledButton.tonal(
            onPressed: onRefresh,
            child: Text(AppLocalizations.of(context).translate('refresh')),
          ),
        ),
      ],
    );
  }
}
