import 'dart:async';
import 'dart:isolate';

import 'package:broker_wallet/src/services/signature/signature_models.dart';
import 'package:broker_wallet/src/services/signature/signature_pdf_engine.dart';

/// Lets the user stop a save that is running.
class SignatureCancelToken {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }
}

/// Where PDF work runs. Reading and signing PDFs is CPU work on whole
/// documents, so production runs it on a worker isolate and the screen never
/// freezes; tests run it inline.
abstract interface class SignatureExecutor {
  /// Reads and checks one file. Throws a [SignatureException].
  Future<SignatureAnalysis> analyze(String path, {int? maxBytes});

  /// Writes [job]. Throws a [SignatureException]; `cancelled` when [token] was
  /// cancelled. The output file does not exist after a failure.
  Future<SignatureWriteResult> write(
      SignatureWriteJob job, SignatureCancelToken token);
}

/// Runs in the caller's isolate. For tests.
class InlineSignatureExecutor implements SignatureExecutor {
  const InlineSignatureExecutor({
    this.maxSourceBytes = SignatureLimits.maxSourceBytes,
  });

  final int maxSourceBytes;

  @override
  Future<SignatureAnalysis> analyze(String path, {int? maxBytes}) async =>
      analyzeSignaturePdf(path, maxBytes: maxBytes ?? maxSourceBytes);

  @override
  Future<SignatureWriteResult> write(
      SignatureWriteJob job, SignatureCancelToken token) async {
    return runSignatureWrite(job, isCancelled: () => token.isCancelled);
  }
}

class _WriteStart {
  const _WriteStart(this.reply, this.job);

  final SendPort reply;
  final SignatureWriteJob job;
}

void _writeEntry(_WriteStart start) {
  try {
    start.reply.send(runSignatureWrite(start.job));
  } on SignatureException catch (error) {
    start.reply.send(error);
  } catch (_) {
    start.reply.send(const SignatureException(SignatureFailure.writeFailed));
  }
}

/// Production: every file check is a short-lived isolate, and a save owns one
/// isolate that is stopped at once if the user cancels.
class IsolateSignatureExecutor implements SignatureExecutor {
  const IsolateSignatureExecutor({
    this.maxSourceBytes = SignatureLimits.maxSourceBytes,
  });

  final int maxSourceBytes;

  @override
  Future<SignatureAnalysis> analyze(String path, {int? maxBytes}) {
    final limit = maxBytes ?? maxSourceBytes;
    return Isolate.run(() => analyzeSignaturePdf(path, maxBytes: limit));
  }

  @override
  Future<SignatureWriteResult> write(
      SignatureWriteJob job, SignatureCancelToken token) async {
    if (token.isCancelled) {
      throw const SignatureException(SignatureFailure.cancelled);
    }
    final results = ReceivePort();
    final errors = ReceivePort();
    final done = Completer<SignatureWriteResult>();
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn<_WriteStart>(
        _writeEntry,
        _WriteStart(results.sendPort, job),
        onError: errors.sendPort,
        errorsAreFatal: true,
      );
    } catch (_) {
      results.close();
      errors.close();
      throw const SignatureException(SignatureFailure.writeFailed);
    }
    results.listen((Object? message) {
      if (done.isCompleted) return;
      if (message is SignatureWriteResult) {
        done.complete(message);
      } else if (message is SignatureException) {
        done.completeError(message);
      } else {
        done.completeError(
            const SignatureException(SignatureFailure.writeFailed));
      }
    });
    errors.listen((Object? _) {
      if (done.isCompleted) return;
      done.completeError(
          const SignatureException(SignatureFailure.writeFailed));
    });
    token._onCancel = () {
      isolate.kill(priority: Isolate.immediate);
      if (!done.isCompleted) {
        done.completeError(
            const SignatureException(SignatureFailure.cancelled));
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
