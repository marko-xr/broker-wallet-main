import '../../data/models/ScreensModel/request_model.dart';
import '../../repositories/repository_provider.dart';
import '../encrypted_account_list_cache.dart';
import '../requests_local_cache.dart';
import '../supabase_core_entities_service.dart';

class RequestService {
  RequestService({
    RequestsLocalCache localCache = const RequestsLocalCache(),
    String? Function()? currentUserId,
    SupabaseCoreEntitiesService Function()? coreEntities,
  })  : _localCache = localCache,
        _currentUserIdOverride = currentUserId,
        _coreEntities = coreEntities;

  final RequestsLocalCache _localCache;
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

  Future<String?> saveRequest(RequestModel request) async {
    return _supabase.saveRequest(request);
  }

  Future<void> updateRequest(String requestId, RequestModel request) async {
    await _supabase.updateRequest(requestId, request);
  }

  Stream<List<RequestModel>> getUserRequests() {
    return _supabase.getRequests();
  }

  /// The Requests list for the Requests screen: this account's saved copy at
  /// once (when there is one), then the server's list, which replaces it and
  /// is saved for next time.
  ///
  /// The saved copy is only ever this account's own. A server failure is
  /// passed on as before; a screen that already shows the saved copy keeps
  /// it. Nothing is saved for an account that is no longer signed in.
  Stream<List<RequestModel>> watchUserRequestsLocalFirst() => localFirstList(
        server: getUserRequests,
        cache: _localCache,
        currentUserId: _currentUserId,
      );

  /// Deletes on the server and, once the server has confirmed it,
  /// remembers the deletion so the offline list never shows it again.
  Future<void> deleteRequest(String requestId) => deleteThenRemember(
        cache: _localCache,
        id: requestId,
        currentUserId: _currentUserId,
        delete: () => _supabase.deleteRequest(requestId),
      );

  Future<RequestModel?> getRequest(String requestId) async {
    return _supabase.getRequest(requestId);
  }

  /// The Requests with these ids this account may see, in a few requests
  /// rather than one per id. Missing and deleted ones are left out.
  Future<List<RequestModel>> getRequestsByIds(List<String> requestIds) =>
      _supabase.getRequestsByIds(requestIds);
}
