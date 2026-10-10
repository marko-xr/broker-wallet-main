import 'dart:async';

/// Runs one asynchronous task at a time, and makes sure that a request that
/// arrives while it is running is not lost.
///
/// [run] starts the task. If the task is already running, nothing is started
/// in parallel: the task runs once more right after it finishes, however many
/// requests came in meanwhile, so the last request always sees the latest state
/// and a burst of requests costs at most two runs.
class CoalescedRunner {
  CoalescedRunner(this._task);

  final Future<void> Function() _task;

  Future<void>? _current;
  bool _again = false;

  /// Whether the task is running now.
  bool get isRunning => _current != null;

  /// Completes when the run this request belongs to has finished: the run it
  /// started, or the run it joined (including the extra run it asked for).
  Future<void> run() {
    final running = _current;
    if (running != null) {
      _again = true;
      return running;
    }
    return _current = _loop();
  }

  Future<void> _loop() async {
    try {
      do {
        _again = false;
        await _task();
      } while (_again);
    } finally {
      _current = null;
    }
  }
}
