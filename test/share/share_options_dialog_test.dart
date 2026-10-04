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
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/share/share_flow_controller.dart';
import 'package:broker_wallet/src/services/share/share_media_fetcher.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_source.dart';
import 'package:broker_wallet/src/services/share/share_sources.dart';
import 'package:broker_wallet/src/views/Widgets/share_media_picker.dart';
import 'package:broker_wallet/src/views/Widgets/share_options_dialog.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/full_screen_media_viewer.dart';

import 'share_fixtures.dart';

const String _linkA = 'https://store.example/a?sig=1';
const String _linkB = 'https://store.example/b?sig=2';

const ValueKey<String> _submit = ValueKey('share-submit');
const ValueKey<String> _cancel = ValueKey('share-cancel');
const ValueKey<String> _selectAll = ValueKey('share-select-all');

ValueKey<String> _option(ShareSection section) =>
    ValueKey('share-option-${section.name}');

ValueKey<String> _pickerTile(String key) => ValueKey('share-picker-media-$key');

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
    String? initialMediaKey,
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
                    initialMediaKey: initialMediaKey,
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

  /// For fixed controls and already visible widgets.
  Future<void> tapAt(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    expect(finder.hitTestable(), findsOneWidget);
    await tester.tap(finder);
  }

  /// Eager rows already exist while clipped. `scrollUntilVisible` skips its
  /// drag loop for them and aligns their leading edge; center the tap target
  /// in the actual keyed viewport instead.
  Future<void> tapInViewport(
    WidgetTester tester,
    Finder target, {
    required Key viewportKey,
    required Key footerKey,
    bool lazy = false,
  }) async {
    final viewport = find.byKey(viewportKey);
    final scrollable = find.descendant(
      of: viewport,
      matching: find.byType(Scrollable),
    );
    expect(viewport, findsOneWidget);
    expect(scrollable, findsOneWidget);
    if (lazy && target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(target, 80, scrollable: scrollable);
    }
    expect(target, findsOneWidget);
    expect(Scrollable.of(tester.element(target)),
        same(tester.state<ScrollableState>(scrollable)));
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
    final visible = tester.getRect(viewport);
    final item = tester.getRect(target);
    final footer = tester.getRect(find.byKey(footerKey));
    expect(visible.overlaps(item), isTrue);
    expect(visible.contains(item.center), isTrue);
    expect(item.center.dy, lessThan(footer.top));
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
  }

  Future<void> tapShareOption(
          WidgetTester tester, ShareSection section) async =>
      tapInViewport(
        tester,
        find.byKey(_option(section)),
        viewportKey: const ValueKey('share-body-scroll'),
        footerKey: _submit,
      );

  Future<void> tapPickerTile(WidgetTester tester, String key) async =>
      tapInViewport(
        tester,
        find.byKey(_pickerTile(key)),
        viewportKey: const ValueKey('share-media-picker-scroll'),
        footerKey: const ValueKey('share-picker-done'),
        lazy: true,
      );

  Future<void> openMediaPicker(WidgetTester tester) async {
    await tapShareOption(tester, ShareSection.media);
    await tester.pumpAndSettle();
    expect(find.byType(ShareMediaPicker), findsOneWidget);
  }

  Future<void> selectVideo(WidgetTester tester) async {
    await openMediaPicker(tester);
    await tapPickerTile(tester, 'video-1');
    await tapAt(tester, find.byKey(const ValueKey('share-picker-done')));
    await tester.pumpAndSettle();
  }

  bool? pickerSelected(WidgetTester tester, String key) {
    return tester
        .widget<Semantics>(find.byKey(ValueKey('share-picker-semantics-$key')))
        .properties
        .selected;
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

      await tapShareOption(tester, ShareSection.notes);
      await tester.pump();
      expect(checkboxOf(tester, _option(ShareSection.notes)), isFalse);

      await tapShareOption(tester, ShareSection.notes);
      await tester.pump();
      expect(checkboxOf(tester, _option(ShareSection.notes)), isTrue);
    });

    testWidgets('Select All shows a dash while only some rows are chosen',
        (tester) async {
      await openDialog(tester, fullRequest());
      expect(checkboxOf(tester, _selectAll), isTrue);

      await tapShareOption(tester, ShareSection.notes);
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
      await tapShareOption(tester, ShareSection.contact);
      await tapShareOption(tester, ShareSection.notes);
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
      // The sheet is open: the button is locked, but nothing is loading, so
      // nothing spins and nothing claims to be sharing behind the sheet.
      expect(find.text('Sharing...'), findsNothing);
      expect(find.text('Share'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

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
            localFilePath:
                area.writeCacheFile('p1.jpg', renderableJpegBytes()).path),
        mediaRef('photo-2',
            localFilePath:
                area.writeCacheFile('p2.jpg', renderableJpegBytes()).path),
        mediaRef('video-1', video: true, signedUrl: _linkB),
      ]);
    }

    testWidgets('summary leads to visual photos and a video tile',
        (tester) async {
      await openDialog(tester, twoPhotosAndAVideo());

      expect(find.text('2 of 3 selected'), findsOneWidget);
      expect(find.byKey(const ValueKey('share-media-summary')), findsOneWidget);
      expect(find.text('Photo 1'), findsNothing);
      expect(find.text('Video 1'), findsNothing);
      expect(checkboxOf(tester, _selectAll), isNull,
          reason: 'the video is not chosen yet');
      await openMediaPicker(tester);
      expect(
          find.descendant(
              of: find.byType(ShareMediaPicker),
              matching: find.byType(ShareMediaPreview)),
          findsNWidgets(3));
      expect(
          find.descendant(
              of: find.byKey(_pickerTile('photo-1')),
              matching: find.byType(Image)),
          findsOneWidget,
          reason: 'a cached photo is shown as an actual thumbnail');
      // This video has no frame anywhere (and no way to make one): one clean
      // placeholder, with no play badge layered over it.
      final videoTile = find.byKey(_pickerTile('video-1'));
      expect(
          find.descendant(
              of: videoTile,
              matching:
                  find.byKey(const ValueKey('share-media-video-placeholder'))),
          findsOneWidget);
      expect(
          find.descendant(
              of: videoTile,
              matching:
                  find.byKey(const ValueKey('share-media-video-indicator'))),
          findsNothing);
      expect(
          find.descendant(
              of: find.byType(ShareMediaPicker),
              matching: find.text('2 of 3 selected')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Cancel discards a draft; Done confirms toggles and reselects',
        (tester) async {
      await openDialog(tester, twoPhotosAndAVideo());
      await openMediaPicker(tester);
      await tapPickerTile(tester, 'video-1');
      await tapAt(tester, find.byKey(const ValueKey('share-picker-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('2 of 3 selected'), findsOneWidget);

      await openMediaPicker(tester);
      await tapPickerTile(tester, 'video-1');
      await tapPickerTile(tester, 'photo-1');
      await tapAt(tester, find.byKey(const ValueKey('share-picker-done')));
      await tester.pumpAndSettle();
      expect(find.text('2 of 3 selected'), findsOneWidget);
      expect(checkboxOf(tester, _selectAll), isNull);

      await openMediaPicker(tester);
      await tapPickerTile(tester, 'photo-1');
      await tapAt(tester, find.byKey(const ValueKey('share-picker-done')));
      await tester.pumpAndSettle();
      expect(find.text('3 of 3 selected'), findsOneWidget);
      expect(checkboxOf(tester, _selectAll), isTrue);
    });

    testWidgets('a viewer key starts with only its current item',
        (tester) async {
      await openDialog(tester, twoPhotosAndAVideo(),
          initialMediaKey: 'video-1');
      expect(find.text('1 of 3 selected'), findsOneWidget);
      await openMediaPicker(tester);
      expect(pickerSelected(tester, 'video-1'), isTrue);
      await tapPickerTile(tester, 'photo-1');
      await tapAt(tester, find.byKey(const ValueKey('share-picker-done')));
      await tester.pumpAndSettle();
      expect(find.text('2 of 3 selected'), findsOneWidget);
    });

    testWidgets('Select all and Clear act only on picker draft',
        (tester) async {
      await openDialog(tester, twoPhotosAndAVideo());
      await openMediaPicker(tester);
      await tapAt(tester, find.byKey(const ValueKey('share-picker-all')));
      await tester.pump();
      expect(
          find.descendant(
              of: find.byType(ShareMediaPicker),
              matching: find.text('3 of 3 selected')),
          findsOneWidget);
      await tapAt(tester, find.byKey(const ValueKey('share-picker-clear')));
      await tester.pump();
      expect(
          find.descendant(
              of: find.byType(ShareMediaPicker),
              matching: find.text('0 of 3 selected')),
          findsOneWidget);
      await tapAt(tester, find.byKey(const ValueKey('share-picker-done')));
      await tester.pumpAndSettle();
      expect(find.text('0 of 3 selected'), findsOneWidget);
      expect(find.byKey(const ValueKey('share-media-summary')), findsNothing);
    });

    testWidgets('short Arabic picker keeps actions and fallback tiles usable',
        (tester) async {
      final source = offerWithMedia(<OfferMediaRef>[
        const OfferMediaRef(mediaObjectId: 'photo-empty', cacheKey: null),
        mediaRef('video-1', video: true, signedUrl: _linkB),
      ]);
      await openDialog(tester, source,
          locale: const Locale('ar'),
          theme: ThemeData.dark(),
          width: 280,
          height: 500,
          textScale: 1.6);
      final body = find.descendant(
        of: find.byKey(const ValueKey('share-body-scroll')),
        matching: find.byType(Scrollable),
      );
      expect(body, findsOneWidget);
      expect(tester.state<ScrollableState>(body).position.maxScrollExtent,
          greaterThan(0));
      final viewport =
          tester.getRect(find.byKey(const ValueKey('share-body-scroll')));
      final mediaBefore =
          tester.getRect(find.byKey(_option(ShareSection.media)));
      final actions =
          tester.getRect(find.byKey(const ValueKey('share-submit')));
      expect(mediaBefore.top, greaterThanOrEqualTo(viewport.top));
      expect(viewport.bottom, lessThanOrEqualTo(actions.top));
      expect(find.byKey(const ValueKey('share-cancel')).hitTestable(),
          findsOneWidget);
      expect(find.byKey(const ValueKey('share-submit')).hitTestable(),
          findsOneWidget);
      await openMediaPicker(tester);
      expect(find.text(arbLookup('ar', 'selectMedia')!), findsOneWidget);
      expect(find.byKey(const ValueKey('share-picker-done')).hitTestable(),
          findsOneWidget);
      expect(find.byKey(const ValueKey('share-picker-cancel')).hitTestable(),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(_pickerTile('photo-empty')),
              matching:
                  find.byKey(const ValueKey('share-media-image-placeholder'))),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(_pickerTile('video-1')),
              matching:
                  find.byKey(const ValueKey('share-media-video-placeholder'))),
          findsOneWidget);
      expect(net.requested, isEmpty,
          reason: 'opening the picker does not download an original video');
      expect(tester.takeException(), isNull);
      await tapAt(tester, find.byKey(const ValueKey('share-picker-cancel')));
      await tester.pumpAndSettle();
      await openMediaPicker(tester);
      await tapAt(tester, find.byKey(const ValueKey('share-picker-done')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a cached video poster is shown without a video download',
        (tester) async {
      final poster = area.writeCacheFile('poster.jpg', renderableJpegBytes());
      final source = offerWithMedia(<OfferMediaRef>[
        OfferMediaRef(
          mediaObjectId: 'video-poster',
          cacheKey: null,
          signedUrl: _linkB,
          isVideo: true,
          posterPath: poster.path,
        ),
      ]);
      await openDialog(tester, source);
      await openMediaPicker(tester);
      final tile = find.byKey(_pickerTile('video-poster'));
      expect(find.descendant(of: tile, matching: find.byType(Image)),
          findsOneWidget);
      // A real frame carries the play badge and nothing else video-shaped.
      expect(
          find.descendant(
              of: tile,
              matching:
                  find.byKey(const ValueKey('share-media-video-indicator'))),
          findsOneWidget);
      expect(
          find.descendant(
              of: tile,
              matching:
                  find.byKey(const ValueKey('share-media-video-placeholder'))),
          findsNothing);
      expect(
          find.descendant(
              of: tile, matching: find.byIcon(Icons.videocam_outlined)),
          findsNothing);
      expect(net.requested, isEmpty);
    });

    testWidgets('a missing poster falls back to the video placeholder',
        (tester) async {
      // A missing poster takes the immediate, deterministic fallback path.
      final missing = '${area.root.path}/missing-poster.jpg';
      expect(File(missing).existsSync(), isFalse);
      final source = offerWithMedia(<OfferMediaRef>[
        OfferMediaRef(
          mediaObjectId: 'video-broken-poster',
          cacheKey: null,
          signedUrl: _linkB,
          isVideo: true,
          posterPath: missing,
        ),
      ]);
      await openDialog(tester, source);
      await openMediaPicker(tester);
      await tester.pump();
      expect(
          find.descendant(
              of: find.byKey(_pickerTile('video-broken-poster')),
              matching:
                  find.byKey(const ValueKey('share-media-video-placeholder'))),
          findsOneWidget);
      // One placeholder, with no play badge layered over it.
      expect(
          find.descendant(
              of: find.byKey(_pickerTile('video-broken-poster')),
              matching:
                  find.byKey(const ValueKey('share-media-video-indicator'))),
          findsNothing);
      expect(
          find.descendant(
              of: find.byKey(_pickerTile('video-broken-poster')),
              matching: find.byType(Image)),
          findsNothing);
      expect(pickerSelected(tester, 'video-broken-poster'), isFalse);
      expect(net.requested, isEmpty);
      expect(tester.takeException(), isNull);
    });

    const noteKey = ValueKey<String>('share-details-note');
    const twoStepKey = ValueKey<String>('share-two-step-note');
    const statusKey = ValueKey<String>('share-step-status');

    // Two videos and nothing else: a family of its own, so a share of them can be
    // held open at a download and observed phase by phase.
    PropertyShareSource twoVideos() => offerWithMedia(<OfferMediaRef>[
          mediaRef('video-1', video: true, signedUrl: _linkA),
          mediaRef('video-2', video: true, signedUrl: _linkB),
        ]);

    Future<void> selectBothVideos(WidgetTester tester) async {
      await openMediaPicker(tester);
      await tapPickerTile(tester, 'video-1');
      await tapPickerTile(tester, 'video-2');
      await tapAt(tester, find.byKey(const ValueKey('share-picker-done')));
      await tester.pumpAndSettle();
    }

    group('photos and videos chosen together: two steps, one choice', () {
      testWidgets(
          'the real breakdown and a note that it is two steps are shown before '
          'sharing, and nothing is asked', (tester) async {
        engine = newEngine(area, sink,
            client: net.client(), clipboard: FakeShareClipboard());
        await openDialog(tester, twoPhotosAndAVideo());
        expect(
            find.byKey(const ValueKey('share-media-breakdown')), findsNothing,
            reason: 'only photos are chosen at first');
        expect(find.byKey(twoStepKey), findsNothing);

        await selectVideo(tester);

        expect(find.text('3 of 3 selected'), findsOneWidget);
        expect(find.text('Photos: 2 · Videos: 1'), findsOneWidget);
        expect(find.byKey(twoStepKey), findsOneWidget);
        expect(find.text(enArb['shareTwoStepNote'] as String), findsOneWidget);
        expect(find.byKey(noteKey), findsOneWidget);
        // Nothing here is a question: no choice, no second selection.
        expect(find.text('Share photos (2)'), findsNothing);
        expect(find.text('Share videos (1)'), findsNothing);
        expect(find.text('Back'), findsNothing);
        expect(sink.requests, isEmpty);
        expect(net.requested, isEmpty);
      });

      testWidgets(
          'Share hands over the photos; the dialog stays, says the videos are '
          'ready, and the next tap on Continue sends only them',
          (tester) async {
        net.bodies[_linkB] = mp4Bytes();
        final clipboard = FakeShareClipboard();
        engine =
            newEngine(area, sink, client: net.client(), clipboard: clipboard);
        final source = twoPhotosAndAVideo();
        await openDialog(tester, source);
        await selectVideo(tester);
        expect(find.text('Share'), findsOneWidget);

        // Step one.
        await tapAt(tester, find.byKey(_submit));
        await tester.pump();
        await realUntil(tester, () => sink.requests.isNotEmpty);
        await tester.pumpAndSettle();

        expect(sink.requests, hasLength(1), reason: 'one external share');
        expect(sink.nativeRequests, hasLength(1));
        final photos = sink.requests.single;
        expect(photos.files.map((f) => f.mimeType).toList(),
            <String>['image/jpeg', 'image/jpeg']);
        expect(photos.text, isNull);
        expect(net.requested, isEmpty, reason: 'the video is not fetched yet');
        expect(clipboard.copied, <String>[
          source.composeText(source.defaultSelection, labelsIn('en'))!,
        ]);

        // The dialog is still here: the choice is as it was, the status is
        // said, and the button now continues.
        expect(find.byType(ShareOptionsDialog), findsOneWidget);
        expect(find.text('3 of 3 selected'), findsOneWidget,
            reason: 'sharing does not change the master selection');
        expect(find.byKey(statusKey), findsOneWidget);
        expect(
            find.text(enArb['shareStepVideosReady'] as String), findsOneWidget);
        expect(find.byKey(twoStepKey), findsNothing);
        expect(find.text('Continue'), findsOneWidget);
        expect(find.text('Share'), findsNothing);
        expect(submitAction(tester), isNotNull);

        // Nothing starts the second step by itself.
        await realTime(tester, milliseconds: 600);
        await tester.pumpAndSettle();
        expect(sink.requests, hasLength(1));
        expect(net.requested, isEmpty);

        // Step two: a double tap on Continue still sends once.
        await tester.tap(find.byKey(_submit));
        await tester.tap(find.byKey(_submit), warnIfMissed: false);
        await tester.pump();
        await realUntil(tester, () => sink.requests.length == 2);
        await tester.pumpAndSettle();

        expect(sink.requests, hasLength(2));
        final video = sink.requests.last;
        expect(
            video.files.map((f) => f.mimeType).toList(), <String>['video/mp4']);
        expect(video.text, isNotNull,
            reason: 'one video goes with its message');
        expect(video.mediaBatch, isFalse);
        expect(net.requested, <String>[_linkB], reason: 'only the video');
        expect(clipboard.attempts, 1, reason: 'the details are copied once');
        expect(find.byType(ShareOptionsDialog), findsNothing,
            reason: 'the last step is the end of the share');
      });

      testWidgets('the notes and the Continue button are Arabic in Arabic',
          (tester) async {
        net.bodies[_linkB] = mp4Bytes();
        engine = newEngine(area, sink,
            client: net.client(), clipboard: FakeShareClipboard());
        await openDialog(tester, twoPhotosAndAVideo(),
            locale: const Locale('ar'));
        await selectVideo(tester);
        expect(find.text(arArb['shareTwoStepNote'] as String), findsOneWidget);
        expect(find.text('الصور: 2 · الفيديوهات: 1'), findsOneWidget);

        await tapAt(tester, find.byKey(_submit));
        await tester.pump();
        await realUntil(tester, () => sink.requests.isNotEmpty);
        await tester.pumpAndSettle();

        expect(
            find.text(arArb['shareStepVideosReady'] as String), findsOneWidget);
        expect(find.text('متابعة'), findsOneWidget);
        expect(find.text('Continue'), findsNothing);
      });

      testWidgets(
          'a second step that fails keeps the status, and Retry sends only the '
          'videos', (tester) async {
        net.failures[_linkB] = const SocketException('offline');
        engine = newEngine(area, sink,
            client: net.client(), clipboard: FakeShareClipboard());
        await openDialog(tester, twoPhotosAndAVideo());
        await selectVideo(tester);
        await tapAt(tester, find.byKey(_submit));
        await tester.pump();
        await realUntil(tester, () => sink.requests.isNotEmpty);
        await tester.pumpAndSettle();
        expect(sink.requests, hasLength(1));

        await tapAt(tester, find.byKey(_submit));
        await tester.pump();
        await realUntil(tester, () => net.requested.isNotEmpty);
        await realTime(tester);
        await tester.pump();

        expect(find.byKey(const ValueKey('share-error')), findsOneWidget);
        expect(
            find.text(arbLookup('en', 'shareErrorNetwork')!), findsOneWidget);
        expect(sink.requests, hasLength(1), reason: 'nothing more was sent');
        expect(find.byKey(statusKey), findsOneWidget,
            reason: 'the photos are done; the videos are still ready');
        expect(find.text('Continue'), findsOneWidget);
        expect(find.text('3 of 3 selected'), findsOneWidget);

        net.failures.clear();
        net.bodies[_linkB] = mp4Bytes();
        net.requested.clear();
        await tapAt(tester, find.byKey(const ValueKey('share-retry')));
        await tester.pump();
        await realUntil(tester, () => sink.requests.length == 2);
        await tester.pumpAndSettle();

        expect(sink.requests.last.files.map((f) => f.mimeType).toList(),
            <String>['video/mp4']);
        expect(net.requested, <String>[_linkB],
            reason: 'the photos are not sent or fetched again');
        expect(find.byType(ShareOptionsDialog), findsNothing);
      });

      testWidgets(
          'the breakdown is in Arabic in Arabic, and informational only',
          (tester) async {
        await openDialog(tester, twoPhotosAndAVideo(),
            locale: const Locale('ar'));
        await selectVideo(tester);

        expect(find.text('الصور: 2 · الفيديوهات: 1'), findsOneWidget);
        expect(find.text('Photos: 2 · Videos: 1'), findsNothing);
        expect(find.byType(ShareOptionsDialog), findsOneWidget);
      });

      testWidgets('only photos, or only videos, need no breakdown or note',
          (tester) async {
        await openDialog(tester, twoPhotosAndAVideo());
        expect(
            find.byKey(const ValueKey('share-media-breakdown')), findsNothing);

        await openMediaPicker(tester);
        await tapPickerTile(tester, 'photo-1');
        await tapPickerTile(tester, 'photo-2');
        await tapPickerTile(tester, 'video-1');
        await tapAt(tester, find.byKey(const ValueKey('share-picker-done')));
        await tester.pumpAndSettle();
        expect(find.text('1 of 3 selected'), findsOneWidget);
        expect(
            find.byKey(const ValueKey('share-media-breakdown')), findsNothing);
        expect(find.byKey(twoStepKey), findsNothing);
      });
    });

    group('one family: several videos', () {
      testWidgets(
          'a double tap on Share is one preparation, one copy and one native '
          'share, and the lock is taken before anything is awaited',
          (tester) async {
        // Two gates make every phase observable without a clock: the second
        // video's download holds preparation open, and the share sheet stays
        // open until it is released. Both videos are served: without a body a
        // download would fail and nothing would ever reach the sheet.
        final download = Completer<List<int>>();
        net.bodies[_linkA] = mp4Bytes();
        net.bodies[_linkB] = mp4Bytes();
        net.held[_linkB] = download;
        sink.hold = Completer<ShareOutcome>();
        final clipboard = FakeShareClipboard();
        engine =
            newEngine(area, sink, client: net.client(), clipboard: clipboard);
        await openDialog(tester, twoVideos());
        await selectBothVideos(tester);
        expect(find.text('2 of 2 selected'), findsOneWidget);

        // Phase 1: two taps with no frame between them. The second reaches the
        // same, still enabled button; the first attempt has already taken the
        // lock inside the controller, so the second cannot enter the pipeline.
        await tapAt(tester, find.byKey(_submit));
        await tester.tap(find.byKey(_submit), warnIfMissed: false);
        await tester.pump();
        expect(submitAction(tester), isNull, reason: 'the dialog is busy');
        // One loading indicator for the one preparation: a spinner where the
        // icon was, under the same label. No second line, no second spinner.
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Preparing files...'), findsNothing);
        expect(find.text('Share'), findsOneWidget);

        // Phase 2: the first attempt is held inside preparation, at the second
        // download, with the first video already prepared. Still the one
        // spinner: progress is not a second indicator.
        await realUntil(tester, () => net.requested.length == 2);
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
            find.byKey(const ValueKey('share-preparing-count')), findsNothing);
        expect(find.text('1 of 2 files prepared'), findsNothing);
        await tester.tap(find.byKey(_submit), warnIfMissed: false);
        await tester.pump();
        expect(net.requested, <String>[_linkA, _linkB],
            reason: 'one preparation: each video is fetched once');
        expect(sink.requests, isEmpty, reason: 'nothing is handed over yet');
        expect(clipboard.attempts, 0, reason: 'nothing is copied yet');

        // Phase 3: preparation ends and the one batch is handed to the sheet,
        // which stays open. Another tap changes nothing.
        download.complete(<int>[1, 2, 3]);
        await realUntil(tester, () => sink.requests.isNotEmpty);
        await tester.pump();
        expect(submitAction(tester), isNull, reason: 'the sheet is open');
        expect(find.byType(CircularProgressIndicator), findsNothing,
            reason: 'preparation is over: nothing spins behind the sheet');
        await tester.tap(find.byKey(_submit), warnIfMissed: false);
        await tester.pump();
        expect(sink.nativeRequests, hasLength(1),
            reason: 'one batch for the Android transport');
        expect(sink.systemRequests, isEmpty);
        final batch = sink.nativeRequests.single;
        expect(batch.files.map((f) => f.mimeType).toList(),
            <String>['video/mp4', 'video/mp4']);
        expect(batch.text, isNull);
        expect(clipboard.attempts, 1, reason: 'one copy');
        expect(clipboard.copied, hasLength(1));

        // The platform reports nothing for a started chooser; the share is done.
        // Nothing real is left to wait for: only the flow's own continuations,
        // which the frames below run.
        sink.hold!.complete(ShareOutcome.unknown);
        await tester.pumpAndSettle();
        expect(sink.requests, hasLength(1));
        expect(net.requested, <String>[_linkA, _linkB]);
        expect(clipboard.attempts, 1);
        expect(find.byType(ShareOptionsDialog), findsNothing);
      });

      testWidgets('Cancel while files are being prepared opens nothing',
          (tester) async {
        final gate = Completer<List<int>>();
        net.bodies[_linkA] = mp4Bytes();
        net.held[_linkA] = gate;
        net.bodies[_linkB] = mp4Bytes();
        engine = newEngine(area, sink,
            client: net.client(), clipboard: FakeShareClipboard());
        await openDialog(tester, twoVideos());
        await selectBothVideos(tester);
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
        net.failures[_linkA] = const SocketException('offline');
        engine = newEngine(area, sink,
            client: net.client(), clipboard: FakeShareClipboard());
        await openDialog(tester, twoVideos());
        await selectBothVideos(tester);
        await tapAt(tester, find.byKey(_submit));
        await tester.pump();
        await realUntil(tester, () => net.requested.isNotEmpty);
        await realTime(tester);
        await tester.pump();

        expect(find.byKey(const ValueKey('share-error')), findsOneWidget);
        expect(
            find.text(arbLookup('en', 'shareErrorNetwork')!), findsOneWidget);
        expect(sink.requests, isEmpty, reason: 'nothing goes out incomplete');
        expect(find.text('2 of 2 selected'), findsOneWidget);
        expect(submitAction(tester), isNotNull);

        net.failures.clear();
        net.bodies[_linkA] = mp4Bytes();
        net.bodies[_linkB] = mp4Bytes();
        await tapAt(tester, find.byKey(const ValueKey('share-retry')));
        await tester.pump();
        await realUntil(tester, () => sink.requests.isNotEmpty);
        await tester.pumpAndSettle();
        expect(sink.requests.single.files, hasLength(2));
      });

      testWidgets(
          'a file that is gone is marked, left out, and never looks chosen',
          (tester) async {
        net.bodies[_linkA] = mp4Bytes();
        net.statuses[_linkB] = 404;
        engine = newEngine(area, sink,
            client: net.client(), clipboard: FakeShareClipboard());
        await openDialog(tester, twoVideos());
        await selectBothVideos(tester);
        await tapAt(tester, find.byKey(_submit));
        await tester.pump();
        await realUntil(tester, () => net.requested.length == 2);
        await realTime(tester);
        await tester.pump();

        expect(find.text(arbLookup('en', 'shareErrorUnavailable')!),
            findsOneWidget);
        expect(find.byKey(const ValueKey('share-retry')), findsNothing,
            reason: 'retrying cannot bring the file back');
        expect(find.text('1 of 2 selected'), findsOneWidget);
        expect(sink.requests, isEmpty);

        await openMediaPicker(tester);
        expect(tester.widget<InkWell>(find.byKey(_pickerTile('video-2'))).onTap,
            isNull);
        expect(find.text('Video 2'), findsNothing);
        await tapAt(tester, find.byKey(const ValueKey('share-picker-cancel')));
        await tester.pumpAndSettle();

        // Sharing again goes on without it, with the person's say-so.
        await tapAt(tester, find.byKey(_submit));
        await tester.pump();
        await realUntil(tester, () => sink.requests.isNotEmpty);
        await tester.pumpAndSettle();
        expect(sink.requests.single.files, hasLength(1));
      });
    });

    group('the details note', () {
      testWidgets(
          'two photos: the note is shown before sharing, then one batch goes '
          'with no message in it and the message is copied', (tester) async {
        final clipboard = FakeShareClipboard();
        engine =
            newEngine(area, sink, client: net.client(), clipboard: clipboard);
        final source = twoPhotosAndAVideo();
        await openDialog(tester, source);

        expect(find.byKey(noteKey), findsOneWidget,
            reason: 'said before the native sheet can cover the screen');
        expect(
            find.text(enArb['shareDetailsCopyNote'] as String), findsOneWidget);
        expect(clipboard.attempts, 0,
            reason: 'nothing is copied by opening it');

        await tapAt(tester, find.byKey(_submit));
        await tester.pump();
        await realUntil(tester, () => sink.requests.isNotEmpty);
        await tester.pumpAndSettle();

        expect(sink.requests, hasLength(1), reason: 'one share, not two');
        expect(sink.nativeRequests, hasLength(1),
            reason: 'two photos go to the Android batch transport');
        expect(sink.requests.single.files, hasLength(2));
        expect(sink.requests.single.text, isNull,
            reason: 'no caption that a receiving app repeats or drops');
        final message =
            source.composeText(source.defaultSelection, labelsIn('en'));
        expect(clipboard.copied, <String>[message!]);
        expect(find.byType(ShareOptionsDialog), findsNothing);
      });

      testWidgets('the note is Arabic in Arabic', (tester) async {
        engine = newEngine(area, sink,
            client: net.client(), clipboard: FakeShareClipboard());
        await openDialog(tester, twoPhotosAndAVideo(),
            locale: const Locale('ar'));

        expect(
            find.text(arArb['shareDetailsCopyNote'] as String), findsOneWidget);
        expect(
            find.text(enArb['shareDetailsCopyNote'] as String), findsNothing);
      });

      testWidgets('one photo has no note and copies nothing', (tester) async {
        final clipboard = FakeShareClipboard();
        engine =
            newEngine(area, sink, client: net.client(), clipboard: clipboard);
        await openDialog(
          tester,
          offerWithMedia(<OfferMediaRef>[
            mediaRef('photo-1',
                localFilePath:
                    area.writeCacheFile('p1.jpg', renderableJpegBytes()).path),
          ]),
        );
        expect(find.byKey(noteKey), findsNothing);

        await tapAt(tester, find.byKey(_submit));
        await tester.pump();
        await realUntil(tester, () => sink.requests.isNotEmpty);
        await tester.pumpAndSettle();

        expect(sink.requests.single.files, hasLength(1));
        expect(sink.requests.single.text, isNotNull);
        expect(clipboard.attempts, 0);
      });

      testWidgets('the note follows the choice of media and of message',
          (tester) async {
        engine = newEngine(area, sink,
            client: net.client(), clipboard: FakeShareClipboard());
        await openDialog(tester, twoPhotosAndAVideo());
        expect(find.byKey(noteKey), findsOneWidget);

        // Leave one photo: no longer several.
        await openMediaPicker(tester);
        await tapPickerTile(tester, 'photo-2');
        await tapAt(tester, find.byKey(const ValueKey('share-picker-done')));
        await tester.pumpAndSettle();
        expect(find.text('1 of 3 selected'), findsOneWidget);
        expect(find.byKey(noteKey), findsNothing);
      });

      testWidgets('an engine with no clipboard promises nothing',
          (tester) async {
        await openDialog(tester, twoPhotosAndAVideo());
        expect(find.byKey(noteKey), findsNothing);
      });

      testWidgets(
          'closing the share sheet keeps the dialog and the note, and the copy '
          'is left alone', (tester) async {
        sink.outcome = ShareOutcome.dismissed;
        final clipboard = FakeShareClipboard();
        engine =
            newEngine(area, sink, client: net.client(), clipboard: clipboard);
        await openDialog(tester, twoPhotosAndAVideo());

        await tapAt(tester, find.byKey(_submit));
        await tester.pump();
        await realUntil(tester, () => sink.requests.isNotEmpty);
        await tester.pumpAndSettle();

        expect(find.byType(ShareOptionsDialog), findsOneWidget);
        expect(find.byKey(const ValueKey('share-error')), findsNothing);
        expect(find.byKey(noteKey), findsOneWidget);
        expect(clipboard.copied, hasLength(1));
        expect(clipboard.attempts, 1);
      });

      testWidgets(
          'a clipboard that fails still shares, and the note is withdrawn',
          (tester) async {
        sink.outcome = ShareOutcome.dismissed;
        final clipboard = FakeShareClipboard(succeeds: false);
        engine =
            newEngine(area, sink, client: net.client(), clipboard: clipboard);
        await openDialog(tester, twoPhotosAndAVideo());
        expect(find.byKey(noteKey), findsOneWidget);

        await tapAt(tester, find.byKey(_submit));
        await tester.pump();
        await realUntil(tester, () => sink.requests.isNotEmpty);
        await tester.pumpAndSettle();

        expect(sink.requests.single.files, hasLength(2));
        expect(find.byKey(const ValueKey('share-error')), findsNothing);
        expect(find.byKey(noteKey), findsNothing);
      });
    });

    group('one loading indicator, and notes that begin at the reading edge',
        () {
      int spinners() =>
          find.byType(CircularProgressIndicator).evaluate().length;

      testWidgets(
          'a mixed share shows one spinner for each preparation, none while a '
          'sheet is open, none after, and the button never changes size',
          (tester) async {
        // Step one is held before any file work (a gate in the staging folder
        // lookup), and step two at the video's download, so each preparation can
        // be looked at while it is really under way.
        final preparing = Completer<void>();
        final download = Completer<List<int>>();
        net.bodies[_linkB] = mp4Bytes();
        net.held[_linkB] = download;
        engine = newEngine(area, sink,
            client: net.client(),
            clipboard: FakeShareClipboard(),
            hold: preparing.future);
        await openDialog(tester, twoPhotosAndAVideo());
        await selectVideo(tester);
        expect(spinners(), 0, reason: 'nothing is loading before Share');
        final idle = tester.getSize(find.byKey(_submit));

        // Step one is being prepared: one spinner, the button locked, its label
        // unchanged, and no second line of progress. A second tap changes nothing.
        await tapAt(tester, find.byKey(_submit));
        await tester.tap(find.byKey(_submit), warnIfMissed: false);
        await tester.pump();
        expect(spinners(), 1);
        expect(submitAction(tester), isNull);
        expect(find.text('Share'), findsOneWidget);
        expect(find.text('Preparing files...'), findsNothing);
        expect(
            find.byKey(const ValueKey('share-preparing-count')), findsNothing);
        expect(tester.getSize(find.byKey(_submit)), idle);
        expect(
            tester
                .widget<CircularProgressIndicator>(
                    find.byType(CircularProgressIndicator))
                .semanticsLabel,
            enArb['preparingFiles'],
            reason: 'a screen reader is told what is being waited for');

        // The photos are handed over: nothing spins any more, and the button
        // now continues, enabled, the same size.
        preparing.complete();
        await realUntil(tester, () => sink.requests.isNotEmpty);
        await tester.pumpAndSettle();
        expect(sink.requests, hasLength(1));
        expect(spinners(), 0, reason: 'nothing is left spinning');
        expect(find.text('Continue'), findsOneWidget);
        expect(submitAction(tester), isNotNull);
        expect(tester.getSize(find.byKey(_submit)), idle);

        // Continue prepares only the video: again exactly one spinner, under the
        // label it already has, and the photos are not prepared again.
        await tapAt(tester, find.byKey(_submit));
        await tester.tap(find.byKey(_submit), warnIfMissed: false);
        await tester.pump();
        await realUntil(tester, () => net.requested.isNotEmpty);
        await tester.pump();
        expect(spinners(), 1);
        expect(submitAction(tester), isNull);
        expect(find.text('Continue'), findsOneWidget);
        expect(tester.getSize(find.byKey(_submit)), idle);
        expect(net.requested, <String>[_linkB], reason: 'only the video');

        download.complete(<int>[1]);
        await realUntil(tester, () => sink.requests.length == 2);
        await tester.pumpAndSettle();
        expect(sink.requests, hasLength(2), reason: 'a double tap sent once');
        expect(spinners(), 0);
        expect(find.byType(ShareOptionsDialog), findsNothing);
      });

      testWidgets('a failed preparation leaves no spinner, only the reason',
          (tester) async {
        net.failures[_linkA] = const SocketException('offline');
        engine = newEngine(area, sink,
            client: net.client(), clipboard: FakeShareClipboard());
        await openDialog(tester, twoVideos());
        await selectBothVideos(tester);
        await tapAt(tester, find.byKey(_submit));
        await tester.pump();
        await realUntil(tester, () => net.requested.isNotEmpty);
        await realTime(tester);
        await tester.pump();

        expect(find.byKey(const ValueKey('share-error')), findsOneWidget);
        expect(spinners(), 0);
        expect(submitAction(tester), isNotNull, reason: 'ready to try again');
      });

      testWidgets(
          'a message alone never spins, and a closed share sheet leaves no '
          'spinner and keeps the dialog', (tester) async {
        final gate = Completer<ShareOutcome>();
        sink.hold = gate;
        await openDialog(tester, fullRequest());
        await tapAt(tester, find.byKey(_submit));
        await tester.pump();
        expect(spinners(), 0, reason: 'a message alone has nothing to prepare');
        expect(submitAction(tester), isNull, reason: 'the sheet is open');

        gate.complete(ShareOutcome.dismissed);
        await tester.pumpAndSettle();
        expect(spinners(), 0);
        expect(find.byType(ShareOptionsDialog), findsOneWidget);
        expect(submitAction(tester), isNotNull);
      });

      testWidgets('the locked button keeps the look of the idle one',
          (tester) async {
        final preparing = Completer<void>();
        engine = newEngine(area, sink,
            client: net.client(),
            clipboard: FakeShareClipboard(),
            hold: preparing.future);
        await openDialog(tester, twoPhotosAndAVideo());
        Color? backgroundOf() => tester
            .widgetList<Material>(find.descendant(
                of: find.byKey(_submit), matching: find.byType(Material)))
            .first
            .color;
        final idle = backgroundOf();

        await tapAt(tester, find.byKey(_submit));
        // The spinner never settles, so advance by hand.
        await tester.pump(const Duration(milliseconds: 400));
        expect(spinners(), 1);
        expect(submitAction(tester), isNull);
        expect(backgroundOf(), idle,
            reason: 'the spinner is drawn on the button\'s own colour');

        preparing.complete();
        await realUntil(tester, () => sink.requests.isNotEmpty);
        await tester.pumpAndSettle();
      });

      // The short status line and the long details note must begin from the
      // same edge: the left in English, the right in Arabic.
      RenderParagraph paragraphOf(WidgetTester tester, Key key) =>
          tester.renderObject<RenderParagraph>(find.descendant(
              of: find.byKey(key), matching: find.byType(RichText)));

      double readingEdge(WidgetTester tester, Key key, TextDirection d) {
        final paragraph = paragraphOf(tester, key);
        final first = paragraph
            .getBoxesForSelection(
                const TextSelection(baseOffset: 0, extentOffset: 1))
            .first;
        final origin = paragraph.localToGlobal(Offset.zero);
        return d == TextDirection.ltr
            ? origin.dx + first.left
            : origin.dx + first.right;
      }

      double wordsWidth(WidgetTester tester, Key key) {
        final text = tester.widget<Text>(find.byKey(key)).data!;
        final boxes = paragraphOf(tester, key).getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: text.length));
        final left = boxes.map((b) => b.left).reduce((a, b) => a < b ? a : b);
        final right = boxes.map((b) => b.right).reduce((a, b) => a > b ? a : b);
        return right - left;
      }

      void expectOneReadingEdge(
        WidgetTester tester,
        List<Key> keys,
        TextDirection direction, {
        Key? shortLine,
      }) {
        final edges = <double>[];
        final widths = <double>[];
        for (final key in keys) {
          expect(find.byKey(key), findsOneWidget, reason: '$key is shown');
          expect(
              tester.widget<Text>(find.byKey(key)).textAlign, TextAlign.start,
              reason: '$key follows the reading direction, not a side');
          widths.add(tester.getSize(find.byKey(key)).width);
          edges.add(readingEdge(tester, key, direction));
        }
        for (var i = 1; i < keys.length; i++) {
          expect(edges[i], closeTo(edges.first, 0.5),
              reason: '${keys[i]} begins where ${keys.first} does');
          expect(widths[i], closeTo(widths.first, 0.5),
              reason: 'every note takes the whole width of its row');
        }
        if (shortLine != null) {
          // The line is shorter than its row, so where it begins is decided by
          // alignment and not by filling the row: the case that looked centered.
          expect(wordsWidth(tester, shortLine),
              lessThan(widths[keys.indexOf(shortLine)] - 40),
              reason: 'the premise: this line does not fill its row');
        }
      }

      for (final language in <String>['en', 'ar']) {
        final direction =
            language == 'ar' ? TextDirection.rtl : TextDirection.ltr;
        testWidgets(
            language == 'ar'
                ? 'Arabic: every note begins at the right'
                : 'English: every note begins at the left', (tester) async {
          engine = newEngine(area, sink,
              client: net.client(), clipboard: FakeShareClipboard());
          // Small text in a roomy dialog, so the status line is shorter than the
          // row, the way a real font makes it.
          await openDialog(tester, twoPhotosAndAVideo(),
              locale: Locale(language), width: 600, textScale: 0.5);
          await selectVideo(tester);

          // Before sharing: what the dialog explains.
          expectOneReadingEdge(tester, <Key>[twoStepKey, noteKey], direction);

          // After the photos: the status line and the details note.
          await tapAt(tester, find.byKey(_submit));
          await tester.pump();
          await realUntil(tester, () => sink.requests.isNotEmpty);
          await tester.pumpAndSettle();
          expectOneReadingEdge(tester, <Key>[statusKey, noteKey], direction,
              shortLine: statusKey);
          final row = tester.getRect(find.byKey(statusKey));
          final edge = readingEdge(tester, statusKey, direction);
          if (direction == TextDirection.ltr) {
            expect(edge, closeTo(row.left, 0.5), reason: 'from the left');
          } else {
            expect(edge, closeTo(row.right, 0.5), reason: 'from the right');
          }
          expect(tester.takeException(), isNull);
        });
      }
    });
  });

  testWidgets('gallery Share passes the displayed media identity',
      (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(
      supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: FullScreenMediaViewer(
        mediaRefs: <OfferMediaRef>[
          mediaRef('video-1', video: true),
          mediaRef('video-2', video: true),
        ],
        onShareMedia: opened.add,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('viewer-share-media')));
    expect(opened, <String>['video-1']);
    final page = find.byType(PageView);
    await tester.drag(page, Offset(-tester.getSize(page).width * 0.75, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('viewer-share-media')));
    expect(opened, <String>['video-1', 'video-2']);
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

      await tapShareOption(tester, ShareSection.notes);
      await tester.pump();
      expect(checkboxOf(tester, _option(ShareSection.notes)), isFalse);
    });

    testWidgets('a failure on a short screen is brought into view with Retry',
        (tester) async {
      sink.error = StateError('platform said no');
      await openDialog(tester, fullRequest(),
          textScale: 1.6, height: shortScreen);
      // A choice made before the failure must survive it.
      await tapShareOption(tester, ShareSection.notes);
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
      expect(find.text('Sharing...'), findsNothing);
      expect(find.text('Share'), findsOneWidget);
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
