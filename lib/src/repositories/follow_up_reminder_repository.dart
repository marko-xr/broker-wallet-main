import 'package:broker_wallet/src/data/models/follow_up_reminder.dart';
import 'package:broker_wallet/src/services/app_access_policy.dart';
import 'package:broker_wallet/src/services/app_session_coordinator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Why a follow-up reminder operation did not happen. Each value is a fixed
/// server code (or the app's offline state); nothing is guessed.
enum FollowUpFailureCode {
  offline,
  sessionSuperseded,
  inPast,
  tooFar,
  notFound,
  tooMany,
  unavailable,
}

class FollowUpFailure implements Exception {
  const FollowUpFailure(this.code);
  final FollowUpFailureCode code;

  @override
  String toString() => 'FollowUpFailure(${code.name})';
}

abstract class FollowUpReminderRepository {
  /// The reminder of one record, or null when it never had one.
  Future<FollowUpReminder?> fetch(FollowUpTarget target, String targetId);

  /// Creates or moves the record's reminder to [remindAt] (any time zone).
  Future<FollowUpReminder> schedule(
    FollowUpTarget target,
    String targetId,
    DateTime remindAt,
  );

  /// Cancels a scheduled reminder. False when there was none to cancel.
  Future<bool> cancel(FollowUpTarget target, String targetId);
}

class SupabaseFollowUpReminderRepository implements FollowUpReminderRepository {
  SupabaseFollowUpReminderRepository({SupabaseClient? client})
      : _injected = client;

  final SupabaseClient? _injected;

  /// Resolved on use, inside the error guard: a screen that shows this
  /// section never fails to build because Supabase is not ready.
  SupabaseClient get _client => _injected ?? Supabase.instance.client;

  @override
  Future<FollowUpReminder?> fetch(FollowUpTarget target, String targetId) {
    return _guard(() async {
      final column =
          target == FollowUpTarget.request ? 'request_id' : 'offer_id';
      final row = await _client
          .from('follow_up_reminders')
          .select('id, remind_at, status')
          .eq(column, targetId)
          .maybeSingle();
      return row == null ? null : FollowUpReminder.fromRow(row);
    });
  }

  @override
  Future<FollowUpReminder> schedule(
    FollowUpTarget target,
    String targetId,
    DateTime remindAt,
  ) {
    return _guard(() async {
      final rows = await _client.rpc('set_follow_up_reminder', params: {
        'p_target_type': target.wireName,
        'p_target_id': targetId,
        'p_remind_at': remindAt.toUtc().toIso8601String(),
      }) as List<dynamic>;
      final reminder = rows.isEmpty
          ? null
          : FollowUpReminder.fromRow(Map<String, dynamic>.from(rows.first));
      if (reminder == null) {
        throw const FollowUpFailure(FollowUpFailureCode.unavailable);
      }
      return reminder;
    });
  }

  @override
  Future<bool> cancel(FollowUpTarget target, String targetId) {
    return _guard(() async {
      final result = await _client.rpc('cancel_follow_up_reminder', params: {
        'p_target_type': target.wireName,
        'p_target_id': targetId,
      });
      return result == true;
    });
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    if (!AppAccessPolicy.isOnline) {
      throw const FollowUpFailure(FollowUpFailureCode.offline);
    }
    String? accessToken;
    try {
      accessToken = _client.auth.currentSession?.accessToken;
      return await body();
    } on FollowUpFailure {
      rethrow;
    } on PostgrestException catch (error) {
      final code = mapFollowUpError(error.message);
      if (code == FollowUpFailureCode.sessionSuperseded &&
          accessToken != null) {
        AppSessionCoordinator.reportBackendError(error,
            accessToken: accessToken);
      }
      throw FollowUpFailure(code);
    } catch (_) {
      throw const FollowUpFailure(FollowUpFailureCode.unavailable);
    }
  }
}

/// Maps the fixed messages of the follow-up RPCs to failure codes.
FollowUpFailureCode mapFollowUpError(String message) {
  if (message.contains('session_superseded')) {
    return FollowUpFailureCode.sessionSuperseded;
  }
  if (message.contains('remind_at_in_past')) return FollowUpFailureCode.inPast;
  if (message.contains('remind_at_too_far')) return FollowUpFailureCode.tooFar;
  if (message.contains('target_not_found')) {
    return FollowUpFailureCode.notFound;
  }
  if (message.contains('too_many_reminders')) {
    return FollowUpFailureCode.tooMany;
  }
  return FollowUpFailureCode.unavailable;
}
