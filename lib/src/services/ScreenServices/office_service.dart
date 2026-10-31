import '../../data/models/ScreensModel/offices_model.dart';
import '../supabase_core_entities_service.dart';

class OfficeService {
  SupabaseCoreEntitiesService get _supabase => SupabaseCoreEntitiesService();

  Future<String?> saveOffice(OfficeModel office) async {
    return _supabase.saveOffice(office);
  }

  Future<void> updateOffice(String officeId, OfficeModel office) async {
    await _supabase.updateOffice(officeId, office);
  }

  Stream<List<OfficeModel>> getUserOffices() {
    return _supabase.getOffices();
  }

  Future<void> deleteOffice(String officeId) async {
    await _supabase.deleteOffice(officeId);
  }

  Future<OfficeModel?> getOffice(String officeId) async {
    return _supabase.getOffice(officeId);
  }
}
