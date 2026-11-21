import 'package:broker_wallet/src/data/models/notification_model.dart';
import 'package:broker_wallet/src/viewmodels/notification_viewmodel.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/views/Widgets/delete_confirmation_dialog.dart';
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
  /// One tap opens one screen: further taps are ignored until it is closed.
  bool _opening = false;

  Future<void> _onRefresh(NotificationViewModel vm) async {
    await vm.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationViewModel>(
      builder: (context, vm, _) {
        final textScaler = MediaQuery.textScalerOf(context);
        final compactHeader =
            MediaQuery.sizeOf(context).width < 360 || textScaler.scale(14) > 20;
        final markAllButton = vm.unreadCount > 0
            ? TextButton(
                onPressed: vm.markAllAsRead,
                child: Text(
                  AppLocalizations.of(context).translate('markAllRead'),
                ),
              )
            : null;
        final deleteAllButton = vm.notifications.isEmpty
            ? null
            : IconButton(
                key: const ValueKey('notifications-delete-all'),
                tooltip: AppLocalizations.of(context)
                    .translate('deleteAllNotifications'),
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () => _confirmDeleteAll(context, vm),
              );
        final showRetryFooter = vm.loadMoreFailed;
        final feed = RefreshIndicator(
          onRefresh: () => _onRefresh(vm),
          child: vm.isLoading
              ? const Center(child: CircularProgressIndicator())
              : vm.isEmpty && vm.isOffline
                  ? _StatusState(
                      icon: Icons.cloud_off_outlined,
                      titleKey: 'notificationsOffline',
                      actionKey: 'retry',
                      onAction: () => _onRefresh(vm),
                    )
                  : vm.isEmpty && vm.isFeedUnavailable
                      ? _StatusState(
                          icon: Icons.error_outline,
                          titleKey: 'notificationsLoadFailed',
                          actionKey: 'retry',
                          onAction: () => _onRefresh(vm),
                        )
                      : vm.isEmpty
                          ? _EmptyState(onRefresh: () => _onRefresh(vm))
                          : NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (vm.hasMore &&
                                    notification.metrics.pixels >=
                                        notification.metrics.maxScrollExtent -
                                            200) {
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
                                itemCount: vm.notifications.length +
                                    (showRetryFooter ? 1 : 0),
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  if (index == vm.notifications.length) {
                                    return Center(
                                      child: TextButton(
                                        onPressed: vm.retryLoadMore,
                                        child: Text(
                                          AppLocalizations.of(context)
                                              .translate('retry'),
                                        ),
                                      ),
                                    );
                                  }
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
        );

        return Scaffold(
          appBar: AppBar(
            toolbarHeight: compactHeader ? 72 : null,
            title: Text(
              AppLocalizations.of(context).translate('notifications'),
              maxLines: 2,
            ),
            actions: [
              if (!compactHeader && markAllButton != null) markAllButton,
              if (deleteAllButton != null) deleteAllButton,
            ],
          ),
          body: compactHeader && markAllButton != null
              ? Column(
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          12,
                          4,
                          12,
                          0,
                        ),
                        child: markAllButton,
                      ),
                    ),
                    Expanded(child: feed),
                  ],
                )
              : feed,
        );
      },
    );
  }

  /// Opens the destination at once: nothing is awaited before the screen
  /// starts to move. A reminder's record is found by the destination while
  /// its fade through plays (see [inboxDestination]).
  void _handleTap(
    BuildContext context,
    NotificationViewModel vm,
    NotificationModel notification,
  ) {
    vm.markAsRead(notification.id);
    final target = inboxDestination(notification);
    if (target == null || _opening) return;
    _opening = true;
    context
        .push(target.location, extra: target.extra)
        .whenComplete(() => _opening = false);
  }

  Future<void> _confirmDeleteAll(
    BuildContext context,
    NotificationViewModel vm,
  ) async {
    final loc = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final confirmed = await showDeleteConfirmationDialog(
      context,
      title: loc.translate('deleteAllNotifications'),
      message: loc.translate('deleteAllNotificationsMessage'),
      itemIcon: Icons.notifications_outlined,
      itemLabel: loc.translate('allNotifications'),
    );
    if (!confirmed) return;
    final deleted = await vm.deleteAllNotifications();
    if (!deleted && mounted) {
      messenger?.showSnackBar(SnackBar(
        content: Text(loc.translate('deleteAllNotificationsFailed')),
      ));
    }
  }
}

/// The app's own wording for notifications it knows, in the app language;
/// the stored English text otherwise. A follow-up reminder is created by the
/// server in English and shown here in Arabic or English.
({String title, String body}) localizedNotificationText(
  BuildContext context,
  NotificationModel notification,
) {
  if (notification.data['kind'] == 'follow_up' &&
      notification.category == NotificationCategory.reminder) {
    final loc = AppLocalizations.of(context);
    return (
      title: loc.translate('followUpReminder'),
      body: loc.translate(notification.data['target'] == 'offer'
          ? 'followUpNotificationOffer'
          : 'followUpNotificationRequest'),
    );
  }
  return (title: notification.title, body: notification.body);
}

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool _isRecordId(String? value) => value != null && _uuid.hasMatch(value);

/// Where a tapped notification may lead. Only these fixed screens are
/// reachable, each built from a validated record id; the stored
/// `action_route`, `data['route']` and any URL in `data` are never followed.
/// Null means the tap only marks the notification read.
/// Request details opened from the inbox: fades through like the Home list
/// screens and finds its record while the motion plays (app.dart).
const String notificationRequestRoute = '/notification-request';

/// Offer details opened from the inbox, the same way.
const String notificationOfferRoute = '/notification-offer';

/// Where an inbox tap goes, decided at once: nothing is awaited before the
/// screen starts to open. A follow-up reminder opens
/// [notificationRequestRoute] or [notificationOfferRoute]; match and plan
/// notifications keep [notificationTarget] unchanged.
({String location, Object? extra})? inboxDestination(
  NotificationModel notification,
) {
  final target = notificationTarget(notification);
  if (target == null ||
      notification.category != NotificationCategory.reminder) {
    return target;
  }
  final offerId = notification.offerId;
  if (target.location.startsWith('/offers-details-by-id/') && offerId != null) {
    return (
      location: '$notificationOfferRoute/${Uri.encodeComponent(offerId)}',
      extra: null,
    );
  }
  final requestId = notification.requestId;
  if (target.location.startsWith('/requested-details-by-id/') &&
      requestId != null) {
    return (
      location: '$notificationRequestRoute/${Uri.encodeComponent(requestId)}',
      extra: null,
    );
  }
  return target;
}

@visibleForTesting
({String location, Object? extra})? notificationTarget(
  NotificationModel notification,
) {
  final offerId = notification.offerId;
  final requestId = notification.requestId;
  switch (notification.category) {
    case NotificationCategory.match:
      if (_isRecordId(requestId) && _isRecordId(offerId)) {
        return (
          location: '/match-details',
          extra: <String, dynamic>{
            'requestId': requestId,
            'offerId': offerId,
            'matchScore': notification.matchScore,
          },
        );
      }
      return null;
    case NotificationCategory.reminder:
      if (_isRecordId(offerId)) {
        return (location: '/offers-details-by-id/$offerId', extra: null);
      }
      if (_isRecordId(requestId)) {
        return (location: '/requested-details-by-id/$requestId', extra: null);
      }
      return null;
    case NotificationCategory.plan:
      return (location: '/my-plan', extra: null);
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

  static const BorderRadius _cardRadius = BorderRadius.all(Radius.circular(16));

  IconData get _leadingIcon {
    switch (notification.category) {
      case NotificationCategory.match:
        return Icons.handshake;
      case NotificationCategory.reminder:
        return Icons.alarm;
      case NotificationCategory.plan:
        return Icons.workspace_premium;
    }
  }

  /// The card every notification sits on, read or not: the plain card
  /// surface (white in light mode, the app's dark surface in dark mode) with
  /// a fine neutral outline and, in light mode, a soft neutral shadow, so it
  /// stands off the page without colour. Unread is shown by signals, not by
  /// recolouring the card: a brand-colour dot, a bold title, a brand-colour
  /// icon and time, and a very light flat brand tint.
  static BoxDecoration _cardDecoration(
    ColorScheme colors, {
    required bool unread,
  }) {
    final dark = colors.brightness == Brightness.dark;
    final card = dark ? colors.surface : Colors.white;
    return BoxDecoration(
      color: unread
          ? Color.alphaBlend(
              colors.primary.withValues(alpha: dark ? 0.12 : 0.06),
              card,
            )
          : card,
      borderRadius: _cardRadius,
      border: Border.all(
        color: unread
            ? colors.primary.withValues(alpha: 0.28)
            : colors.onSurface.withValues(alpha: dark ? 0.12 : 0.08),
      ),
      boxShadow: dark
          ? null
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final unread = !notification.isRead;
    final loc = AppLocalizations.of(context);
    final text = localizedNotificationText(context, notification);
    final muted = colors.onSurface.withValues(alpha: 0.6);

    final listTile = ListTile(
      onTap: onTap,
      shape: const RoundedRectangleBorder(borderRadius: _cardRadius),
      // Compact row: tight padding, still well above the 48 dp tap target.
      contentPadding: const EdgeInsetsDirectional.fromSTEB(14, 2, 12, 2),
      minVerticalPadding: 6,
      horizontalTitleGap: 12,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: unread
            ? colors.primary.withValues(alpha: 0.12)
            : colors.onSurface.withValues(alpha: 0.06),
        child: Icon(
          _leadingIcon,
          color: unread ? colors.primary : muted,
        ),
      ),
      title: Text(
        text.title,
        style: theme.textTheme.titleMedium?.copyWith(
          color: colors.onSurface,
          fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            text.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: unread
                  ? colors.onSurface.withValues(alpha: 0.87)
                  : colors.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _formatTimeLabel(context, _relativeTime(notification.createdAt)),
            style: theme.textTheme.labelSmall?.copyWith(
              color: unread ? colors.primary : muted,
              fontWeight: unread ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
      // Unread: a small brand-colour dot at the end of the row.
      trailing: unread
          ? Semantics(
              label: loc.translate('notificationUnread'),
              child: Container(
                key: const ValueKey('notification-unread-dot'),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );

    final tile = DecoratedBox(
      key: ValueKey('notification-card-${notification.id}'),
      decoration: _cardDecoration(colors, unread: unread),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: _cardRadius,
        clipBehavior: Clip.antiAlias,
        child: listTile,
      ),
    );

    // The swipe runs from the end edge toward the start (right to left in
    // English, left to right in Arabic), so the bin sits on the end side,
    // where the card uncovers it.
    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        key: const ValueKey('notification-delete-background'),
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          borderRadius: _cardRadius,
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

/// The same layout as [_EmptyState] for a feed that could not be read
/// (offline or failed), so an empty screen is never shown as "all caught up".
class _StatusState extends StatelessWidget {
  const _StatusState({
    required this.icon,
    required this.titleKey,
    required this.actionKey,
    required this.onAction,
  });

  final IconData icon;
  final String titleKey;
  final String actionKey;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        Icon(
          icon,
          size: 64,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 16),
        Text(
          AppLocalizations.of(context).translate(titleKey),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 24),
        Center(
          child: FilledButton.tonal(
            onPressed: onAction,
            child: Text(AppLocalizations.of(context).translate(actionKey)),
          ),
        ),
      ],
    );
  }
}
