import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:broker_wallet/src/common/utils/images.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';

/// The signed-in user's avatar.
///
/// Presentation only. It reads [AuthViewModel.profileImage] — which carries the
/// canonical `profile_media_id` alongside the short-lived signed R2 URL — and
/// passes the media id as the image cache key.
///
/// That distinction is the whole point of this widget. A signed R2 URL rotates
/// its signature and expiry on every resolution, so keying the cache by URL
/// guarantees a miss on every cold start: a placeholder, then a re-download of
/// bytes the device already holds. The media id does not rotate, so the same
/// image resolves to the same cache entry no matter how many times its URL is
/// re-signed.
///
/// Home, Search, Favorites and Profile each used to re-implement this block,
/// which is why the cache defect had to be fixed in four places at once.
class CurrentUserAvatar extends StatefulWidget {
  const CurrentUserAvatar({
    super.key,
    required this.size,
    this.borderRadius,
    this.onTap,
  });

  /// Rendered width and height, in logical pixels.
  final double size;

  /// Defaults to a circle. Favorites uses a rounded square.
  final BorderRadius? borderRadius;

  final VoidCallback? onTap;

  @override
  State<CurrentUserAvatar> createState() => _CurrentUserAvatarState();
}

class _CurrentUserAvatarState extends State<CurrentUserAvatar> {
  String? _warmedMediaId;

  /// Records where the cache holds this media id's bytes, so the next cold
  /// start can render them before any signed URL exists.
  void _warm(String? mediaId) {
    if (mediaId == null || mediaId.isEmpty) return;
    if (_warmedMediaId == mediaId) return;
    _warmedMediaId = mediaId;

    OfflineMediaService.instance.warmMediaIdMapping(mediaId).then((path) {
      if (!mounted || path == null) return;
      // Rebuild so the synchronous local-file path is taken from now on.
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = context.watch<AuthViewModel>().profileImage;
    _warm(image.mediaId);

    final size = widget.size;

    final fallback = Image.asset(
      AppImages.avatarPlaceholder,
      fit: BoxFit.cover,
      width: size,
      height: size,
    );

    Widget child;
    if (image.hasNetworkSource || image.hasStableIdentity) {
      child = OfflineMediaService.instance.buildOfflineAwareImage(
        imageUrl: image.signedUrl ?? '',
        cacheKey: image.mediaId,
        fit: BoxFit.cover,
        width: size,
        height: size,
        placeholder: fallback,
        errorWidget: fallback,
      );
    } else {
      child = fallback;
    }

    final clipped = ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.circular(size / 2),
      child: SizedBox(width: size, height: size, child: child),
    );

    final onTap = widget.onTap;
    if (onTap == null) return clipped;
    return GestureDetector(onTap: onTap, child: clipped);
  }
}
