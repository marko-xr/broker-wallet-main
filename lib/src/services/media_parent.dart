import 'package:broker_wallet/src/services/offer_media_policy.dart';

/// The records private media can belong to: an Offer, or an Owner record.
///
/// Both run one lifecycle — the same Media Worker, types, size and length
/// limits, idempotent upload queue, local cache and players — each against
/// its own Worker routes, database link table and object-key segment, so
/// neither can reach the other's media: the Worker refuses an item under the
/// wrong parent.
///
/// Owner decision (2026-09-28): Owner media follows the Offer media rules —
/// photos and videos, at most [maxItems] per record, the same size and
/// three-minute limits, Documents not yet available.
///
/// What differs for the user is only the wording that names the record ("an
/// offer can hold…", "an owner can hold…"); every other media message is
/// shared.
enum MediaParent {
  offer(
    routePrefix: '/offer-media',
    idField: 'offerId',
    limitReachedKey: 'offerMediaLimitReached',
    limitTrimmedKey: 'offerMediaLimitTrimmed',
    documentsUnavailableKey: 'offerMediaSourceDocumentsUnavailable',
    removeFailedKey: 'offerMediaRemoveFailed',
    prepareFailedKey: 'offerMediaPrepareFailed',
    savedUploadingKey: 'offerSavedMediaUploading',
    updatedUploadingKey: 'offerUpdatedMediaUploading',
  ),
  owner(
    routePrefix: '/owner-media',
    idField: 'ownerRecordId',
    limitReachedKey: 'ownerMediaLimitReached',
    limitTrimmedKey: 'ownerMediaLimitTrimmed',
    documentsUnavailableKey: 'ownerMediaSourceDocumentsUnavailable',
    removeFailedKey: 'ownerMediaRemoveFailed',
    prepareFailedKey: 'ownerMediaPrepareFailed',
    savedUploadingKey: 'ownerSavedMediaUploading',
    updatedUploadingKey: 'ownerUpdatedMediaUploading',
  );

  const MediaParent({
    required this.routePrefix,
    required this.idField,
    required this.limitReachedKey,
    required this.limitTrimmedKey,
    required this.documentsUnavailableKey,
    required this.removeFailedKey,
    required this.prepareFailedKey,
    required this.savedUploadingKey,
    required this.updatedUploadingKey,
  });

  /// The Media Worker's routes for this parent: `<prefix>/authorize`,
  /// `<prefix>/confirm`, `<prefix>` (list) and `<prefix>/remove`.
  final String routePrefix;

  /// The request field (and list query parameter) naming the record.
  final String idField;

  final String limitReachedKey;
  final String limitTrimmedKey;
  final String documentsUnavailableKey;
  final String removeFailedKey;
  final String prepareFailedKey;
  final String savedUploadingKey;
  final String updatedUploadingKey;

  /// Photos and videos together per record, including media already on it.
  int get maxItems => OfferMediaPolicy.maxItemsPerOffer;

  /// The ARB key explaining [rejection] on this parent's screens: the shared
  /// message, except that a full record is named as what it is.
  String messageKeyFor(OfferMediaRejection rejection) =>
      rejection == OfferMediaRejection.limitReached
          ? limitReachedKey
          : rejection.messageKey;

  /// Reads a persisted name; null for anything unknown.
  static MediaParent? byName(String? name) {
    for (final parent in values) {
      if (parent.name == name) return parent;
    }
    return null;
  }
}
