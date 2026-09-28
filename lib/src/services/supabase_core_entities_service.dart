import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/models/ScreensModel/brokers_model.dart';
import '../data/models/ScreensModel/offers_model.dart';
import '../data/models/ScreensModel/offices_model.dart';
import '../data/models/ScreensModel/owners_model.dart';
import '../data/models/ScreensModel/request_model.dart';
import '../data/models/ScreensModel/watchmen_model.dart';
import '../data/models/property_status.dart';
import 'core_entity_mutation_notifier.dart';
import 'core_entity_payload_builder.dart';
import 'media_parent.dart';
import 'offer_media_cache_identity.dart';
import 'offer_media_url_cache.dart';
import 'offline_media_service.dart';
import 'r2_offer_media_upload_service.dart';

/// Supabase CRUD adapter for the six core Broker Wallet entity tables.
///
/// Every operation runs with the current authenticated Supabase session. RLS is
/// therefore the ownership/security boundary. Core rows use soft delete via
/// `deleted_at`; hard delete is intentionally not granted to client sessions.
class SupabaseCoreEntitiesService {
  SupabaseCoreEntitiesService({
    SupabaseClient? client,
    R2OfferMediaUploadService? offerMedia,
    R2OfferMediaUploadService? ownerMedia,
  })  : _client = client ?? Supabase.instance.client,
        _offerMedia = offerMedia ?? R2OfferMediaUploadService(),
        _ownerMediaOverride = ownerMedia;

  final SupabaseClient _client;
  final R2OfferMediaUploadService _offerMedia;
  final R2OfferMediaUploadService? _ownerMediaOverride;

  /// The Owner-media routes of the same Worker, created on first use and
  /// bound to this service's client.
  late final R2OfferMediaUploadService _ownerMedia = _ownerMediaOverride ??
      R2OfferMediaUploadService(
        supabaseClient: _client,
        parent: MediaParent.owner,
      );
  static const Uuid _uuid = Uuid();

  String generateId() => _uuid.v4();

  String _requireUserId() {
    final id = _client.auth.currentUser?.id;
    if (id == null || id.isEmpty) {
      throw StateError('A Supabase session is required.');
    }
    return id;
  }

  DateTime _date(dynamic value) {
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value?.toString() ?? '')?.toLocal() ??
        DateTime.now();
  }

  int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double? _doubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  String _numberText(dynamic value) {
    if (value == null) return '';
    if (value is num && value % 1 == 0) return value.toInt().toString();
    return value.toString();
  }

  List<String> _areas(dynamic raw) {
    final rows = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) rows.add(Map<String, dynamic>.from(item));
      }
    }
    rows.sort((a, b) => _int(a['ordinal']).compareTo(_int(b['ordinal'])));
    return rows
        .map((row) => row['area']?.toString() ?? '')
        .where((area) => area.isNotEmpty)
        .toList(growable: false);
  }

  /// The rows now, then again after every core-entity mutation in this
  /// process.
  ///
  /// Mutations are listened to before the first read starts, so one that
  /// lands while a read is in flight, or just after a list was delivered, is
  /// never missed. Reads run one at a time; mutations during a read cause one
  /// more read after it. A failed re-read is delivered as an error event and
  /// the stream keeps listening, so one transient failure does not end a
  /// screen's live updates. A failed first read has nothing to fall back to
  /// and ends the stream as before. Cancelling stops listening at once; a
  /// read still in flight is discarded. (An `async*` generator could do
  /// neither: it subscribed only after the first list was delivered, and a
  /// cancel could not stop it while it awaited the next mutation.)
  Stream<List<T>> _refreshedStream<T>(Future<List<T>> Function() fetch) {
    late final StreamController<List<T>> controller;
    StreamSubscription<void>? mutations;
    var reading = false;
    var readAgain = false;
    var delivered = false;

    Future<void>? stopListening() {
      final subscription = mutations;
      mutations = null;
      return subscription?.cancel();
    }

    Future<void> read() async {
      if (reading) {
        readAgain = true;
        return;
      }
      reading = true;
      do {
        readAgain = false;
        try {
          final rows = await fetch();
          if (!controller.hasListener) return;
          delivered = true;
          controller.add(rows);
        } catch (error, stackTrace) {
          if (!controller.hasListener) return;
          controller.addError(error, stackTrace);
          if (!delivered) {
            unawaited(stopListening());
            unawaited(controller.close());
            return;
          }
        }
      } while (readAgain);
      reading = false;
    }

    controller = StreamController<List<T>>(
      onListen: () {
        mutations =
            CoreEntityMutationNotifier.changes.listen((_) => unawaited(read()));
        unawaited(read());
      },
      onCancel: stopListening,
    );
    return controller.stream;
  }

  // -------------------------------------------------------------------------
  // Requests
  // -------------------------------------------------------------------------

  Future<String> saveRequest(RequestModel model, {String? requestId}) async {
    final ownerId = _requireUserId();
    final id = requestId ?? generateId();

    final payload = CoreEntityPayloadBuilder.request(
      model,
      id: id,
      ownerId: ownerId,
    );
    await _insert('request.create', 'requests', payload);

    try {
      await _replaceAreas(
          'request_areas', 'request_id', id, model.selectedAreas);
    } catch (error, stackTrace) {
      try {
        await _softDelete('requests', id);
        _debugLog('request.create', 'child write failed; parent rolled back');
      } catch (cleanupError, cleanupStackTrace) {
        _debugError('request.create.rollback', cleanupError, cleanupStackTrace);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    CoreEntityMutationNotifier.notify();
    return id;
  }

  Future<void> updateRequest(String id, RequestModel model) async {
    final ownerId = _requireUserId();
    final payload = CoreEntityPayloadBuilder.forUpdate(
      CoreEntityPayloadBuilder.request(model, id: id, ownerId: ownerId),
    );
    await _updateWithAreas(
      operation: 'request.update',
      table: 'requests',
      areaTable: 'request_areas',
      foreignKey: 'request_id',
      id: id,
      payload: payload,
      areas: model.selectedAreas,
    );
    CoreEntityMutationNotifier.notify();
  }

  Stream<List<RequestModel>> getRequests() => _refreshedStream(_fetchRequests);

  Future<List<RequestModel>> _fetchRequests() async {
    final ownerId = _requireUserId();
    final rows = await _client
        .from('requests')
        .select('''
          id, owner_id, request_type, selected_city, location_text,
          phone_number, country_code, min_price, max_price, square_footage,
          notes, property_type, specific_property_type, rooms, bathrooms,
          status, created_at, updated_at, request_areas(area, ordinal)
        ''')
        .eq('owner_id', ownerId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return rows.map(_requestFromRow).toList(growable: false);
  }

  Future<RequestModel?> getRequest(String id) async {
    final ownerId = _requireUserId();
    final rows = await _client
        .from('requests')
        .select('''
          id, owner_id, request_type, selected_city, location_text,
          phone_number, country_code, min_price, max_price, square_footage,
          notes, property_type, specific_property_type, rooms, bathrooms,
          status, created_at, updated_at, request_areas(area, ordinal)
        ''')
        .eq('owner_id', ownerId)
        .eq('id', id)
        .isFilter('deleted_at', null)
        .limit(1);
    return rows.isEmpty ? null : _requestFromRow(rows.first);
  }

  RequestModel _requestFromRow(Map<String, dynamic> row) => RequestModel(
        id: row['id']?.toString(),
        userId: row['owner_id']?.toString() ?? '',
        requestType: row['request_type']?.toString() ?? 'rent',
        selectedCity: row['selected_city']?.toString() ?? '',
        selectedAreas: _areas(row['request_areas']),
        location: row['location_text']?.toString() ?? '',
        phoneNumber: row['phone_number']?.toString() ?? '',
        countryCode: row['country_code']?.toString() ?? '+971',
        minPrice: _numberText(row['min_price']),
        maxPrice: _numberText(row['max_price']),
        squareFootage: _numberText(row['square_footage']),
        notes: row['notes']?.toString() ?? '',
        propertyType: row['property_type']?.toString(),
        specificPropertyType: row['specific_property_type']?.toString() ?? '',
        rooms: _int(row['rooms']),
        bathrooms: _int(row['bathrooms']),
        status:
            PropertyStatus.fromString(row['status']?.toString() ?? 'active'),
        createdAt: _date(row['created_at']),
        updatedAt: _date(row['updated_at']),
      );

  Future<void> deleteRequest(String id) => _softDeleteAndNotify('requests', id);

  // -------------------------------------------------------------------------
  // Offers
  // -------------------------------------------------------------------------

  Future<String> saveOffer(OfferModel model, {String? offerId}) async {
    final ownerId = _requireUserId();
    final id = offerId ?? generateId();
    final payload = CoreEntityPayloadBuilder.offer(
      model,
      id: id,
      ownerId: ownerId,
    );
    await _insert('offer.create', 'offers', payload);
    try {
      await _replaceAreas('offer_areas', 'offer_id', id, model.selectedAreas);
    } catch (error, stackTrace) {
      try {
        await _softDelete('offers', id);
        _debugLog('offer.create', 'child write failed; parent rolled back');
      } catch (cleanupError, cleanupStackTrace) {
        _debugError('offer.create.rollback', cleanupError, cleanupStackTrace);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    CoreEntityMutationNotifier.notify();
    return id;
  }

  Future<void> updateOffer(String id, OfferModel model) async {
    final ownerId = _requireUserId();
    final payload = CoreEntityPayloadBuilder.forUpdate(
      CoreEntityPayloadBuilder.offer(model, id: id, ownerId: ownerId),
    );
    await _updateWithAreas(
      operation: 'offer.update',
      table: 'offers',
      areaTable: 'offer_areas',
      foreignKey: 'offer_id',
      id: id,
      payload: payload,
      areas: model.selectedAreas,
    );
    CoreEntityMutationNotifier.notify();
  }

  Stream<List<OfferModel>> getOffers() => _refreshedStream(_fetchOffers);

  Future<List<OfferModel>> _fetchOffers() async {
    final ownerId = _requireUserId();
    final rows = await _client
        .from('offers')
        .select('''
          id, owner_id, offer_type, selected_city, location_text,
          phone_number, country_code, min_price, max_price, square_footage,
          notes, property_type, specific_property_type, rooms, bathrooms,
          pickup_location_text, pickup_latitude, pickup_longitude,
          pickup_address, legacy_uploaded_file_name, status, created_at,
          updated_at, offer_areas(area, ordinal)
        ''')
        .eq('owner_id', ownerId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return rows.map(_offerFromRow).toList(growable: false);
  }

  /// Reads only the authoritative Offer row. Private-media URL signing is a
  /// separate operation so an otherwise usable details screen never waits on
  /// the media Worker before it can render.
  Future<OfferModel?> getOfferMetadata(String id) async {
    final ownerId = _requireUserId();
    final rows = await _client
        .from('offers')
        .select('''
          id, owner_id, offer_type, selected_city, location_text,
          phone_number, country_code, min_price, max_price, square_footage,
          notes, property_type, specific_property_type, rooms, bathrooms,
          pickup_location_text, pickup_latitude, pickup_longitude,
          pickup_address, legacy_uploaded_file_name, status, created_at,
          updated_at, offer_areas(area, ordinal)
        ''')
        .eq('owner_id', ownerId)
        .eq('id', id)
        .isFilter('deleted_at', null)
        .limit(1);
    if (_client.auth.currentUser?.id != ownerId) {
      throw StateError('The authenticated account changed during the read.');
    }
    if (rows.isEmpty) return null;
    return _offerFromRow(rows.first);
  }

  /// The signed-in account, or null when there is no session.
  ///
  /// Exposed so presentation can read this device's remembered Offer media for
  /// the *current* account without reaching into Supabase itself.
  String? get currentOwnerId => _client.auth.currentUser?.id;

  /// What this device already holds for [offerId], with no network at all.
  ///
  /// Synchronous: it is read while building Offer Details' first frame. Each
  /// entry carries its durable media id and, when the bytes are already on
  /// disk, the file holding them — which is what lets the image paint before
  /// any signed URL exists. Entries whose bytes are not held locally are
  /// dropped, so this never promises content it cannot draw.
  List<OfferMediaRef> cachedOfferMedia(String offerId) =>
      _cachedRecordMedia(offerId);

  /// What this device already holds for the Owner record [ownerRecordId],
  /// with no network at all; see [cachedOfferMedia].
  List<OfferMediaRef> cachedOwnerMedia(String ownerRecordId) =>
      _cachedRecordMedia(ownerRecordId);

  /// [cachedOfferMedia] for any record: the device's media catalogue is keyed
  /// by the account and the record's id (Offer and Owner ids are UUIDs, so
  /// they never share an entry).
  List<OfferMediaRef> _cachedRecordMedia(String recordId) {
    final ownerId = currentOwnerId;
    if (ownerId == null || ownerId.isEmpty) return const <OfferMediaRef>[];

    final offline = OfflineMediaService.instance;
    final ids = offline.readOfferMediaCatalog(
      ownerId: ownerId,
      offerId: recordId,
    );

    final refs = <OfferMediaRef>[];
    for (final id in ids) {
      final cacheKey = offerMediaCacheKey(ownerId: ownerId, mediaObjectId: id);
      if (cacheKey == null) continue;
      final path = _localPathFor(cacheKey);
      // A still-valid signed URL from earlier this session also draws at
      // once (a video, or a photo not on disk yet). Memory only.
      final cached = OfferMediaUrlCache.instance.get(cacheKey);
      final poster = _localPathFor(offerMediaPosterKey(cacheKey));
      if (path == null && cached == null && poster == null) continue;
      refs.add(OfferMediaRef(
        mediaObjectId: id,
        cacheKey: cacheKey,
        localFilePath: path,
        signedUrl: cached?.url,
        isVideo: cached?.isVideo ?? (path == null && poster != null),
        durationMs: cached?.durationMs,
        posterPath: poster,
      ));
    }
    return refs;
  }

  /// Resolves the current confirmed private media for an Offer.
  ///
  /// Needs only the Offer id and the owning account, never the Offer row, so
  /// it can run *concurrently* with the authoritative metadata read instead of
  /// waiting behind it. Ownership is still enforced twice: the live session
  /// must match [ownerId] here, and the Worker independently re-verifies
  /// ownership server-side before it signs anything.
  ///
  /// Media ids and URLs come from one response and are replaced atomically, so
  /// an empty response clears old media instead of retaining stale URLs.
  ///
  /// On success the durable ids are remembered for this account and the bytes
  /// are warmed into the shared image cache under their stable key, which is
  /// what makes the next open instant.
  Future<OfferMediaResolution> resolveOfferMedia({
    required String offerId,
    required String ownerId,
  }) =>
      _resolveRecordMedia(
        media: _offerMedia,
        recordId: offerId,
        ownerId: ownerId,
        recordName: 'Offer',
      );

  /// Resolves the current confirmed private media of the Owner record
  /// [ownerRecordId], exactly as [resolveOfferMedia] does for an Offer —
  /// through the Worker's Owner routes, which verify ownership of the Owner
  /// record server-side. The resolution's `offerId` is the Owner record's id.
  Future<OfferMediaResolution> resolveOwnerMedia({
    required String ownerRecordId,
    required String ownerId,
  }) =>
      _resolveRecordMedia(
        media: _ownerMedia,
        recordId: ownerRecordId,
        ownerId: ownerId,
        recordName: 'Owner',
      );

  Future<OfferMediaResolution> _resolveRecordMedia({
    required R2OfferMediaUploadService media,
    required String recordId,
    required String ownerId,
    required String recordName,
  }) async {
    final id = recordId.trim();
    if (id.isEmpty) {
      throw StateError('$recordName identity is required.');
    }
    final sessionOwnerId = _requireUserId();
    if (ownerId.isEmpty || ownerId != sessionOwnerId) {
      throw StateError('The current session does not own this $recordName.');
    }

    final List<R2OfferMediaItem> mediaItems;
    try {
      mediaItems = await media.getOfferMedia(id);
    } on R2OfferMediaHttpException catch (error) {
      throw await _classifyMediaFailure(error, id, sessionOwnerId);
    } catch (_) {
      // Offline, a timeout, or anything else that establishes nothing about
      // this account's access. Locally held media is left exactly as it is.
      throw const OfferMediaException(OfferMediaFailureKind.transient);
    }
    if (_client.auth.currentUser?.id != sessionOwnerId) {
      throw StateError(
        'The authenticated account changed during media resolution.',
      );
    }

    final refs = <OfferMediaRef>[
      for (final item in mediaItems)
        _refFor(
          ownerId: sessionOwnerId,
          mediaObjectId: item.mediaObjectId,
          signedUrl: item.url,
          isVideo: item.mediaType == 'video',
          durationMs: item.durationMs,
        ),
    ];
    // Transport, held in memory only until shortly before it expires, so a
    // reopened Offer or a video tapped to play need not wait for a new one.
    for (var i = 0; i < refs.length; i++) {
      final cacheKey = refs[i].cacheKey;
      final expiresAt = mediaItems[i].expiresAt;
      if (cacheKey == null || expiresAt == null) continue;
      OfferMediaUrlCache.instance.put(
        cacheKey,
        mediaItems[i].url,
        expiresAt,
        isVideo: refs[i].isVideo,
        durationMs: refs[i].durationMs,
      );
    }

    unawaited(_rememberOfferMediaCatalog(id, sessionOwnerId, refs));
    return OfferMediaResolution(
      offerId: id,
      ownerId: sessionOwnerId,
      items: refs,
    );
  }

  /// Turns a Worker status into the one classification presentation may act
  /// on, and removes locally held bytes only when access is actually proven
  /// gone.
  ///
  /// The Worker answers 404 for "no such Offer for this account" only after
  /// its ownership query has succeeded and returned no row; an upstream
  /// failure answers 502 instead. A 401 means the access token was rejected,
  /// which is a session problem and never proof that access to this Offer was
  /// revoked, so it deletes nothing.
  ///
  /// An expired signed R2 URL cannot reach this code at all: that 403 is
  /// raised by R2 while the image itself is being fetched, on the cache
  /// manager's path, never on this Worker API call.
  Future<OfferMediaException> _classifyMediaFailure(
    R2OfferMediaHttpException error,
    String offerId,
    String ownerId,
  ) async {
    if (error.isUnauthenticated) {
      return const OfferMediaException(OfferMediaFailureKind.unauthenticated);
    }
    if (!error.isAccessDenied) {
      return const OfferMediaException(OfferMediaFailureKind.transient);
    }
    if (_client.auth.currentUser?.id != ownerId) {
      // The account changed while the request was in flight, so this answer
      // says nothing about either account. Remove nothing.
      return const OfferMediaException(OfferMediaFailureKind.transient);
    }
    await _forgetOfferMediaLocally(offerId, ownerId);
    return const OfferMediaException(OfferMediaFailureKind.accessDenied);
  }

  /// Drops this device's copy of one Offer's media for [ownerId].
  ///
  /// Scoped to that account and that Offer: another account's originals and
  /// this account's other Offers are untouched.
  Future<void> _forgetOfferMediaLocally(String offerId, String ownerId) async {
    final offline = OfflineMediaService.instance;
    try {
      await offline.reconcileOfferMediaCatalog(
        ownerId: ownerId,
        offerId: offerId,
        mediaObjectIds: const <String>[],
      );
    } catch (e) {
      _debugLog('offer.media', 'local media removal incomplete');
    }
  }

  /// One media item with its stable key and, when the bytes are already on
  /// this device, the file holding them — so the display layer can prefer
  /// local bytes over re-fetching a URL it was just handed.
  OfferMediaRef _refFor({
    required String ownerId,
    required String mediaObjectId,
    String? signedUrl,
    bool isVideo = false,
    int? durationMs,
  }) {
    final cacheKey = offerMediaCacheKey(
      ownerId: ownerId,
      mediaObjectId: mediaObjectId,
    );
    return OfferMediaRef(
      mediaObjectId: mediaObjectId,
      cacheKey: cacheKey,
      signedUrl: signedUrl,
      localFilePath: isVideo ? null : _localPathFor(cacheKey),
      isVideo: isVideo,
      durationMs: durationMs,
      posterPath: isVideo && cacheKey != null
          ? _localPathFor(offerMediaPosterKey(cacheKey))
          : null,
    );
  }

  /// The local file holding [cacheKey]'s bytes, if this device still has it.
  String? _localPathFor(String? cacheKey) {
    if (cacheKey == null) return null;
    final path =
        OfflineMediaService.instance.getLocalFilePathForMediaId(cacheKey);
    if (path == null || path.isEmpty) return null;
    return File(path).existsSync() ? path : null;
  }

  /// Persists the durable identity of [refs] for this account.
  ///
  /// Only the identity, never the bytes: this runs on every Offer Details
  /// open, and downloading an entire gallery the viewer may never scroll to
  /// would spend their data to fill a cache. The bytes are fetched by the
  /// gallery for what it actually shows, under this same identity.
  ///
  /// Best effort and off the critical path — the screen has already rendered
  /// from the signed URLs by the time this matters. Its only job is to let the
  /// *next* open find those bytes without a network round trip first.
  Future<void> _rememberOfferMediaCatalog(
    String offerId,
    String ownerId,
    List<OfferMediaRef> refs,
  ) async {
    try {
      // Replaces the remembered set and removes whatever this response no
      // longer lists; display order is preserved by passing the ordered list.
      await OfflineMediaService.instance.reconcileOfferMediaCatalog(
        ownerId: ownerId,
        offerId: offerId,
        mediaObjectIds: [for (final ref in refs) ref.mediaObjectId],
      );
    } catch (e) {
      _debugLog('offer.media', 'media catalogue update skipped');
    }
  }

  /// Legacy whole-model contract used by list, Favorites, search and edit
  /// callers. Offer Details uses the split reads above instead.
  Future<OfferModel> resolveOfferMediaFor(OfferModel offer) async {
    final media = await resolveOfferMedia(
      offerId: offer.id?.trim() ?? '',
      ownerId: offer.userId,
    );
    return applyOfferMedia(offer, media);
  }

  Future<OfferModel?> getOffer(String id) async {
    final offer = await getOfferMetadata(id);
    if (offer == null) return null;

    // Single-offer reads (detail/edit screens, Favorites cards, search
    // results) populate real signed media URLs; the bulk list fetch below
    // deliberately does not, to avoid an unbounded fan-out of per-offer
    // Worker calls for a whole list at once. Existing callers retain the
    // historical best-effort contract: metadata still returns if media
    // resolution fails. Offer Details uses the strict split methods above so
    // it can present a localized, recoverable media error instead.
    try {
      return await resolveOfferMediaFor(offer);
    } catch (_) {
      if (_client.auth.currentUser?.id != offer.userId) return null;
      _debugLog('offer.media', 'media fetch failed for display');
      return offer;
    }
  }

  OfferModel _offerFromRow(Map<String, dynamic> row) => OfferModel(
        id: row['id']?.toString(),
        userId: row['owner_id']?.toString() ?? '',
        offerType: row['offer_type']?.toString() ?? 'rent',
        selectedCity: row['selected_city']?.toString() ?? '',
        selectedAreas: _areas(row['offer_areas']),
        location: row['location_text']?.toString() ?? '',
        phoneNumber: row['phone_number']?.toString() ?? '',
        countryCode: row['country_code']?.toString() ?? '+971',
        minPrice: _numberText(row['min_price']),
        maxPrice: _numberText(row['max_price']),
        squareFootage: _numberText(row['square_footage']),
        notes: row['notes']?.toString() ?? '',
        propertyType: row['property_type']?.toString(),
        specificPropertyType: row['specific_property_type']?.toString() ?? '',
        rooms: _int(row['rooms']),
        bathrooms: _int(row['bathrooms']),
        pickUpLocation: row['pickup_location_text']?.toString() ?? '',
        pickUpLatitude: _doubleOrNull(row['pickup_latitude']),
        pickUpLongitude: _doubleOrNull(row['pickup_longitude']),
        pickUpAddress: row['pickup_address']?.toString() ?? '',
        uploadedFileName: row['legacy_uploaded_file_name']?.toString() ?? '',
        mediaUrl: null,
        mediaUrls: const <String>[],
        status:
            PropertyStatus.fromString(row['status']?.toString() ?? 'available'),
        createdAt: _date(row['created_at']),
        updatedAt: _date(row['updated_at']),
      );

  Future<void> deleteOffer(String id) => _softDeleteAndNotify('offers', id);

  // -------------------------------------------------------------------------
  // Owners
  // -------------------------------------------------------------------------

  Future<String> saveOwner(OwnerModel model, {String? ownerRecordId}) async {
    final ownerId = _requireUserId();
    final id = ownerRecordId ?? generateId();
    final payload = CoreEntityPayloadBuilder.owner(
      model,
      id: id,
      ownerId: ownerId,
    );
    await _insert('owner.create', 'owners', payload);
    CoreEntityMutationNotifier.notify();
    return id;
  }

  Future<void> updateOwner(String id, OwnerModel model) async {
    final ownerId = _requireUserId();
    final payload = CoreEntityPayloadBuilder.forUpdate(
      CoreEntityPayloadBuilder.owner(model, id: id, ownerId: ownerId),
    );
    await _update('owner.update', 'owners', id, payload);
    CoreEntityMutationNotifier.notify();
  }

  Stream<List<OwnerModel>> getOwners() => _refreshedStream(_fetchOwners);

  Future<List<OwnerModel>> _fetchOwners() async {
    final ownerId = _requireUserId();
    final rows = await _client
        .from('owners')
        .select()
        .eq('owner_id', ownerId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return rows.map(_ownerFromRow).toList(growable: false);
  }

  Future<OwnerModel?> getOwner(String id) async {
    final ownerId = _requireUserId();
    final rows = await _client
        .from('owners')
        .select()
        .eq('owner_id', ownerId)
        .eq('id', id)
        .isFilter('deleted_at', null)
        .limit(1);
    return rows.isEmpty ? null : _ownerFromRow(rows.first);
  }

  OwnerModel _ownerFromRow(Map<String, dynamic> row) => OwnerModel(
        id: row['id']?.toString(),
        userId: row['owner_id']?.toString() ?? '',
        name: row['name']?.toString() ?? '',
        phoneNumber: row['phone_number']?.toString() ?? '',
        countryCode: row['country_code']?.toString() ?? '+971',
        typeOfProperties: row['property_type_text']?.toString() ?? '',
        propertyLocation: row['property_location']?.toString() ?? '',
        notes: row['notes']?.toString() ?? '',
        pickUpLocation: row['pickup_location_text']?.toString() ?? '',
        pickUpLatitude: _doubleOrNull(row['pickup_latitude']),
        pickUpLongitude: _doubleOrNull(row['pickup_longitude']),
        pickUpAddress: row['pickup_address']?.toString() ?? '',
        uploadedFileName: row['legacy_uploaded_file_name']?.toString(),
        mediaUrl: null,
        mediaUrls: const <String>[],
        createdAt: _date(row['created_at']),
        updatedAt: _date(row['updated_at']),
      );

  Future<void> deleteOwner(String id) => _softDeleteAndNotify('owners', id);

  // -------------------------------------------------------------------------
  // Offices
  // -------------------------------------------------------------------------

  Future<String> saveOffice(OfficeModel model) async {
    final ownerId = _requireUserId();
    final id = generateId();
    final payload = CoreEntityPayloadBuilder.office(
      model,
      id: id,
      ownerId: ownerId,
    );
    await _insert('office.create', 'offices', payload);
    CoreEntityMutationNotifier.notify();
    return id;
  }

  Future<void> updateOffice(String id, OfficeModel model) async {
    final ownerId = _requireUserId();
    final payload = CoreEntityPayloadBuilder.forUpdate(
      CoreEntityPayloadBuilder.office(model, id: id, ownerId: ownerId),
    );
    await _update('office.update', 'offices', id, payload);
    CoreEntityMutationNotifier.notify();
  }

  Stream<List<OfficeModel>> getOffices() => _refreshedStream(_fetchOffices);

  Future<List<OfficeModel>> _fetchOffices() async {
    final ownerId = _requireUserId();
    final rows = await _client
        .from('offices')
        .select()
        .eq('owner_id', ownerId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return rows.map(_officeFromRow).toList(growable: false);
  }

  Future<OfficeModel?> getOffice(String id) async {
    final ownerId = _requireUserId();
    final rows = await _client
        .from('offices')
        .select()
        .eq('owner_id', ownerId)
        .eq('id', id)
        .isFilter('deleted_at', null)
        .limit(1);
    return rows.isEmpty ? null : _officeFromRow(rows.first);
  }

  OfficeModel _officeFromRow(Map<String, dynamic> row) => OfficeModel(
        id: row['id']?.toString(),
        userId: row['owner_id']?.toString(),
        officeName: row['office_name']?.toString() ?? '',
        managerName: row['manager_name']?.toString() ?? '',
        countryCode: row['country_code']?.toString() ?? '+971',
        phoneNumber: row['phone_number']?.toString() ?? '',
        officeLocation: row['office_location']?.toString() ?? '',
        notes: row['notes']?.toString() ?? '',
        pickUpLocation: row['pickup_location_text']?.toString() ?? '',
        pickUpLatitude: _doubleOrNull(row['pickup_latitude']),
        pickUpLongitude: _doubleOrNull(row['pickup_longitude']),
        pickUpAddress: row['pickup_address']?.toString() ?? '',
        createdAt: _date(row['created_at']),
        updatedAt: _date(row['updated_at']),
      );

  Future<void> deleteOffice(String id) => _softDeleteAndNotify('offices', id);

  // -------------------------------------------------------------------------
  // Brokers
  // -------------------------------------------------------------------------

  Future<String> saveBroker(BrokerModel model) async {
    final ownerId = _requireUserId();
    final id = generateId();
    final payload = CoreEntityPayloadBuilder.broker(
      model,
      id: id,
      ownerId: ownerId,
    );
    await _insert('broker.create', 'brokers', payload);
    CoreEntityMutationNotifier.notify();
    return id;
  }

  Future<void> updateBroker(String id, BrokerModel model) async {
    final ownerId = _requireUserId();
    final payload = CoreEntityPayloadBuilder.forUpdate(
      CoreEntityPayloadBuilder.broker(model, id: id, ownerId: ownerId),
    );
    await _update('broker.update', 'brokers', id, payload);
    CoreEntityMutationNotifier.notify();
  }

  Stream<List<BrokerModel>> getBrokers() => _refreshedStream(_fetchBrokers);

  Future<List<BrokerModel>> _fetchBrokers() async {
    final ownerId = _requireUserId();
    final rows = await _client
        .from('brokers')
        .select()
        .eq('owner_id', ownerId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return rows.map(_brokerFromRow).toList(growable: false);
  }

  Future<BrokerModel?> getBroker(String id) async {
    final ownerId = _requireUserId();
    final rows = await _client
        .from('brokers')
        .select()
        .eq('owner_id', ownerId)
        .eq('id', id)
        .isFilter('deleted_at', null)
        .limit(1);
    return rows.isEmpty ? null : _brokerFromRow(rows.first);
  }

  BrokerModel _brokerFromRow(Map<String, dynamic> row) => BrokerModel(
        id: row['id']?.toString(),
        userId: row['owner_id']?.toString(),
        name: row['name']?.toString() ?? '',
        countryCode: row['country_code']?.toString() ?? '+971',
        phoneNumber: row['phone_number']?.toString() ?? '',
        notes: row['notes']?.toString() ?? '',
        createdAt: _date(row['created_at']),
        updatedAt: _date(row['updated_at']),
      );

  Future<void> deleteBroker(String id) => _softDeleteAndNotify('brokers', id);

  // -------------------------------------------------------------------------
  // Watchmen
  // -------------------------------------------------------------------------

  Future<String> saveWatchman(WatchmenModel model) async {
    final ownerId = _requireUserId();
    final id = generateId();
    final payload = CoreEntityPayloadBuilder.watchman(
      model,
      id: id,
      ownerId: ownerId,
    );
    await _insert('watchman.create', 'watchmen', payload);
    CoreEntityMutationNotifier.notify();
    return id;
  }

  Future<void> updateWatchman(String id, WatchmenModel model) async {
    final ownerId = _requireUserId();
    final payload = CoreEntityPayloadBuilder.forUpdate(
      CoreEntityPayloadBuilder.watchman(model, id: id, ownerId: ownerId),
    );
    await _update('watchman.update', 'watchmen', id, payload);
    CoreEntityMutationNotifier.notify();
  }

  Stream<List<WatchmenModel>> getWatchmen() => _refreshedStream(_fetchWatchmen);

  Future<List<WatchmenModel>> _fetchWatchmen() async {
    final ownerId = _requireUserId();
    final rows = await _client
        .from('watchmen')
        .select()
        .eq('owner_id', ownerId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return rows.map(_watchmanFromRow).toList(growable: false);
  }

  Future<WatchmenModel?> getWatchman(String id) async {
    final ownerId = _requireUserId();
    final rows = await _client
        .from('watchmen')
        .select()
        .eq('owner_id', ownerId)
        .eq('id', id)
        .isFilter('deleted_at', null)
        .limit(1);
    return rows.isEmpty ? null : _watchmanFromRow(rows.first);
  }

  WatchmenModel _watchmanFromRow(Map<String, dynamic> row) => WatchmenModel(
        id: row['id']?.toString(),
        userId: row['owner_id']?.toString(),
        name: row['name']?.toString() ?? '',
        countryCode: row['country_code']?.toString() ?? '+971',
        phoneNumber: row['phone_number']?.toString() ?? '',
        buildingName: row['building_name']?.toString() ?? '',
        notes: row['notes']?.toString() ?? '',
        buildingLocation: row['building_location']?.toString() ?? '',
        pickUpLocation: row['pickup_location_text']?.toString() ?? '',
        pickUpLatitude: _doubleOrNull(row['pickup_latitude']),
        pickUpLongitude: _doubleOrNull(row['pickup_longitude']),
        pickUpAddress: row['pickup_address']?.toString() ?? '',
        createdAt: _date(row['created_at']),
        updatedAt: _date(row['updated_at']),
      );

  Future<void> deleteWatchman(String id) =>
      _softDeleteAndNotify('watchmen', id);

  Future<void> _replaceAreas(
    String table,
    String foreignKey,
    String parentId,
    List<String> areas,
  ) async {
    final normalizedAreas = CoreEntityPayloadBuilder.areas(areas);
    try {
      await _client.from(table).delete().eq(foreignKey, parentId);
      if (normalizedAreas.isEmpty) return;
      await _client.from(table).insert([
        for (var i = 0; i < normalizedAreas.length; i++)
          {foreignKey: parentId, 'ordinal': i, 'area': normalizedAreas[i]},
      ]);
      _debugLog('$table.replace',
          'child write succeeded count=${normalizedAreas.length}');
    } catch (error, stackTrace) {
      _debugError('$table.replace', error, stackTrace);
      rethrow;
    }
  }

  Future<void> _insert(
    String operation,
    String table,
    Map<String, dynamic> payload,
  ) async {
    _debugLog(operation, 'insert payload keys=${payload.keys.join(',')}');
    try {
      await _client.from(table).insert(payload);
      _debugLog(operation, 'parent insert succeeded');
    } catch (error, stackTrace) {
      _debugError(operation, error, stackTrace);
      rethrow;
    }
  }

  Future<void> _update(
    String operation,
    String table,
    String id,
    Map<String, dynamic> payload,
  ) async {
    _debugLog(operation, 'update payload keys=${payload.keys.join(',')}');
    try {
      await _client.from(table).update(payload).eq('id', id);
      _debugLog(operation, 'parent update succeeded');
    } catch (error, stackTrace) {
      _debugError(operation, error, stackTrace);
      rethrow;
    }
  }

  Future<void> _updateWithAreas({
    required String operation,
    required String table,
    required String areaTable,
    required String foreignKey,
    required String id,
    required Map<String, dynamic> payload,
    required List<String> areas,
  }) async {
    final oldRows = await _client
        .from(areaTable)
        .select('area')
        .eq(foreignKey, id)
        .order('ordinal');
    final oldAreas = oldRows
        .map((row) => row['area']?.toString() ?? '')
        .where((area) => area.isNotEmpty)
        .toList(growable: false);
    await _replaceAreas(areaTable, foreignKey, id, areas);
    try {
      await _update(operation, table, id, payload);
    } catch (error, stackTrace) {
      try {
        await _replaceAreas(areaTable, foreignKey, id, oldAreas);
        _debugLog(operation, 'area rollback succeeded');
      } catch (rollbackError, rollbackStackTrace) {
        _debugError(
            '$operation.areaRollback', rollbackError, rollbackStackTrace);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void _debugLog(String operation, String message) {
    if (kDebugMode) {
      debugPrint('[SupabaseCoreEntitiesService][$operation] $message');
    }
  }

  void _debugError(String operation, Object error, StackTrace stackTrace) {
    if (!kDebugMode) return;
    if (error is PostgrestException) {
      debugPrint(
        '[SupabaseCoreEntitiesService][$operation] '
        'PostgrestException code=${error.code} message=${error.message} '
        'details=${error.details} hint=${error.hint}',
      );
    } else {
      debugPrint(
        '[SupabaseCoreEntitiesService][$operation] '
        '${error.runtimeType}: $error',
      );
    }
    debugPrintStack(stackTrace: stackTrace);
  }

  Future<void> _softDelete(String table, String id) async {
    _requireUserId();
    await _client.from(table).update(
        {'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
  }

  Future<void> _softDeleteAndNotify(String table, String id) async {
    await _softDelete(table, id);
    CoreEntityMutationNotifier.notify();
  }
}
