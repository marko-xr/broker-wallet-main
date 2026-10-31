import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Caches the Home dashboard counts so they show at once, also offline.
///
/// Counts are private to the account they were read for. Each account's
/// counts live under their own key, named by the account's Supabase user id,
/// and are only ever returned for that same id. With no signed-in account
/// every count is 0.
///
/// The old single cache under [legacyCountsKey] belonged to no known account,
/// so it is never read and never adopted into an account. It is left on disk
/// untouched; only [clearLegacyCache] (used when the signed-in account is
/// deleted) removes it.
class CountCacheService {
  @visibleForTesting
  static const String legacyCountsKey = 'cached_item_counts';
  @visibleForTesting
  static const String legacyUpdatedKey = 'counts_last_updated';

  static const String _countsKeyPrefix = 'cached_item_counts_by_account::';
  static const String _updatedKeyPrefix = 'counts_last_updated_by_account::';

  @visibleForTesting
  static String countsKeyFor(String accountId) => '$_countsKeyPrefix$accountId';

  /// The kinds of item Home counts.
  static const List<String> countTypes = [
    'watchmen',
    'brokers',
    'offers',
    'offices',
    'owners',
    'requested',
    'quotation',
  ];

  static CountCacheService? _instance;
  static CountCacheService get instance => _instance ??= CountCacheService._();
  CountCacheService._();

  /// A separate cache with nothing in memory, so a test does not share the
  /// app-wide instance.
  @visibleForTesting
  factory CountCacheService.forTesting() => CountCacheService._();

  SharedPreferences? _prefs;
  final Map<String, Map<String, int>> _memoryByAccount = {};

  /// Opens the preferences so later reads are synchronous.
  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // Without preferences every account simply starts from 0.
    }
  }

  static Map<String, int> _zeros() => {for (final type in countTypes) type: 0};

  /// The counts cached for [accountId], at once. All 0 when [accountId] is
  /// null or empty, or when nothing is cached for that account yet.
  Map<String, int> getAllCachedCounts(String? accountId) {
    if (accountId == null || accountId.isEmpty) return _zeros();
    final inMemory = _memoryByAccount[accountId];
    if (inMemory != null) return Map<String, int>.from(inMemory);

    final counts = _zeros();
    try {
      final raw = _prefs?.getString(countsKeyFor(accountId));
      if (raw != null) {
        final decoded = json.decode(raw);
        if (decoded is Map) {
          for (final type in countTypes) {
            final value = decoded[type];
            if (value is int && value >= 0) counts[type] = value;
          }
        }
      }
    } catch (_) {
      // A damaged entry counts as nothing cached.
    }
    _memoryByAccount[accountId] = counts;
    return Map<String, int>.from(counts);
  }

  /// Stores [counts] as [accountId]'s counts and writes them to disk.
  Future<void> updateCachedCounts(
    String accountId,
    Map<String, int> counts,
  ) async {
    if (accountId.isEmpty) return;
    final merged = getAllCachedCounts(accountId);
    for (final type in countTypes) {
      final value = counts[type];
      if (value != null) merged[type] = value;
    }
    _memoryByAccount[accountId] = merged;

    try {
      final prefs = _prefs = await SharedPreferences.getInstance();
      await prefs.setString(countsKeyFor(accountId), json.encode(merged));
      await prefs.setInt(
        '$_updatedKeyPrefix$accountId',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // Non-critical: the counts stay in memory for this run.
    }
  }

  /// Removes [accountId]'s cached counts, and only those. Used when that
  /// account is deleted; other accounts' counts stay.
  Future<void> clearAccount(String accountId) async {
    if (accountId.isEmpty) return;
    _memoryByAccount.remove(accountId);
    final prefs = _prefs = await SharedPreferences.getInstance();
    await prefs.remove(countsKeyFor(accountId));
    await prefs.remove('$_updatedKeyPrefix$accountId');
  }

  /// Removes the old unowned cache. Used when the signed-in account is
  /// deleted, as that cache may still hold its counts.
  Future<void> clearLegacyCache() async {
    final prefs = _prefs = await SharedPreferences.getInstance();
    await prefs.remove(legacyCountsKey);
    await prefs.remove(legacyUpdatedKey);
  }
}
