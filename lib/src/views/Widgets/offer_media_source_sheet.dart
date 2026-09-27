import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/offer_media_picker.dart';

/// Shows the Offer media attachment sheet and returns what the user chose,
/// or null when they dismiss it.
///
/// Three sections: **Camera**, with two direct actions — Take photo and
/// Record video, each opening the phone's own camera app at once (a system
/// capture returns one kind of media, so both are offered here rather than
/// in a second step) — **Gallery** (photos and videos together, one native
/// selection) and **Documents**, shown but not available for Offers until
/// secure Offer documents exist (Task C), rather than offering an upload that
/// would be refused.
Future<OfferMediaSource?> showOfferMediaSourceSheet(
  BuildContext context, {
  required int remaining,
}) {
  final colors = Theme.of(context).colorScheme;
  return showModalBottomSheet<OfferMediaSource>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => OfferMediaSourceSheet(remaining: remaining),
  );
}

class OfferMediaSourceSheet extends StatelessWidget {
  const OfferMediaSourceSheet({super.key, required this.remaining});

  /// How many more items the Offer can take.
  final int remaining;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    void choose(OfferMediaSource source) => Navigator.of(context).pop(source);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4),
            child: Text(
              loc.translate('offerMediaSheetTitle'),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 16),
            child: Text(
              loc
                  .translate('offerMediaSheetRemaining')
                  .replaceAll('{count}', '$remaining'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          // The three sections share one height: the Camera section, with its
          // two actions, is the tallest on a narrow phone.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _CameraSection(
                    key: const Key('offerMediaSource.camera'),
                    title: loc.translate('offerMediaSourceCamera'),
                    photoLabel: loc.translate('offerMediaCameraTakePhoto'),
                    videoLabel: loc.translate('offerMediaCameraRecordVideo'),
                    onPhoto: () => choose(OfferMediaSource.cameraPhoto),
                    onVideo: () => choose(OfferMediaSource.cameraVideo),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SourceTile(
                    key: const Key('offerMediaSource.gallery'),
                    icon: Icons.photo_library_outlined,
                    label: loc.translate('offerMediaSourceGallery'),
                    hint: loc.translate('offerMediaSourceGalleryHint'),
                    onTap: () => choose(OfferMediaSource.gallery),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SourceTile(
                    key: const Key('offerMediaSource.documents'),
                    icon: Icons.description_outlined,
                    label: loc.translate('offerMediaSourceDocuments'),
                    hint: loc.translate('offerMediaSourceDocumentsUnavailable'),
                    onTap: null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Camera section: its title and two small direct actions, each of which
/// closes the sheet with its choice so the system camera opens at once.
class _CameraSection extends StatelessWidget {
  const _CameraSection({
    super.key,
    required this.title,
    required this.photoLabel,
    required this.videoLabel,
    required this.onPhoto,
    required this.onVideo,
  });

  final String title;
  final String photoLabel;
  final String videoLabel;
  final VoidCallback onPhoto;
  final VoidCallback onVideo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.primary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 120),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ),
              _CameraAction(
                key: const Key('offerMediaSource.cameraPhoto'),
                icon: Icons.photo_camera_outlined,
                label: photoLabel,
                onTap: onPhoto,
              ),
              const SizedBox(height: 6),
              _CameraAction(
                key: const Key('offerMediaSource.cameraVideo'),
                icon: Icons.videocam_outlined,
                label: videoLabel,
                onTap: onVideo,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One small camera action: an icon and a label on the brand tint, at least
/// 48 dp tall.
class _CameraAction extends StatelessWidget {
  const _CameraAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: colors.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: colors.primary, size: 20),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One action: an icon in a tinted circle, a label and a one-line hint.
/// Disabled (no [onTap]) it is dimmed and announced as unavailable.
class _SourceTile extends StatelessWidget {
  const _SourceTile({
    super.key,
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabled = onTap != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label. $hint',
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: colors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 120),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: colors.primary, size: 26),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
