import '../../data/models/ScreensModel/offices_model.dart';
import '../../repositories/repository_provider.dart';
import '../encrypted_account_list_cache.dart';
import '../offices_local_cache.dart';
import '../supabase_core_entities_service.dart';

class OfficeService {
  OfficeService({
    OfficesLocalCache localCache = const OfficesLocalCache(),
    String? Function()? currentUserId,
    SupabaseCoreEntitiesService Function()? coreEntities,
  })  : _localCache = localCache,
        _currentUserIdOverride = currentUserId,
        _coreEntities = coreEntities;

  final OfficesLocalCache _localCache;
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

  Future<String?> saveOffice(OfficeModel office) async {
    return _supabase.saveOffice(office);
  }

  Future<void> updateOffice(String officeId, OfficeModel office) async {
    await _supabase.updateOffice(officeId, office);
  }

  Stream<List<OfficeModel>> getUserOffices() {
    return _supabase.getOffices();
  }

  /// The Offices list for the Offices screen: this account's encrypted saved
  /// copy at once (when there is one), then the server's list, which replaces
  /// it and is saved for next time. A server failure is passed on as before;
  /// a screen that already shows the saved copy keeps it.
  Stream<List<OfficeModel>> watchUserOfficesLocalFirst() => localFirstList(
        server: getUserOffices,
        cache: _localCache,
        currentUserId: _currentUserId,
      );

  /// Deletes on the server and, once the server has confirmed it,
  /// remembers the deletion so the offline list never shows it again.
  Future<void> deleteOffice(String officeId) => deleteThenRemember(
        cache: _localCache,
        id: officeId,
        currentUserId: _currentUserId,
        delete: () => _supabase.deleteOffice(officeId),
      );

  Future<OfficeModel?> getOffice(String officeId) async {
    return _supabase.getOffice(officeId);
  }
}
