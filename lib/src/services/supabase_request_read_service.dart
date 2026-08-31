import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/ScreensModel/request_model.dart';

/// Read-only Supabase adapter for the Requests list during the backend migration.
///
/// Writes remain on the legacy path for now; this service deliberately handles
/// only the authenticated list/read checkpoint.
class SupabaseRequestReadService {
  SupabaseRequestReadService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Stream<List<RequestModel>> getUserRequests() {
    final user = _client.auth.currentUser;
    if (user == null) {
      return Stream.value(const <RequestModel>[]);
    }

    return Stream.fromFuture(_fetchUserRequests(user.id));
  }

  Future<List<RequestModel>> _fetchUserRequests(String ownerId) async {
    final rows = await _client
        .from('requests')
        .select('''
          id,
          owner_id,
          request_type,
          selected_city,
          location_text,
          phone_number,
          country_code,
          min_price,
          max_price,
          square_footage,
          notes,
          property_type,
          specific_property_type,
          rooms,
          bathrooms,
          status,
          created_at,
          updated_at,
          request_areas(area, ordinal)
        ''')
        .eq('owner_id', ownerId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    return rows
        .map((row) => RequestModel.fromSupabaseMap(row))
        .toList(growable: false);
  }
}
