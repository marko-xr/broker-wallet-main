import 'dart:async';
import 'dart:isolate';

import 'package:broker_wallet/src/services/combine_pdf/combine_models.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_pdf_engine.dart';
import 'package:broker_wallet/src/services/toolkit/bounded_isolate.dart';

/// Lets the user stop a combine that is running.
class CombineCancelToken {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }
}

/// Where PDF work runs. Reading and combining PDFs is CPU work on whole
/// documents, so production runs it on a worker isolate and the screen never
/// freezes; tests run it inline.
abstract interface class CombineExecutor {
  /// Reads and checks one file. Throws a [CombinePdfException].
  Future<CombineAnalysis> analyze(String path, {int? maxBytes});

  /// Combines [job]. Throws a [CombinePdfException]; `cancelled` when [token]
  /// was cancelled. The output file does not exist after a failure.
  Future<CombineMergeResult> merge(
      CombineMergeJob job, CombineCancelToken token);
}

/// Runs in the caller's isolate. For tests.
class InlineCombineExecutor implements CombineExecutor {
  const InlineCombineExecutor({
    this.maxSourceBytes = CombineLimits.maxSourceBytes,
  });

  final int maxSourceBytes;

  @override
  Future<CombineAnalysis> analyze(String path, {int? maxBytes}) async =>
      analyzeCombinePdf(path, maxBytes: maxBytes ?? maxSourceBytes);

  @override
  Future<CombineMergeResult> merge(
      CombineMergeJob job, CombineCancelToken token) async {
    return runCombineMerge(job, isCancelled: () => token.isCancelled);
  }
}

class _MergeStart {
  const _MergeStart(this.reply, this.job);

  final SendPort reply;
  final CombineMergeJob job;
}

void _mergeEntry(_MergeStart start) {
  try {
    start.reply.send(runCombineMerge(start.job));
  } on CombinePdfException catch (error) {
    start.reply.send(error);
  } catch (_) {
    start.reply.send(const CombinePdfException(CombinePdfFailure.mergeFailed));
  }
}

/// Production: every file check is a short-lived isolate, and a combine owns
/// one isolate that is stopped at once if the user cancels.
class IsolateCombineExecutor implements CombineExecutor {
  const IsolateCombineExecutor({
    this.maxSourceBytes = CombineLimits.maxSourceBytes,
    this.analysisDeadline = const Duration(minutes: 2),
  });

  final int maxSourceBytes;

  /// The longest one file's check may run. Generous on purpose (a debug build
  /// reads a large PDF many times slower than a release one); it only ends a
  /// check that would otherwise never report.
  final Duration analysisDeadline;

  @override
  Future<CombineAnalysis> analyze(String path, {int? maxBytes}) {
    final limit = maxBytes ?? maxSourceBytes;
    // A check that never ends would leave the selection looking empty with
    // nothing to tap: past the deadline the worker is stopped and the file is
    // reported as one that could not be read, so it can be removed or retried.
    return runBoundedIsolate<CombineAnalysis>(
      () => analyzeCombinePdf(path, maxBytes: limit),
      limit: analysisDeadline,
      onTimeout: () => const CombinePdfException(
          CombinePdfFailure.missingSource,
          detail: 'timeout'),
      onFailure: () => const CombinePdfException(
          CombinePdfFailure.corruptSource,
          detail: 'worker'),
    );
  }

  @override
  Future<CombineMergeResult> merge(
      CombineMergeJob job, CombineCancelToken token) async {
    if (token.isCancelled) {
      throw const CombinePdfException(CombinePdfFailure.cancelled);
    }
    final results = ReceivePort();
    final errors = ReceivePort();
    final done = Completer<CombineMergeResult>();
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn<_MergeStart>(
        _mergeEntry,
        _MergeStart(results.sendPort, job),
        onError: errors.sendPort,
        errorsAreFatal: true,
      );
    } catch (_) {
      results.close();
      errors.close();
      throw const CombinePdfException(CombinePdfFailure.mergeFailed);
    }
    results.listen((Object? message) {
      if (done.isCompleted) return;
      if (message is CombineMergeResult) {
        done.complete(message);
      } else if (message is CombinePdfException) {
        done.completeError(message);
      } else {
        done.completeError(
            const CombinePdfException(CombinePdfFailure.mergeFailed));
      }
    });
    errors.listen((Object? _) {
      if (done.isCompleted) return;
      done.completeError(
          const CombinePdfException(CombinePdfFailure.mergeFailed));
    });
    token._onCancel = () {
      isolate.kill(priority: Isolate.immediate);
      if (!done.isCompleted) {
        done.completeError(
            const CombinePdfException(CombinePdfFailure.cancelled));
      }
    };
    try {
      return await done.future;
    } finally {
      token._onCancel = null;
      isolate.kill(priority: Isolate.immediate);
      results.close();
      errors.close();
    }
  }
}
