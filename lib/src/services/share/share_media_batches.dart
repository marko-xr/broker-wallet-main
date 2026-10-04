import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_payload.dart';

/// One of the two kinds of media a record has.
enum MediaFamily { images, videos }

/// The photos and videos a person chose in the media picker, kept as chosen and
/// told apart by kind.
///
/// [master] is the choice itself, in the record's own (gallery) order, each item
/// once, named by the stable identity of the item and never by its position. It
/// is never changed by sharing. [images] and [videos] are derived from it, each
/// keeping the relative order of [master]. A mixed choice is shared as its photos
/// and then its videos ([steps]), because a receiving app (WhatsApp, in real
/// Samsung runs) does not reliably take one batch that mixes the two; nothing is
/// ever declared to be a family it is not, and the person is never asked which
/// family goes first.
class MediaBatches {
  const MediaBatches._(this.master, this.images, this.videos);

  /// The batches of [selected], in the order given, each item once.
  factory MediaBatches.of(Iterable<ShareMediaItem> selected) {
    final master = <ShareMediaItem>[];
    final images = <ShareMediaItem>[];
    final videos = <ShareMediaItem>[];
    final seen = <String>{};
    for (final item in selected) {
      if (!seen.add(item.key)) continue;
      master.add(item);
      (item.isVideo ? videos : images).add(item);
    }
    return MediaBatches._(
      List<ShareMediaItem>.unmodifiable(master),
      List<ShareMediaItem>.unmodifiable(images),
      List<ShareMediaItem>.unmodifiable(videos),
    );
  }

  /// Everything that was chosen, as chosen.
  final List<ShareMediaItem> master;

  /// The chosen photos, in the order of [master].
  final List<ShareMediaItem> images;

  /// The chosen videos, in the order of [master].
  final List<ShareMediaItem> videos;

  bool get isEmpty => master.isEmpty;

  /// Whether both photos and videos were chosen.
  bool get isMixed => images.isNotEmpty && videos.isNotEmpty;

  /// The chosen items of [family].
  List<ShareMediaItem> itemsOf(MediaFamily family) =>
      family == MediaFamily.images ? images : videos;

  /// The families to share, in the one fixed order (photos, then videos), only
  /// those with something chosen. One or none for a choice of a single family.
  List<MediaFamily> get steps => <MediaFamily>[
        if (images.isNotEmpty) MediaFamily.images,
        if (videos.isNotEmpty) MediaFamily.videos,
      ];

  /// Whether some family holds several files, which is when a batch carries no
  /// message of its own and the message is copied for the person to paste once.
  bool get hasSeveralInAFamily =>
      images.length >= SharePayload.severalFiles ||
      videos.length >= SharePayload.severalFiles;
}
