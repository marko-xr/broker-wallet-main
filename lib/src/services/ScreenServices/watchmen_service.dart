import '../../data/models/ScreensModel/watchmen_model.dart';
import '../../repositories/repository_provider.dart';
import '../encrypted_account_list_cache.dart';
import '../supabase_core_entities_service.dart';
import '../watchmen_local_cache.dart';

class WatchmenService {
  WatchmenService({
    WatchmenLocalCache localCache = const WatchmenLocalCache(),
    String? Function()? currentUserId,
  })  : _localCache = localCache,
        _currentUserIdOverride = currentUserId;

  final WatchmenLocalCache _localCache;
  final String? Function()? _currentUserIdOverride;

  SupabaseCoreEntitiesService get _supabase => SupabaseCoreEntitiesService();

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

  Future<void> deleteWatchmen(String watchmenId) async {
    await _supabase.deleteWatchman(watchmenId);
  }

  Future<WatchmenModel?> getWatchmen(String watchmenId) async {
    return _supabase.getWatchman(watchmenId);
  }
}
