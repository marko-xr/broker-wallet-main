import 'dart:async';

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
import 'app_session_coordinator.dart';
import 'bounded_tasks.dart';
import 'core_entity_mutation_notifier.dart';
import 'core_entity_payload_builder.dart';
import 'list_session_check.dart';
import 'media_parent.dart';
import 'offer_media_cache_identity.dart';
import 'offer_media_url_cache.dart';
import 'offline_media_service.dart';
import 'private_media_images.dart';
import 'r2_offer_media_upload_service.dart';

/// How the media of an Offer read for display went (tracker §7AZ,
/// FU-FAV-OFFER-MEDIA-FAILURE, Option B): an Offer without media because its
/// media could not be read is not an Offer the Worker said has none.
enum DisplayMediaOutcome {
  /// The Worker answered: the Offer carries exactly what it listed, even none.
  resolved,

  /// The read failed for a temporary reason (no answer, no connection, a
  /// server error, an unreadable body); nothing was learned about the media.
  transient,

  /// The read was refused (the session, or access to the record): nothing
  /// held may be shown for it.
  refused,
}

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
  /// [fetch] is told whether its read is still wanted, so a read made of
  /// several requests can stop between them once the stream is cancelled.
  Stream<List<T>> _refreshedStream<T>(
      Future<List<T>> Function(bool Function() stillWanted) fetch) {
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
          final rows = await fetch(() => controller.hasListener);
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
    CoreEntityMutationNotifier.notify(CoreEntityKind.request);
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
    CoreEntityMutationNotifier.notify(CoreEntityKind.request);
  }

  Stream<List<RequestModel>> getRequests() => _refreshedStream(_fetchRequests);

  /// The same account-scoped, soft-delete-aware read as the Requests list,
  /// narrowed to the phone stored on the row. Related Items uses the legacy
  /// exact-match contract after cleaning the detail record's phone.
  Stream<List<RequestModel>> getRelatedRequests(String phoneNumber) =>
      _refreshedStream((_) async {
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
            .eq('phone_number', phoneNumber)
            .isFilter('deleted_at', null)
            .order('id', ascending: true)
            .limit(10);
        return rows.map(_requestFromRow).toList(growable: false);
      });

  /// The whole Requests list, read in pages (see [_wholeList]).
  Future<List<RequestModel>> _fetchRequests(bool Function() stillWanted) async {
    final rows = await _wholeList('requests', _requestColumns, stillWanted);
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

  Future<void> deleteRequest(String id) =>
      _softDeleteAndNotify('requests', id, CoreEntityKind.request);

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
    CoreEntityMutationNotifier.notify(CoreEntityKind.offer);
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
    CoreEntityMutationNotifier.notify(CoreEntityKind.offer);
  }

  Stream<List<OfferModel>> getOffers() => _refreshedStream(_fetchOffers);

  /// Related Items shares the Offers list's mapping and refresh lifecycle.
  Stream<List<OfferModel>> getRelatedOffers(String phoneNumber) =>
      _refreshedStream((_) async {
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
            .eq('phone_number', phoneNumber)
            .isFilter('deleted_at', null)
            .order('id', ascending: true)
            .limit(10);
        return rows.map(_offerFromRow).toList(growable: false);
      });

  /// Exact count is independent of the carousel's ten-row limit.
  Future<int> getRelatedItemsCount(String phoneNumber) async {
    final ownerId = _requireUserId();
    Future<int> count(String table) async {
      final response = await _client
          .from(table)
          .select('id')
          .eq('owner_id', ownerId)
          .eq('phone_number', phoneNumber)
          .isFilter('deleted_at', null)
          .count(CountOption.exact);
      return response.count;
    }

    return (await count('offers')) + (await count('requests'));
  }

  /// The whole Offers list, read in pages (see [_wholeList]). Rows only:
  /// media is resolved per Offer where it is shown, never for the list.
  Future<List<OfferModel>> _fetchOffers(bool Function() stillWanted) async {
    final rows = await _wholeList('offers', _offerColumns, stillWanted);
    return rows.map(_offerFromRow).toList(growable: false);
  }

  /// Reads only the authoritative Offer row. Private-media URL signing is a
  /// separate operation so an otherwise usable details screen never waits on
  /// the media Worker before it can render.
  Future<OfferModel?> getOfferMetadata(String id) async {
    final ownerId = _requireUserId();
    final rows = await _client
        .from('offers')
        .select(_offerColumns)
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

  /// What this device holds for [recordId] by its saved list's media identity
  /// [ids] (`listedMediaObjectIds`, tracker §7AZ, M2-3b) — for Offer and Owner
  /// records alike. Synchronous, with no network, for the first frame.
  ///
  /// Used only when the device has no catalogue entry for the record at all:
  /// an entry, even an empty one, is a Worker answer this device received and
  /// wins (D-M2-3-1, D-M2-3-3) — the saved ids are never merged with it. Only
  /// for a record of the signed-in account ([ownerId]), only keys its
  /// authorized session may read, and only items whose bytes are on disk:
  /// never a link, never a placeholder for bytes not held. Empty [ids] — an
  /// older saved list, a copy that does not keep them, or an invalid field —
  /// prove nothing and give nothing.
  List<OfferMediaRef> listedRecordMedia(
    String recordId, {
    required String ownerId,
    required List<String> ids,
  }) {
    final owner = _listedOwner(recordId, ownerId, ids);
    if (owner == null) return const <OfferMediaRef>[];
    return <OfferMediaRef>[
      for (final id in ids)
        if (_heldNowRef(owner, id) case final ref?) ref,
    ];
  }

  /// The items of [recordId] this device holds, found with no network: those
  /// [listedRecordMedia] or the catalogue seed draw at once, and those whose
  /// bytes are in the private image cache with no mapping (M2-3b, D-M2-3-2).
  ///
  /// Follows the catalogue when the device has an entry for the record, else
  /// the saved [ids] under the same conditions as [listedRecordMedia]; keeps
  /// that order. Read only: no download, no signed link, no mapping or
  /// catalogue write (the image itself records its mapping when it is shown,
  /// as before). Returns nothing once the account or its session changed
  /// while it waited.
  Future<List<OfferMediaRef>> discoverHeldRecordMedia(
    String recordId, {
    required String ownerId,
    required List<String> ids,
  }) async {
    final owner = currentOwnerId?.trim();
    if (owner == null || owner.isEmpty || ownerId.trim() != owner) {
      return const <OfferMediaRef>[];
    }
    final offline = OfflineMediaService.instance;
    final List<String> order;
    if (offline.hasOfferMediaCatalog(ownerId: owner, offerId: recordId)) {
      order = offline.readOfferMediaCatalog(ownerId: owner, offerId: recordId);
    } else {
      order = _listedOwner(recordId, ownerId, ids) == null ? const [] : ids;
    }
    if (order.isEmpty) return const <OfferMediaRef>[];

    final found = <OfferMediaRef>[];
    for (final id in order) {
      final now = _heldNowRef(owner, id);
      if (now != null) {
        found.add(now);
        continue;
      }
      final key = offerMediaCacheKey(ownerId: owner, mediaObjectId: id);
      if (key == null || !PrivateMediaImages.canRead(key)) continue;
      final file = await PrivateMediaImages.heldInPrivateCache(key);
      if (currentOwnerId != owner || !PrivateMediaImages.canRead(key)) {
        return const <OfferMediaRef>[];
      }
      if (file == null) continue;
      found.add(OfferMediaRef(
        mediaObjectId: id,
        cacheKey: key,
        localFilePath: file.path,
      ));
    }
    return found;
  }

  /// The signed-in account when [ids] may be used for [recordId]: a record of
  /// that account, with saved ids, and no catalogue entry on this device.
  String? _listedOwner(String recordId, String ownerId, List<String> ids) {
    final owner = currentOwnerId?.trim();
    if (owner == null || owner.isEmpty || ownerId.trim() != owner) return null;
    if (recordId.trim().isEmpty || ids.isEmpty) return null;
    if (OfflineMediaService.instance
        .hasOfferMediaCatalog(ownerId: owner, offerId: recordId)) {
      return null;
    }
    return owner;
  }

  /// [id]'s item when its bytes (or a video's still frame) are on disk now
  /// and the authorized session may read its key; null otherwise.
  OfferMediaRef? _heldNowRef(String owner, String id) {
    final key = offerMediaCacheKey(ownerId: owner, mediaObjectId: id);
    if (key == null || !PrivateMediaImages.canRead(key)) return null;
    final path = _localPathFor(key);
    final poster = _localPathFor(offerMediaPosterKey(key));
    if (path == null && poster == null) return null;
    return OfferMediaRef(
      mediaObjectId: id,
      cacheKey: key,
      localFilePath: path,
      isVideo: path == null,
      posterPath: poster,
    );
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
      throw await _classifyMediaFailure(media, error, id, sessionOwnerId);
    } on R2OfferMediaContractException {
      // A 200 that is not the complete media list proves nothing: nothing is
      // reconciled from it (tracker §7AZ, Option C, D-FOMF-4).
      _debugLog('offer.media', 'media answer incomplete');
      throw const OfferMediaException(OfferMediaFailureKind.inconclusive);
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
  /// The Worker answers a 404 with the route's own not-found code
  /// (`offer_not_found`, `owner_not_found`) only after its ownership query has
  /// succeeded and returned no row; an upstream failure answers 502 instead.
  /// That is the only answer here that removes anything (tracker §7AZ,
  /// Option C, D-FOMF-2/3):
  ///  * 401 and any 403 — a superseded session included — are about the
  ///    session, never the record: `unauthenticated`, nothing removed;
  ///  * any other 4xx — a 404 without the route's code among them — proves
  ///    nothing: `inconclusive`, nothing removed;
  ///  * anything else (5xx, an unexpected status): `transient`.
  ///
  /// An expired signed R2 URL cannot reach this code at all: that 403 is
  /// raised by R2 while the image itself is being fetched, on the cache
  /// manager's path, never on this Worker API call.
  Future<OfferMediaException> _classifyMediaFailure(
    R2OfferMediaUploadService media,
    R2OfferMediaHttpException error,
    String offerId,
    String ownerId,
  ) async {
    if (error.isSessionRefused) {
      return const OfferMediaException(OfferMediaFailureKind.unauthenticated);
    }
    if (!media.provesRecordGone(error)) {
      if (error.statusCode >= 400 && error.statusCode < 500) {
        _debugLog('offer.media', 'media answer inconclusive');
        return const OfferMediaException(OfferMediaFailureKind.inconclusive);
      }
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

  /// The local file holding [cacheKey]'s bytes, if this device still has it:
  /// the mapped file, or — when a private copy it was switched to is gone —
  /// the old-cache file it replaced (tracker §7AZ, M1d-2).
  String? _localPathFor(String? cacheKey) =>
      OfflineMediaService.instance.usableLocalPathForMediaId(cacheKey);

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
    return _withDisplayMedia(offer);
  }

  /// [offer] with its signed media, best effort.
  ///
  /// Single-offer reads (detail/edit screens, search results) and Favorites
  /// cards populate real signed media URLs; the bulk list fetch below
  /// deliberately does not, to avoid an unbounded fan-out of per-offer
  /// Worker calls for a whole list at once. Existing callers retain the
  /// historical best-effort contract: metadata still returns if media
  /// resolution fails. Offer Details uses the strict split methods above so
  /// it can present a localized, recoverable media error instead.
  ///
  /// How the media read went is kept with the Offer returned
  /// ([displayMediaOutcomeOf]), so a caller never has to read "no media"
  /// into an Offer whose media could not be read (tracker §7AZ,
  /// FU-FAV-OFFER-MEDIA-FAILURE, Option B).
  Future<OfferModel?> _withDisplayMedia(OfferModel offer) async {
    try {
      final resolved = await resolveOfferMediaFor(offer);
      _displayMediaOutcomes[resolved] = DisplayMediaOutcome.resolved;
      return resolved;
    } catch (error) {
      if (_client.auth.currentUser?.id != offer.userId) return null;
      _debugLog('offer.media', 'media fetch failed for display');
      _displayMediaOutcomes[offer] = error is OfferMediaException &&
              error.kind == OfferMediaFailureKind.transient
          ? DisplayMediaOutcome.transient
          : DisplayMediaOutcome.refused;
      return offer;
    }
  }

  static final Expando<DisplayMediaOutcome> _displayMediaOutcomes =
      Expando<DisplayMediaOutcome>('displayMediaOutcome');

  /// How the media of [offer] — an Offer this service returned from
  /// [getOffer] or [getOffersByIds] — was read; null for any other Offer.
  /// Kept with that exact object, never on disk.
  static DisplayMediaOutcome? displayMediaOutcomeOf(OfferModel offer) =>
      _displayMediaOutcomes[offer];

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
        listedMediaObjectIds: _readyMediaIds(row['offer_media']),
      );

  Future<void> deleteOffer(String id) =>
      _softDeleteAndNotify('offers', id, CoreEntityKind.offer);

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
    CoreEntityMutationNotifier.notify(CoreEntityKind.owner);
    return id;
  }

  Future<void> updateOwner(String id, OwnerModel model) async {
    final ownerId = _requireUserId();
    final payload = CoreEntityPayloadBuilder.forUpdate(
      CoreEntityPayloadBuilder.owner(model, id: id, ownerId: ownerId),
    );
    await _update('owner.update', 'owners', id, payload);
    CoreEntityMutationNotifier.notify(CoreEntityKind.owner);
  }

  Stream<List<OwnerModel>> getOwners() => _refreshedStream(_fetchOwners);

  /// The whole Owners list, read in pages (see [_wholeList]); rows only.
  Future<List<OwnerModel>> _fetchOwners(bool Function() stillWanted) async {
    final rows = await _wholeList('owners', _ownerColumns, stillWanted);
    return rows.map(_ownerFromRow).toList(growable: false);
  }

  Future<OwnerModel?> getOwner(String id) async {
    final ownerId = _requireUserId();
    final rows = await _client
        .from('owners')
        .select(_ownerColumns)
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
        listedMediaObjectIds: _readyMediaIds(row['owner_media']),
      );

  Future<void> deleteOwner(String id) =>
      _softDeleteAndNotify('owners', id, CoreEntityKind.owner);

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
    CoreEntityMutationNotifier.notify(CoreEntityKind.office);
    return id;
  }

  Future<void> updateOffice(String id, OfficeModel model) async {
    final ownerId = _requireUserId();
    final payload = CoreEntityPayloadBuilder.forUpdate(
      CoreEntityPayloadBuilder.office(model, id: id, ownerId: ownerId),
    );
    await _update('office.update', 'offices', id, payload);
    CoreEntityMutationNotifier.notify(CoreEntityKind.office);
  }

  Stream<List<OfficeModel>> getOffices() => _refreshedStream(_fetchOffices);

  /// The whole Offices list, read in pages (see [_wholeList]).
  Future<List<OfficeModel>> _fetchOffices(bool Function() stillWanted) async {
    final rows = await _wholeList('offices', '*', stillWanted);
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

  Future<void> deleteOffice(String id) =>
      _softDeleteAndNotify('offices', id, CoreEntityKind.office);

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
    CoreEntityMutationNotifier.notify(CoreEntityKind.broker);
    return id;
  }

  Future<void> updateBroker(String id, BrokerModel model) async {
    final ownerId = _requireUserId();
    final payload = CoreEntityPayloadBuilder.forUpdate(
      CoreEntityPayloadBuilder.broker(model, id: id, ownerId: ownerId),
    );
    await _update('broker.update', 'brokers', id, payload);
    CoreEntityMutationNotifier.notify(CoreEntityKind.broker);
  }

  Stream<List<BrokerModel>> getBrokers() => _refreshedStream(_fetchBrokers);

  /// The whole Brokers list, read in pages (see [_wholeList]).
  Future<List<BrokerModel>> _fetchBrokers(bool Function() stillWanted) async {
    final rows = await _wholeList('brokers', '*', stillWanted);
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

  Future<void> deleteBroker(String id) =>
      _softDeleteAndNotify('brokers', id, CoreEntityKind.broker);

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
    CoreEntityMutationNotifier.notify(CoreEntityKind.watchman);
    return id;
  }

  Future<void> updateWatchman(String id, WatchmenModel model) async {
    final ownerId = _requireUserId();
    final payload = CoreEntityPayloadBuilder.forUpdate(
      CoreEntityPayloadBuilder.watchman(model, id: id, ownerId: ownerId),
    );
    await _update('watchman.update', 'watchmen', id, payload);
    CoreEntityMutationNotifier.notify(CoreEntityKind.watchman);
  }

  Stream<List<WatchmenModel>> getWatchmen() => _refreshedStream(_fetchWatchmen);

  /// The whole Watchmen list, read in pages (see [_wholeList]).
  Future<List<WatchmenModel>> _fetchWatchmen(
      bool Function() stillWanted) async {
    final rows = await _wholeList('watchmen', '*', stillWanted);
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
      _softDeleteAndNotify('watchmen', id, CoreEntityKind.watchman);

  // -------------------------------------------------------------------------
  // Reads of several records by id (Favorites)
  // -------------------------------------------------------------------------

  /// Ids per request. Each id names at most one row, so a read never asks
  /// for more rows than this — well under the server's row cap — and the
  /// request line stays a few kilobytes.
  static const int _idsPerRead = 100;

  /// The same columns as [getRequest].
  static const String _requestColumns = '''
          id, owner_id, request_type, selected_city, location_text,
          phone_number, country_code, min_price, max_price, square_footage,
          notes, property_type, specific_property_type, rooms, bathrooms,
          status, created_at, updated_at, request_areas(area, ordinal)
        ''';

  /// The columns of every Offer read: the list, [getOfferMetadata] and the
  /// reads by id.
  ///
  /// `offer_media(…)` is the Offer's media identity (tracker §7AZ, M2-1): its
  /// link rows with only what decides which ids count — never an object key,
  /// a bucket or a link. A plain embed: an Offer with no link rows is still
  /// returned (with `[]`), and RLS and the session gate apply to the embedded
  /// rows as to the Offer. Which links count is decided by [_readyMediaIds].
  static const String _offerColumns = '''
          id, owner_id, offer_type, selected_city, location_text,
          phone_number, country_code, min_price, max_price, square_footage,
          notes, property_type, specific_property_type, rooms, bathrooms,
          pickup_location_text, pickup_latitude, pickup_longitude,
          pickup_address, legacy_uploaded_file_name, status, created_at,
          updated_at, offer_areas(area, ordinal),
          offer_media(media_id, ordinal, media_objects(status, content_type))
        ''';

  /// The columns of every Owner read: the list, [getOwner] and the reads by
  /// id — all of the row, and its media identity as for Offers.
  static const String _ownerColumns = '''
          *, owner_media(media_id, ordinal, media_objects(status, content_type))
        ''';

  /// The content types the media Worker lists for a record (its
  /// `OFFER_MEDIA_TYPES`, HEIC included: listed though no longer uploaded).
  static const Set<String> _listedMediaTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'video/mp4',
    'video/quicktime',
    'video/3gpp',
  };

  /// A `media_objects.id` as the database prints it.
  static final RegExp _mediaId =
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

  /// The record's media identity from its embedded link rows, as the media
  /// Worker would list it: only `ready` media of a listed type, each id once,
  /// by `ordinal` (then id, for a stable order). Anything malformed — a link
  /// that is not a map, an id that is not a canonical UUID, a missing or
  /// negative ordinal, a missing media row — is left out. Identity only: it
  /// is never a reason to show, fetch or keep anything.
  static List<String> _readyMediaIds(Object? links) {
    if (links is! List) return const <String>[];
    final found = <(int, String)>[];
    final seen = <String>{};
    for (final link in links) {
      if (link is! Map) continue;
      final id = link['media_id'];
      final ordinal = link['ordinal'];
      final media = link['media_objects'];
      if (id is! String || !_mediaId.hasMatch(id)) continue;
      if (ordinal is! int || ordinal < 0) continue;
      if (media is! Map ||
          media['status'] != 'ready' ||
          !_listedMediaTypes.contains(media['content_type'])) {
        continue;
      }
      if (seen.add(id)) found.add((ordinal, id));
    }
    found.sort(
        (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    return List<String>.unmodifiable([for (final f in found) f.$2]);
  }

  /// The rows of [table] with these [ids] that this account owns and has not
  /// deleted — the same filters as the single-record reads — in
  /// [_idsPerRead] ids per request, one after another. A missing, deleted or
  /// other account's id is simply not returned. Rows come back in no
  /// particular order. Throws when the signed-in account changed during the
  /// read, as [getOfferMetadata] does.
  Future<List<T>> _rowsByIds<T>(
    String table,
    String columns,
    Iterable<String> ids,
    T Function(Map<String, dynamic> row) fromRow,
  ) async {
    final ownerId = _requireUserId();
    final unique = <String>{
      for (final id in ids)
        if (id.isNotEmpty) id,
    }.toList(growable: false);
    final found = <T>[];
    for (var start = 0; start < unique.length; start += _idsPerRead) {
      final end = start + _idsPerRead < unique.length
          ? start + _idsPerRead
          : unique.length;
      final rows = await _client
          .from(table)
          .select(columns)
          .eq('owner_id', ownerId)
          .inFilter('id', unique.sublist(start, end))
          .isFilter('deleted_at', null);
      if (_client.auth.currentUser?.id != ownerId) {
        throw StateError('The authenticated account changed during the read.');
      }
      found.addAll(rows.map(fromRow));
    }
    return found;
  }

  Future<List<RequestModel>> getRequestsByIds(Iterable<String> ids) =>
      _rowsByIds('requests', _requestColumns, ids, _requestFromRow);

  /// The Offers with these ids, each with its signed media as [getOffer]
  /// gives it: one Worker call per Offer, [mediaReadsAtOnce] at a time. Once
  /// [stop] returns true no further media read starts and the Offers not yet
  /// read are left out (the caller no longer wants the answer).
  Future<List<OfferModel>> getOffersByIds(
    Iterable<String> ids, {
    bool Function()? stop,
  }) async {
    final offers =
        await _rowsByIds('offers', _offerColumns, ids, _offerFromRow);
    final withMedia = await mapWithLimit(
      offers,
      mediaReadsAtOnce,
      _withDisplayMedia,
      stop: stop,
    );
    return [
      for (final offer in withMedia)
        if (offer != null) offer,
    ];
  }

  Future<List<OwnerModel>> getOwnersByIds(Iterable<String> ids) =>
      _rowsByIds('owners', _ownerColumns, ids, _ownerFromRow);

  Future<List<OfficeModel>> getOfficesByIds(Iterable<String> ids) =>
      _rowsByIds('offices', '*', ids, _officeFromRow);

  Future<List<BrokerModel>> getBrokersByIds(Iterable<String> ids) =>
      _rowsByIds('brokers', '*', ids, _brokerFromRow);

  Future<List<WatchmenModel>> getWatchmenByIds(Iterable<String> ids) =>
      _rowsByIds('watchmen', '*', ids, _watchmanFromRow);

  // -------------------------------------------------------------------------
  // Whole lists, read in pages (P4.1: Requests; P4.2: the other five)
  // -------------------------------------------------------------------------

  /// Rows asked for per page. The server may answer fewer (its own row cap);
  /// a short page is never taken to mean the list has ended.
  static const int _pageSize = 500;

  /// The most pages one read may take, and the most rows one list may hold.
  /// Beyond either, the read fails ([CoreEntityListProblem.tooLarge]); it
  /// never returns the first rows only.
  static const int _maxPages = 40;
  static const int _maxListRows = 20000;

  /// Every row of [table] the signed-in account owns and has not deleted,
  /// newest first, read whole in pages exactly as the entity lists are (see
  /// [_wholeList] and [_pagedRows]): for a table of the same shape —
  /// `owner_id`, `created_at`, a unique `id` and `deleted_at`. Used by the
  /// Quotations list (Q-1a). [stillWanted] stops the read between pages.
  Future<List<Map<String, dynamic>>> readWholeOwnedList(
    String table,
    String columns, {
    bool Function()? stillWanted,
  }) =>
      _wholeList(table, columns, stillWanted ?? () => true);

  /// [_pagedRows], read once more from the start when the rows changed while
  /// the pages were read and did not add up. Once only: a list that changes
  /// on every read fails ([CoreEntityListProblem.changedDuringRead]).
  Future<List<Map<String, dynamic>>> _wholeList(
    String table,
    String columns,
    bool Function() stillWanted,
  ) async {
    try {
      return await _pagedRows(table, columns, stillWanted);
    } on CoreEntityListIncomplete catch (error) {
      if (error.problem != CoreEntityListProblem.changedDuringRead) rethrow;
      _debugLog('$table.list', 'rows changed while paging; read once more');
      return _pagedRows(table, columns, stillWanted);
    }
  }

  /// Every row of [table] this account owns and has not deleted — the same
  /// filters as before — newest first, by `created_at` and then `id`.
  ///
  /// The rows come in pages of [_pageSize]; each page starts after the last
  /// row of the page before (a keyset: an add or a delete between two pages
  /// cannot shift what comes next, as it would shift an offset). The first
  /// page also brings the exact number of rows, and the rows are returned
  /// only once the pages add up to it: nothing is returned in part.
  ///
  /// Separate requests are not one database snapshot. A Request added at the
  /// top while the pages are read is not in this list (the next read has
  /// it); one deleted after its page arrived is (until the next read). When
  /// the pages and the first count disagree, the session is confirmed (a
  /// replaced session's pages come back empty: [ListSessionNotCurrent]) and
  /// the rows are counted again; if that count is not what the pages hold,
  /// the read fails with [CoreEntityListProblem.changedDuringRead].
  ///
  /// Between two requests the read stops when [stillWanted] says no, and
  /// fails with [ListSessionNotCurrent] once the signed-in account or its
  /// session is not the one it started under — a sign-out and a sign-in to
  /// the same account included (a token refresh keeps the session).
  Future<List<Map<String, dynamic>>> _pagedRows(
    String table,
    String columns,
    bool Function() stillWanted,
  ) async {
    final ownerId = _requireUserId();
    final session =
        AppSessionCoordinator.sessionId(_client.auth.currentSession);

    void stillOurs() {
      if (!stillWanted()) throw const _ListReadNotWanted();
      if (_client.auth.currentUser?.id != ownerId ||
          AppSessionCoordinator.sessionId(_client.auth.currentSession) !=
              session) {
        throw const ListSessionNotCurrent();
      }
    }

    PostgrestTransformBuilder<PostgrestList> page(_ListCursor? after) {
      var rows = _client
          .from(table)
          .select(columns)
          .eq('owner_id', ownerId)
          .isFilter('deleted_at', null);
      if (after != null) {
        rows = rows.or('created_at.lt.${after.at},'
            'and(created_at.eq.${after.at},id.lt.${after.id})');
      }
      return rows
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(_pageSize);
    }

    final collected = <Map<String, dynamic>>[];
    final seen = <String>{};
    _ListCursor? cursor;

    // Every row comes strictly after the one before it, and only once: a
    // page that repeats, reorders or does not move on is refused.
    void take(PostgrestList rows) {
      if (rows.length > _pageSize) {
        throw const CoreEntityListIncomplete(CoreEntityListProblem.badPage);
      }
      for (final row in rows) {
        final key = _ListCursor.of(row);
        final previous = cursor;
        if (!seen.add(key.id) ||
            (previous != null && !key.comesAfter(previous))) {
          throw const CoreEntityListIncomplete(CoreEntityListProblem.badPage);
        }
        cursor = key;
        collected.add(row);
      }
    }

    stillOurs();
    final PostgrestResponse<PostgrestList> first;
    try {
      first = await page(null).count(CountOption.exact);
    } on TypeError {
      // No count in the answer ("*" or none): the client's own cast fails.
      throw const CoreEntityListIncomplete(CoreEntityListProblem.missingCount);
    } on FormatException {
      throw const CoreEntityListIncomplete(CoreEntityListProblem.missingCount);
    }
    stillOurs();
    final total = first.count;
    if (total < 0) {
      throw const CoreEntityListIncomplete(CoreEntityListProblem.missingCount);
    }
    if (first.data.length > total) {
      throw const CoreEntityListIncomplete(CoreEntityListProblem.badPage);
    }
    if (total > _maxListRows) {
      throw const CoreEntityListIncomplete(CoreEntityListProblem.tooLarge);
    }
    take(first.data);

    var pages = 1;
    var lastPage = first.data.length;
    while (collected.length < total && lastPage > 0) {
      if (pages == _maxPages) {
        throw const CoreEntityListIncomplete(CoreEntityListProblem.tooLarge);
      }
      stillOurs();
      final rows = await page(cursor);
      stillOurs();
      take(rows);
      pages++;
      lastPage = rows.length;
      if (collected.length > _maxListRows) {
        throw const CoreEntityListIncomplete(CoreEntityListProblem.tooLarge);
      }
    }
    if (collected.length == total) return collected;

    // The pages and the first count disagree: rows were added or deleted
    // between requests — or the session was replaced, whose pages the
    // database answers empty. The database decides which.
    final check = ListSessionCheck.confirmFor(session);
    if (check != null && !await check) throw const ListSessionNotCurrent();
    stillOurs();
    final int now;
    try {
      now = await _client
          .from(table)
          .count(CountOption.exact)
          .eq('owner_id', ownerId)
          .isFilter('deleted_at', null);
    } on TypeError {
      throw const CoreEntityListIncomplete(CoreEntityListProblem.missingCount);
    } on FormatException {
      throw const CoreEntityListIncomplete(CoreEntityListProblem.missingCount);
    }
    stillOurs();
    if (now == collected.length) return collected;
    throw const CoreEntityListIncomplete(
        CoreEntityListProblem.changedDuringRead);
  }

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

  /// Soft-deletes the row [id] of [table], and returns only once the server
  /// has confirmed it.
  ///
  /// PostgREST answers an update that changed no row with success — for
  /// another account's row, a missing id or a session the database no longer
  /// accepts alike — so success alone proves nothing. The update applies
  /// only to a row not yet deleted and returns the id it changed: a returned
  /// id is the confirmation, and a deleted row is never stamped again (its
  /// `deleted_at` and `version` stay). When nothing came back, one read tells
  /// this account's row already deleted (done) from anything else, which
  /// fails with [CoreEntityNotDeleted] — saying nothing about the row — and
  /// asks the existing session check, so a replaced session is signed out
  /// as usual. Network and authorization failures are passed on as they are.
  Future<void> _softDelete(String table, String id) async {
    _requireUserId();
    final changed = await _client
        .from(table)
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .isFilter('deleted_at', null)
        .select('id');
    if (changed.isNotEmpty) return;
    final deleted = await _client
        .from(table)
        .select('id')
        .eq('id', id)
        .not('deleted_at', 'is', null);
    if (deleted.isNotEmpty) return;
    _debugLog('entity.delete', 'not confirmed by the server');
    final check =
        ListSessionCheck.confirmFor(ListSessionCheck.currentSession());
    if (check != null) {
      unawaited(check.then<void>((_) {}, onError: (Object _) {}));
    }
    throw const CoreEntityNotDeleted();
  }

  Future<void> _softDeleteAndNotify(
      String table, String id, CoreEntityKind kind) async {
    await _softDelete(table, id);
    CoreEntityMutationNotifier.notify(kind);
  }
}

/// Where a page ends: the last row's `created_at` exactly as the server sent
/// it (microseconds and offset kept, so equality holds) and its id.
class _ListCursor {
  const _ListCursor(this.at, this.time, this.id);

  /// [row]'s position, or a [CoreEntityListProblem.badPage] when it has none.
  factory _ListCursor.of(Map<String, dynamic> row) {
    final at = row['created_at'];
    final id = row['id'];
    final time = at is String ? DateTime.tryParse(at) : null;
    if (time == null || id is! String || id.isEmpty) {
      throw const CoreEntityListIncomplete(CoreEntityListProblem.badPage);
    }
    return _ListCursor(at as String, time, id);
  }

  final String at;
  final DateTime time;
  final String id;

  /// Whether this row comes after [other], newest first: an older time, or
  /// the same time and a smaller id (the database's uuid order).
  bool comesAfter(_ListCursor other) {
    final byTime = time.compareTo(other.time);
    return byTime < 0 || (byTime == 0 && id.compareTo(other.id) < 0);
  }
}

/// A paged read stopped because its stream was cancelled; nobody sees it.
class _ListReadNotWanted implements Exception {
  const _ListReadNotWanted();
}

/// Why a list could not be read whole.
enum CoreEntityListProblem {
  /// The server gave no usable exact number of rows.
  missingCount,

  /// More rows than one list may hold, or more pages than one read may take.
  tooLarge,

  /// A page broke the order, repeated a row or did not move on.
  badPage,

  /// The rows changed while the pages were read and did not add up, even
  /// read again once.
  changedDuringRead,
}

/// A list that could not be read whole. It is never delivered in part, and
/// it is not a network failure: reading again at once would not help.
class CoreEntityListIncomplete implements Exception {
  const CoreEntityListIncomplete(this.problem);

  final CoreEntityListProblem problem;

  @override
  String toString() => 'CoreEntityListIncomplete(${problem.name})';
}

/// A soft delete the server did not confirm: no row this session may change
/// was changed, and this account has no such row already deleted. The record
/// may not exist, may belong to another account, or the session may no
/// longer be the account's current one; which is deliberately not said.
class CoreEntityNotDeleted implements Exception {
  const CoreEntityNotDeleted();

  @override
  String toString() => 'CoreEntityNotDeleted';
}
