// The Share Options dialog: what it offers, what it hides, how it shows a file
// being prepared, what it does with an empty choice, a double tap, a failure and
// a closed share sheet. Local widget tests with the real ARB text and Flutter's
// test font; they prove behaviour, not how a phone renders it.
//
// Preparing a share does real file work, which never advances inside a widget
// test's fake clock, so every step that touches a file waits on the real one
// through [WidgetTester.runAsync].

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/share/share_flow_controller.dart';
import 'package:broker_wallet/src/services/share/share_media_fetcher.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_source.dart';
import 'package:broker_wallet/src/services/share/share_sources.dart';
import 'package:broker_wallet/src/views/Widgets/share_options_dialog.dart';

import 'share_fixtures.dart';

const String _linkA = 'https://store.example/a?sig=1';
const String _linkB = 'https://store.example/b?sig=2';

const ValueKey<String> _submit = ValueKey('share-submit');
const ValueKey<String> _cancel = ValueKey('share-cancel');
const ValueKey<String> _selectAll = ValueKey('share-select-all');

ValueKey<String> _option(ShareSection section) =>
    ValueKey('share-option-${section.name}');

ValueKey<String> _chip(String key) => ValueKey('share-media-$key');

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late TempArea area;
  late FakeNet net;
  late FakeShareSink sink;
  late ShareEngine engine;

  setUpAll(() async {
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        final file = File(key);
        if (!file.existsSync()) return null;
        final bytes = Uint8List.fromList(file.readAsBytesSync());
        return ByteData.view(bytes.buffer);
      },
    );
    await AppLocalizations.preloadAllLanguages();
  });

  setUp(() {
    area = TempArea();
    net = FakeNet();
    sink = FakeShareSink();
    engine = newEngine(area, sink, client: net.client());
  });
  tearDown(() => area.dispose());

  Future<void> openDialog(
    WidgetTester tester,
    ShareSource source, {
    Locale locale = const Locale('en'),
    ThemeData? theme,
    double textScale = 1,
    double width = 360,
    double height = 800,
    LinkRefresher? refreshLink,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: Directionality(
            textDirection: locale.languageCode == 'ar'
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: child!,
          ),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                key: const ValueKey('open'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ShareOptionsDialog(
                    source: source,
                    engine: engine,
                    refreshLink: refreshLink,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    // The localization delegates load asynchronously: until they have, the app
    // draws nothing, so the button below does not exist yet.
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
  }

  /// Lets the real clock run, so file work and downloads can finish. A share
  /// started in a widget test runs in the test's fake zone, so each step needs
  /// the real clock (for the file work) and a pump (to run what the fake zone
  /// queued) before the next step can start: hence the loop.
  Future<void> realTime(WidgetTester tester, {int milliseconds = 150}) async {
    for (var i = 0; i < milliseconds ~/ 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  Future<void> realUntil(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 600 && !ready(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    expect(ready(), isTrue, reason: 'timed out waiting');
    await realTime(tester, milliseconds: 50);
  }

  /// Taps [finder] after scrolling it into view (the rows scroll inside the
  /// dialog).
  Future<void> tapAt(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
  }

  bool? checkboxOf(WidgetTester tester, Key key) => tester
      .widget<Checkbox>(find.descendant(
        of: find.byKey(key),
        matching: find.byType(Checkbox),
      ))
      .value;

  VoidCallback? submitAction(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(_submit)).onPressed;

  PropertyShareSource fullRequest() => PropertyShareSource.request(request(
        type: 'rent',
        propertyType: 'residential',
        specific: 'Villa',
        rooms: 3,
        bathrooms: 2,
        min: '1000000',
        max: '1500000',
        areas: <String>['jbr', 'dubaiMarina'],
        phone: '+971501234567',
        notes: 'Corner unit',
      ));

  PropertyShareSource offerWithMedia(List<OfferMediaRef> refs) =>
      PropertyShareSource.offer(
        offer(
          specific: 'Villa',
          areas: <String>['dubaiMarina'],
          phone: '+971501234567',
        ),
        media: mediaItems(refs),
      );

  group('what it offers', () {
    testWidgets('a row for every part the record has, and none for the rest',
        (tester) async {
      await openDialog(tester, fullRequest());

      expect(find.text('Share Request'), findsOneWidget);
      expect(find.text('Select what information to share'), findsOneWidget);
      for (final section in <ShareSection>[
        ShareSection.basicInfo,
        ShareSection.pricing,
        ShareSection.propertyDetails,
        ShareSection.locationDetails,
        ShareSection.contact,
        ShareSection.notes,
      ]) {
        expect(find.byKey(_option(section)), findsOneWidget,
            reason: section.name);
      }
      // A Request has no map, no photos and no document.
      for (final section in <ShareSection>[
        ShareSection.map,
        ShareSection.media,
        ShareSection.document,
      ]) {
        expect(find.byKey(_option(section)), findsNothing,
            reason: section.name);
      }
      expect(find.byKey(_selectAll), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a row says what is in it', (tester) async {
      await openDialog(tester, fullRequest());
      expect(find.text('AED 1,000,000 - 1,500,000'), findsOneWidget);
      expect(find.text('+971 50 123 4567'), findsOneWidget);
      expect(find.textContaining('Dubai'), findsWidgets);
    });

    testWidgets('an option with no data behind it is not shown',
        (tester) async {
      await openDialog(
          tester, PropertyShareSource.request(request(city: '', phone: '')));
      expect(find.byKey(_option(ShareSection.basicInfo)), findsOneWidget);
      expect(find.byKey(_option(ShareSection.contact)), findsNothing);
      expect(find.byKey(_option(ShareSection.pricing)), findsNothing);
      expect(find.byKey(_option(ShareSection.notes)), findsNothing);
      expect(find.byKey(_option(ShareSection.locationDetails)), findsNothing);
    });

    testWidgets('media and the map show only when the record has them',
        (tester) async {
      final withBoth = PropertyShareSource.offer(
        offer(latitude: 25.2, longitude: 55.27),
        media:
            mediaItems(<OfferMediaRef>[mediaRef('photo-1', signedUrl: _linkA)]),
      );
      await openDialog(tester, withBoth);
      expect(find.byKey(_option(ShareSection.media)), findsOneWidget);
      expect(find.byKey(_option(ShareSection.map)), findsOneWidget);
    });

    testWidgets('an Offer with no media has no media row', (tester) async {
      await openDialog(tester, offerWithMedia(const <OfferMediaRef>[]));
      expect(find.byKey(_option(ShareSection.media)), findsNothing);
    });

    testWidgets('a quotation offers its PDF by name', (tester) async {
      final source = QuotationShareSource(
        quotation(officeName: 'Prime', total: 1000),
        fetchPdf: () async => throw StateError('not used'),
      );
      await openDialog(tester, source);
      expect(find.text('Share Quotation'), findsOneWidget);
      expect(find.text('Quotation PDF'), findsOneWidget);
      expect(checkboxOf(tester, _option(ShareSection.document)), isTrue);
      // The money lines start unchosen.
      expect(checkboxOf(tester, _option(ShareSection.pricing)), isFalse);
    });

    testWidgets('a quotation with no PDF has no PDF row', (tester) async {
      final source = QuotationShareSource(
        quotation(pdfMediaId: null),
        fetchPdf: () async => throw StateError('not used'),
      );
      await openDialog(tester, source);
      expect(find.byKey(_option(ShareSection.document)), findsNothing);
      expect(find.text('Quotation PDF'), findsNothing);
    });

    testWidgets('an Owner starts with the name and the place, not the number',
        (tester) async {
      final source = OwnerShareSource(owner(
        name: 'Khalid',
        phone: '+971501234567',
        location: 'Dubai Marina, Dubai',
        notes: 'private',
      ));
      await openDialog(tester, source);
      expect(find.text('Share Owner'), findsOneWidget);
      expect(checkboxOf(tester, _option(ShareSection.basicInfo)), isTrue);
      expect(checkboxOf(tester, _option(ShareSection.locationDetails)), isTrue);
      expect(checkboxOf(tester, _option(ShareSection.contact)), isFalse);
      expect(checkboxOf(tester, _option(ShareSection.notes)), isFalse);
    });
  });

  group('choosing', () {
    testWidgets('a tap chooses and un-chooses a row', (tester) async {
      await openDialog(tester, fullRequest());
      expect(checkboxOf(tester, _option(ShareSection.notes)), isTrue);

      await tapAt(tester, find.byKey(_option(ShareSection.notes)));
      await tester.pump();
      expect(checkboxOf(tester, _option(ShareSection.notes)), isFalse);

      await tapAt(tester, find.byKey(_option(ShareSection.notes)));
      await tester.pump();
      expect(checkboxOf(tester, _option(ShareSection.notes)), isTrue);
    });

    testWidgets('Select All shows a dash while only some rows are chosen',
        (tester) async {
      await openDialog(tester, fullRequest());
      expect(checkboxOf(tester, _selectAll), isTrue);

      await tapAt(tester, find.byKey(_option(ShareSection.notes)));
      await tester.pump();
      expect(checkboxOf(tester, _selectAll), isNull);

      await tapAt(tester, find.byKey(_selectAll));
      await tester.pump();
      expect(checkboxOf(tester, _selectAll), isTrue);
      expect(checkboxOf(tester, _option(ShareSection.notes)), isTrue);
    });
  });

  group('an empty choice', () {
    testWidgets('turns Share off and says to choose something', (tester) async {
      await openDialog(tester, fullRequest());
      expect(submitAction(tester), isNotNull);
      expect(find.byKey(const ValueKey('share-empty-hint')), findsNothing);

      await tapAt(tester, find.byKey(_selectAll)); // all chosen -> none chosen
      await tester.pump();

      expect(checkboxOf(tester, _selectAll), isFalse);
      expect(submitAction(tester), isNull);
      expect(find.text('Select at least one item to share.'), findsOneWidget);

      await tester.tap(find.byKey(_submit), warnIfMissed: false);
      await tester.pump();
      expect(sink.requests, isEmpty, reason: 'no empty share sheet');
    });

    testWidgets('the hint is Arabic in Arabic', (tester) async {
      await openDialog(tester, fullRequest(), locale: const Locale('ar'));
      await tapAt(tester, find.byKey(_selectAll));
      await tester.pump();
      expect(
          find.text(arbLookup('ar', 'shareSelectAtLeastOne')!), findsOneWidget);
    });
  });

  group('sharing text', () {
    testWidgets('opens the share sheet once and closes the dialog',
        (tester) async {
      await openDialog(tester, fullRequest());
      await tapAt(tester, find.byKey(_submit));
      await tester.pumpAndSettle();

      expect(sink.requests, hasLength(1));
      expect(sink.requests.single.text, contains('Phone: +971 50 123 4567'));
      expect(sink.requests.single.subject, 'Request Details');
      expect(find.byType(ShareOptionsDialog), findsNothing);
    });

    testWidgets('tells the sheet where the Share button is, for an iPad',
        (tester) async {
      await openDialog(tester, fullRequest());
      final button = tester.getRect(find.byKey(_submit));
      await tapAt(tester, find.byKey(_submit));
      await tester.pumpAndSettle();

      final origin = sink.requests.single.origin!;
      expect(origin.isEmpty, isFalse);
      expect(origin.left, closeTo(button.left, 0.5));
      expect(origin.top, closeTo(button.top, 0.5));
      expect(origin.width, closeTo(button.width, 0.5));
      expect(origin.height, closeTo(button.height, 0.5));
    });

    testWidgets('only the rows still chosen are in the message',
        (tester) async {
      await openDialog(tester, fullRequest());
      await tapAt(tester, find.byKey(_option(ShareSection.contact)));
      await tapAt(tester, find.byKey(_option(ShareSection.notes)));
      await tester.pump();
      await tapAt(tester, find.byKey(_submit));
      await tester.pumpAndSettle();

      final text = sink.requests.single.text!;
      expect(text.contains('Phone'), isFalse);
      expect(text.contains('Corner unit'), isFalse);
      expect(text, contains('Price: AED 1,000,000 - 1,500,000'));
    });

    testWidgets('closing the share sheet is not an error and keeps the dialog',
        (tester) async {
      sink.outcome = ShareOutcome.dismissed;
      await openDialog(tester, fullRequest());
      await tapAt(tester, find.byKey(_submit));
      await tester.pumpAndSettle();

      expect(find.byType(ShareOptionsDialog), findsOneWidget);
      expect(find.byKey(const ValueKey('share-error')), findsNothing);
      expect(submitAction(tester), isNotNull, reason: 'ready to share again');
      expect(checkboxOf(tester, _option(ShareSection.notes)), isTrue,
          reason: 'the choices are kept');
    });

    testWidgets('a double tap opens one share sheet', (tester) async {
      final gate = Completer<ShareOutcome>();
      sink.hold = gate;
      await openDialog(tester, fullRequest());

      await tapAt(tester, find.byKey(_submit));
      await tester.tap(find.byKey(_submit), warnIfMissed: false);
      await tester.tap(find.byKey(_submit), warnIfMissed: false);
      await tester.pump();

      expect(sink.requests, hasLength(1));
      expect(submitAction(tester), isNull);
      expect(find.text('Sharing...'), findsOneWidget);

      gate.complete(ShareOutcome.shared);
      await tester.pumpAndSettle();
      expect(find.byType(ShareOptionsDialog), findsNothing);
      expect(sink.requests, hasLength(1));
    });

    testWidgets('a share sheet that cannot open says so and can be retried',
        (tester) async {
      sink.error = StateError('platform said no');
      await openDialog(tester, fullRequest());
      await tapAt(tester, find.byKey(_submit));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('share-error')), findsOneWidget);
      expect(find.text(arbLookup('en', 'shareErrorGeneric')!), findsOneWidget);
      expect(find.textContaining('platform said no'), findsNothing);

      sink.error = null;
      await tapAt(tester, find.byKey(const ValueKey('share-retry')));
      await tester.pumpAndSettle();
      expect(sink.requests, hasLength(2));
      expect(find.byType(ShareOptionsDialog), findsNothing);
    });
  });

  group('photos and videos', () {
    PropertyShareSource twoPhotosAndAVideo() {
      return offerWithMedia(<OfferMediaRef>[
        mediaRef('photo-1',
            localFilePath: area.writeCacheFile('p1.jpg', jpegBytes(10)).path),
        mediaRef('photo-2',
            localFilePath: area.writeCacheFile('p2.jpg', jpegBytes(20)).path),
        mediaRef('video-1', video: true, signedUrl: _linkB),
      ]);
    }

    testWidgets('each is a chip, photos chosen and the video not',
        (tester) async {
      await openDialog(tester, twoPhotosAndAVideo());

      expect(find.text('Photo 1'), findsOneWidget);
      expect(find.text('Photo 2'), findsOneWidget);
      expect(find.text('Video 1'), findsOneWidget);
      expect(find.text('2 of 3 selected'), findsOneWidget);
      expect(checkboxOf(tester, _option(ShareSection.media)), isTrue);
      expect(checkboxOf(tester, _selectAll), isNull,
          reason: 'the video is not chosen yet');
    });

    testWidgets('a tap on a chip chooses or drops that one', (tester) async {
      await openDialog(tester, twoPhotosAndAVideo());

      await tapAt(tester, find.byKey(_chip('video-1')));
      await tester.pump();
      expect(find.text('3 of 3 selected'), findsOneWidget);
      expect(checkboxOf(tester, _selectAll), isTrue);

      await tapAt(tester, find.byKey(_chip('photo-1')));
      await tester.pump();
      expect(find.text('2 of 3 selected'), findsOneWidget);

      await tapAt(tester, find.byKey(_chip('photo-2')));
      await tapAt(tester, find.byKey(_chip('video-1')));
      await tester.pump();
      expect(find.text('0 of 3 selected'), findsOneWidget);
      expect(checkboxOf(tester, _option(ShareSection.media)), isFalse);
    });

    testWidgets('the row\'s box drops them all, then chooses the photos',
        (tester) async {
      await openDialog(tester, twoPhotosAndAVideo());
      await tapAt(tester, find.byKey(_option(ShareSection.media)));
      await tester.pump();
      expect(find.text('0 of 3 selected'), findsOneWidget);

      await tapAt(tester, find.byKey(_option(ShareSection.media)));
      await tester.pump();
      expect(find.text('2 of 3 selected'), findsOneWidget);
    });

    testWidgets('Select All under the chips chooses every one', (tester) async {
      await openDialog(tester, twoPhotosAndAVideo());
      await tapAt(tester, find.byKey(const ValueKey('share-media-all')));
      await tester.pump();
      expect(find.text('3 of 3 selected'), findsOneWidget);
      await tapAt(tester, find.byKey(const ValueKey('share-media-all')));
      await tester.pump();
      expect(find.text('0 of 3 selected'), findsOneWidget);
    });

    testWidgets('sharing attaches the chosen files and shows the wait',
        (tester) async {
      final gate = Completer<List<int>>();
      net.bodies[_linkB] = mp4Bytes();
      net.held[_linkB] = gate;
      await openDialog(tester, twoPhotosAndAVideo());
      await tapAt(tester, find.byKey(_chip('video-1')));
      await tester.pump();

      await tapAt(tester, find.byKey(_submit));
      await tester.pump();
      // The video has to be fetched: the dialog says so and cannot be pressed.
      expect(find.text('Preparing files...'), findsOneWidget);
      expect(submitAction(tester), isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byKey(_submit), warnIfMissed: false);

      await realUntil(tester, () => net.requested.isNotEmpty);
      gate.complete(<int>[1, 2, 3]);
      await realUntil(tester, () => sink.requests.isNotEmpty);
      await tester.pumpAndSettle();

      expect(sink.requests, hasLength(1), reason: 'one share, not two');
      expect(net.requested, <String>[_linkB], reason: 'one download');
      final files = sink.requests.single.files;
      expect(files.map((f) => f.name).toList(), <String>[
        'Offer-Dubai-Marina-01.jpg',
        'Offer-Dubai-Marina-02.jpg',
        'Offer-Dubai-Marina-03.mp4',
      ]);
      expect(find.byType(ShareOptionsDialog), findsNothing);
    });

    testWidgets('Cancel while files are being prepared opens nothing',
        (tester) async {
      final gate = Completer<List<int>>();
      net.bodies[_linkB] = mp4Bytes();
      net.held[_linkB] = gate;
      await openDialog(tester, twoPhotosAndAVideo());
      await tapAt(tester, find.byKey(_chip('video-1')));
      await tester.pump();
      await tapAt(tester, find.byKey(_submit));
      await tester.pump();
      await realUntil(tester, () => net.requested.isNotEmpty);

      await tapAt(tester, find.byKey(_cancel));
      await tester.pumpAndSettle();
      expect(find.byType(ShareOptionsDialog), findsNothing);

      gate.complete(<int>[1]);
      await realTime(tester, milliseconds: 300);
      expect(sink.requests, isEmpty);
      expect(area.staging.existsSync() ? area.staging.listSync() : <Object>[],
          isEmpty,
          reason: 'nothing is kept for a share that was called off');
    });

    testWidgets('offline: says so, keeps the choices, and Retry works',
        (tester) async {
      net.failures[_linkB] = const SocketException('offline');
      await openDialog(tester, twoPhotosAndAVideo());
      await tapAt(tester, find.byKey(_chip('video-1')));
      await tester.pump();
      await tapAt(tester, find.byKey(_submit));
      await tester.pump();
      await realUntil(tester, () => net.requested.isNotEmpty);
      await realTime(tester);
      await tester.pump();

      expect(find.byKey(const ValueKey('share-error')), findsOneWidget);
      expect(find.text(arbLookup('en', 'shareErrorNetwork')!), findsOneWidget);
      expect(sink.requests, isEmpty, reason: 'nothing goes out incomplete');
      expect(find.text('3 of 3 selected'), findsOneWidget);
      expect(submitAction(tester), isNotNull);

      net.failures.clear();
      net.bodies[_linkB] = mp4Bytes();
      await tapAt(tester, find.byKey(const ValueKey('share-retry')));
      await tester.pump();
      await realUntil(tester, () => sink.requests.isNotEmpty);
      await tester.pumpAndSettle();
      expect(sink.requests.single.files, hasLength(3));
    });

    testWidgets(
        'a file that is gone is marked, left out, and never looks chosen',
        (tester) async {
      net.statuses[_linkB] = 404;
      await openDialog(tester, twoPhotosAndAVideo());
      await tapAt(tester, find.byKey(_chip('video-1')));
      await tester.pump();
      await tapAt(tester, find.byKey(_submit));
      await tester.pump();
      await realUntil(tester, () => net.requested.isNotEmpty);
      await realTime(tester);
      await tester.pump();

      expect(
          find.text(arbLookup('en', 'shareErrorUnavailable')!), findsOneWidget);
      expect(find.byKey(const ValueKey('share-retry')), findsNothing,
          reason: 'retrying cannot bring the file back');
      expect(find.text('Video 1 · Unavailable'), findsOneWidget);
      expect(find.text('2 of 3 selected'), findsOneWidget);
      expect(sink.requests, isEmpty);

      // Sharing again goes on without it, with the person\'s say-so.
      await tapAt(tester, find.byKey(_submit));
      await tester.pump();
      await realUntil(tester, () => sink.requests.isNotEmpty);
      await tester.pumpAndSettle();
      expect(sink.requests.single.files, hasLength(2));
    });
  });

  group('a quotation PDF', () {
    testWidgets('is shared as a file with a professional name', (tester) async {
      final cached = area.writeCacheFile(
          'quotation_quotation-id-1b2c_pdf-media-id-7f3a.pdf', pdfBytes());
      final source = QuotationShareSource(
        quotation(officeName: 'Prime'),
        fetchPdf: () async => cached,
      );
      await openDialog(tester, source);
      await tapAt(tester, find.byKey(_submit));
      await tester.pump();
      await realUntil(tester, () => sink.requests.isNotEmpty);
      await tester.pumpAndSettle();

      final file = sink.requests.single.files.single;
      expect(file.name, 'Broker-Wallet-Quotation-Apartment-306.pdf');
      expect(file.mimeType, 'application/pdf');
    });

    testWidgets('one that cannot be fetched is marked unavailable',
        (tester) async {
      final source = QuotationShareSource(
        quotation(),
        fetchPdf: () async =>
            throw const ShareFailure(ShareFailureKind.unavailable),
      );
      await openDialog(tester, source);
      await tapAt(tester, find.byKey(_submit));
      await tester.pump();
      await realTime(tester);
      await tester.pump();

      expect(
          find.text(arbLookup('en', 'shareErrorUnavailable')!), findsOneWidget);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(checkboxOf(tester, _option(ShareSection.document)), isFalse);
      expect(sink.requests, isEmpty);
    });
  });

  group('English, Arabic, light, dark', () {
    final looks = <String, List<Object>>{
      'English light': <Object>[const Locale('en'), ThemeData.light()],
      'English dark': <Object>[const Locale('en'), ThemeData.dark()],
      'Arabic light': <Object>[const Locale('ar'), ThemeData.light()],
      'Arabic dark': <Object>[const Locale('ar'), ThemeData.dark()],
    };

    for (final entry in looks.entries) {
      testWidgets(
          '${entry.key}: lays out without overflow, even at a large font',
          (tester) async {
        final locale = entry.value[0] as Locale;
        final source = offerWithMedia(<OfferMediaRef>[
          mediaRef('photo-1', signedUrl: _linkA),
          mediaRef('video-1', video: true, signedUrl: _linkB),
        ]);
        await openDialog(tester, source,
            locale: locale, theme: entry.value[1] as ThemeData, textScale: 1.6);
        expect(tester.takeException(), isNull);
        expect(find.byKey(_submit), findsOneWidget);
        expect(find.byKey(_option(ShareSection.media)), findsOneWidget);

        // The heading, the rows and the buttons stack without overlap.
        final top =
            tester.getRect(find.byKey(const ValueKey('share-header-scroll')));
        final middle =
            tester.getRect(find.byKey(const ValueKey('share-body-scroll')));
        final bottom = tester.getRect(find.byKey(_cancel));
        expect(top.bottom, lessThanOrEqualTo(middle.top + 0.01));
        expect(middle.bottom, lessThanOrEqualTo(bottom.top + 0.01));

        // Both buttons are inside the screen and can be pressed as they are,
        // without scrolling anything first.
        for (final key in <Key>[_submit, _cancel]) {
          final rect = tester.getRect(find.byKey(key));
          expect(rect.top, greaterThanOrEqualTo(0), reason: '$key');
          expect(rect.bottom, lessThanOrEqualTo(800), reason: '$key');
        }
        await tester.tap(find.byKey(_cancel));
        await tester.pumpAndSettle();
        expect(find.byType(ShareOptionsDialog), findsNothing);
      });
    }

    testWidgets('Arabic: every visible word is Arabic, rows start at the right',
        (tester) async {
      await openDialog(tester, fullRequest(), locale: const Locale('ar'));
      expect(find.text(arbLookup('ar', 'shareRequest')!), findsOneWidget);
      expect(find.text(arbLookup('ar', 'selectWhatToShare')!), findsOneWidget);
      expect(find.text(arbLookup('ar', 'share')!), findsOneWidget);
      expect(find.text(arbLookup('ar', 'cancel')!), findsOneWidget);
      expect(find.text(arbLookup('ar', 'selectAll')!), findsOneWidget);
      expect(find.text(arbLookup('ar', 'pricing')!), findsOneWidget);
      expect(find.text(arbLookup('en', 'pricing')!), findsNothing);

      final title = tester.getTopRight(find.text(arbLookup('ar', 'pricing')!));
      final dialog = tester.getRect(find.byType(Dialog));
      expect(title.dx, greaterThan(dialog.center.dx),
          reason: 'right-to-left: the label sits on the right');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the icon-only close button has a label', (tester) async {
      await openDialog(tester, fullRequest());
      expect(find.byTooltip('Close'), findsOneWidget);
    });
  });

  group('a short screen, a large font, and the order of the buttons', () {
    // Short for this dialog at a 1.6 font: its rows do not fit, so they scroll.
    const shortScreen = 600.0;

    // The heading and the buttons stay put; the rows scroll between them.
    Finder body() => find.byKey(const ValueKey('share-body-scroll'));

    Finder heading() => find.byKey(const ValueKey('share-header-scroll'));

    Finder insideBody(Finder finder) => find.ancestor(
          of: finder,
          matching: body(),
        );

    testWidgets('the rows scroll, the heading and the buttons do not',
        (tester) async {
      await openDialog(tester, fullRequest(),
          textScale: 1.6, height: shortScreen);

      expect(tester.takeException(), isNull);
      expect(body(), findsOneWidget);
      expect(
          insideBody(find.byKey(_option(ShareSection.notes))), findsOneWidget);
      expect(insideBody(find.byKey(_selectAll)), findsOneWidget);
      expect(insideBody(find.byKey(_submit)), findsNothing);
      expect(insideBody(find.byKey(_cancel)), findsNothing);
      expect(insideBody(find.text('Share Request')), findsNothing);
      expect(insideBody(find.byTooltip('Close')), findsNothing);

      // On a screen this short the rows really do not fit.
      final scrollable = tester.state<ScrollableState>(find.descendant(
        of: body(),
        matching: find.byType(Scrollable),
      ));
      expect(scrollable.position.maxScrollExtent, greaterThan(0));

      // The dialog stays inside the screen.
      final dialog = tester.getRect(find.byType(Dialog));
      expect(dialog.top, greaterThanOrEqualTo(0));
      expect(dialog.bottom, lessThanOrEqualTo(shortScreen));

      // One bounded column: the heading, the rows and the buttons are stacked
      // in that order and never overlap, and the whole stays inside the dialog.
      final top = tester.getRect(heading());
      final middle = tester.getRect(body());
      final buttons = tester.getRect(find.byKey(_cancel));
      expect(top.bottom, lessThanOrEqualTo(middle.top + 0.01));
      expect(middle.bottom, lessThanOrEqualTo(buttons.top + 0.01));
      expect(top.top, greaterThanOrEqualTo(dialog.top));
      expect(buttons.bottom, lessThanOrEqualTo(dialog.bottom));

      // The rows are always given a real share of the height, however much the
      // heading wants: here at least 30% of what the dialog has.
      final available =
          shortScreen - 2 * 24 - 2 * 24; // screen - insets - padding
      expect(middle.height, greaterThanOrEqualTo(0.3 * available - 1));

      // The heading is reachable even when it has to scroll inside its space.
      expect(tester.getRect(find.text('Share Request')).top,
          greaterThanOrEqualTo(top.top - 0.01));
      expect(find.byTooltip('Close'), findsOneWidget);
    });

    testWidgets('both buttons stay on a short screen and work as they are',
        (tester) async {
      await openDialog(tester, fullRequest(),
          textScale: 1.6, height: shortScreen);

      for (final key in <Key>[_submit, _cancel]) {
        final rect = tester.getRect(find.byKey(key));
        expect(rect.top, greaterThanOrEqualTo(0), reason: '$key');
        expect(rect.bottom, lessThanOrEqualTo(shortScreen), reason: '$key');
      }

      // Share is pressed without scrolling anything first.
      await tester.tap(find.byKey(_submit));
      await tester.pumpAndSettle();
      expect(sink.requests, hasLength(1));
      expect(find.byType(ShareOptionsDialog), findsNothing);
    });

    testWidgets('a row below the fold can be scrolled to and chosen',
        (tester) async {
      await openDialog(tester, fullRequest(),
          textScale: 1.6, height: shortScreen);
      expect(checkboxOf(tester, _option(ShareSection.notes)), isTrue);

      await tester.drag(body(), const Offset(0, -2000));
      await tester.pump();
      await tester.tap(find.byKey(_option(ShareSection.notes)));
      await tester.pump();
      expect(checkboxOf(tester, _option(ShareSection.notes)), isFalse);
    });

    testWidgets('a failure on a short screen is brought into view with Retry',
        (tester) async {
      sink.error = StateError('platform said no');
      await openDialog(tester, fullRequest(),
          textScale: 1.6, height: shortScreen);
      // A choice made before the failure must survive it.
      await tester.drag(body(), const Offset(0, -2000));
      await tester.pump();
      await tester.tap(find.byKey(_option(ShareSection.notes)));
      await tester.pump();

      await tester.tap(find.byKey(_submit));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('share-error')), findsOneWidget);
      expect(find.text(arbLookup('en', 'shareErrorGeneric')!), findsOneWidget);
      expect(checkboxOf(tester, _option(ShareSection.notes)), isFalse,
          reason: 'the choices are kept');

      // Retry is inside the scrolling region's visible part, not below it.
      final viewport = tester.getRect(body());
      final retry = tester.getRect(find.byKey(const ValueKey('share-retry')));
      expect(retry.top, greaterThanOrEqualTo(viewport.top - 0.5));
      expect(retry.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));

      // And it works as it is, with nothing scrolled first.
      sink.error = null;
      await tester.tap(find.byKey(const ValueKey('share-retry')));
      await tester.pumpAndSettle();
      expect(sink.requests, hasLength(2));
      expect(find.byType(ShareOptionsDialog), findsNothing);
    });

    testWidgets(
        'an unavailable quotation PDF on a short screen: Share still works',
        (tester) async {
      final source = QuotationShareSource(
        quotation(officeName: 'Prime Offices', total: 1000, fee: 100),
        fetchPdf: () async =>
            throw const ShareFailure(ShareFailureKind.unavailable),
      );
      await openDialog(tester, source, textScale: 1.6, height: shortScreen);

      await tester.tap(find.byKey(_submit));
      await tester.pump();
      await realTime(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
          find.text(arbLookup('en', 'shareErrorUnavailable')!), findsOneWidget);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(checkboxOf(tester, _option(ShareSection.document)), isFalse);
      expect(find.byKey(const ValueKey('share-retry')), findsNothing);
      expect(sink.requests, isEmpty);
      for (final key in <Key>[_submit, _cancel]) {
        final rect = tester.getRect(find.byKey(key));
        expect(rect.bottom, lessThanOrEqualTo(shortScreen), reason: '$key');
      }

      // Sharing again goes on without the PDF: the summary alone.
      await tester.tap(find.byKey(_submit));
      await tester.pumpAndSettle();
      expect(sink.requests, hasLength(1));
      expect(sink.requests.single.files, isEmpty);
      expect(find.byType(ShareOptionsDialog), findsNothing);
    });

    testWidgets('the buttons keep their order: Cancel first, Share last',
        (tester) async {
      await openDialog(tester, fullRequest());
      final cancel = tester.getCenter(find.byKey(_cancel));
      final share = tester.getCenter(find.byKey(_submit));
      expect(cancel.dx, lessThan(share.dx), reason: 'left to right');
      expect(cancel.dy, closeTo(share.dy, 0.5));
    });

    testWidgets('and mirror in Arabic: Cancel on the right, Share on the left',
        (tester) async {
      await openDialog(tester, fullRequest(), locale: const Locale('ar'));
      final cancel = tester.getCenter(find.byKey(_cancel));
      final share = tester.getCenter(find.byKey(_submit));
      expect(cancel.dx, greaterThan(share.dx), reason: 'right to left');
      expect(cancel.dy, closeTo(share.dy, 0.5));
    });

    testWidgets('the buttons are the same size busy and idle', (tester) async {
      final gate = Completer<ShareOutcome>();
      sink.hold = gate;
      await openDialog(tester, fullRequest(), textScale: 1.6);
      final idle = tester.getSize(find.byKey(_submit));

      await tester.tap(find.byKey(_submit));
      await tester.pump();
      expect(find.text('Sharing...'), findsOneWidget);
      expect(tester.getSize(find.byKey(_submit)), idle);
      expect(tester.takeException(), isNull);

      gate.complete(ShareOutcome.dismissed);
      await tester.pumpAndSettle();
    });
  });

  group('opening it', () {
    testWidgets('a double tap on a Share icon opens one dialog',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const ValueKey('icon'),
                  onPressed: () {
                    ShareOptionsDialog.show(context,
                        source: PropertyShareSource.request(request()));
                    ShareOptionsDialog.show(context,
                        source: PropertyShareSource.request(request()));
                  },
                  child: const Text('share'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('icon')));
      await tester.pumpAndSettle();
      expect(find.byType(ShareOptionsDialog), findsOneWidget);

      await tapAt(tester, find.byKey(_cancel));
      await tester.pumpAndSettle();
      expect(find.byType(ShareOptionsDialog), findsNothing);
    });
  });
}
