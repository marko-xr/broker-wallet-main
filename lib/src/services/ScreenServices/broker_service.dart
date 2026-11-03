import '../../data/models/ScreensModel/brokers_model.dart';
import '../../repositories/repository_provider.dart';
import '../brokers_local_cache.dart';
import '../encrypted_account_list_cache.dart';
import '../supabase_core_entities_service.dart';

class BrokerService {
  BrokerService({
    BrokersLocalCache localCache = const BrokersLocalCache(),
    String? Function()? currentUserId,
    SupabaseCoreEntitiesService Function()? coreEntities,
  })  : _localCache = localCache,
        _currentUserIdOverride = currentUserId,
        _coreEntities = coreEntities;

  final BrokersLocalCache _localCache;
  final String? Function()? _currentUserIdOverride;
  final SupabaseCoreEntitiesService Function()? _coreEntities;

  SupabaseCoreEntitiesService get _supabase =>
      _coreEntities?.call() ?? SupabaseCoreEntitiesService();

  /// The canonical signed-in account, or null when there is none (or no
  /// auth repository yet).
  String? _currentUserId() {
    final override = _currentUserIdOverride;
    if (override != null) return override();
    try {
      return RepositoryProvider.instance.authRepository.currentUserId;
    } catch (_) {
      return null;
    }
  }

  Future<String?> saveBroker(BrokerModel broker) async {
    return _supabase.saveBroker(broker);
  }

  Future<void> updateBroker(String brokerId, BrokerModel broker) async {
    await _supabase.updateBroker(brokerId, broker);
  }

  Stream<List<BrokerModel>> getUserBrokers() {
    return _supabase.getBrokers();
  }

  /// The Brokers list for the Brokers screen: this account's encrypted saved
  /// copy at once (when there is one), then the server's list, which replaces
  /// it and is saved for next time. A server failure is passed on as before;
  /// a screen that already shows the saved copy keeps it.
  Stream<List<BrokerModel>> watchUserBrokersLocalFirst() => localFirstList(
        server: getUserBrokers,
        cache: _localCache,
        currentUserId: _currentUserId,
      );

  /// Deletes on the server and, once the server has confirmed it,
  /// remembers the deletion so the offline list never shows it again.
  Future<void> deleteBroker(String brokerId) => deleteThenRemember(
        cache: _localCache,
        id: brokerId,
        currentUserId: _currentUserId,
        delete: () => _supabase.deleteBroker(brokerId),
      );

  Future<BrokerModel?> getBroker(String brokerId) async {
    return _supabase.getBroker(brokerId);
  }

  /// The Brokers with these ids this account may see, in a few requests
  /// rather than one per id. Missing and deleted ones are left out.
  Future<List<BrokerModel>> getBrokersByIds(List<String> brokerIds) =>
      _supabase.getBrokersByIds(brokerIds);
}
