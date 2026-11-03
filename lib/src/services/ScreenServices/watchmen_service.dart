import '../../data/models/ScreensModel/watchmen_model.dart';
import '../../repositories/repository_provider.dart';
import '../encrypted_account_list_cache.dart';
import '../supabase_core_entities_service.dart';
import '../watchmen_local_cache.dart';

class WatchmenService {
  WatchmenService({
    WatchmenLocalCache localCache = const WatchmenLocalCache(),
    String? Function()? currentUserId,
    SupabaseCoreEntitiesService Function()? coreEntities,
  })  : _localCache = localCache,
        _currentUserIdOverride = currentUserId,
        _coreEntities = coreEntities;

  final WatchmenLocalCache _localCache;
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

  Future<String?> saveWatchmen(WatchmenModel watchmen) async {
    return _supabase.saveWatchman(watchmen);
  }

  Future<void> updateWatchmen(String watchmenId, WatchmenModel watchmen) async {
    await _supabase.updateWatchman(watchmenId, watchmen);
  }

  Stream<List<WatchmenModel>> getUserWatchmen() {
    return _supabase.getWatchmen();
  }

  /// The Watchmen list for the Watchmen screen: this account's encrypted
  /// saved copy at once (when there is one), then the server's list, which
  /// replaces it and is saved for next time. A server failure is passed on as
  /// before; a screen that already shows the saved copy keeps it.
  Stream<List<WatchmenModel>> watchUserWatchmenLocalFirst() => localFirstList(
        server: getUserWatchmen,
        cache: _localCache,
        currentUserId: _currentUserId,
      );

  /// Deletes on the server and, once the server has confirmed it,
  /// remembers the deletion so the offline list never shows it again.
  Future<void> deleteWatchmen(String watchmenId) => deleteThenRemember(
        cache: _localCache,
        id: watchmenId,
        currentUserId: _currentUserId,
        delete: () => _supabase.deleteWatchman(watchmenId),
      );

  Future<WatchmenModel?> getWatchmen(String watchmenId) async {
    return _supabase.getWatchman(watchmenId);
  }

  /// The Watchmen with these ids this account may see, in a few requests
  /// rather than one per id. Missing and deleted ones are left out.
  Future<List<WatchmenModel>> getWatchmenByIds(List<String> watchmenIds) =>
      _supabase.getWatchmenByIds(watchmenIds);
}
