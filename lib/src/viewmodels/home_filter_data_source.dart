import '../data/models/ScreensModel/brokers_model.dart';
import '../data/models/ScreensModel/offers_model.dart';
import '../data/models/ScreensModel/offices_model.dart';
import '../data/models/ScreensModel/owners_model.dart';
import '../data/models/ScreensModel/request_model.dart';
import '../data/models/ScreensModel/watchmen_model.dart';
import '../data/models/unified_item_model.dart';
import 'home_filter_controller.dart';

/// Reads the records the Home filters look through, as one snapshot.
///
/// It is handed the record streams of the app's own services — the ones every
/// list screen uses — so which backend answers, and as whom, is theirs to
/// decide: in Supabase mode each is read as the signed-in user with row-level
/// security as the ownership boundary. Home never picks a backend itself.
///
/// Each stream's first answer is one full snapshot of its records as they are
/// now. Nothing is subscribed to afterwards and nothing is polled. Only the
/// kinds of record asked for are read, all at once, and [load] completes when
/// every one of them has arrived; if any cannot be read the whole load fails and
/// none of the others' records is used. Quotations are not part of the Home
/// filters and are never read.
class SnapshotHomeFilterDataSource implements HomeFilterDataSource {
  const SnapshotHomeFilterDataSource({
    required this.requests,
    required this.offers,
    required this.brokers,
    required this.owners,
    required this.offices,
    required this.watchmen,
  });

  final Stream<List<RequestModel>> Function() requests;
  final Stream<List<OfferModel>> Function() offers;
  final Stream<List<BrokerModel>> Function() brokers;
  final Stream<List<OwnerModel>> Function() owners;
  final Stream<List<OfficeModel>> Function() offices;
  final Stream<List<WatchmenModel>> Function() watchmen;

  @override
  Future<List<UnifiedItemModel>> load(List<ItemType> types) async {
    final reads = <Future<List<UnifiedItemModel>>>[
      if (types.contains(ItemType.request))
        _first(requests(), UnifiedItemModel.fromRequest),
      if (types.contains(ItemType.offer))
        _first(offers(), UnifiedItemModel.fromOffer),
      if (types.contains(ItemType.broker))
        _first(brokers(), UnifiedItemModel.fromBroker),
      if (types.contains(ItemType.owner))
        _first(owners(), UnifiedItemModel.fromOwner),
      if (types.contains(ItemType.office))
        _first(offices(), UnifiedItemModel.fromOffice),
      if (types.contains(ItemType.watchmen))
        _first(watchmen(), UnifiedItemModel.fromWatchmen),
    ];
    // Concurrently, and as a whole.
    final lists = await Future.wait(reads, eagerError: true);
    return <UnifiedItemModel>[for (final list in lists) ...list];
  }

  static Future<List<UnifiedItemModel>> _first<T>(
    Stream<List<T>> records,
    UnifiedItemModel Function(T record) toItem,
  ) async {
    final snapshot = await records.first;
    return snapshot.map(toItem).toList(growable: false);
  }
}
