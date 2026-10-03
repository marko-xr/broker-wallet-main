import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/share/share_flow_controller.dart';
import 'package:broker_wallet/src/services/share/share_media_fetcher.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
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
  }) =>
      ShareFlowController(
        source: source,
        labels: labelsIn(language),
        engine: engine,
        refreshLink: refreshLink,
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
      expect(sink.requests.single.files.map((f) => f.name).toList(), <String>[
        'Offer-Dubai-Marina-01.jpg',
        'Offer-Dubai-Marina-02.jpg',
        'Offer-Dubai-Marina-03.jpg',
      ]);
    });

    test('with the location left out, no place is in a file name', () async {
      final controller = controllerFor(offerWith(localPhotos: 1));
      controller.toggleSection(ShareSection.locationDetails);
      await controller.share();
      expect(sink.requests.single.files.single.name, 'Offer-01.jpg');
    });

    test('only the chosen media is shared', () async {
      final controller = controllerFor(offerWith(localPhotos: 3));
      controller.toggleMedia('photo-1');
      controller.toggleMedia('photo-3');
      await controller.share();
      final sent = sink.requests.single;
      expect(sent.files, hasLength(1));
      // Numbered among what is shared, not among what the record holds.
      expect(sent.files.single.name, endsWith('-01.jpg'));
      expect(File(sent.files.single.path).readAsBytesSync(), jpegBytes(20));
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

    test('a photo and a video that must be fetched come as their real files',
        () async {
      net.bodies[_linkA] = jpegBytes();
      net.bodies[_linkV] = mp4Bytes();
      final source = offerWith(extra: <OfferMediaRef>[
        mediaRef('photo-1', signedUrl: _linkA),
        mediaRef('video-1', video: true, signedUrl: _linkV),
      ]);
      final controller = controllerFor(source);
      controller.selectAllMedia();
      controller.toggleSection(ShareSection.notes);

      final result = await controller.share();

      expect(result, ShareFlowResult.shared);
      final files = sink.requests.single.files;
      expect(files.map((f) => f.name).toList(),
          <String>['Offer-Dubai-Marina-01.jpg', 'Offer-Dubai-Marina-02.mp4']);
      expect(files.map((f) => f.mimeType).toList(),
          <String>['image/jpeg', 'video/mp4']);
      expect(File(files[1].path).readAsBytesSync(), mp4Bytes(),
          reason: 'the original video, not a poster or a link');
      // The links stayed out of everything that was shared.
      final text = sink.requests.single.text ?? '';
      expect(text.contains('store.example'), isFalse);
      expect(text.contains('sig='), isFalse);
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
      final source = offerWith(
          extra: <OfferMediaRef>[mediaRef('photo-1', signedUrl: _linkA)]);
      final controller = controllerFor(source);
      final seen = <ShareFlowStatus>[];
      controller.addListener(() => seen.add(controller.status));

      final pending = controller.share();
      expect(controller.status, ShareFlowStatus.preparing);
      expect(controller.isBusy, isTrue);
      expect(controller.canShare, isFalse);

      await until(() => controller.status == ShareFlowStatus.sharing);

      gate.complete(ShareOutcome.shared);
      await pending;
      expect(controller.status, ShareFlowStatus.idle);
      expect(seen, <ShareFlowStatus>[
        ShareFlowStatus.preparing,
        ShareFlowStatus.sharing,
        ShareFlowStatus.idle,
      ]);
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
