import '../../data/models/ScreensModel/watchmen_model.dart';
import '../supabase_core_entities_service.dart';

class WatchmenService {
  SupabaseCoreEntitiesService get _supabase => SupabaseCoreEntitiesService();

  Future<String?> saveWatchmen(WatchmenModel watchmen) async {
    return _supabase.saveWatchman(watchmen);
  }

  Future<void> updateWatchmen(String watchmenId, WatchmenModel watchmen) async {
    await _supabase.updateWatchman(watchmenId, watchmen);
  }

  Stream<List<WatchmenModel>> getUserWatchmen() {
    return _supabase.getWatchmen();
  }

  Future<void> deleteWatchmen(String watchmenId) async {
    await _supabase.deleteWatchman(watchmenId);
  }

  Future<WatchmenModel?> getWatchmen(String watchmenId) async {
    return _supabase.getWatchman(watchmenId);
  }
}
