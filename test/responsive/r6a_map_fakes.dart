import 'dart:async';

import 'package:broker_wallet/src/Views/Screens/home/map/map_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/search_card_media.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/map_data_cache_service.dart';
import 'package:broker_wallet/src/services/map_filter.dart';
import 'package:broker_wallet/src/services/map_nearby_locator.dart';
import 'package:broker_wallet/src/services/map_places_loader.dart';

/// Empty local reads exercise the real filter controller, never a repository.
class LayoutMapSource implements MapLocationSource {
  int reads = 0;
  bool fail = false;
  Completer<List<CachedLocationData>>? pending;
  @override
  String get currentUserId => 'layout-only';
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<List<CachedLocationData>> load() async {
    reads++;
    if (fail) throw StateError('local read failure');
    return pending == null ? [] : await pending!.future;
  }
}

class LayoutMapCache implements MapDataCacheService {
  @override
  List<CachedLocationData>? get valid => null;
  @override
  int get generation => 0;
  @override
  void store(String userId, List<CachedLocationData> places,
      {required int generation}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected cache access: ${invocation.memberName}');
}

class LayoutMapDevice implements DeviceLocationPlatform {
  int checks = 0;
  int unexpectedAccesses = 0;
  @override
  Future<DevicePermission> permission() async {
    checks++;
    return DevicePermission.denied;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedAccesses++;
    throw StateError('Unexpected device access: ${invocation.memberName}');
  }
}

class _LayoutMedia implements SearchCardMediaSource {
  @override
  String? get accountId => null;
  @override
  List<OfferMediaRef> cached(CardMediaKind kind, String recordId) => [];
  @override
  Future<OfferMediaResolution?> resolve(
          CardMediaKind kind, String recordId, String accountId) async =>
      throw StateError('No media request expected without a session');
}

/// Only selected-card presentation is seeded. Loading, filtering, city choices
/// and reset remain the production implementation; fixtures are not markers.
class LayoutMapModel extends MapViewViewModel {
  LayoutMapModel(this.source, this.device, {this.cluster})
      : super(
          source: source,
          device: device,
          cache: LayoutMapCache(),
          cardMedia: SearchCardMediaResolver(source: _LayoutMedia()),
        );
  final LayoutMapSource source;
  final LayoutMapDevice device;
  ClusteredLocationInfo? cluster;
  bool nearbyPresentation = false;
  void showNearbyPresentation() {
    nearbyPresentation = true;
    notifyListeners();
  }

  @override
  MapFilterState get filterState => nearbyPresentation
      ? super
          .filterState
          .withNearby(const NearbyFilter(latitude: 25.2, longitude: 55.3))
      : super.filterState;
  @override
  ClusteredLocationInfo? get selectedCluster => cluster;
  @override
  LocationInfo? get selectedLocationInfo => cluster?.activeItem;
  @override
  void clearSelectedLocation() {
    cluster = null;
    notifyListeners();
  }

  @override
  void updateClusterActiveIndex(int index) {
    cluster!.activeIndex = index;
    notifyListeners();
  }
}
