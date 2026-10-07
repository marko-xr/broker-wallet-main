import 'dart:convert';

import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offer_media_url_cache.dart';

/// The one picture a favorite's card shows, taken from its record's private
/// media: the first photo; when the record has no photo, the still frame of
/// its first video. A video that comes first never hides a photo behind it.
///
/// It is addressed by the media's stable, account-scoped [cacheKey], never by
/// a link. [signedUrl] is transport: it is held in memory for the session and
/// is never stored (see [toStored]).
class FavoriteCardMedia {
  const FavoriteCardMedia({
    required this.cacheKey,
    required this.isVideo,
    this.signedUrl,
    this.posterPath,
  });

  /// The media's `offerMediaCacheKey`.
  final String cacheKey;

  /// Whether the card draws a video's still frame instead of a photo.
  final bool isVideo;

  /// A short-lived link to the media, when one is known right now.
  final String? signedUrl;

  /// A still frame of the video this device already holds, when it does.
  final String? posterPath;

  /// The media a card should show for [refs] (a record's media in the order
  /// the server lists it): the first photo that can be drawn, otherwise the
  /// first video that can be, otherwise null.
  static FavoriteCardMedia? pick(Iterable<OfferMediaRef> refs) {
    FavoriteCardMedia? firstVideo;
    for (final ref in refs) {
      final key = ref.cacheKey;
      if (key == null || key.isEmpty) continue;
      if (ref.isVideo) {
        if (firstVideo == null && ref.isRenderable) {
          firstVideo = FavoriteCardMedia(
            cacheKey: key,
            isVideo: true,
            signedUrl: ref.signedUrl,
            posterPath: ref.posterPath,
          );
        }
        continue;
      }
      if (ref.hasSignedUrl || ref.hasLocalBytes) {
        return FavoriteCardMedia(
          cacheKey: key,
          isVideo: false,
          signedUrl: ref.signedUrl,
        );
      }
    }
    return firstVideo;
  }

  /// The card media of an Offer the Supabase service has just read: its media
  /// ids with the kind and link the server gave each one, which that read keeps
  /// in [urlCache]. Null for an Offer with no private media (the Firebase
  /// backend, whose Offers carry plain URLs) or whose items' kinds are no
  /// longer known — an item is never guessed to be a photo.
  static FavoriteCardMedia? fromOffer(
    OfferModel offer, {
    OfferMediaUrlCache? urlCache,
  }) {
    final ids = offer.mediaObjectIds;
    if (ids.isEmpty) return null;
    final cache = urlCache ?? OfferMediaUrlCache.instance;
    final refs = <OfferMediaRef>[];
    for (final id in ids) {
      final key = offerMediaCacheKey(ownerId: offer.userId, mediaObjectId: id);
      final entry = cache.get(key);
      if (entry == null) continue;
      refs.add(OfferMediaRef(
        mediaObjectId: id,
        cacheKey: key,
        signedUrl: entry.url,
        isVideo: entry.isVideo,
      ));
    }
    return pick(refs);
  }

  /// What is kept on disk with the cached favorite: the identity and the
  /// kind, so the next open can draw it before any link exists. Never a link.
  String toStored() => jsonEncode({'k': cacheKey, 'v': isVideo});

  /// The inverse of [toStored]; null for anything else.
  static FavoriteCardMedia? fromStored(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) return null;
      final key = decoded['k'];
      final isVideo = decoded['v'];
      if (key is! String ||
          !key.startsWith(offerMediaCacheKeyPrefix) ||
          isVideo is! bool) {
        return null;
      }
      return FavoriteCardMedia(cacheKey: key, isVideo: isVideo);
    } catch (_) {
      return null;
    }
  }
}
