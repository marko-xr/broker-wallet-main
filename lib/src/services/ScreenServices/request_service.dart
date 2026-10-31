import '../../data/models/ScreensModel/request_model.dart';
import '../supabase_core_entities_service.dart';

class RequestService {
  SupabaseCoreEntitiesService get _supabase => SupabaseCoreEntitiesService();

  Future<String?> saveRequest(RequestModel request) async {
    return _supabase.saveRequest(request);
  }

  Future<void> updateRequest(String requestId, RequestModel request) async {
    await _supabase.updateRequest(requestId, request);
  }

  Stream<List<RequestModel>> getUserRequests() {
    return _supabase.getRequests();
  }

  Future<void> deleteRequest(String requestId) async {
    await _supabase.deleteRequest(requestId);
  }

  Future<RequestModel?> getRequest(String requestId) async {
    return _supabase.getRequest(requestId);
  }
}
