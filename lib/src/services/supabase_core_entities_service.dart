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
  })  : _client = client ?? Supabase.instance.client,
        _offerMedia = offerMedia ?? R2OfferMediaUploadService();

  final SupabaseClient _client;
  final R2OfferMediaUploadService _offerMedia;
  static const Uuid _uuid = Uuid();

  /// Best-effort: an Offer's core fields must still display even if the
  /// media Worker is briefly unreachable, so a failure here is swallowed to
  /// an empty list rather than propagated — the same tolerance the rest of
  /// this class already gives read paths against transient failures.
  Future<List<String>> _fetchOfferMediaDisplayUrls(String offerId) async {
    try {
      final media = await _offerMedia.getOfferMedia(offerId);
      return media.map((item) => item.url).toList(growable: false);
    } catch (e) {
      _debugLog('offer.media', 'media fetch failed for display: $e');
      return const [];
    }
  }

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

  Stream<List<T>> _refreshedStream<T>(Future<List<T>> Function() fetch) async* {
    yield await fetch();
    await for (final _ in CoreEntityMutationNotifier.changes) {
      yield await fetch();
    }
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

  Future<OfferModel?> getOffer(String id) async {
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
    if (rows.isEmpty) return null;
    final offer = _offerFromRow(rows.first);

    // Single-offer reads (detail/edit screens, Favorites cards, search
    // results) populate real signed media URLs; the bulk list fetch below
    // deliberately does not, to avoid an unbounded fan-out of per-offer
    // Worker calls for a whole list at once.
    final mediaUrls = await _fetchOfferMediaDisplayUrls(id);
    if (mediaUrls.isEmpty) return offer;
    return offer.copyWith(mediaUrls: mediaUrls, mediaUrl: mediaUrls.first);
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
