import '../../data/models/ScreensModel/brokers_model.dart';
import '../supabase_core_entities_service.dart';

class BrokerService {
  SupabaseCoreEntitiesService get _supabase => SupabaseCoreEntitiesService();

  Future<String?> saveBroker(BrokerModel broker) async {
    return _supabase.saveBroker(broker);
  }

  Future<void> updateBroker(String brokerId, BrokerModel broker) async {
    await _supabase.updateBroker(brokerId, broker);
  }

  Stream<List<BrokerModel>> getUserBrokers() {
    return _supabase.getBrokers();
  }

  Future<void> deleteBroker(String brokerId) async {
    await _supabase.deleteBroker(brokerId);
  }

  Future<BrokerModel?> getBroker(String brokerId) async {
    return _supabase.getBroker(brokerId);
  }
}
