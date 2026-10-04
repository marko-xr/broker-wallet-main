import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/views/Widgets/offer_video_poster.dart';

/// One photo or video of a record, as a small preview. The picker's tiles and
/// the compact summary in Share Options are both this widget, so a given item
/// is previewed by one resolution everywhere in Share.
///
/// A photo is drawn from the same local/cache image path as the detail
/// gallery. A video is drawn by the very widget the gallery's video tile, the
/// full-screen viewer's strip and the form grid use ([OfferVideoPoster]), in
/// the same order:
///
///  1. the still frame the record already carries ([OfferMediaRef.posterPath]),
///  2. the one this device keeps under the video's stable identity,
///  3. a frame made once from the video and then kept under that identity:
///     from the original when this device already holds it, else from the link
///     the record already holds. The platform reads only the video's index and
///     first frame, never the whole video; no link is refreshed and nothing is
///     downloaded for a preview, and a frame made here is the one the gallery
///     then finds, and the reverse,
///  4. otherwise one plain video placeholder.
///
/// A video that has no stable identity (an old record that only has a stored
/// link) or no link and no kept frame cannot be given a frame, and shows the
/// placeholder. The play badge is drawn only over a real frame.
class ShareMediaPreview extends StatelessWidget {
  const ShareMediaPreview(
      {super.key, required this.item, this.cacheWidth = 240});

  final ShareMediaItem item;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      key: ValueKey(item.isVideo
          ? 'share-media-video-placeholder'
          : 'share-media-image-placeholder'),
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(
          item.isVideo ? Icons.videocam_outlined : Icons.image_outlined,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
    final ref = item.ref;
    if (item.isVideo) {
      return OfferVideoPoster(
        cacheKey: ref.cacheKey,
        signedUrl: _videoSource(ref),
        posterPath: ref.posterPath,
        cacheWidth: cacheWidth,
        placeholder: placeholder,
        loading: placeholder,
        frameOverlay: const _PlayBadge(),
      );
    }
    final local = ref.localFilePath?.trim() ?? '';
    if (local.isNotEmpty && File(local).existsSync()) {
      return Image.file(
        File(local),
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        errorBuilder: (context, error, stackTrace) => placeholder,
      );
    }
    return OfflineMediaService.instance.buildOfflineAwareImage(
      imageUrl: ref.signedUrl ?? '',
      cacheKey: ref.cacheKey,
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      placeholder: placeholder,
      errorWidget: placeholder,
    );
  }

  /// What a frame is made from when none is kept: the original when this
  /// device already holds it (no network at all), else the link the record
  /// already holds. Never a link fetched for the preview.
  static String? _videoSource(OfferMediaRef ref) {
    final local = ref.localFilePath?.trim() ?? '';
    if (local.isNotEmpty && File(local).existsSync()) return local;
    return ref.signedUrl;
  }
}

/// The play mark over a real video frame: it scales down for the compact
/// summary and sits where the picker's tiles have always shown it.
class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, limits) {
      final side = limits.biggest.shortestSide;
      final radius =
          side.isFinite ? (side * 0.14).clamp(8.0, 14.0).toDouble() : 14.0;
      return Align(
        key: const ValueKey('share-media-video-indicator'),
        alignment: AlignmentDirectional.bottomStart,
        child: Padding(
          padding: EdgeInsets.all(radius < 14 ? 3 : 6),
          child: CircleAvatar(
            radius: radius,
            backgroundColor: colors.surface.withValues(alpha: 0.9),
            child: Icon(Icons.play_arrow_rounded,
                color: colors.onSurface, size: radius * 1.4),
          ),
        ),
      );
    });
  }
}

/// One local picker session: Cancel drops its draft; Done returns the stable
/// media keys to the Share Options controller in a single update.
class ShareMediaPicker extends StatefulWidget {
  const ShareMediaPicker({
    super.key,
    required this.items,
    required this.initialKeys,
    required this.unavailableKeys,
  });

  final List<ShareMediaItem> items;
  final Set<String> initialKeys;
  final Set<String> unavailableKeys;

  static Future<Set<String>?> show(
    BuildContext context, {
    required List<ShareMediaItem> items,
    required Set<String> initialKeys,
    required Set<String> unavailableKeys,
  }) =>
      showModalBottomSheet<Set<String>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => ShareMediaPicker(
          items: items,
          initialKeys: initialKeys,
          unavailableKeys: unavailableKeys,
        ),
      );

  @override
  State<ShareMediaPicker> createState() => _ShareMediaPickerState();
}

class _ShareMediaPickerState extends State<ShareMediaPicker> {
  late final Set<String> _draft;

  @override
  void initState() {
    super.initState();
    final available = <String>{
      for (final item in widget.items)
        if (!widget.unavailableKeys.contains(item.key)) item.key,
    };
    _draft = widget.initialKeys.intersection(available);
  }

  void _toggle(String key) {
    if (widget.unavailableKeys.contains(key)) return;
    setState(() {
      if (!_draft.remove(key)) _draft.add(key);
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final available = widget.items
        .where((item) => !widget.unavailableKeys.contains(item.key))
        .toList(growable: false);
    final count = loc
        .translate('shareMediaCount')
        .replaceAll('{selected}', '${_draft.length}')
        .replaceAll('{total}', '${available.length}');

    return LayoutBuilder(builder: (context, limits) {
      final screenHeight = MediaQuery.sizeOf(context).height;
      final height =
          math.min(limits.maxHeight, math.min(screenHeight * 0.86, 680.0));
      return SizedBox(
        height: height,
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                key: const ValueKey('share-media-picker-scroll'),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(loc.translate('selectMedia'),
                              style: texts.titleLarge),
                          Text(count,
                              key: const ValueKey('share-picker-count'),
                              style: texts.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              )),
                          if (available.length > 1)
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton(
                                  key: const ValueKey('share-picker-clear'),
                                  onPressed: _draft.isEmpty
                                      ? null
                                      : () => setState(_draft.clear),
                                  child: Text(loc.translate('clear')),
                                ),
                                TextButton(
                                  key: const ValueKey('share-picker-all'),
                                  onPressed: _draft.length == available.length
                                      ? null
                                      : () => setState(() => _draft.addAll(
                                          available.map((item) => item.key))),
                                  child: Text(loc.translate('selectAll')),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.crossAxisExtent;
                        return SliverGrid.builder(
                          itemCount: widget.items.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: width < 280 ? 2 : 3,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                          itemBuilder: (context, index) {
                            final item = widget.items[index];
                            return _tile(context, item);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('share-picker-cancel'),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(loc.translate('cancel')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('share-picker-done'),
                        onPressed: () =>
                            Navigator.of(context).pop(Set<String>.of(_draft)),
                        child: Text(loc.translate('done')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _tile(BuildContext context, ShareMediaItem item) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final selected = _draft.contains(item.key);
    final unavailable = widget.unavailableKeys.contains(item.key);
    final kind = loc.translate(item.isVideo ? 'video' : 'photo');
    final state = loc.translate(unavailable
        ? 'shareItemUnavailable'
        : selected
            ? 'selected'
            : 'shareMediaNotSelected');
    return Semantics(
      key: ValueKey('share-picker-semantics-${item.key}'),
      container: true,
      button: true,
      selected: selected,
      enabled: !unavailable,
      label: '$kind, $state',
      excludeSemantics: true,
      child: Material(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('share-picker-media-${item.key}'),
          onTap: unavailable ? null : () => _toggle(item.key),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ShareMediaPreview(item: item),
              if (unavailable)
                ColoredBox(color: colors.surface.withValues(alpha: 0.6)),
              if (selected)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.primary, width: 3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              PositionedDirectional(
                top: 6,
                end: 6,
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: selected
                      ? colors.primary
                      : colors.surface.withValues(alpha: 0.9),
                  child: Icon(
                    selected ? Icons.check_rounded : Icons.circle_outlined,
                    size: 18,
                    color: selected ? colors.onPrimary : colors.onSurface,
                  ),
                ),
              ),
              if (unavailable)
                Center(
                  child: Icon(Icons.block_rounded, color: colors.onSurface),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
