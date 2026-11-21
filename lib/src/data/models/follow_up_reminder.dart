import 'package:flutter/foundation.dart';

/// The kind of record a follow-up reminder belongs to.
enum FollowUpTarget {
  request('request'),
  offer('offer');

  const FollowUpTarget(this.wireName);

  /// The value the server RPCs expect (`p_target_type`).
  final String wireName;
}

enum FollowUpReminderStatus { scheduled, sent, cancelled }

/// A user-chosen follow-up time for one Request or Offer. The server owns the
/// row; the app only reads it and changes it through session-gated RPCs.
@immutable
class FollowUpReminder {
  const FollowUpReminder({
    required this.id,
    required this.remindAt,
    required this.status,
  });

  final String id;

  /// The instant the reminder is due, in UTC.
  final DateTime remindAt;
  final FollowUpReminderStatus status;

  bool get isScheduled => status == FollowUpReminderStatus.scheduled;

  /// Null for a row the app cannot read honestly (bad id, time or status).
  static FollowUpReminder? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? row['reminder_id']?.toString() ?? '';
    final remindAt = DateTime.tryParse(row['remind_at']?.toString() ?? '');
    final status = switch (row['status']?.toString()) {
      'scheduled' => FollowUpReminderStatus.scheduled,
      'sent' => FollowUpReminderStatus.sent,
      'cancelled' => FollowUpReminderStatus.cancelled,
      _ => null,
    };
    if (id.isEmpty || remindAt == null || status == null) return null;
    return FollowUpReminder(id: id, remindAt: remindAt.toUtc(), status: status);
  }
}
