import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

/// Widget that handles displaying HEIC images with fallback UI
/// Shows a helpful message for legacy HEIC files that need conversion
class HEICImageHandler extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final Widget? placeholder;
  final VoidCallback? onReuploadTap;

  const HEICImageHandler({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.onReuploadTap,
  });

  bool _isHEICImage(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.contains('.heic') || lowerUrl.contains('.heif');
  }

  @override
  Widget build(BuildContext context) {
    // If it's a HEIC file, show conversion needed UI
    if (_isHEICImage(imageUrl)) {
      return _buildHEICFallback(context);
    }

    // Otherwise, display normally
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      placeholder: (context, url) =>
          placeholder ?? const Center(child: CircularProgressIndicator()),
      errorWidget: (context, url, error) {
        // If loading fails and it might be HEIC, show fallback
        if (_isHEICImage(url)) {
          return _buildHEICFallback(context);
        }
        return const Center(child: Icon(Icons.broken_image, size: 64));
      },
    );
  }

  Widget _buildHEICFallback(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    return Container(
      color: colors.surfaceContainerHighest,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_outlined,
            size: 64,
            color: colors.primary,
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              loc.translate('heicImageDetected'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.onSurface,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              loc.translate('heicConversionNeeded'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          if (onReuploadTap != null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onReuploadTap,
              icon: const Icon(Icons.upload),
              label: Text(loc.translate('reuploadAsJPEG')),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Utility class to detect and handle legacy media formats
class LegacyMediaDetector {
  /// Check if a URL points to a HEIC/HEIF image
  static bool isHEICImage(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.contains('.heic') || lowerUrl.contains('.heif');
  }

  /// Check if a URL points to a MOV video
  static bool isMOVVideo(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.contains('.mov') && !lowerUrl.contains('.mp4');
  }

  /// Check if media needs conversion (legacy format)
  static bool needsConversion(String url) {
    return isHEICImage(url) || isMOVVideo(url);
  }

  /// Get the recommended format for conversion
  static String getRecommendedFormat(String url) {
    if (isHEICImage(url)) return 'JPEG';
    if (isMOVVideo(url)) return 'MP4';
    return 'Unknown';
  }

  /// Get user-friendly message about the format issue
  static String getConversionMessage(String url, Function(String) translate) {
    if (isHEICImage(url)) {
      return translate('heicConversionMessage');
    }
    if (isMOVVideo(url)) {
      return translate('movConversionMessage');
    }
    return translate('legacyFileWarning');
  }
}
