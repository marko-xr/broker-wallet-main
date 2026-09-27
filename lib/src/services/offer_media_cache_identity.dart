/// Cache identity for private Offer media.
///
/// A Cloudflare R2 signed GET URL is *transport*: the Worker mints a brand new
/// one, with a new signature and expiry, on every `/offer-media` call, and
/// answers `Cache-Control: no-store`. Keying an image cache by that URL is
/// therefore a guaranteed miss on every open. The durable identity is the
/// `media_objects.id` behind it, which never changes for a given set of bytes
/// under today's append-only Offer-media upload contract.
///
/// This lives in the service layer rather than in a widget file so the upload
/// service, the read service and the gallery can all agree on one key without
/// a UI import.
library;

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';

/// Why a private Offer-media resolution failed.
///
/// The distinction is security-relevant, so it is deliberately narrow. Only
/// [accessDenied] is treated as proof that this account may no longer see the
/// media, and only that outcome may remove locally held bytes.
enum OfferMediaFailureKind {
  /// The Worker answered authoritatively that this authenticated account has
  /// no such Offer — it was deleted, or it is not owned by this account.
  ///
  /// The Worker's `/offer-media` route reaches this only after its ownership
  /// query has *succeeded* and returned no row; an upstream failure answers
  /// 502 instead. It is therefore a trustworthy revocation signal.
  accessDenied,

  /// The access token was missing, malformed or expired.
  ///
  /// A session problem, never proof that access to the Offer was revoked, so
  /// it must not delete anything.
  unauthenticated,

  /// Offline, a timeout, an upstream failure, or an unexpected status.
  ///
  /// Nothing about the account's access is established, so previously
  /// authorized media stays exactly as it is.
  transient,
}

/// A private Offer-media resolution that failed, carrying only the
/// classification the presentation layer is allowed to act on.
///
/// It intentionally carries no URL, object key, token or provider text.
class OfferMediaException implements Exception {
  const OfferMediaException(this.kind);

  final OfferMediaFailureKind kind;

  /// Whether this outcome proves the account may no longer see the media.
  bool get isAccessDenied => kind == OfferMediaFailureKind.accessDenied;

  @override
  String toString() => 'OfferMediaException(${kind.name})';
}

/// Account-scoped, stable cache identity for one Offer media object.
///
/// The authenticated owner id is part of the key so one account's cache entry
/// can never collide with — or be addressed by — another account on the same
/// device. Returns null when either half is missing, which callers treat as
/// "no stable identity" and fall back to URL-keyed behaviour.
/// Prefix shared by every Offer-media cache key.
///
/// Lets a presentation cache recognise its private Offer entries without
/// re-deriving the key format.
const String offerMediaCacheKeyPrefix = 'offer-media:';

String? offerMediaCacheKey({
  required String? ownerId,
  required String? mediaObjectId,
}) {
  final owner = ownerId?.trim();
  final media = mediaObjectId?.trim();
  if (owner == null || owner.isEmpty || media == null || media.isEmpty) {
    return null;
  }
  return '$offerMediaCacheKeyPrefix$owner:$media';
}

/// The key under which a video's still frame, made on this device, is kept.
///
/// Derived from the item's own cache key, so it carries the same account
/// scope and its adopted file shares the same ownership prefix — the account
/// sweep removes it with everything else.
String offerMediaPosterKey(String cacheKey) => '$cacheKey:poster';

/// The states the Offer media UI distinguishes for an item that is not yet
/// (or not successfully) on the server.
enum OfferMediaUploadPhase {
  /// Saved on the device and waiting for its turn — including while the app
  /// is in the background, where Android allows it no network.
  queued,

  /// Being authorized or sent right now (with progress while sending).
  uploading,

  /// Every byte was sent; the server is verifying and attaching it.
  confirming,

  /// Accepted and attached by the server.
  ready,

  /// A failure that can pass, retried automatically; Retry skips the wait.
  retrying,

  /// Failed for a reason that can pass; waiting for the user's Retry.
  retryableFailure,

  /// Refused for good; only Remove helps.
  permanentFailure,
}

/// One displayable piece of Offer media, in the order the Worker returned it.
///
/// [mediaObjectId] is always present and durable. [signedUrl] is present only
/// after a successful `/offer-media` resolution and expires. [localFilePath]
/// is present when this device already holds the bytes, in which case the
/// image can be painted on the first frame with no network at all.
///
/// An item still in the upload queue carries an [uploadPhase]; items the
/// server already holds carry none.
class OfferMediaRef {
  const OfferMediaRef({
    required this.mediaObjectId,
    required this.cacheKey,
    this.signedUrl,
    this.localFilePath,
    this.isVideo = false,
    this.posterPath,
    this.durationMs,
    this.uploadPhase,
    this.progress,
    this.failureMessageKey,
    this.displayName,
    this.byteLength,
  });

  final String mediaObjectId;

  /// [offerMediaCacheKey] for this item, or null when no owner id was known.
  final String? cacheKey;

  final String? signedUrl;
  final String? localFilePath;

  /// Whether the server recorded this item as a video. Authoritative: it comes
  /// from `media_objects.media_type`, never from guessing at a URL, whose
  /// path and query are signing details rather than a description of content.
  final bool isVideo;

  /// A still frame of a video, when this device made one.
  final String? posterPath;

  /// A video's duration as the server measured it.
  final int? durationMs;

  /// Set only for an item still in the upload queue.
  final OfferMediaUploadPhase? uploadPhase;

  /// Fraction of the bytes sent, while [uploadPhase] is uploading.
  final double? progress;

  /// The ARB key explaining a failed upload.
  final String? failureMessageKey;

  final String? displayName;
  final int? byteLength;

  bool get hasLocalBytes =>
      localFilePath != null && localFilePath!.trim().isNotEmpty;

  bool get hasSignedUrl => signedUrl != null && signedUrl!.trim().isNotEmpty;

  bool get hasPoster => posterPath != null && posterPath!.trim().isNotEmpty;

  /// Whether this item can put pixels on screen right now.
  bool get isRenderable => hasLocalBytes || hasSignedUrl || hasPoster;

  /// Whether this item is still in the upload queue rather than on the server.
  bool get isPendingUpload =>
      uploadPhase != null && uploadPhase != OfferMediaUploadPhase.ready;

  OfferMediaRef copyWith({String? signedUrl, String? localFilePath}) =>
      OfferMediaRef(
        mediaObjectId: mediaObjectId,
        cacheKey: cacheKey,
        signedUrl: signedUrl ?? this.signedUrl,
        localFilePath: localFilePath ?? this.localFilePath,
        isVideo: isVideo,
        posterPath: posterPath,
        durationMs: durationMs,
        uploadPhase: uploadPhase,
        progress: progress,
        failureMessageKey: failureMessageKey,
        displayName: displayName,
        byteLength: byteLength,
      );

  @override
  bool operator ==(Object other) =>
      other is OfferMediaRef &&
      other.mediaObjectId == mediaObjectId &&
      other.cacheKey == cacheKey &&
      other.signedUrl == signedUrl &&
      other.localFilePath == localFilePath &&
      other.isVideo == isVideo &&
      other.posterPath == posterPath &&
      other.durationMs == durationMs &&
      other.uploadPhase == uploadPhase &&
      other.progress == progress &&
      other.failureMessageKey == failureMessageKey &&
      other.displayName == displayName &&
      other.byteLength == byteLength;

  @override
  int get hashCode => Object.hash(
        mediaObjectId,
        cacheKey,
        signedUrl,
        localFilePath,
        isVideo,
        posterPath,
        durationMs,
        uploadPhase,
        progress,
        failureMessageKey,
        displayName,
        byteLength,
      );
}

/// The result of one authoritative `/offer-media` resolution.
///
/// URLs and ids come from the same response and are always replaced together,
/// so an empty response clears stale media rather than leaving old URLs behind.
class OfferMediaResolution {
  const OfferMediaResolution({
    required this.offerId,
    required this.ownerId,
    required this.items,
  });

  final String offerId;
  final String ownerId;
  final List<OfferMediaRef> items;

  List<String> get urls => [
        for (final item in items)
          if (item.hasSignedUrl) item.signedUrl!,
      ];

  List<String> get mediaObjectIds =>
      [for (final item in items) item.mediaObjectId];

  bool get isEmpty => items.isEmpty;
}

/// Merges an authoritative media resolution into an Offer row.
///
/// Media is always replaced as a unit — an empty resolution clears the Offer's
/// media rather than leaving previously signed URLs in place.
OfferModel applyOfferMedia(OfferModel offer, OfferMediaResolution media) {
  final urls = media.urls;
  return offer.copyWith(
    mediaUrls: urls,
    mediaUrl: urls.isEmpty ? null : urls.first,
    clearMediaUrl: urls.isEmpty,
    mediaObjectIds: media.mediaObjectIds,
  );
}
