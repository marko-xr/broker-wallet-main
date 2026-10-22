import 'dart:async';
import 'dart:isolate';

class _Start {
  const _Start(this.reply, this.work);

  final SendPort reply;
  final Object? Function() work;
}

class _Done {
  const _Done(this.value);

  final Object? value;
}

class _Failed {
  const _Failed(this.error);

  final Object? error;
}

void _entry(_Start start) {
  try {
    start.reply.send(_Done(start.work()));
  } catch (error) {
    try {
      start.reply.send(_Failed(error));
    } catch (_) {
      // The error itself cannot cross isolates: the caller maps "no detail".
      start.reply.send(const _Failed(null));
    }
  }
}

/// Runs [work] on a short-lived worker isolate, like `Isolate.run`, but with a
/// deadline: when [limit] passes the worker is killed (a `Future.timeout`
/// around `Isolate.run` would leave it computing) and the result is the error
/// [onTimeout] returns. An error the worker threw is rethrown as it was, so a
/// caller's own typed failures keep their meaning; an error that cannot cross
/// isolates, or a worker that dies, becomes [onFailure]'s error.
///
/// [work] may capture only plain sendable data (a path, a number): no plugin,
/// no view model, no account object.
Future<R> runBoundedIsolate<R>(
  R Function() work, {
  required Duration limit,
  required Object Function() onTimeout,
  required Object Function() onFailure,
}) async {
  final results = ReceivePort();
  final errors = ReceivePort();
  final done = Completer<R>();
  Isolate? worker;
  Timer? deadline;
  try {
    results.listen((Object? message) {
      if (done.isCompleted) return;
      if (message is _Done) {
        done.complete(message.value as R);
      } else if (message is _Failed) {
        done.completeError(message.error ?? onFailure());
      } else {
        done.completeError(onFailure());
      }
    });
    errors.listen((Object? _) {
      if (!done.isCompleted) done.completeError(onFailure());
    });
    try {
      worker = await Isolate.spawn<_Start>(
        _entry,
        _Start(results.sendPort, work),
        onError: errors.sendPort,
        errorsAreFatal: true,
      );
    } catch (_) {
      throw onFailure();
    }
    deadline = Timer(limit, () {
      if (!done.isCompleted) done.completeError(onTimeout());
    });
    return await done.future;
  } finally {
    deadline?.cancel();
    worker?.kill(priority: Isolate.immediate);
    results.close();
    errors.close();
  }
}
