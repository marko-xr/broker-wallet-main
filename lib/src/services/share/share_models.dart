import 'dart:io';

import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';

/// One thing a person can choose to include when sharing a record.
///
/// [labelKey] is the ARB key of the row's title. The text sections become lines
/// of the shared message; [media] and [document] become files.
enum ShareSection {
  basicInfo('basicInformation'),
  pricing('pricing'),
  propertyDetails('propertyDetails'),
  locationDetails('locationDetails'),
  map('mapLocation'),
  contact('contactInfo'),
  notes('notes'),
  media('mediaFiles'),
  document('documents');

  const ShareSection(this.labelKey);

  final String labelKey;

  /// Whether this section is written into the message rather than attached.
  bool get isText => this != media && this != document;
}

enum ShareMediaKind { image, video }

/// One photo or video of a record that can be attached to a share.
///
/// It is addressed by its durable media identity, never by a link: the signed
/// link a [ref] may carry is transport for the download and is never written
/// into a message, a file name or a log.
class ShareMediaItem {
  const ShareMediaItem._({
    required this.key,
    required this.kind,
    required this.ref,
  });

  /// Stable within one share: the media object id, or a position for an old
  /// record that never had one.
  final String key;
  final ShareMediaKind kind;
  final OfferMediaRef ref;

  bool get isVideo => kind == ShareMediaKind.video;

  /// The items of [refs] that can actually be fetched, in the gallery's order
  /// and never twice. An item still in the upload queue is not on the server
  /// yet and is left out, as is one with no bytes, no link and no identity to
  /// ask for a link with.
  static List<ShareMediaItem> fromRefs(Iterable<OfferMediaRef> refs) {
    final items = <ShareMediaItem>[];
    final used = <String>{};
    var position = 0;
    for (final ref in refs) {
      position++;
      if (ref.isPendingUpload) continue;
      final id = ref.mediaObjectId.trim();
      final fetchable = ref.hasLocalBytes || ref.hasSignedUrl || id.isNotEmpty;
      if (!fetchable) continue;
      final key = id.isNotEmpty ? id : 'item-$position';
      if (!used.add(key)) continue;
      items.add(ShareMediaItem._(
        key: key,
        kind: ref.isVideo ? ShareMediaKind.video : ShareMediaKind.image,
        ref: ref,
      ));
    }
    return List<ShareMediaItem>.unmodifiable(items);
  }
}

/// A document a record can attach, held as a private local copy.
class ShareDocument {
  const ShareDocument({required this.fileBaseName, required this.fetch});

  /// The shared file's name without its extension: `Broker-Wallet-Quotation-…`.
  final String fileBaseName;

  /// The local copy of the document. May throw a [ShareFailure]; any other error
  /// is treated as a generic preparation failure.
  final Future<File> Function() fetch;
}

/// Why the files of a share could not be prepared.
enum ShareFailureKind {
  /// Offline, a timeout or a server that is not answering: trying again may work.
  network,

  /// A selected file is gone or refused: it will not come back by retrying.
  unavailable,

  /// The session is missing or expired.
  session,

  /// Anything else.
  generic;

  /// The ARB key of the sentence explaining this failure.
  String get messageKey => switch (this) {
        ShareFailureKind.network => 'shareErrorNetwork',
        ShareFailureKind.unavailable => 'shareErrorUnavailable',
        ShareFailureKind.session => 'shareErrorSession',
        ShareFailureKind.generic => 'shareErrorGeneric',
      };
}

/// A share that could not be prepared or opened.
///
/// It carries only a category and the keys of the items concerned: never a URL,
/// an object key, a path or provider text, so nothing here can leak.
class ShareFailure implements Exception {
  const ShareFailure(this.kind, {this.failedKeys = const <String>[]});

  final ShareFailureKind kind;

  /// The [ShareMediaItem.key]s that could not be prepared, when [kind] is
  /// [ShareFailureKind.unavailable].
  final List<String> failedKeys;

  @override
  String toString() => 'ShareFailure(${kind.name})';
}

/// How the native share sheet ended.
enum ShareOutcome {
  /// The person picked an app.
  shared,

  /// The person closed the sheet without choosing anything. Not an error.
  dismissed,

  /// The sheet opened but the platform cannot say how it ended (Android reports
  /// no result on some versions). Treated as done, never as a failure.
  unknown,
}

/// Where on screen a share started, for the popover iPad and macOS anchor the
/// share sheet to. A plain value so the share logic stays free of widgets.
class ShareOrigin {
  const ShareOrigin(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  bool get isEmpty => width <= 0 || height <= 0;
}

/// A file ready to hand to the share sheet: a real file on disk with the name
/// and type the receiving app will see.
class PreparedShareFile {
  const PreparedShareFile({
    required this.path,
    required this.name,
    required this.mimeType,
  });

  final String path;
  final String name;
  final String mimeType;
}

/// Everything handed to the native share sheet.
class ShareRequest {
  const ShareRequest({
    this.text,
    this.subject,
    this.files = const <PreparedShareFile>[],
    this.origin,
  });

  /// The message, or null when only files are shared.
  final String? text;
  final String? subject;
  final List<PreparedShareFile> files;
  final ShareOrigin? origin;

  /// Whether there is anything to send: a message or at least one file. A share
  /// without either is never handed to the share sheet.
  bool get hasContent =>
      (text != null && text!.trim().isNotEmpty) || files.isNotEmpty;
}

/// Lets one share be called off while its files are still being prepared.
class ShareCancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      try {
        listener();
      } catch (_) {
        // A listener that cannot stop must not keep the others from stopping.
      }
    }
  }

  /// Calls [listener] when cancelled (at once if it already was). The returned
  /// function stops listening.
  void Function() onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

/// Thrown inside the preparation when its [ShareCancelToken] was cancelled.
class ShareCancelled implements Exception {
  const ShareCancelled();

  @override
  String toString() => 'ShareCancelled';
}
