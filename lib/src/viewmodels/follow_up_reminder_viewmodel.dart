import 'package:broker_wallet/src/data/models/follow_up_reminder.dart';
import 'package:broker_wallet/src/repositories/follow_up_reminder_repository.dart';
import 'package:flutter/foundation.dart';

enum FollowUpLoadState { loading, ready, failed, offline }

/// State of the follow-up reminder of one Request or Offer on its Details
/// screen. Every change goes through the server; nothing is shown as saved
/// until the server answered.
class FollowUpReminderViewModel extends ChangeNotifier {
  FollowUpReminderViewModel({
    required FollowUpReminderRepository repository,
    required this.target,
    required this.targetId,
    DateTime Function()? now,
  })  : _repository = repository,
        _now = now ?? DateTime.now;

  final FollowUpReminderRepository _repository;
  final FollowUpTarget target;
  final String targetId;
  final DateTime Function() _now;

  FollowUpLoadState _state = FollowUpLoadState.loading;
  FollowUpReminder? _reminder;
  bool _busy = false;
  bool _disposed = false;
  int _generation = 0;

  FollowUpLoadState get state => _state;
  bool get isBusy => _busy;

  /// The reminder still due, or null when none is scheduled.
  FollowUpReminder? get scheduled =>
      _reminder?.isScheduled == true ? _reminder : null;

  /// The earliest time the server accepts (it requires one minute ahead).
  DateTime get earliest => _now().add(const Duration(minutes: 2));

  /// The latest time the server accepts (it allows up to 366 days ahead).
  DateTime get latest => _now().add(const Duration(days: 365));

  Future<void> load() async {
    final generation = ++_generation;
    _state = FollowUpLoadState.loading;
    _notify();
    try {
      final reminder = await _repository.fetch(target, targetId);
      if (generation != _generation || _disposed) return;
      _reminder = reminder;
      _state = FollowUpLoadState.ready;
    } on FollowUpFailure catch (failure) {
      if (generation != _generation || _disposed) return;
      _state = failure.code == FollowUpFailureCode.offline
          ? FollowUpLoadState.offline
          : FollowUpLoadState.failed;
    } catch (_) {
      if (generation != _generation || _disposed) return;
      _state = FollowUpLoadState.failed;
    }
    _notify();
  }

  /// Schedules or moves the reminder. Returns null on success, otherwise the
  /// server's reason; the shown reminder only changes on success.
  Future<FollowUpFailureCode?> schedule(DateTime localTime) async {
    if (_busy) return null;
    if (localTime.isBefore(earliest)) return FollowUpFailureCode.inPast;
    if (localTime.isAfter(latest)) return FollowUpFailureCode.tooFar;
    return _run(() async {
      _reminder = await _repository.schedule(target, targetId, localTime);
    });
  }

  Future<FollowUpFailureCode?> cancel() async {
    if (_busy || scheduled == null) return null;
    return _run(() async {
      await _repository.cancel(target, targetId);
      _reminder = null;
    });
  }

  Future<FollowUpFailureCode?> _run(Future<void> Function() body) async {
    final generation = ++_generation;
    _busy = true;
    _notify();
    try {
      await body();
      if (generation != _generation || _disposed) return null;
      _state = FollowUpLoadState.ready;
      return null;
    } on FollowUpFailure catch (failure) {
      return failure.code;
    } catch (_) {
      return FollowUpFailureCode.unavailable;
    } finally {
      if (generation == _generation) _busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
