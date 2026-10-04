// The master selection and the batches derived from it.
//
// Pure logic, no phone. A person chooses photos and videos once, in the media
// picker; that choice is the master selection and sharing never changes it. A
// mixed choice is derived into its photos and its videos, each keeping the
// relative order of the master, and shared photos first, then videos. Nothing is
// majority-driven, labelled as a family it is not, or asked of the person.

import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/share/share_media_batches.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';

import 'share_fixtures.dart';

List<ShareMediaItem> _items(List<OfferMediaRef> refs) => mediaItems(refs);

List<String> _keys(Iterable<ShareMediaItem> items) =>
    <String>[for (final item in items) item.key];

void main() {
  group('the master selection', () {
    test('is kept as chosen: its order, each item once, named by identity', () {
      final photoA = mediaRef('photo-a');
      final batches = MediaBatches.of(_items(<OfferMediaRef>[
        photoA,
        mediaRef('video-x', video: true),
        mediaRef('photo-b'),
        mediaRef('video-y', video: true),
        // The same photo again, even under a different signed link.
        mediaRef('photo-a', signedUrl: 'https://store.example/a?sig=2'),
      ]));

      expect(_keys(batches.master),
          <String>['photo-a', 'video-x', 'photo-b', 'video-y']);
      expect(batches.isEmpty, isFalse);
    });

    test('is never changed by deriving batches from it', () {
      final master = _items(<OfferMediaRef>[
        mediaRef('photo-a'),
        mediaRef('video-x', video: true),
        mediaRef('photo-b'),
        mediaRef('video-y', video: true),
      ]);
      final batches = MediaBatches.of(master);
      final steps = batches.steps;
      final images = batches.itemsOf(MediaFamily.images);
      final videos = batches.itemsOf(MediaFamily.videos);

      expect(steps, <MediaFamily>[MediaFamily.images, MediaFamily.videos]);
      expect(_keys(images), <String>['photo-a', 'photo-b']);
      expect(_keys(videos), <String>['video-x', 'video-y']);
      expect(_keys(batches.master), _keys(master));
      expect(() => batches.master.add(master.first), throwsUnsupportedError,
          reason: 'the master selection cannot be edited from outside');
      expect(() => batches.images.clear(), throwsUnsupportedError);
      expect(() => batches.videos.clear(), throwsUnsupportedError);
    });
  });

  group('the derived batches', () {
    test('a mixed choice gives its photos and its videos in relative order',
        () {
      final batches = MediaBatches.of(_items(<OfferMediaRef>[
        mediaRef('photo-a'),
        mediaRef('video-x', video: true),
        mediaRef('photo-b'),
        mediaRef('video-y', video: true),
      ]));

      expect(batches.isMixed, isTrue);
      expect(_keys(batches.images), <String>['photo-a', 'photo-b']);
      expect(_keys(batches.videos), <String>['video-x', 'video-y']);
      expect(_keys(batches.itemsOf(MediaFamily.images)),
          <String>['photo-a', 'photo-b']);
      expect(_keys(batches.itemsOf(MediaFamily.videos)),
          <String>['video-x', 'video-y']);
    });

    test('photos come first, then videos, whatever was chosen first', () {
      final videoFirst = MediaBatches.of(_items(<OfferMediaRef>[
        mediaRef('video-x', video: true),
        mediaRef('video-y', video: true),
        mediaRef('photo-a'),
      ]));
      expect(videoFirst.steps,
          <MediaFamily>[MediaFamily.images, MediaFamily.videos]);
    });

    test('the order never follows which family has more files', () {
      final moreVideos = MediaBatches.of(_items(<OfferMediaRef>[
        mediaRef('video-x', video: true),
        mediaRef('video-y', video: true),
        mediaRef('video-z', video: true),
        mediaRef('photo-a'),
      ]));
      expect(moreVideos.steps.first, MediaFamily.images);
      final morePhotos = MediaBatches.of(_items(<OfferMediaRef>[
        mediaRef('photo-a'),
        mediaRef('photo-b'),
        mediaRef('photo-c'),
        mediaRef('video-x', video: true),
      ]));
      expect(morePhotos.steps.first, MediaFamily.images);
    });

    test('a choice of one family is one step; nothing is no step', () {
      expect(
          MediaBatches.of(_items(<OfferMediaRef>[
            mediaRef('photo-a'),
            mediaRef('photo-b'),
          ])).steps,
          <MediaFamily>[MediaFamily.images]);
      expect(
          MediaBatches.of(_items(<OfferMediaRef>[
            mediaRef('video-x', video: true),
          ])).steps,
          <MediaFamily>[MediaFamily.videos]);
      final none = MediaBatches.of(const <ShareMediaItem>[]);
      expect(none.steps, isEmpty);
      expect(none.isEmpty, isTrue);
      expect(none.isMixed, isFalse);
    });

    test('a family holds several files only from two on', () {
      expect(
          MediaBatches.of(_items(<OfferMediaRef>[
            mediaRef('photo-a'),
            mediaRef('video-x', video: true),
          ])).hasSeveralInAFamily,
          isFalse,
          reason: 'one photo and one video: each is a single file');
      expect(
          MediaBatches.of(_items(<OfferMediaRef>[
            mediaRef('photo-a'),
            mediaRef('photo-b'),
            mediaRef('video-x', video: true),
          ])).hasSeveralInAFamily,
          isTrue);
      expect(
          MediaBatches.of(_items(<OfferMediaRef>[
            mediaRef('video-x', video: true),
            mediaRef('video-y', video: true),
          ])).hasSeveralInAFamily,
          isTrue);
    });
  });
}
