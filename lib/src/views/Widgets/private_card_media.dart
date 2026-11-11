import 'dart:async';

import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/views/Widgets/offer_video_poster.dart';
import 'package:broker_wallet/src/views/Widgets/private_media_image.dart';
import 'package:flutter/material.dart';

/// The picture on a list card whose media is private (an Offer's or an
/// Owner's): the photo, or a video's still frame with a play mark. Favorites and
/// Search draw their cards' media through this one widget.
///
/// It is drawn by the media's stable identity ([cacheKey]), never by its link:
/// bytes this device holds win, and a new link never means a new download.
/// [fallback] is what shows while there is nothing to draw and when the picture
/// cannot be drawn.
///
/// It takes plain values, not the cards' media type, on purpose. That type is
/// reached through differently spelled imports (`Views` and `views` are two
/// libraries to Dart), and a type that crosses such a boundary fails to compile
/// in one spelling or the other.
class PrivateCardMedia extends StatefulWidget {
  const PrivateCardMedia({
    super.key,
    required this.cacheKey,
    required this.isVideo,
    required this.fallback,
    this.signedUrl,
    this.posterPath,
    this.privateCache = false,
  });

  /// Draws a photo through the account-scoped private image cache
  /// ([PrivateMediaImage], tracker §7AZ, M3b-1) instead of the shared image
  /// cache: only for the current authorized session's account, bytes held
  /// first (the mapping and its M1d-2 fallback, then the private cache), a
  /// fetch with [signedUrl] only when nothing is held, and never the link as
  /// what is stored. Off unless a caller asks for it — Favorites and Search
  /// do; Smart Map keeps the shared cache (D-M3-1(b)). Videos are unaffected.
  final bool privateCache;

  /// The media's stable, account-scoped identity.
  final String cacheKey;

  /// Whether to draw a video's still frame instead of a photo.
  final bool isVideo;

  /// A short-lived link to the media, when one is known right now.
  final String? signedUrl;

  /// A still frame of the video this device already holds, when it does.
  final String? posterPath;

  final Widget fallback;

  @override
  State<PrivateCardMedia> createState() => _PrivateCardMediaState();
}

class _PrivateCardMediaState extends State<PrivateCardMedia> {
  @override
  void initState() {
    super.initState();
    _keepPhotoOnDevice();
  }

  @override
  void didUpdateWidget(covariant PrivateCardMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A refreshed list brings the item a fresh link: keep its photo then.
    if (oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.signedUrl != widget.signedUrl) {
      _keepPhotoOnDevice();
    }
  }

  /// Keeps a private photo's bytes on this device under its stable identity,
  /// so the next open draws it before any link exists. The same call the
  /// details gallery makes.
  void _keepPhotoOnDevice() {
    // The private image keeps its own copy; nothing goes to the shared cache.
    if (widget.privateCache) return;
    final url = widget.signedUrl;
    if (widget.isVideo || url == null || url.isEmpty) return;
    unawaited(OfflineMediaService.instance.ensureMediaIdCached(
      cacheKey: widget.cacheKey,
      url: url,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isVideo) {
      // A video's still frame: the one this device keeps, or one made from the
      // video itself. The play mark tells it from a photo.
      return OfferVideoPoster(
        cacheKey: widget.cacheKey,
        signedUrl: widget.signedUrl,
        posterPath: widget.posterPath,
        placeholder: widget.fallback,
        loading: widget.fallback,
        cacheWidth: 600,
        frameOverlay: const Center(
          child: Icon(
            Icons.play_circle_fill_rounded,
            color: Colors.white,
            size: 40,
          ),
        ),
      );
    }
    if (widget.privateCache) {
      // The private image path (M3b-1), filling the card as the shared one
      // does, decoded at the card width.
      return SizedBox.expand(
        child: PrivateMediaImage(
          cacheKey: widget.cacheKey,
          signedUrl: widget.signedUrl,
          fit: BoxFit.cover,
          cacheWidth: 600,
          placeholder: widget.fallback,
          errorWidget: widget.fallback,
        ),
      );
    }
    // Bytes this device holds win; otherwise the link, cached under the stable
    // identity so a new link never means a new download.
    return OfflineMediaService.instance.buildOfflineAwareImage(
      imageUrl: widget.signedUrl ?? '',
      cacheKey: widget.cacheKey,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: 600,
      placeholder: widget.fallback,
      errorWidget: widget.fallback,
    );
  }
}
