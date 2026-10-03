// Shared fixtures for the Share tests: the real English and Arabic strings read
// straight from the ARB files, record builders with only the fields a test cares
// about filled in, and the small fakes that stand in for the platform.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/share/share_flow_controller.dart';
import 'package:broker_wallet/src/services/share/share_labels.dart';
import 'package:broker_wallet/src/services/share/share_launcher.dart';
import 'package:broker_wallet/src/services/share/share_media_fetcher.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_preparer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final Map<String, dynamic> enArb = json.decode(
  File('lib/src/common/localization/app_en.arb').readAsStringSync(),
) as Map<String, dynamic>;

final Map<String, dynamic> arArb = json.decode(
  File('lib/src/common/localization/app_ar.arb').readAsStringSync(),
) as Map<String, dynamic>;

/// The text of [key] in [language], from the ARB files on disk.
String? arbLookup(String language, String key) {
  final table = language == 'en'
      ? enArb
      : language == 'ar'
          ? arArb
          : const <String, dynamic>{};
  return table[key] as String?;
}

ShareLabels labelsIn(String language) =>
    ShareLabels(languageCode: language, lookup: arbLookup);

/// Labels that remember every key they were asked for, so a test can prove each
/// of them exists in both languages.
class RecordingLabels {
  RecordingLabels(String language) {
    labels = ShareLabels(
      languageCode: language,
      lookup: (lang, key) {
        asked.add(key);
        return arbLookup(lang, key);
      },
    );
  }

  late final ShareLabels labels;
  final Set<String> asked = <String>{};
}

final DateTime _then = DateTime(2026, 9, 1);

OfferModel offer({
  String? id = 'offer-1',
  String type = 'sell',
  String city = 'Dubai',
  List<String> areas = const <String>[],
  String location = '',
  String phone = '',
  String min = '',
  String max = '',
  String squareFootage = '',
  String notes = '',
  String? propertyType,
  String specific = '',
  int rooms = 0,
  int bathrooms = 0,
  double? latitude,
  double? longitude,
  String address = '',
  String pickUpLocation = '',
}) =>
    OfferModel(
      id: id,
      userId: 'user-1',
      offerType: type,
      selectedCity: city,
      selectedAreas: areas,
      location: location,
      phoneNumber: phone,
      countryCode: '+971',
      minPrice: min,
      maxPrice: max,
      squareFootage: squareFootage,
      notes: notes,
      propertyType: propertyType,
      specificPropertyType: specific,
      rooms: rooms,
      bathrooms: bathrooms,
      pickUpLocation: pickUpLocation,
      pickUpLatitude: latitude,
      pickUpLongitude: longitude,
      pickUpAddress: address,
      uploadedFileName: '',
      createdAt: _then,
      updatedAt: _then,
      mediaUrls: const <String>[],
    );

RequestModel request({
  String type = 'rent',
  String city = 'Dubai',
  List<String> areas = const <String>[],
  String location = '',
  String phone = '',
  String min = '',
  String max = '',
  String squareFootage = '',
  String notes = '',
  String? propertyType,
  String specific = '',
  int rooms = 0,
  int bathrooms = 0,
}) =>
    RequestModel(
      id: 'request-1',
      userId: 'user-1',
      requestType: type,
      selectedCity: city,
      selectedAreas: areas,
      location: location,
      phoneNumber: phone,
      countryCode: '+971',
      minPrice: min,
      maxPrice: max,
      squareFootage: squareFootage,
      notes: notes,
      propertyType: propertyType,
      specificPropertyType: specific,
      rooms: rooms,
      bathrooms: bathrooms,
      createdAt: _then,
      updatedAt: _then,
    );

OwnerModel owner({
  String name = '',
  String phone = '',
  String propertyType = '',
  String location = '',
  String notes = '',
  double? latitude,
  double? longitude,
  String address = '',
  String pickUpLocation = '',
}) =>
    OwnerModel(
      id: 'owner-1',
      userId: 'user-1',
      name: name,
      phoneNumber: phone,
      countryCode: '+971',
      typeOfProperties: propertyType,
      propertyLocation: location,
      notes: notes,
      pickUpLocation: pickUpLocation,
      pickUpLatitude: latitude,
      pickUpLongitude: longitude,
      pickUpAddress: address,
      mediaUrls: const <String>[],
      createdAt: _then,
      updatedAt: _then,
    );

BrokerModel broker({String name = '', String phone = '', String notes = ''}) =>
    BrokerModel(
      id: 'broker-1',
      userId: 'user-1',
      name: name,
      countryCode: '+971',
      phoneNumber: phone,
      notes: notes,
    );

WatchmenModel watchman({
  String name = '',
  String phone = '',
  String building = '',
  String buildingLocation = '',
  String notes = '',
  double? latitude,
  double? longitude,
  String address = '',
  String pickUpLocation = '',
}) =>
    WatchmenModel(
      id: 'watchman-1',
      userId: 'user-1',
      name: name,
      countryCode: '+971',
      phoneNumber: phone,
      buildingName: building,
      notes: notes,
      buildingLocation: buildingLocation,
      pickUpLocation: pickUpLocation,
      pickUpLatitude: latitude,
      pickUpLongitude: longitude,
      pickUpAddress: address,
    );

OfficeModel office({
  String name = '',
  String manager = '',
  String phone = '',
  String location = '',
  String notes = '',
  double? latitude,
  double? longitude,
  String address = '',
  String pickUpLocation = '',
}) =>
    OfficeModel(
      id: 'office-1',
      userId: 'user-1',
      officeName: name,
      managerName: manager,
      countryCode: '+971',
      phoneNumber: phone,
      officeLocation: location,
      notes: notes,
      pickUpLocation: pickUpLocation,
      pickUpLatitude: latitude,
      pickUpLongitude: longitude,
      pickUpAddress: address,
    );

QuotationModel quotation({
  String title = 'Apartment 306',
  String? propertyType,
  String officeName = '',
  double? total,
  double? fee,
  int? installments,
  String? currency,
  String? pdfMediaId = 'pdf-media-id-7f3a',
}) =>
    QuotationModel(
      id: 'quotation-id-1b2c',
      userId: 'user-1',
      propertyTitle: title,
      propertyType: propertyType,
      officeName: officeName,
      totalAmount: total,
      professionalFee: fee,
      numberOfInstallments: installments,
      currencyCode: currency,
      pdfMediaId: pdfMediaId,
      createdAt: _then,
      updatedAt: _then,
    );

/// A confirmed photo or video of a record, as a gallery would hold it.
OfferMediaRef mediaRef(
  String id, {
  bool video = false,
  String? localFilePath,
  String? signedUrl,
  bool withCacheKey = true,
  OfferMediaUploadPhase? phase,
}) =>
    OfferMediaRef(
      mediaObjectId: id,
      cacheKey: withCacheKey
          ? offerMediaCacheKey(ownerId: 'user-1', mediaObjectId: id)
          : null,
      isVideo: video,
      localFilePath: localFilePath,
      signedUrl: signedUrl,
      uploadPhase: phase,
    );

List<ShareMediaItem> mediaItems(List<OfferMediaRef> refs) =>
    ShareMediaItem.fromRefs(refs);

// ---------- Real bytes ----------

Uint8List jpegBytes([int length = 300]) => Uint8List.fromList(<int>[
      0xFF, 0xD8, 0xFF, 0xE0, //
      ...List<int>.filled(length, 7),
    ]);

Uint8List pngBytes([int length = 300]) => Uint8List.fromList(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      ...List<int>.filled(length, 7),
    ]);

/// An MP4: a `ftyp` box with the `isom` brand.
Uint8List mp4Bytes([int length = 600]) => Uint8List.fromList(<int>[
      0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, // size, "ftyp"
      0x69, 0x73, 0x6F, 0x6D, 0, 0, 2, 0, // "isom", minor version
      0x69, 0x73, 0x6F, 0x6D, 0x6D, 0x70, 0x34, 0x31, // compatible brands
      ...List<int>.filled(length, 3),
    ]);

Uint8List pdfBytes() => Uint8List.fromList(
      utf8.encode('%PDF-1.7\n1 0 obj\n<<>>\nendobj\n%%EOF\n'),
    );

Uint8List textBytes() => Uint8List.fromList(utf8.encode('just some text'));

// ---------- Fakes ----------

/// A network that answers from a table and remembers what it was asked.
class FakeNet {
  final Map<String, List<int>> bodies = <String, List<int>>{};
  final Map<String, int> statuses = <String, int>{};
  final Map<String, Object> failures = <String, Object>{};

  /// A body the test releases by hand, to hold a download open.
  final Map<String, Completer<List<int>>> held =
      <String, Completer<List<int>>>{};
  final List<String> requested = <String>[];
  bool closed = false;

  http.Client client() => MockClient.streaming((request, body) async {
        final url = request.url.toString();
        requested.add(url);
        final failure = failures[url];
        if (failure != null) throw failure;
        final status = statuses[url] ?? 200;
        final bytes = bodies[url] ?? const <int>[];
        final pending = held[url];
        if (pending != null) {
          Stream<List<int>> slowly() async* {
            yield bytes;
            yield await pending.future;
          }

          return http.StreamedResponse(slowly(), status);
        }
        return http.StreamedResponse(
          Stream<List<int>>.value(bytes),
          status,
          contentLength: bytes.length,
        );
      });
}

/// Records what the native share sheet was asked to open.
class FakeShareSink implements ShareSink {
  FakeShareSink({this.outcome = ShareOutcome.shared});

  ShareOutcome outcome;
  Object? error;

  /// Completes the open sheet by hand when set; otherwise [send] answers at once.
  Completer<ShareOutcome>? hold;

  final List<ShareRequest> requests = <ShareRequest>[];

  /// The files the sheet could still read at the moment it was opened.
  final List<List<bool>> filesExistedAtSend = <List<bool>>[];

  @override
  Future<ShareOutcome> send(ShareRequest request) async {
    requests.add(request);
    filesExistedAtSend.add(
      <bool>[for (final f in request.files) File(f.path).existsSync()],
    );
    final failure = error;
    if (failure != null) throw failure;
    final pending = hold;
    if (pending != null) return pending.future;
    return outcome;
  }
}

/// A temporary folder for one test.
class TempArea {
  TempArea() : root = Directory.systemTemp.createTempSync('share_test_');

  final Directory root;

  Directory get staging => Directory('${root.path}/staging');
  Directory get cache => Directory('${root.path}/cache')..createSync();

  File writeCacheFile(String name, List<int> bytes) {
    final file = File('${cache.path}/$name')..writeAsBytesSync(bytes);
    return file;
  }

  void dispose() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  }
}

SharePreparer newPreparer(TempArea area, {DateTime Function()? now}) =>
    SharePreparer(stagingRoot: () async => area.staging, now: now);

/// A fetcher whose local lookup, cached links and HTTP client are all fakes.
ShareMediaFetcher newFetcher({
  Future<String?> Function(String key)? localPath,
  String? Function(String key)? cachedLink,
  required http.Client client,
  int? maxImageBytes,
  int? maxVideoBytes,
}) =>
    ShareMediaFetcher(
      localPath: localPath ?? (key) async => null,
      cachedLink: cachedLink ?? (key) => null,
      clientFactory: () => client,
      connectTimeout: const Duration(seconds: 5),
      idleTimeout: const Duration(seconds: 5),
      maxImageBytes: maxImageBytes ?? ShareMediaFetcher.defaultMaxImageBytes,
      maxVideoBytes: maxVideoBytes ?? ShareMediaFetcher.defaultMaxVideoBytes,
    );

ShareEngine newEngine(
  TempArea area,
  FakeShareSink sink, {
  required http.Client client,
  Future<String?> Function(String key)? localPath,
  String? Function(String key)? cachedLink,
  DateTime Function()? now,
}) =>
    ShareEngine(
      preparer: newPreparer(area, now: now),
      fetcher: newFetcher(
        client: client,
        localPath: localPath,
        cachedLink: cachedLink,
      ),
      launcher: ShareLauncher(sink),
    );
