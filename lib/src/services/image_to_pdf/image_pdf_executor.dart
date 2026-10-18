import 'dart:async';
import 'dart:isolate';

import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_engine.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_models.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_processor.dart';

/// Lets the user stop a conversion that is running.
class ImagePdfCancelToken {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }
}

/// Where picture and PDF work runs. Decoding photographs and writing a PDF is
/// CPU work on whole files, so production runs it on worker isolates and the
/// screen never freezes; tests run it inline.
abstract interface class ImagePdfExecutor {
  /// Reads and fully decodes one picture. Throws an [ImagePdfException].
  Future<ImageAnalysis> analyzeImage(String path);

  /// Makes the PDF of [job]. Throws an [ImagePdfException]; `cancelled` when
  /// [token] was cancelled. The output file does not exist after a failure.
  Future<ImagePdfBuildResult> build(
      ImagePdfBuildJob job, ImagePdfCancelToken token);

  /// Reads a PDF file back. A protected file reports `encrypted` with page
  /// count 0 unless [password] is given.
  Future<ImagePdfFileInfo> analyzePdf(String path, {String? password});
}

/// Runs in the caller's isolate. For tests.
class InlineImagePdfExecutor implements ImagePdfExecutor {
  const InlineImagePdfExecutor();

  @override
  Future<ImageAnalysis> analyzeImage(String path) async =>
      analyzeImageFile(path);

  @override
  Future<ImagePdfBuildResult> build(
      ImagePdfBuildJob job, ImagePdfCancelToken token) async {
    return buildImagePdf(job, isCancelled: () => token.isCancelled);
  }

  @override
  Future<ImagePdfFileInfo> analyzePdf(String path, {String? password}) async =>
      analyzeImagePdf(path, password: password);
}

class _BuildStart {
  const _BuildStart(this.reply, this.job);

  final SendPort reply;
  final ImagePdfBuildJob job;
}

void _buildEntry(_BuildStart start) {
  try {
    start.reply.send(buildImagePdf(start.job));
  } on ImagePdfException catch (error) {
    start.reply.send(error);
  } catch (_) {
    start.reply.send(const ImagePdfException(ImagePdfFailure.buildFailed));
  }
}

/// Production: every picture check is a short-lived isolate, and a conversion
/// owns one isolate that is stopped at once if the user cancels.
class IsolateImagePdfExecutor implements ImagePdfExecutor {
  const IsolateImagePdfExecutor();

  @override
  Future<ImageAnalysis> analyzeImage(String path) =>
      Isolate.run(() => analyzeImageFile(path));

  @override
  Future<ImagePdfFileInfo> analyzePdf(String path, {String? password}) =>
      Isolate.run(() => analyzeImagePdf(path, password: password));

  @override
  Future<ImagePdfBuildResult> build(
      ImagePdfBuildJob job, ImagePdfCancelToken token) async {
    if (token.isCancelled) {
      throw const ImagePdfException(ImagePdfFailure.cancelled);
    }
    final results = ReceivePort();
    final errors = ReceivePort();
    final done = Completer<ImagePdfBuildResult>();
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn<_BuildStart>(
        _buildEntry,
        _BuildStart(results.sendPort, job),
        onError: errors.sendPort,
        errorsAreFatal: true,
      );
    } catch (_) {
      results.close();
      errors.close();
      throw const ImagePdfException(ImagePdfFailure.buildFailed);
    }
    results.listen((Object? message) {
      if (done.isCompleted) return;
      if (message is ImagePdfBuildResult) {
        done.complete(message);
      } else if (message is ImagePdfException) {
        done.completeError(message);
      } else {
        done.completeError(
            const ImagePdfException(ImagePdfFailure.buildFailed));
      }
    });
    errors.listen((Object? _) {
      if (done.isCompleted) return;
      done.completeError(const ImagePdfException(ImagePdfFailure.buildFailed));
    });
    token._onCancel = () {
      isolate.kill(priority: Isolate.immediate);
      if (!done.isCompleted) {
        done.completeError(const ImagePdfException(ImagePdfFailure.cancelled));
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
