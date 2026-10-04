import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/share/share_flow_controller.dart';
import 'package:broker_wallet/src/services/share/share_media_batches.dart';
import 'package:broker_wallet/src/services/share/share_media_fetcher.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_payload.dart';
import 'package:broker_wallet/src/services/share/share_source.dart';
import 'package:broker_wallet/src/services/share/share_sources.dart';

import 'share_fixtures.dart';

const String _linkA = 'https://store.example/a?sig=1';
const String _linkB = 'https://store.example/b?sig=2';
const String _linkV = 'https://store.example/v?sig=3';

void main() {
  late TempArea area;
  late FakeNet net;
  late FakeShareSink sink;
  late ShareEngine engine;

  setUp(() {
    area = TempArea();
    net = FakeNet();
    sink = FakeShareSink();
    engine = newEngine(area, sink, client: net.client());
  });
  tearDown(() => area.dispose());

  ShareFlowController controllerFor(
    ShareSource source, {
    String language = 'en',
    LinkRefresher? refreshLink,
    String? initialMediaKey,
  }) =>
      ShareFlowController(
        source: source,
        labels: labelsIn(language),
        engine: engine,
        refreshLink: refreshLink,
        initialMediaKey: initialMediaKey,
      );

  /// Waits (briefly) until [ready]: preparing a share does real file work.
  Future<void> until(bool Function() ready) async {
    for (var i = 0; i < 600 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(ready(), isTrue, reason: 'timed out waiting');
  }

  /// An Offer with photos already on the phone (and a video to fetch).
  PropertyShareSource offerWith({
    int localPhotos = 0,
    List<OfferMediaRef> extra = const <OfferMediaRef>[],
  }) {
    final refs = <OfferMediaRef>[
      for (var i = 1; i <= localPhotos; i++)
        mediaRef('photo-$i',
            localFilePath:
                area.writeCacheFile('p$i.jpg', jpegBytes(i * 10)).path),
      ...extra,
    ];
    return PropertyShareSource.offer(
      offer(
        propertyType: 'residential',
        specific: 'Villa',
        city: 'Dubai',
        areas: <String>['dubaiMarina'],
        phone: '+971501234567',
        max: '2500000',
        notes: 'Corner unit',
      ),
      media: mediaItems(refs),
    );
  }

  List<FileSystemEntity> stagedFolders() => area.staging.existsSync()
      ? area.staging.listSync()
      : <FileSystemEntity>[];

  group('choosing', () {
    test('starts with the source\'s own choices', () {
      final source = offerWith(
        localPhotos: 2,
        extra: <OfferMediaRef>[
          mediaRef('video-1', video: true, signedUrl: _linkV)
        ],
      );
      final controller = controllerFor(source);

      expect(controller.selection, <ShareSection>{
        ShareSection.basicInfo,
        ShareSection.pricing,
        ShareSection.locationDetails,
        ShareSection.contact,
        ShareSection.notes,
        ShareSection.media,
      });
      expect(controller.isMediaSelected('photo-1'), isTrue);
      expect(controller.isMediaSelected('photo-2'), isTrue);
      expect(controller.isMediaSelected('video-1'), isFalse);
      expect(controller.selectedMediaCount, 2);
      expect(controller.totalMediaCount, 3);
      expect(controller.canShare, isTrue);
    });

    test('Select All shows a dash while a video is left out', () {
      final controller = controllerFor(offerWith(
        localPhotos: 1,
        extra: <OfferMediaRef>[
          mediaRef('video-1', video: true, signedUrl: _linkV)
        ],
      ));
      expect(controller.allState, isNull);

      controller.toggleMedia('video-1');
      expect(controller.allState, isTrue);
    });

    test('Select All chooses everything, then nothing', () {
      final controller = controllerFor(offerWith(
        localPhotos: 1,
        extra: <OfferMediaRef>[
          mediaRef('video-1', video: true, signedUrl: _linkV)
        ],
      ));
      controller.toggleAll();
      expect(controller.allState, isTrue);
      expect(controller.isMediaSelected('video-1'), isTrue);

      controller.toggleAll();
      expect(controller.allState, isFalse);
      expect(controller.hasSelection, isFalse);
      expect(controller.canShare, isFalse);

      controller.toggleAll();
      expect(controller.allState, isTrue);
    });

    test('ticking Media chooses the photos, ticking it again clears them', () {
      final controller = controllerFor(offerWith(
        localPhotos: 2,
        extra: <OfferMediaRef>[
          mediaRef('video-1', video: true, signedUrl: _linkV)
        ],
      ));
      controller.toggleSection(ShareSection.media);
      expect(controller.isSelected(ShareSection.media), isFalse);
      expect(controller.selectedMediaCount, 0);

      controller.toggleSection(ShareSection.media);
      expect(controller.selectedMediaKeys, <String>{'photo-1', 'photo-2'});
    });

    test('a record with only videos starts with none and ticking chooses them',
        () {
      final controller = controllerFor(PropertyShareSource.offer(offer(),
          media: mediaItems(<OfferMediaRef>[
            mediaRef('video-1', video: true, signedUrl: _linkV),
          ])));
      expect(controller.isSelected(ShareSection.media), isFalse);
      controller.toggleSection(ShareSection.media);
      expect(controller.selectedMediaKeys, <String>{'video-1'});
    });

    test('choosing every photo and video one by one is the same as all', () {
      final controller = controllerFor(offerWith(localPhotos: 2));
      controller.clearMedia();
      expect(controller.isSelected(ShareSection.media), isFalse);
      controller.toggleMedia('photo-2');
      expect(controller.isSelected(ShareSection.media), isTrue);
      expect(controller.selectedMediaCount, 1);
      controller.toggleMedia('photo-2');
      expect(controller.isSelected(ShareSection.media), isFalse);
      controller.selectAllMedia();
      expect(controller.selectedMediaCount, 2);
    });

    test('viewer starts with its current key and can add more media', () {
      final source = offerWith(
        localPhotos: 2,
        extra: <OfferMediaRef>[
          mediaRef('video-1', video: true, signedUrl: _linkV),
        ],
      );
      final controller = controllerFor(source, initialMediaKey: 'video-1');
      expect(controller.selectedMediaKeys, <String>{'video-1'});
      controller.replaceMediaSelection(<String>{'video-1', 'photo-2'});
      expect(controller.selectedMediaKeys, <String>{'video-1', 'photo-2'});
      controller.replaceMediaSelection(<String>{'photo-1', 'missing'});
      expect(controller.selectedMediaKeys, <String>{'photo-1'});
    });

    test('a part the record does not have cannot be chosen', () {
      final controller = controllerFor(PropertyShareSource.request(request()));
      controller.toggleSection(ShareSection.map);
      controller.toggleSection(ShareSection.media);
      controller.toggleSection(ShareSection.document);
      controller.toggleMedia('nothing');
      expect(controller.selection, <ShareSection>{
        ShareSection.basicInfo,
        ShareSection.locationDetails,
      });
    });

    test('Select All covers only what the record has', () {
      final controller = controllerFor(PropertyShareSource.request(request()));
      controller.toggleAll();
      expect(controller.hasSelection, isFalse);
      controller.toggleAll();
      expect(controller.selection, <ShareSection>{
        ShareSection.basicInfo,
        ShareSection.locationDetails,
      });
    });

    test('a choice tells listeners', () {
      final controller = controllerFor(offerWith(localPhotos: 1));
      var notified = 0;
      controller.addListener(() => notified++);
      controller.toggleSection(ShareSection.notes);
      controller.toggleMedia('photo-1');
      expect(notified, 2);
    });
  });

  group('an empty share', () {
    test('cannot be started and opens no share sheet', () async {
      final controller = controllerFor(PropertyShareSource.request(request()));
      controller.toggleAll();
      expect(controller.hasSelection, isFalse);
      expect(controller.canShare, isFalse);

      final result = await controller.share();
      expect(result, ShareFlowResult.nothingSelected);
      expect(sink.requests, isEmpty);
      expect(stagedFolders(), isEmpty);
    });
  });

  group('sharing text', () {
    test('opens the sheet once with the message and the subject', () async {
      final source = PropertyShareSource.request(request(
          min: '1000000', phone: '+971501234567', notes: 'Corner unit'));
      final controller = controllerFor(source);
      const origin = ShareOrigin(10, 20, 30, 40);

      final result = await controller.share(origin: origin);

      expect(result, ShareFlowResult.shared);
      expect(sink.requests, hasLength(1));
      final sent = sink.requests.single;
      expect(sent.files, isEmpty);
      expect(sent.subject, 'Request Details');
      expect(sent.origin, same(origin));
      expect(sent.text,
          source.composeText(source.defaultSelection, labelsIn('en')));
      expect(sent.text, contains('Phone: +971 50 123 4567'));
      expect(controller.status, ShareFlowStatus.idle);
      expect(controller.failure, isNull);
      expect(stagedFolders(), isEmpty, reason: 'no files, no folder');
    });

    test('works with no connection at all', () async {
      // Nothing was ever given a network: text needs none.
      final controller = controllerFor(PropertyShareSource.request(request()));
      expect(await controller.share(), ShareFlowResult.shared);
      expect(net.requested, isEmpty);
    });

    test('a share of one part writes only that part', () async {
      final controller = controllerFor(PropertyShareSource.request(
          request(min: '1000000', phone: '+971501234567', notes: 'secret')));
      controller.toggleAll();
      controller.toggleSection(ShareSection.pricing);
      await controller.share();
      final text = sink.requests.single.text!;
      expect(text, contains('Price: AED 1,000,000'));
      expect(text.contains('Phone'), isFalse);
      expect(text.contains('secret'), isFalse);
    });

    test('is written in Arabic for an Arabic message', () async {
      final controller = controllerFor(
          PropertyShareSource.request(request(type: 'sell')),
          language: 'ar');
      await controller.share();
      expect(sink.requests.single.subject, arbLookup('ar', 'requestDetails'));
      expect(
          sink.requests.single.text, contains(arbLookup('ar', 'saleRequest')!));
    });
  });

  group('sharing files', () {
    test('one photo goes with the message, under a professional name',
        () async {
      final controller = controllerFor(offerWith(localPhotos: 1));
      final result = await controller.share();

      expect(result, ShareFlowResult.shared);
      final sent = sink.requests.single;
      expect(sent.text, isNotNull);
      expect(sent.files.map((f) => f.name).toList(),
          <String>['Offer-Dubai-Marina-01.jpg']);
      expect(sent.files.single.mimeType, 'image/jpeg');
      expect(sink.filesExistedAtSend.single, <bool>[true]);
      expect(net.requested, isEmpty,
          reason: 'the photo was already on the phone');
    });

    test('several photos are numbered in the gallery\'s order', () async {
      final controller = controllerFor(offerWith(localPhotos: 3));
      await controller.share();
      expect(sink.requests, hasLength(1));
      expect(sink.requests.single.files, hasLength(3));
      expect(sink.requests.single.files.map((f) => f.name).toList(), <String>[
        'Offer-Dubai-Marina-01.jpg',
        'Offer-Dubai-Marina-02.jpg',
        'Offer-Dubai-Marina-03.jpg',
      ]);
    });

    test('duplicate media identity reaches the sheet only once', () async {
      net.bodies[_linkA] = jpegBytes();
      final controller = controllerFor(offerWith(extra: <OfferMediaRef>[
        mediaRef('same-photo', signedUrl: _linkA),
        mediaRef('same-photo', signedUrl: _linkB),
      ]));
      expect(controller.totalMediaCount, 1);
      expect(await controller.share(), ShareFlowResult.shared);
      expect(net.requested, <String>[_linkA]);
      expect(sink.requests, hasLength(1));
      expect(sink.requests.single.files, hasLength(1));
    });

    test('with the location left out, no place is in a file name', () async {
      final controller = controllerFor(offerWith(localPhotos: 1));
      controller.toggleSection(ShareSection.locationDetails);
      await controller.share();
      expect(sink.requests.single.files.single.name, 'Offer-01.jpg');
    });

    test('only the chosen media is shared', () async {
      final controller =
          controllerFor(offerWith(localPhotos: 3, extra: <OfferMediaRef>[
        mediaRef('photo-4', signedUrl: _linkA),
      ]));
      controller.toggleMedia('photo-1');
      controller.toggleMedia('photo-3');
      controller.toggleMedia('photo-4');
      await controller.share();
      final sent = sink.requests.single;
      expect(sent.files, hasLength(1));
      // Numbered among what is shared, not among what the record holds.
      expect(sent.files.single.name, endsWith('-01.jpg'));
      expect(File(sent.files.single.path).readAsBytesSync(), jpegBytes(20));
      expect(net.requested, isEmpty,
          reason: 'the unselected remote photo is never fetched');
    });

    test('files alone carry no message when no text part is chosen', () async {
      final controller = controllerFor(offerWith(localPhotos: 2));
      controller.toggleAll();
      controller.toggleSection(ShareSection.media);
      expect(controller.selection, <ShareSection>{ShareSection.media});
      await controller.share();
      expect(sink.requests.single.text, isNull);
      expect(sink.requests.single.files, hasLength(2));
    });

    test('a quotation PDF is shared as a file with a professional name',
        () async {
      final cached = area.writeCacheFile(
          'quotation_quotation-id-1b2c_pdf-media-id-7f3a.pdf', pdfBytes());
      final source = QuotationShareSource(
        quotation(officeName: 'Prime'),
        fetchPdf: () async => cached,
      );
      final controller = controllerFor(source);
      expect(controller.selection, <ShareSection>{
        ShareSection.basicInfo,
        ShareSection.document,
      });

      await controller.share();

      final sent = sink.requests.single;
      expect(
          sent.files.single.name, 'Broker-Wallet-Quotation-Apartment-306.pdf');
      expect(sent.files.single.mimeType, 'application/pdf');
      expect(sent.files.single.path.contains('quotation-id'), isFalse);
      expect(sent.subject, 'Quotation Details');
      expect(cached.existsSync(), isTrue);
    });

    test('a quotation shared without its PDF is the message alone', () async {
      final source = QuotationShareSource(
        quotation(),
        fetchPdf: () async => throw StateError('must not be fetched'),
      );
      final controller = controllerFor(source);
      controller.toggleSection(ShareSection.document);
      final result = await controller.share();
      expect(result, ShareFlowResult.shared);
      expect(sink.requests.single.files, isEmpty);
    });
  });

  group('what reaches the native sheet: 0, 1, a family, or a mix', () {
    const linkV1 = 'https://store.example/v1?sig=11';
    const linkV2 = 'https://store.example/v2?sig=12';
    const linkV3 = 'https://store.example/v3?sig=13';
    late FakeShareClipboard clipboard;

    setUp(() {
      clipboard = FakeShareClipboard();
      engine =
          newEngine(area, sink, client: net.client(), clipboard: clipboard);
    });

    /// The message the dialog's default choice writes, as the controller does.
    String messageOf(ShareSource source) =>
        source.composeText(source.defaultSelection, labelsIn('en'))!;

    List<int> bytesOf(PreparedShareFile file) =>
        File(file.path).readAsBytesSync();

    List<OfferMediaRef> threeVideos() => <OfferMediaRef>[
          mediaRef('video-1', video: true, signedUrl: linkV1),
          mediaRef('video-2', video: true, signedUrl: linkV2),
          mediaRef('video-3', video: true, signedUrl: linkV3),
        ];

    void serveThreeVideos() {
      net.bodies[linkV1] = mp4Bytes(600);
      net.bodies[linkV2] = mp4Bytes(700);
      net.bodies[linkV3] = mp4Bytes(800);
    }

    group('no media, one image, one video', () {
      test('no media shares the message alone', () async {
        final controller = controllerFor(offerWith());

        expect(await controller.share(), ShareFlowResult.shared);

        final sent = sink.requests.single;
        expect(sent.files, isEmpty);
        expect(sent.text, isNotNull);
        expect(sent.mediaBatch, isFalse);
        expect(clipboard.attempts, 0);
      });

      test('one image goes with the message, and the clipboard is untouched',
          () async {
        final controller = controllerFor(offerWith(localPhotos: 1));
        expect(controller.copiesDetails, isFalse);
        expect(controller.twoStepShare, isFalse);

        expect(await controller.share(), ShareFlowResult.shared);

        final sent = sink.requests.single;
        expect(sent.files, hasLength(1));
        expect(sent.files.single.mimeType, 'image/jpeg');
        expect(sent.text, isNotNull);
        expect(sent.subject, isNotNull);
        expect(sent.mediaBatch, isFalse,
            reason: 'one file keeps the existing system share');
        expect(sink.systemRequests, hasLength(1));
        expect(sink.nativeRequests, isEmpty);
        expect(clipboard.attempts, 0);
      });

      test(
          'one video goes with the message as its real file, and the '
          'clipboard is untouched', () async {
        net.bodies[linkV1] = mp4Bytes();
        final controller = controllerFor(
            offerWith(extra: <OfferMediaRef>[threeVideos().first]));
        controller.replaceMediaSelection(<String>{'video-1'});
        expect(controller.copiesDetails, isFalse);

        expect(await controller.share(), ShareFlowResult.shared);

        final sent = sink.requests.single;
        expect(sent.files, hasLength(1));
        expect(sent.files.single.name, 'Offer-Dubai-Marina-01.mp4');
        expect(sent.files.single.mimeType, 'video/mp4');
        expect(bytesOf(sent.files.single), mp4Bytes(),
            reason: 'the original video, not a poster or a link');
        expect(sent.text, isNotNull);
        expect(sent.text!.contains('store.example'), isFalse);
        expect(sent.text!.contains('sig='), isFalse);
        expect(sent.mediaBatch, isFalse);
        expect(sink.systemRequests, hasLength(1));
        expect(clipboard.attempts, 0);
      });
    });

    group('several photos', () {
      test(
          'all of them go in one homogeneous batch, in the gallery\'s order, '
          'with no message in the request; the message is copied once',
          () async {
        final source = offerWith(localPhotos: 3);
        final controller = controllerFor(source);
        expect(controller.copiesDetails, isTrue);
        expect(controller.twoStepShare, isFalse);

        expect(await controller.share(), ShareFlowResult.shared);

        expect(sink.requests, hasLength(1), reason: 'one external share');
        expect(sink.nativeRequests, hasLength(1));
        final sent = sink.requests.single;
        expect(sent.mediaBatch, isTrue);
        expect(sent.text, isNull,
            reason: 'no caption that a receiving app repeats or drops');
        expect(sent.subject, isNull);
        expect(sent.files.map((f) => f.name).toList(), <String>[
          'Offer-Dubai-Marina-01.jpg',
          'Offer-Dubai-Marina-02.jpg',
          'Offer-Dubai-Marina-03.jpg',
        ]);
        expect(
            sent.files.map((f) => f.mimeType).toSet(), <String>{'image/jpeg'},
            reason: 'the type the files proved, not a family they are not');
        expect(
            sent.files.map((f) => bytesOf(f).length).toList(),
            <int>[
              jpegBytes(10).length,
              jpegBytes(20).length,
              jpegBytes(30).length,
            ],
            reason: 'the gallery\'s order');
        expect(sink.filesExistedAtSend.single, <bool>[true, true, true]);
        expect(clipboard.copied, <String>[messageOf(source)],
            reason: 'the complete details, once');
      });

      test('the copied details carry no link, id or private path', () async {
        net.bodies[_linkA] = jpegBytes();
        net.bodies[_linkB] = jpegBytes();
        final controller = controllerFor(offerWith(extra: <OfferMediaRef>[
          mediaRef('photo-1', signedUrl: _linkA),
          mediaRef('photo-2', signedUrl: _linkB),
        ]));

        await controller.share();

        final copied = clipboard.copied.single;
        expect(copied.contains('store.example'), isFalse);
        expect(copied.contains('sig='), isFalse);
        expect(copied.contains('photo-1'), isFalse);
        expect(copied.contains('offer-media:'), isFalse);
        expect(copied.contains(area.root.path), isFalse);
        expect(
            RegExp(r'https?://').allMatches(copied).every((m) =>
                copied.startsWith('https://www.google.com/maps/', m.start)),
            isTrue,
            reason: 'the only link is the public map link, if the message has '
                'one');
      });

      test('with no text part chosen, the files go alone and nothing is copied',
          () async {
        final controller = controllerFor(offerWith(localPhotos: 2));
        controller.toggleAll();
        controller.toggleSection(ShareSection.media);
        expect(controller.selection, <ShareSection>{ShareSection.media});
        expect(controller.copiesDetails, isFalse);

        expect(await controller.share(), ShareFlowResult.shared);
        expect(sink.requests.single.files, hasLength(2));
        expect(sink.requests.single.text, isNull);
        expect(clipboard.attempts, 0);
      });
    });

    group('several videos', () {
      test(
          'all of them are prepared as real video files and go in one '
          'homogeneous batch, with the message copied once', () async {
        serveThreeVideos();
        final source = offerWith(extra: threeVideos());
        final controller = controllerFor(source);
        controller
            .replaceMediaSelection(<String>{'video-1', 'video-2', 'video-3'});
        expect(controller.copiesDetails, isTrue);
        expect(controller.twoStepShare, isFalse);

        expect(await controller.share(), ShareFlowResult.shared);

        expect(sink.requests, hasLength(1), reason: 'one external share');
        final sent = sink.requests.single;
        expect(sent.mediaBatch, isTrue);
        expect(sent.text, isNull);
        expect(sent.files, hasLength(3), reason: 'every video survives');
        expect(sent.files.map((f) => f.name).toList(), <String>[
          'Offer-Dubai-Marina-01.mp4',
          'Offer-Dubai-Marina-02.mp4',
          'Offer-Dubai-Marina-03.mp4',
        ]);
        expect(sent.files.map((f) => f.mimeType).toList(),
            <String>['video/mp4', 'video/mp4', 'video/mp4'],
            reason: 'the type each file\'s own bytes proved');
        for (final file in sent.files) {
          expect(file.path.endsWith('.mp4'), isTrue,
              reason: 'the extension agrees with the type');
          expect(bytesOf(file).sublist(4, 8), <int>[0x66, 0x74, 0x79, 0x70],
              reason: 'the bytes are the video container the type names');
        }
        expect(
            sent.files.map((f) => bytesOf(f).length).toList(),
            <int>[
              mp4Bytes(600).length,
              mp4Bytes(700).length,
              mp4Bytes(800).length,
            ],
            reason: 'the gallery\'s order');
        expect(sink.filesExistedAtSend.single, <bool>[true, true, true]);
        expect(net.requested, <String>[linkV1, linkV2, linkV3]);
        expect(clipboard.copied, <String>[messageOf(source)]);
      });
    });

    group('photos and videos chosen together: two steps, one choice', () {
      // Photo A, Video X, Photo B, Video Y: the order the person chose them in.
      PropertyShareSource master() => offerWith(extra: <OfferMediaRef>[
            mediaRef('photo-a', signedUrl: _linkA),
            mediaRef('video-x', video: true, signedUrl: linkV1),
            mediaRef('photo-b', signedUrl: _linkB),
            mediaRef('video-y', video: true, signedUrl: linkV2),
          ]);

      void serve() {
        net.bodies[_linkA] = jpegBytes(10);
        net.bodies[linkV1] = mp4Bytes(600);
        net.bodies[_linkB] = jpegBytes(20);
        net.bodies[linkV2] = mp4Bytes(700);
      }

      List<String> keys(Iterable<ShareMediaItem> items) =>
          <String>[for (final item in items) item.key];

      test('the choice is kept as chosen and the batches are derived from it',
          () {
        final controller = controllerFor(master());
        controller.selectAllMedia();

        expect(keys(controller.mediaBatches.master),
            <String>['photo-a', 'video-x', 'photo-b', 'video-y']);
        expect(keys(controller.mediaBatches.images),
            <String>['photo-a', 'photo-b']);
        expect(keys(controller.mediaBatches.videos),
            <String>['video-x', 'video-y']);
        expect(controller.twoStepShare, isTrue);
        expect(controller.hasPendingStep, isFalse);
        expect(controller.pendingFamily, isNull);
        expect(controller.copiesDetails, isTrue);
      });

      test(
          'Share hands over the photos only, as a homogeneous batch, and says '
          'nothing else: no question, no videos fetched, the details copied '
          'once', () async {
        serve();
        final source = master();
        final controller = controllerFor(source);
        controller.selectAllMedia();

        final result = await controller.share();

        expect(result, ShareFlowResult.stepShared);
        expect(sink.requests, hasLength(1), reason: 'one external share');
        final sent = sink.requests.single;
        expect(sent.mediaBatch, isTrue);
        expect(sent.files.map((f) => f.mimeType).toList(),
            <String>['image/jpeg', 'image/jpeg'],
            reason: 'the type the photos proved; nothing is relabelled');
        expect(sent.files.map((f) => f.name).toList(), <String>[
          'Offer-Dubai-Marina-01.jpg',
          'Offer-Dubai-Marina-02.jpg',
        ]);
        expect(sent.text, isNull);
        expect(net.requested, <String>[_linkA, _linkB],
            reason: 'the videos are not fetched for the photo step');
        expect(clipboard.copied, <String>[messageOf(source)]);
        expect(controller.hasPendingStep, isTrue);
        expect(controller.pendingFamily, MediaFamily.videos);
        expect(controller.status, ShareFlowStatus.idle);
      });

      test(
          'the master selection is not changed by sharing: only the progress '
          'is tracked', () async {
        serve();
        final controller = controllerFor(master());
        controller.selectAllMedia();
        final before = controller.selectedMediaKeys;

        await controller.share();

        expect(controller.selectedMediaKeys, before);
        expect(keys(controller.mediaBatches.master),
            <String>['photo-a', 'video-x', 'photo-b', 'video-y']);
        expect(controller.isMediaSelected('photo-a'), isTrue);
        expect(controller.isMediaSelected('video-y'), isTrue);
        expect(controller.selectedMediaCount, 4);
      });

      test(
          'nothing starts the second step by itself: no timer, no second '
          'sheet while the first receiving app may be open', () async {
        serve();
        final controller = controllerFor(master());
        controller.selectAllMedia();

        await controller.share();
        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await pumpEventQueue();

        expect(sink.requests, hasLength(1));
        expect(net.requested, <String>[_linkA, _linkB]);
        expect(controller.hasPendingStep, isTrue);
        expect(controller.status, ShareFlowStatus.idle);
      });

      test(
          'the next Share hands over the videos only, in their order, with no '
          're-selection, no second copy, and the photos are not sent again',
          () async {
        serve();
        final controller = controllerFor(master());
        controller.selectAllMedia();
        await controller.share();
        net.requested.clear();

        final result = await controller.share();

        expect(result, ShareFlowResult.shared);
        expect(sink.requests, hasLength(2), reason: 'one external share each');
        final second = sink.requests.last;
        expect(second.mediaBatch, isTrue);
        expect(second.files.map((f) => f.mimeType).toList(),
            <String>['video/mp4', 'video/mp4']);
        expect(second.files.map((f) => f.name).toList(), <String>[
          'Offer-Dubai-Marina-01.mp4',
          'Offer-Dubai-Marina-02.mp4',
        ]);
        expect(second.text, isNull);
        expect(net.requested, <String>[linkV1, linkV2],
            reason: 'only the videos are fetched, and the photos are not');
        expect(clipboard.attempts, 1, reason: 'the details are copied once');
        expect(controller.hasPendingStep, isFalse);
        expect(controller.selectedMediaCount, 4);
      });

      test('a retry after a failed second step sends only the second step',
          () async {
        serve();
        final controller = controllerFor(master());
        controller.selectAllMedia();
        await controller.share();
        net.requested.clear();
        net.failures[linkV1] = const SocketException('offline');

        final failed = await controller.share();

        expect(failed, ShareFlowResult.failed);
        expect(controller.failure!.kind, ShareFailureKind.network);
        expect(sink.requests, hasLength(1), reason: 'nothing more was sent');
        expect(controller.hasPendingStep, isTrue,
            reason: 'the photos are done; the videos are still pending');
        expect(controller.pendingFamily, MediaFamily.videos);
        expect(controller.selectedMediaCount, 4);

        net.failures.clear();
        net.requested.clear();
        final retried = await controller.share();

        expect(retried, ShareFlowResult.shared);
        expect(sink.requests, hasLength(2));
        expect(sink.requests.last.files.map((f) => f.mimeType).toSet(),
            <String>{'video/mp4'});
        expect(net.requested, <String>[linkV1, linkV2],
            reason: 'the photos are not fetched or sent again');
        expect(clipboard.attempts, 1);
      });

      test('a second step that cannot be opened is retried alone', () async {
        serve();
        final controller = controllerFor(master());
        controller.selectAllMedia();
        await controller.share();
        sink.error = StateError('no sheet');

        expect(await controller.share(), ShareFlowResult.failed);
        expect(controller.hasPendingStep, isTrue);
        expect(clipboard.attempts, 1, reason: 'not copied again');

        sink.error = null;
        expect(await controller.share(), ShareFlowResult.shared);
        final videoRequests =
            sink.requests.where((r) => r.files.any((f) => f.isVideo)).toList();
        expect(videoRequests, hasLength(2),
            reason: 'the failed attempt and the retry');
        final photoRequests =
            sink.requests.where((r) => r.files.any((f) => f.isImage)).toList();
        expect(photoRequests, hasLength(1), reason: 'the photos went once');
      });

      test('a closed second sheet leaves the videos pending', () async {
        serve();
        final controller = controllerFor(master());
        controller.selectAllMedia();
        await controller.share();
        sink.outcome = ShareOutcome.dismissed;

        expect(await controller.share(), ShareFlowResult.dismissed);
        expect(controller.hasPendingStep, isTrue);
        expect(controller.failure, isNull);
        expect(clipboard.attempts, 1);

        sink.outcome = ShareOutcome.shared;
        expect(await controller.share(), ShareFlowResult.shared);
        expect(controller.hasPendingStep, isFalse);
      });

      test(
          'a failure before the first step sends nothing, copies nothing and '
          'leaves the choice intact', () async {
        serve();
        net.failures[_linkA] = const SocketException('offline');
        final controller = controllerFor(master());
        controller.selectAllMedia();

        final result = await controller.share();

        expect(result, ShareFlowResult.failed);
        expect(sink.requests, isEmpty);
        expect(clipboard.attempts, 0);
        expect(controller.hasPendingStep, isFalse);
        expect(controller.selectedMediaCount, 4);
        expect(net.requested.contains(linkV1), isFalse,
            reason: 'the videos were never reached');
      });

      test('a closed first sheet starts the share over from the photos',
          () async {
        serve();
        sink.outcome = ShareOutcome.dismissed;
        final controller = controllerFor(master());
        controller.selectAllMedia();

        expect(await controller.share(), ShareFlowResult.dismissed);
        expect(controller.hasPendingStep, isFalse);

        sink.outcome = ShareOutcome.shared;
        expect(await controller.share(), ShareFlowResult.stepShared);
        expect(
            sink.requests.every((r) => r.files.every((f) => f.isImage)), isTrue,
            reason: 'both attempts were the photo step');
      });

      test('changing the media choice starts the share over', () async {
        serve();
        final controller = controllerFor(master());
        controller.selectAllMedia();
        await controller.share();
        expect(controller.hasPendingStep, isTrue);

        controller.toggleMedia('video-y');

        expect(controller.hasPendingStep, isFalse);
        expect(controller.pendingFamily, isNull);
        expect(controller.selectedMediaCount, 3);
      });

      test(
          'one photo with several videos: the photo goes with its message, the '
          'videos as a batch, and the details are copied once', () async {
        serve();
        final source = offerWith(extra: <OfferMediaRef>[
          mediaRef('photo-a', signedUrl: _linkA),
          mediaRef('video-x', video: true, signedUrl: linkV1),
          mediaRef('video-y', video: true, signedUrl: linkV2),
        ]);
        final controller = controllerFor(source);
        controller.selectAllMedia();

        expect(await controller.share(), ShareFlowResult.stepShared);
        expect(sink.requests.single.files, hasLength(1));
        expect(sink.requests.single.text, messageOf(source));
        expect(sink.requests.single.mediaBatch, isFalse);
        expect(clipboard.attempts, 1);

        expect(await controller.share(), ShareFlowResult.shared);
        expect(sink.requests.last.mediaBatch, isTrue);
        expect(sink.requests.last.text, isNull);
        expect(clipboard.attempts, 1, reason: 'once for the whole share');
      });

      test(
          'one photo and one video: each goes with its message, and nothing '
          'is copied', () async {
        serve();
        final controller = controllerFor(offerWith(extra: <OfferMediaRef>[
          mediaRef('photo-a', signedUrl: _linkA),
          mediaRef('video-x', video: true, signedUrl: linkV1),
        ]));
        controller.selectAllMedia();
        expect(controller.copiesDetails, isFalse);

        expect(await controller.share(), ShareFlowResult.stepShared);
        expect(await controller.share(), ShareFlowResult.shared);

        expect(sink.requests, hasLength(2));
        expect(sink.requests.every((r) => r.text != null), isTrue);
        expect(sink.requests.every((r) => !r.mediaBatch), isTrue);
        expect(clipboard.attempts, 0);
      });

      test('taps while a step is under way start nothing more', () async {
        serve();
        final gate = Completer<List<int>>();
        net.held[_linkA] = gate;
        final controller = controllerFor(master());
        controller.selectAllMedia();

        final first = controller.share();
        expect(controller.isBusy, isTrue);
        expect(await controller.share(), ShareFlowResult.busy);
        expect(await controller.share(), ShareFlowResult.busy);
        await until(() => net.requested.isNotEmpty);
        expect(clipboard.attempts, 0);
        gate.complete(<int>[1, 2, 3]);
        expect(await first, ShareFlowResult.stepShared);
        expect(sink.requests, hasLength(1));
        expect(clipboard.attempts, 1);

        final next = controller.share();
        expect(await controller.share(), ShareFlowResult.busy);
        expect(await next, ShareFlowResult.shared);
        expect(sink.requests, hasLength(2), reason: 'one request per step');
        expect(clipboard.attempts, 1);
        expect(net.requested, <String>[_linkA, _linkB, linkV1, linkV2],
            reason: 'one download of each file');
      });

      test(
          'a platform that takes the whole selection shares it in one system '
          'share with its message and copies nothing', () async {
        serve();
        engine = newEngine(area, sink,
            client: net.client(),
            clipboard: clipboard,
            delivery: ShareDelivery.wholeSelection);
        final source = master();
        final controller = controllerFor(source);
        controller.selectAllMedia();
        expect(controller.twoStepShare, isFalse);
        expect(controller.copiesDetails, isFalse);

        expect(await controller.share(), ShareFlowResult.shared);

        final sent = sink.requests.single;
        expect(sent.files, hasLength(4));
        expect(sent.text, messageOf(source));
        expect(sent.mediaBatch, isFalse);
        expect(clipboard.attempts, 0);
        expect(controller.hasPendingStep, isFalse);
      });

      test(
          'a batch that proves to mix photos and videos is never launched, '
          'whatever the record said', () async {
        // The record calls both photos; the bytes of one are a video.
        net.bodies[_linkA] = jpegBytes(10);
        net.bodies[_linkB] = mp4Bytes();
        final controller = controllerFor(offerWith(extra: <OfferMediaRef>[
          mediaRef('photo-1', signedUrl: _linkA),
          mediaRef('photo-2', signedUrl: _linkB),
        ]));

        expect(await controller.share(), ShareFlowResult.failed);

        expect(controller.failure!.kind, ShareFailureKind.generic);
        expect(sink.requests, isEmpty);
        expect(clipboard.attempts, 0);
        expect(stagedFolders(), isEmpty);
      });
    });

    group('the fast path: what is already on the phone is reused, once', () {
      String keyOf(String id) =>
          offerMediaCacheKey(ownerId: 'user-1', mediaObjectId: id)!;

      List<String> namesIn(Directory folder) => folder
          .listSync()
          .map((e) => e.path.split(RegExp(r'[\\/]')).last)
          .toList()
        ..sort();

      test(
          'files held on the phone are found by lookup, never downloaded, and '
          'Continue looks up only the pending family', () async {
        final held = <String, String>{
          keyOf('photo-a'): area.writeCacheFile('a.jpg', jpegBytes(10)).path,
          keyOf('video-x'): area.writeCacheFile('x.mp4', mp4Bytes(600)).path,
          keyOf('photo-b'): area.writeCacheFile('b.jpg', jpegBytes(20)).path,
          keyOf('video-y'): area.writeCacheFile('y.mp4', mp4Bytes(700)).path,
        };
        final lookups = <String>[];
        engine = newEngine(area, sink,
            client: net.client(), clipboard: clipboard, localPath: (key) async {
          lookups.add(key);
          return held[key];
        });
        final controller = controllerFor(offerWith(extra: <OfferMediaRef>[
          mediaRef('photo-a'),
          mediaRef('video-x', video: true),
          mediaRef('photo-b'),
          mediaRef('video-y', video: true),
        ]));
        controller.selectAllMedia();

        // Step one: the photos, each looked up once; the videos are not touched.
        expect(await controller.share(), ShareFlowResult.stepShared);
        expect(lookups, <String>[keyOf('photo-a'), keyOf('photo-b')]);
        expect(net.requested, isEmpty, reason: 'nothing is downloaded');
        final photoFolder = stagedFolders().single as Directory;
        final photoFiles = namesIn(photoFolder);
        expect(photoFiles, hasLength(2),
            reason: 'one staged copy of each photo and nothing else');
        expect(sink.requests.single.files.map((f) => bytesOf(f).length),
            <int>[jpegBytes(10).length, jpegBytes(20).length]);

        // Step two: only the videos are looked up; the photos' folder is left
        // exactly as it was, so nothing is prepared or staged a second time.
        lookups.clear();
        expect(await controller.share(), ShareFlowResult.shared);
        expect(lookups, <String>[keyOf('video-x'), keyOf('video-y')]);
        expect(net.requested, isEmpty, reason: 'still nothing downloaded');
        expect(stagedFolders(), hasLength(2), reason: 'one folder per step');
        expect(namesIn(photoFolder), photoFiles);
        expect(sink.requests, hasLength(2));
        expect(sink.requests.last.files.every((f) => f.isVideo), isTrue);
        expect(clipboard.attempts, 1);
      });

      test(
          'a download is moved into place: the folder holds the finished files '
          'only, no partial or second copy', () async {
        net.bodies[_linkA] = jpegBytes(10);
        net.bodies[_linkB] = jpegBytes(20);
        final controller = controllerFor(offerWith(extra: <OfferMediaRef>[
          mediaRef('photo-1', signedUrl: _linkA),
          mediaRef('photo-2', signedUrl: _linkB),
        ]));

        expect(await controller.share(), ShareFlowResult.shared);

        expect(net.requested, <String>[_linkA, _linkB], reason: 'once each');
        expect(namesIn(stagedFolders().single as Directory), <String>[
          'Offer-Dubai-Marina-01.jpg',
          'Offer-Dubai-Marina-02.jpg',
        ]);
      });

      test(
          'the dialog is told about each phase once, never once per file, and '
          'nothing is shown as preparing once the sheet is open', () async {
        final gate = Completer<ShareOutcome>();
        sink.hold = gate;
        final controller = controllerFor(offerWith(localPhotos: 5));
        final phases = <ShareFlowStatus>[];
        controller.addListener(() => phases.add(controller.status));

        final pending = controller.share();
        expect(controller.isPreparing, isTrue);
        await until(() => controller.status == ShareFlowStatus.sharing);
        expect(controller.isBusy, isTrue, reason: 'still protected');
        expect(controller.isPreparing, isFalse,
            reason: 'the sheet is open: nothing is being prepared');

        gate.complete(ShareOutcome.shared);
        await pending;
        expect(
            phases,
            <ShareFlowStatus>[
              ShareFlowStatus.preparing,
              ShareFlowStatus.sharing,
              ShareFlowStatus.idle,
            ],
            reason: 'five files, three notifications');
        expect(controller.isBusy, isFalse);
        expect(controller.isPreparing, isFalse);
      });

      test(
          'a share with nothing to prepare is never visibly preparing: the '
          'status goes straight on to the sheet', () async {
        final gate = Completer<ShareOutcome>();
        sink.hold = gate;
        final controller = controllerFor(offerWith());
        final seen = <ShareFlowStatus>[];
        controller.addListener(() => seen.add(controller.status));

        final pending = controller.share();
        // Everything up to the sheet ran in the same turn: no file work, so no
        // await in which a frame could have drawn a spinner.
        expect(controller.status, ShareFlowStatus.sharing);
        expect(seen.first, ShareFlowStatus.preparing);
        gate.complete(ShareOutcome.shared);
        await pending;
      });
    });

    group('taps, failures and the clipboard', () {
      test('a repeated tap is one preparation, one copy, one native share',
          () async {
        final source = offerWith(localPhotos: 3);
        final controller = controllerFor(source);

        final first = controller.share();
        // The lock is taken before the first call returns its future: nothing
        // is awaited between the two taps.
        expect(controller.isBusy, isTrue);
        final second = controller.share();

        expect(await second, ShareFlowResult.busy);
        expect(await first, ShareFlowResult.shared);
        expect(sink.requests, hasLength(1));
        expect(sink.nativeRequests, hasLength(1),
            reason: 'three photos go to the Android batch transport');
        expect(sink.systemRequests, isEmpty);
        expect(clipboard.attempts, 1);
        expect(clipboard.copied, <String>[messageOf(source)]);
        expect(stagedFolders(), hasLength(1));
      });

      test('the message is copied before the sheet opens, never after',
          () async {
        var sheetsOpenAtCopy = -1;
        clipboard = FakeShareClipboard(
          onCopy: (_) => sheetsOpenAtCopy = sink.requests.length,
        );
        engine =
            newEngine(area, sink, client: net.client(), clipboard: clipboard);
        final controller = controllerFor(offerWith(localPhotos: 2));

        await controller.share();

        expect(sheetsOpenAtCopy, 0);
        expect(clipboard.attempts, 1);
      });

      test('what is promised follows what is chosen', () async {
        final controller = controllerFor(offerWith(localPhotos: 3));
        expect(controller.copiesDetails, isTrue);

        controller.toggleMedia('photo-1');
        controller.toggleMedia('photo-2');
        expect(controller.selectedMediaCount, 1);
        expect(controller.copiesDetails, isFalse, reason: 'one photo only');

        controller.toggleMedia('photo-2');
        expect(controller.copiesDetails, isTrue);

        controller.toggleMedia('photo-1');
        controller.toggleAll(); // Everything was chosen, so this clears it all.
        controller.toggleSection(ShareSection.media);
        expect(controller.selection, <ShareSection>{ShareSection.media});
        expect(controller.copiesDetails, isFalse, reason: 'no message');
      });

      test('a quotation PDF with its message copies nothing', () async {
        final cached = area.writeCacheFile(
            'quotation_quotation-id-1b2c_pdf-media-id-7f3a.pdf', pdfBytes());
        final controller = controllerFor(QuotationShareSource(
          quotation(officeName: 'Prime'),
          fetchPdf: () async => cached,
        ));

        expect(await controller.share(), ShareFlowResult.shared);
        expect(sink.requests.single.files, hasLength(1));
        expect(sink.requests.single.text, isNotNull);
        expect(sink.requests.single.mediaBatch, isFalse);
        expect(clipboard.attempts, 0);
      });

      test(
          'a clipboard that cannot take the message withdraws the promise, and '
          'the share still goes', () async {
        clipboard.succeeds = false;
        final controller = controllerFor(offerWith(localPhotos: 2));
        expect(controller.copiesDetails, isTrue);

        expect(await controller.share(), ShareFlowResult.shared);

        expect(clipboard.attempts, 1);
        expect(sink.requests.single.files, hasLength(2));
        expect(controller.failure, isNull);
        expect(controller.copiesDetails, isFalse);
      });

      test('a clipboard that throws is handled the same way', () async {
        clipboard.error = StateError('clipboard unavailable');
        final controller = controllerFor(offerWith(localPhotos: 2));

        expect(await controller.share(), ShareFlowResult.shared);

        expect(sink.requests.single.files, hasLength(2));
        expect(controller.failure, isNull);
        expect(controller.copiesDetails, isFalse);
      });

      test('an engine with no clipboard still shares, and promises nothing',
          () async {
        engine = newEngine(area, sink, client: net.client());
        final controller = controllerFor(offerWith(localPhotos: 3));
        expect(controller.copiesDetails, isFalse);

        expect(await controller.share(), ShareFlowResult.shared);
        expect(sink.requests.single.files, hasLength(3));
      });

      test(
          'closing the share sheet after it opened is not an error: the earlier '
          'copy stays and is not undone', () async {
        sink.outcome = ShareOutcome.dismissed;
        final source = offerWith(localPhotos: 2);
        final controller = controllerFor(source);

        expect(await controller.share(), ShareFlowResult.dismissed);

        expect(sink.requests, hasLength(1));
        expect(controller.failure, isNull);
        expect(clipboard.copied, <String>[messageOf(source)],
            reason: 'the details are still there to paste');
        expect(clipboard.attempts, 1,
            reason: 'nothing was copied again or reset');
        expect(controller.copiesDetails, isTrue,
            reason: 'sharing again would copy again');
      });

      test('a sheet that cannot be opened leaves the copy where it is',
          () async {
        sink.error = StateError('no sheet');
        final controller = controllerFor(offerWith(localPhotos: 2));

        expect(await controller.share(), ShareFlowResult.failed);

        expect(controller.failure!.kind, ShareFailureKind.generic);
        expect(clipboard.attempts, 1, reason: 'the copy is not undone');
        expect(clipboard.copied, hasLength(1));
      });

      test('a share that cannot be prepared copies nothing and opens nothing',
          () async {
        net.bodies[_linkA] = jpegBytes();
        net.statuses[_linkB] = 404;
        final controller = controllerFor(offerWith(extra: <OfferMediaRef>[
          mediaRef('photo-1', signedUrl: _linkA),
          mediaRef('photo-2', signedUrl: _linkB),
        ]));

        expect(await controller.share(), ShareFlowResult.failed);
        expect(sink.requests, isEmpty);
        expect(clipboard.attempts, 0);
      });

      test('a share called off before it is handed over copies nothing',
          () async {
        final gate = Completer<List<int>>();
        net.bodies[_linkA] = jpegBytes();
        net.bodies[_linkB] = jpegBytes();
        net.held[_linkA] = gate;
        final controller = controllerFor(offerWith(extra: <OfferMediaRef>[
          mediaRef('photo-1', signedUrl: _linkA),
          mediaRef('photo-2', signedUrl: _linkB),
        ]));

        final pending = controller.share();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        controller.cancel();
        gate.complete(<int>[9]);

        expect(await pending, ShareFlowResult.cancelled);
        expect(sink.requests, isEmpty);
        expect(clipboard.attempts, 0);
      });

      test('a share that finds a sheet already open copies nothing', () async {
        sink.hold = Completer<ShareOutcome>();
        final first = controllerFor(offerWith(localPhotos: 2));
        final firstResult = first.share();
        await until(() => sink.requests.isNotEmpty);
        expect(clipboard.attempts, 1);

        final second = controllerFor(offerWith(localPhotos: 3));
        expect(await second.share(), ShareFlowResult.busy);
        expect(clipboard.attempts, 1,
            reason: 'the second share copied nothing');
        expect(sink.requests, hasLength(1));
        expect(stagedFolders(), hasLength(1),
            reason: 'only the first share still holds its files');

        sink.hold!.complete(ShareOutcome.shared);
        expect(await firstResult, ShareFlowResult.shared);
      });

      test('each share that is handed over copies its own message', () async {
        sink.outcome = ShareOutcome.dismissed;
        final controller = controllerFor(offerWith(localPhotos: 2));

        await controller.share();
        await controller.share();

        expect(clipboard.copied, hasLength(2));
        expect(sink.requests, hasLength(2));
      });
    });
  });

  group('how the share sheet ends', () {
    test('closing it is not an error, and the files go at once', () async {
      sink.outcome = ShareOutcome.dismissed;
      final controller = controllerFor(offerWith(localPhotos: 1));
      final result = await controller.share();

      expect(result, ShareFlowResult.dismissed);
      expect(controller.failure, isNull);
      expect(controller.status, ShareFlowStatus.idle);
      expect(controller.hasSelection, isTrue, reason: 'the choices are kept');
      expect(stagedFolders(), isEmpty, reason: 'nobody received them');
    });

    test('choosing an app leaves the files for the app to read', () async {
      final controller = controllerFor(offerWith(localPhotos: 1));
      final result = await controller.share();
      expect(result, ShareFlowResult.shared);
      expect(stagedFolders(), hasLength(1));
      expect(File(sink.requests.single.files.single.path).existsSync(), isTrue);
    });

    test('a platform that cannot say how it ended is not a failure', () async {
      sink.outcome = ShareOutcome.unknown;
      final controller = controllerFor(PropertyShareSource.request(request()));
      expect(await controller.share(), ShareFlowResult.shared);
      expect(controller.failure, isNull);
    });

    test('a sheet that cannot be opened is a short failure, nothing is kept',
        () async {
      sink.error =
          PlatformException_('sharePositionOrigin: argument must be set');
      final controller = controllerFor(offerWith(localPhotos: 1));
      final result = await controller.share();

      expect(result, ShareFlowResult.failed);
      expect(controller.failure!.kind, ShareFailureKind.generic);
      expect(controller.failure!.toString(), 'ShareFailure(generic)');
      expect(controller.hasSelection, isTrue);
      expect(controller.status, ShareFlowStatus.idle);
      expect(stagedFolders(), isEmpty);
    });

    test('the status runs preparing, sharing, idle', () async {
      final gate = Completer<ShareOutcome>();
      sink.hold = gate;
      net.bodies[_linkA] = jpegBytes();
      final source = offerWith(localPhotos: 2, extra: <OfferMediaRef>[
        mediaRef('photo-3', signedUrl: _linkA),
      ]);
      final controller = controllerFor(source);
      final seen = <ShareFlowStatus>[];
      controller.addListener(() => seen.add(controller.status));

      final pending = controller.share();
      expect(controller.status, ShareFlowStatus.preparing);
      expect(controller.isPreparing, isTrue);
      expect(controller.isBusy, isTrue);
      expect(controller.canShare, isFalse);

      await until(() => controller.status == ShareFlowStatus.sharing);
      expect(controller.isPreparing, isFalse,
          reason: 'with the sheet open nothing is being prepared');
      expect(controller.isBusy, isTrue);

      gate.complete(ShareOutcome.shared);
      await pending;
      expect(controller.status, ShareFlowStatus.idle);
      expect(
          seen,
          <ShareFlowStatus>[
            ShareFlowStatus.preparing,
            ShareFlowStatus.sharing,
            ShareFlowStatus.idle,
          ],
          reason: 'one notification per phase, none per file');
    });
  });

  group('double taps', () {
    test('a second tap while files are being prepared starts nothing',
        () async {
      final gate = Completer<List<int>>();
      net.bodies[_linkA] = jpegBytes();
      net.held[_linkA] = gate;
      final controller = controllerFor(offerWith(
          extra: <OfferMediaRef>[mediaRef('photo-1', signedUrl: _linkA)]));

      final first = controller.share();
      final second = controller.share();
      final third = controller.share();
      expect(await second, ShareFlowResult.busy);
      expect(await third, ShareFlowResult.busy);

      gate.complete(<int>[1, 2, 3]);
      expect(await first, ShareFlowResult.shared);

      expect(net.requested, <String>[_linkA],
          reason: 'one download, not three');
      expect(sink.requests, hasLength(1), reason: 'one sheet, not three');
      expect(sink.systemRequests, hasLength(1),
          reason: 'one file takes the system share');
      expect(sink.nativeRequests, isEmpty);
    });

    test(
        'taps while a batch is being prepared start nothing: one preparation, '
        'one copy, one native request', () async {
      final gate = Completer<List<int>>();
      net.bodies[_linkA] = jpegBytes();
      net.held[_linkA] = gate;
      net.bodies[_linkB] = jpegBytes();
      final clipboard = FakeShareClipboard();
      engine =
          newEngine(area, sink, client: net.client(), clipboard: clipboard);
      final controller = controllerFor(offerWith(extra: <OfferMediaRef>[
        mediaRef('photo-1', signedUrl: _linkA),
        mediaRef('photo-2', signedUrl: _linkB),
      ]));

      final first = controller.share();
      expect(controller.isBusy, isTrue,
          reason: 'the lock is taken before the first call returns');
      expect(await controller.share(), ShareFlowResult.busy);
      expect(await controller.share(), ShareFlowResult.busy);

      // The first attempt is held inside preparation, at the first download.
      await until(() => net.requested.isNotEmpty);
      expect(clipboard.attempts, 0);
      expect(sink.requests, isEmpty);
      expect(await controller.share(), ShareFlowResult.busy);

      gate.complete(<int>[1, 2, 3]);
      expect(await first, ShareFlowResult.shared);

      expect(net.requested, <String>[_linkA, _linkB],
          reason: 'one download of each file, not one per tap');
      expect(clipboard.attempts, 1, reason: 'one copy');
      expect(sink.requests, hasLength(1));
      expect(sink.nativeRequests, hasLength(1),
          reason: 'two photos go to the Android multi-media transport');
      expect(sink.systemRequests, isEmpty);
      expect(stagedFolders(), hasLength(1), reason: 'one preparation');
    });

    test('a second tap while the sheet is open opens no second sheet',
        () async {
      final gate = Completer<ShareOutcome>();
      sink.hold = gate;
      final controller = controllerFor(PropertyShareSource.request(request()));

      final first = controller.share();
      await until(() => controller.status == ShareFlowStatus.sharing);
      expect(await controller.share(), ShareFlowResult.busy);
      expect(sink.requests, hasLength(1));
      expect(sink.systemRequests, hasLength(1),
          reason: 'a message alone takes the system share');

      gate.complete(ShareOutcome.shared);
      expect(await first, ShareFlowResult.shared);
    });

    test('choices cannot change while a share is under way', () async {
      final gate = Completer<ShareOutcome>();
      sink.hold = gate;
      final controller = controllerFor(offerWith(localPhotos: 1));
      final before = controller.selection;
      final pending = controller.share();
      controller.toggleSection(ShareSection.notes);
      controller.toggleMedia('photo-1');
      controller.toggleAll();
      expect(controller.selection, before);
      gate.complete(ShareOutcome.shared);
      await pending;
    });

    test('two dialogs cannot open two sheets between them', () async {
      final gate = Completer<ShareOutcome>();
      sink.hold = gate;
      final one = controllerFor(offerWith(localPhotos: 1));
      final two = controllerFor(PropertyShareSource.request(request()));

      final first = one.share();
      await until(() => sink.requests.isNotEmpty);
      expect(await two.share(), ShareFlowResult.busy);
      expect(sink.requests, hasLength(1));
      expect(two.failure, isNull);

      gate.complete(ShareOutcome.dismissed);
      await first;
    });
  });

  group('when files cannot be prepared', () {
    test('being offline keeps the choices and a retry can succeed', () async {
      net.failures[_linkA] = const SocketException('offline');
      final controller = controllerFor(offerWith(
          extra: <OfferMediaRef>[mediaRef('photo-1', signedUrl: _linkA)]));

      expect(await controller.share(), ShareFlowResult.failed);
      expect(controller.failure!.kind, ShareFailureKind.network);
      expect(controller.failure!.kind.messageKey, 'shareErrorNetwork');
      expect(sink.requests, isEmpty,
          reason: 'nothing is sent with a file missing');
      expect(stagedFolders(), isEmpty);
      expect(controller.isMediaSelected('photo-1'), isTrue);
      expect(controller.canShare, isTrue);

      net.failures.clear();
      net.bodies[_linkA] = jpegBytes();
      expect(await controller.share(), ShareFlowResult.shared);
      expect(controller.failure, isNull);
      expect(sink.requests.single.files, hasLength(1));
    });

    test('a file that is gone is marked and left out; sharing again goes on',
        () async {
      net.bodies[_linkA] = jpegBytes();
      net.statuses[_linkB] = 404;
      final controller = controllerFor(offerWith(extra: <OfferMediaRef>[
        mediaRef('photo-1', signedUrl: _linkA),
        mediaRef('photo-2', signedUrl: _linkB),
      ]));

      expect(await controller.share(), ShareFlowResult.failed);
      expect(sink.requests, isEmpty);
      expect(controller.failure!.kind, ShareFailureKind.unavailable);
      expect(controller.failure!.failedKeys, <String>['photo-2']);
      expect(controller.isMediaUnavailable('photo-2'), isTrue);
      expect(controller.isMediaSelected('photo-2'), isFalse,
          reason: 'an unavailable item never looks chosen');
      expect(controller.isMediaSelected('photo-1'), isTrue);

      // Sharing again is the person\'s decision to go on without it.
      expect(await controller.share(), ShareFlowResult.shared);
      expect(sink.requests.single.files, hasLength(1));
      expect(controller.allState, isTrue,
          reason: 'what cannot be had is not counted');
    });

    test('an unavailable item cannot be chosen again', () async {
      net.statuses[_linkA] = 404;
      final controller = controllerFor(offerWith(
          extra: <OfferMediaRef>[mediaRef('photo-1', signedUrl: _linkA)]));
      await controller.share();
      controller.toggleMedia('photo-1');
      controller.selectAllMedia();
      expect(controller.isMediaSelected('photo-1'), isFalse);
      expect(controller.isSelected(ShareSection.media), isFalse);
    });

    test('a PDF that is gone is marked and left out', () async {
      final source = QuotationShareSource(
        quotation(),
        fetchPdf: () async =>
            throw const ShareFailure(ShareFailureKind.unavailable),
      );
      final controller = controllerFor(source);

      expect(await controller.share(), ShareFlowResult.failed);
      expect(controller.isUnavailable(ShareSection.document), isTrue);
      expect(controller.isSelected(ShareSection.document), isFalse);
      expect(controller.failure!.failedKeys,
          <String>[ShareFlowController.documentKey]);

      // Without the PDF there is still the summary to share.
      expect(await controller.share(), ShareFlowResult.shared);
      expect(sink.requests.single.files, isEmpty);
    });

    test('a signed-out session is its own, non-retryable failure', () async {
      final source = QuotationShareSource(
        quotation(),
        fetchPdf: () async =>
            throw const ShareFailure(ShareFailureKind.session),
      );
      final controller = controllerFor(source);
      expect(await controller.share(), ShareFlowResult.failed);
      expect(controller.failure!.kind, ShareFailureKind.session);
      expect(controller.isUnavailable(ShareSection.document), isFalse);
      expect(controller.isSelected(ShareSection.document), isTrue);
    });

    test('whatever the error was, no text of it survives', () async {
      final source = QuotationShareSource(
        quotation(),
        fetchPdf: () async => throw StateError(
            'PostgrestException: https://x.supabase.co key=SECRET'),
      );
      final controller = controllerFor(source);
      expect(await controller.share(), ShareFlowResult.failed);
      final failure = controller.failure!;
      expect(failure.kind, ShareFailureKind.generic);
      expect('$failure'.contains('Postgrest'), isFalse);
      expect('$failure'.contains('SECRET'), isFalse);
      expect(failure.kind.messageKey, 'shareErrorGeneric');
    });

    test('a choice made after a failure clears it', () async {
      net.failures[_linkA] = const SocketException('offline');
      final controller = controllerFor(offerWith(
          extra: <OfferMediaRef>[mediaRef('photo-1', signedUrl: _linkA)]));
      await controller.share();
      expect(controller.failure, isNotNull);
      controller.toggleSection(ShareSection.notes);
      expect(controller.failure, isNull);
    });

    test('each failure has an Arabic and an English sentence', () {
      for (final kind in ShareFailureKind.values) {
        expect(arbLookup('en', kind.messageKey), isNotNull,
            reason: '${kind.name} en');
        expect(arbLookup('ar', kind.messageKey), isNotNull,
            reason: '${kind.name} ar');
      }
    });
  });

  group('calling a share off', () {
    test('while files are being fetched, no sheet opens and nothing is kept',
        () async {
      final gate = Completer<List<int>>();
      net.bodies[_linkA] = jpegBytes();
      net.held[_linkA] = gate;
      final controller = controllerFor(offerWith(
          extra: <OfferMediaRef>[mediaRef('photo-1', signedUrl: _linkA)]));

      final pending = controller.share();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      controller.cancel();
      gate.complete(<int>[9]);

      expect(await pending, ShareFlowResult.cancelled);
      expect(sink.requests, isEmpty);
      expect(stagedFolders(), isEmpty);
      expect(controller.failure, isNull);
      expect(controller.status, ShareFlowStatus.idle);
    });

    test('disposing the controller mid-share is safe', () async {
      final gate = Completer<List<int>>();
      net.bodies[_linkA] = jpegBytes();
      net.held[_linkA] = gate;
      final controller = controllerFor(offerWith(
          extra: <OfferMediaRef>[mediaRef('photo-1', signedUrl: _linkA)]));

      final pending = controller.share();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      controller.dispose();
      gate.complete(<int>[9]);

      expect(await pending, ShareFlowResult.cancelled);
      expect(sink.requests, isEmpty);
      expect(stagedFolders(), isEmpty);
    });

    test('a share asked for after disposal does nothing', () async {
      final controller = controllerFor(PropertyShareSource.request(request()));
      controller.dispose();
      expect(await controller.share(), ShareFlowResult.cancelled);
      expect(sink.requests, isEmpty);
    });
  });

  group('refreshing a private link', () {
    test('an expired link is replaced through the record\'s own path',
        () async {
      net.statuses[_linkA] = 403;
      net.bodies[_linkB] = jpegBytes();
      final asked = <String>[];
      final controller = controllerFor(
        offerWith(
            extra: <OfferMediaRef>[mediaRef('photo-1', signedUrl: _linkA)]),
        refreshLink: (id) async {
          asked.add(id);
          return _linkB;
        },
      );
      expect(await controller.share(), ShareFlowResult.shared);
      expect(asked, <String>['photo-1']);
      expect(net.requested, <String>[_linkA, _linkB]);
    });
  });
}

/// A stand-in for the platform's own exception.
class PlatformException_ implements Exception {
  PlatformException_(this.message);

  final String message;

  @override
  String toString() => 'PlatformException($message)';
}
