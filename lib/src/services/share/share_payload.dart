import 'package:broker_wallet/src/services/share/share_models.dart';

/// How a chosen set of photos and videos is handed to the platform.
enum ShareDelivery {
  /// Android. Photos and videos are handed over as homogeneous batches: one file
  /// goes with its message; several files of one family go as files only, with
  /// the message copied for the person to paste once (real Samsung / WhatsApp
  /// runs: a message sent with several files is repeated on each, and a batch
  /// that mixes photos and videos is not reliably delivered); a choice of both
  /// families is shared as its photos and then its videos, in two steps.
  familyBatches,

  /// iOS and the rest: the whole choice and the message in one system share, as
  /// before, until a platform is verified separately.
  wholeSelection,
}

/// What kind of share a prepared set of files and a message make.
enum SharePayloadKind {
  /// No file: the message alone.
  textOnly,

  /// One file with its message.
  fileWithText,

  /// Two or more photos, or two or more videos, never both: one homogeneous
  /// batch, handed over as files only.
  mediaBatch,

  /// Two or more files with the message: a whole selection on a system share,
  /// or files that are not photos and videos.
  filesWithText,

  /// Photos and videos in one batch where a homogeneous one was required. Never
  /// launched.
  inconsistentBatch,
}

/// What the native share sheet is handed for one prepared batch, decided in this
/// one place.
///
///  * no file: the message alone;
///  * one file: the file with its message;
///  * two or more photos, or two or more videos (on [ShareDelivery.familyBatches]):
///    one batch of exactly those files, in the order they were prepared, and NO
///    message in the request. The message is copied once by the flow instead, so
///    it never depends on a receiving app showing one caption once;
///  * a [ShareDelivery.wholeSelection]: every file and the message together.
///
/// A batch is never declared to be anything it is not: its type is the common
/// type its files proved, or the wildcard of their one family. A mix of photos
/// and videos is never a batch; it is [SharePayloadKind.inconsistentBatch] and is
/// refused.
///
/// A [ShareRequest] for a record's media is made only here, so the rule cannot be
/// bypassed from a widget or from the flow.
class SharePayload {
  const SharePayload._({
    required this.kind,
    required this.files,
    this.text,
    this.subject,
  });

  /// From this many files on, a share is a batch.
  static const int severalFiles = 2;

  /// The payload for [files] and the message [text] on [delivery].
  factory SharePayload.plan({
    required ShareDelivery delivery,
    required List<PreparedShareFile> files,
    String? text,
    String? subject,
  }) {
    final message = (text == null || text.trim().isEmpty) ? null : text;
    final heading =
        (subject == null || subject.trim().isEmpty) ? null : subject;
    final list = List<PreparedShareFile>.unmodifiable(files);

    SharePayload withMessage(SharePayloadKind kind) => SharePayload._(
          kind: kind,
          files: list,
          text: message,
          subject: heading,
        );

    if (list.isEmpty) return withMessage(SharePayloadKind.textOnly);
    if (list.length < severalFiles) {
      return withMessage(SharePayloadKind.fileWithText);
    }
    if (delivery == ShareDelivery.wholeSelection ||
        !list.every((file) => file.isMedia)) {
      return withMessage(SharePayloadKind.filesWithText);
    }
    if (list.map((file) => file.family).toSet().length > 1) {
      return SharePayload._(
        kind: SharePayloadKind.inconsistentBatch,
        files: list,
      );
    }
    return SharePayload._(kind: SharePayloadKind.mediaBatch, files: list);
  }

  final SharePayloadKind kind;

  /// The files handed to the sheet, in the order they were prepared.
  final List<PreparedShareFile> files;

  /// The message handed to the sheet. Null for a media batch.
  final String? text;

  final String? subject;

  /// Whether this is a homogeneous batch of photos or of videos, which the
  /// Android transport hands over as one `ACTION_SEND_MULTIPLE` request.
  bool get isMediaBatch => kind == SharePayloadKind.mediaBatch;

  /// Whether the sheet may be opened for this payload.
  bool get isLaunchable => kind != SharePayloadKind.inconsistentBatch;

  /// The one request handed to the native share sheet.
  ShareRequest toRequest(ShareOrigin? origin) => ShareRequest(
        text: text,
        subject: subject,
        files: files,
        origin: origin,
        mediaBatch: isMediaBatch,
      );
}
