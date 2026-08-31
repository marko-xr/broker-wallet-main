import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads the authenticated user's Home dashboard counts from Supabase.
///
/// Row-level security is the ownership boundary: every query is executed with
/// the current Supabase session, so only rows owned by that user are visible.
class SupabaseHomeCountsService {
  SupabaseHomeCountsService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const Map<String, String> _tableToCountKey = {
    'watchmen': 'watchmen',
    'brokers': 'brokers',
    'offers': 'offers',
    'offices': 'offices',
    'owners': 'owners',
    'requests': 'requested',
    'quotations': 'quotation',
  };

  Future<Map<String, int>> getCounts({
    Map<String, int> fallback = const <String, int>{},
  }) async {
    if (_client.auth.currentSession == null) {
      throw StateError('A Supabase session is required to read Home counts.');
    }

    final entries = await Future.wait(
      _tableToCountKey.entries.map((entry) async {
        try {
          final count = await _countActiveRows(entry.key);
          return MapEntry(entry.value, count);
        } catch (error) {
          debugPrint('Supabase count failed for ${entry.key}: $error');
          return MapEntry(entry.value, fallback[entry.value] ?? 0);
        }
      }),
    );

    return Map<String, int>.fromEntries(entries);
  }

  Future<int> _countActiveRows(String table) async {
    final response = await _client
        .from(table)
        .select('id')
        .isFilter('deleted_at', null)
        .count(CountOption.exact);

    return response.count;
  }
}
