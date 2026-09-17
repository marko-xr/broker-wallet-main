import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive/hive.dart';
import 'favorites_item_model.dart';
import 'dart:async';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Model for favorite metadata with timestamp
class FavoriteMetadata {
  final String itemId;
  final String type;
  final DateTime addedAt;

  FavoriteMetadata({
    required this.itemId,
    required this.type,
    required this.addedAt,
  });
}

class FavoriteService {
  // Use lazy getters to avoid accessing Firebase before initialization
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // Get current user ID
  String? get _activeUserId =>
      RepositoryProvider.instance.authRepository.currentUserId;
  String? get _currentUserId => _activeUserId;

  String _supabaseTable(String type) {
    const tables = {
      _offersType: 'favorite_offers',
      _requestsType: 'favorite_requests',
      _ownersType: 'favorite_owners',
      _officesType: 'favorite_offices',
      _brokersType: 'favorite_brokers',
      _watchmenType: 'favorite_watchmen',
    };
    final table = tables[type];
    if (table == null) throw ArgumentError.value(type, 'type');
    return table;
  }

  // Check if auth is ready
  bool get isAuthReady => _activeUserId != null;

  // Wait for auth to be ready
  Future<void> waitForAuthReady(
      {Duration timeout = const Duration(seconds: 5)}) async {
    if (isAuthReady) return;

    final completer = Completer<void>();
    late StreamSubscription<UserModel?> subscription;

    Timer? timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        subscription.cancel();
        completer.complete(); // Complete without error for graceful degradation
      }
    });

    subscription =
        RepositoryProvider.instance.authRepository.authStateChanges.listen(
      (UserModel? user) {
        if (user != null && !completer.isCompleted) {
          timeoutTimer.cancel();
          subscription.cancel();
          completer.complete();
        }
      },
      // An auth-stream error must degrade to the existing timeout path, not
      // escape as an unhandled async error.
      onError: (Object _, StackTrace __) {},
    );

    return completer.future;
  }

  static const String _collectionName = 'users';

  // Legacy, pre-account-isolation box name. Never opened, read, or written by
  // this class anymore. Deliberately left in place on disk rather than
  // deleted: its rows cannot be attributed to any account from the legacy
  // schema, so there is nothing safe to migrate, and deleting it destroys
  // real, already-cached data with no isolation benefit — isolation comes
  // entirely from never referencing this name again, not from removing it.
  static const String legacyBoxName = 'cached_favorites';

  /// The on-disk cache is namespaced by account: each canonical Supabase uid
  /// gets its own Hive box, so one account's data physically cannot be read
  /// by a different account, regardless of any cleanup timing or failure.
  /// This replaces an earlier design (a single shared box plus a separately
  /// persisted "owner" marker) that turned out not to be crash-safe: Hive and
  /// SharedPreferences are two independent, non-atomically-durable storage
  /// systems, so a hard process kill could commit one account's Hive write
  /// while the other store still named the previous account — a real
  /// cross-account read became possible on the next launch. Per-account
  /// boxes remove the shared mutable state that made that possible: there is
  /// no longer anything for a marker to fall out of sync with.
  ///
  /// Public: also used by `DeletedAccountLocalDataCleaner` to delete a
  /// deleted account's own box precisely.
  static String boxNameForUid(String uid) => 'cached_favorites_$uid';

  // Hive box for the currently-initialized account's cached favorites, and
  // the uid it was opened for. Both are null until [initializeCache]
  // succeeds, and a mismatch between `_cacheBoxUid` and the live canonical
  // uid (checked fresh on every read/write) is treated as "no valid cache" —
  // never as "fall back to whatever is open."
  Box<CachedFavoriteItem>? _cacheBox;
  String? _cacheBoxUid;

  /// Monotonic marker bumped once, synchronously, whenever the canonical
  /// Supabase identity transitions away from an account (see
  /// [invalidateForAccountChange], called only from
  /// `AuthViewModel._handleSessionIdentity`). This protects a different,
  /// still-real hazard than the box-per-account split above: a Favorites
  /// fetch or optimistic toggle that started under one account but only
  /// resolves after a *later* account is current must not be allowed to
  /// write its (now-wrong-target) result — see the `expectedGeneration`
  /// check in [cacheFavorites]. It is intentionally in-memory only: a
  /// process restart already terminates every in-flight operation this
  /// guards against, so it needs no durable form, unlike account ownership
  /// itself.
  static int _accountGeneration = 0;
  static int get currentAccountGeneration => _accountGeneration;

  /// Marks every Favorites operation captured before this call as stale for
  /// caching/publishing purposes. Called once per identity transition, at
  /// the single canonical point the transition is recognized
  /// (`AuthViewModel._handleSessionIdentity`). Synchronous in effect and
  /// cannot fail — there is no I/O left to perform here now that account
  /// isolation comes from box naming rather than a shared box's contents.
  static Future<void> invalidateForAccountChange() async {
    _accountGeneration++;
  }

  // Opens this account's own cache box. `uidOverride` is an optional
  // injection point for tests only (mirrors the existing injectable-service
  // pattern already used by `FavoritesViewModel`'s constructor) — production
  // callers never pass it and always resolve the canonical uid themselves.
  Future<void> initializeCache({@visibleForTesting String? uidOverride}) async {
    final uid = uidOverride ?? _safeActiveUserId;
    if (uid == null || uid.isEmpty) {
      _cacheBox = null;
      _cacheBoxUid = null;
      return;
    }

    // Captured before the await, so a transition that happens while the box
    // is opening can be detected once it resolves.
    final generationAtStart = _accountGeneration;

    try {
      final box = await Hive.openBox<CachedFavoriteItem>(boxNameForUid(uid));

      // `Hive.openBox` can take real time (first-time disk I/O), during
      // which the canonical identity can change — a sign-out, a different
      // account signing in directly, or this very account signing out and
      // back in. Re-resolve the same way `uid` was captured above (still
      // honoring a test's `uidOverride`, never a second production identity
      // authority — see `_safeActiveUserId`) and compare against both the
      // uid and the generation captured before the await. A stale
      // completion must not become this instance's active cache reference,
      // even though `_hasValidCacheBoxForCurrentUser` would also catch it on
      // the next read/write — this closes the gap locally instead of
      // depending solely on that separate, later check.
      //
      // The box itself is left exactly as `Hive.openBox` returned it: not
      // closed, not touched further. Hive tracks it globally by name, so
      // another `FavoriteService` instance — or this same account's own
      // next, legitimate `initializeCache` call — may still depend on it
      // being open.
      final currentUid = uidOverride ?? _safeActiveUserId;
      final isStillCurrent =
          currentUid == uid && generationAtStart == _accountGeneration;

      if (!isStillCurrent) {
        return;
      }

      _cacheBox = box;
      _cacheBoxUid = uid;
    } catch (e) {
      // Debug log suppressed: Failed to initialize favorites cache: $e
      _cacheBox = null;
      _cacheBoxUid = null;
    }
  }

  // Test-only override for "who is canonically signed in right now" (mirrors
  // `initializeCache`'s `uidOverride`). Production never sets this; a test
  // sets it to the same uid it passed `initializeCache(uidOverride: ...)` to
  // simulate that account being the live session for the duration of a
  // read/write, or leaves it out of sync with a later `initializeCache` call
  // to simulate an account transition without needing a real
  // `RepositoryProvider`.
  @visibleForTesting
  String? debugActiveUserIdOverride;

  // `_activeUserId` throws (rather than returning null) when the identity
  // pipeline itself is not yet available — `RepositoryProvider.instance`
  // asserts Supabase is initialized. That should never happen by the time a
  // `FavoritesViewModel` exists in production, but the cache's own read/write
  // gate must fail closed to "no cache" rather than propagate an exception
  // out of what is meant to be a safe, best-effort local read.
  String? get _safeActiveUserId {
    final override = debugActiveUserIdOverride;
    if (override != null) return override;
    try {
      return _activeUserId;
    } catch (_) {
      return null;
    }
  }

  // True only when a box is open, it was opened for exactly the uid that is
  // canonically current right now, and that uid is non-null. Any mismatch —
  // not yet initialized, initialized for a different (now-stale) uid, or no
  // one signed in — fails closed to "no cache", never to "whatever box
  // happens to be open".
  bool get _hasValidCacheBoxForCurrentUser {
    final uid = _safeActiveUserId;
    final box = _cacheBox;
    return uid != null &&
        uid.isNotEmpty &&
        uid == _cacheBoxUid &&
        box != null &&
        box.isOpen;
  }

  // Get cached favorites instantly (synchronous)
  List<FavoriteItem> getCachedFavoritesSync() {
    if (!_hasValidCacheBoxForCurrentUser) {
      return [];
    }

    try {
      final cachedItems = _cacheBox!.values.toList()
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));

      return cachedItems.map((item) => item.toFavoriteItem()).toList();
    } catch (e) {
      return [];
    }
  }

  // Get cached favorites instantly (async version)
  List<FavoriteItem> getCachedFavorites() {
    return getCachedFavoritesSync();
  }

  // Cache favorites after fetching from network.
  //
  // `expectedGeneration` must be `FavoriteService.currentAccountGeneration`
  // captured by the caller when the fetch that produced [favorites] began —
  // required, not optional, so a future call site cannot silently bypass the
  // check by omitting it. If the account has changed since (see
  // [invalidateForAccountChange]), or the cache box no longer belongs to the
  // account that is canonically current right now, this is a silent no-op: a
  // slow fetch that started under a previous account must never write its
  // result anywhere a later account could read it.
  Future<void> cacheFavorites(
    List<FavoriteItem> favorites, {
    required int expectedGeneration,
  }) async {
    if (expectedGeneration != _accountGeneration) return;
    if (!_hasValidCacheBoxForCurrentUser) return;
    final box = _cacheBox!;

    try {
      await box.clear(); // Clear old cache

      if (expectedGeneration != _accountGeneration ||
          !_hasValidCacheBoxForCurrentUser) {
        // The account changed while the clear was in flight; leave this
        // (no-longer-current) box empty rather than writing into it.
        return;
      }

      final cachedItems = favorites
          .map((item) => CachedFavoriteItem(
                id: item.id,
                type: item.type,
                title: item.title,
                subtitle: item.subtitle,
                imageUrl: item.imageUrl,
                thumbnailUrl:
                    item.imageUrl, // Use same URL for now, can optimize later
                addedAt: item.addedAt,
                cachedAt: DateTime.now(),
                entityData: null, // Can add minimal entity data later
              ))
          .toList();

      await box.addAll(cachedItems);
    } catch (e) {
      // Silently handle cache errors
    }
  }

  // Favorite types
  static const String _offersType = 'offers';
  static const String _requestsType = 'requests';
  static const String _ownersType = 'owners';
  static const String _officesType = 'offices';
  static const String _brokersType = 'brokers';
  static const String _watchmenType = 'watchmen';

  // Add to favorites using the new repository pattern
  Future<void> addToFavorites(String itemId, String type) async {
    if (_activeUserId == null) {
      throw Exception('User not authenticated');
    }

    try {
      if (SupabaseConfig.useSupabaseAuth) {
        await sb.Supabase.instance.client.from(_supabaseTable(type)).upsert(
          {
            'owner_id': _activeUserId!,
            'target_id': itemId,
          },
          ignoreDuplicates: true,
        );
        return;
      }
      await _firestore
          .collection(_collectionName)
          .doc(_currentUserId!)
          .collection('favorites')
          .doc(type)
          .collection('items')
          .doc(itemId)
          .set({
        'itemId': itemId,
        'type': type,
        'addedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Note: Cache will be updated when favorites view loads fresh data
    } catch (e) {
      // Debug log suppressed: Error adding to favorites: $e
      rethrow;
    }
  }

  // Remove from favorites using the new repository pattern
  Future<void> removeFromFavorites(String itemId, String type) async {
    if (_activeUserId == null) {
      throw Exception('User not authenticated');
    }

    try {
      if (SupabaseConfig.useSupabaseAuth) {
        await sb.Supabase.instance.client
            .from(_supabaseTable(type))
            .delete()
            .eq('owner_id', _activeUserId!)
            .eq('target_id', itemId);
        return;
      }
      await _firestore
          .collection(_collectionName)
          .doc(_currentUserId!)
          .collection('favorites')
          .doc(type)
          .collection('items')
          .doc(itemId)
          .delete();
    } catch (e) {
      // Debug log suppressed: Error removing from favorites: $e
      rethrow;
    }
  }

  // Check if item is favorite using the new repository pattern with cache-first approach
  Future<bool> isFavorite(String itemId, String type) async {
    if (_activeUserId == null) {
      return false;
    }

    try {
      if (SupabaseConfig.useSupabaseAuth) {
        final row = await sb.Supabase.instance.client
            .from(_supabaseTable(type))
            .select('target_id')
            .eq('owner_id', _activeUserId!)
            .eq('target_id', itemId)
            .maybeSingle();
        return row != null;
      }
      // Try cache first
      DocumentSnapshot doc;
      try {
        doc = await _firestore
            .collection(_collectionName)
            .doc(_currentUserId!)
            .collection('favorites')
            .doc(type)
            .collection('items')
            .doc(itemId)
            .get(const GetOptions(source: Source.cache));

        return doc.exists;
      } catch (e) {
        // Debug log suppressed: Cache read failed for isFavorite, trying server: $e
      }

      // Fallback to server with timeout
      try {
        doc = await _firestore
            .collection(_collectionName)
            .doc(_currentUserId!)
            .collection('favorites')
            .doc(type)
            .collection('items')
            .doc(itemId)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 3));

        return doc.exists;
      } on TimeoutException {
        // Debug log suppressed: isFavorite server timeout - returning false
        return false;
      }
    } catch (e) {
      // Debug log suppressed: Error checking favorite status: $e
      return false;
    }
  }

  // Toggle favorite status
  Future<bool> toggleFavorite(String itemId, String type) async {
    final isFav = await isFavorite(itemId, type);

    if (isFav) {
      await removeFromFavorites(itemId, type);
      return false;
    } else {
      await addToFavorites(itemId, type);
      return true;
    }
  }

  // Get all favorites by type
  Stream<List<String>> getFavoriteIdsByType(String type) {
    if (_activeUserId == null) {
      return Stream.value([]);
    }

    if (SupabaseConfig.useSupabaseAuth) {
      return sb.Supabase.instance.client
          .from(_supabaseTable(type))
          .stream(primaryKey: const ['owner_id', 'target_id'])
          .eq('owner_id', _activeUserId!)
          .order('added_at', ascending: false)
          .map((rows) => rows
              .map((row) => row['target_id']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toList(growable: false));
    }

    return _firestore
        .collection(_collectionName)
        .doc(_currentUserId!)
        .collection('favorites')
        .doc(type)
        .collection('items')
        .orderBy('addedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.id).toList());
  }

  // Get all favorites with metadata (ID + timestamp)
  Future<Map<String, List<FavoriteMetadata>>>
      getAllFavoritesWithMetadata() async {
    if (_activeUserId == null) {
      // Wait for auth before proceeding
      await waitForAuthReady();
      if (_activeUserId == null) {
        return {};
      }
    }

    if (SupabaseConfig.useSupabaseAuth) {
      return _getServerFavoritesWithMetadata();
    }

    try {
      final Map<String, List<FavoriteMetadata>> favorites = {};

      final types = [
        _offersType,
        _requestsType,
        _ownersType,
        _officesType,
        _brokersType,
        _watchmenType,
      ];

      // Check if this is likely a fresh install by checking if this
      // account's cache box exists and is empty.
      bool isFreshInstall = false;
      try {
        isFreshInstall = !_hasValidCacheBoxForCurrentUser || _cacheBox!.isEmpty;
      } catch (e) {
        isFreshInstall = true;
      }

      // For fresh installs, go directly to server to avoid empty cache delays
      if (isFreshInstall) {
        // Debug log suppressed: Fresh install detected, loading favorites from server...
        return await _getServerFavoritesWithMetadata();
      }

      // For existing installs, try cache first with server fallback
      for (final type in types) {
        try {
          final snapshot = await _firestore
              .collection(_collectionName)
              .doc(_currentUserId!)
              .collection('favorites')
              .doc(type)
              .collection('items')
              .orderBy('addedAt', descending: true)
              .get(const GetOptions(source: Source.cache));

          favorites[type] = snapshot.docs.map((doc) {
            final data = doc.data();
            return FavoriteMetadata(
              itemId: doc.id,
              type: type,
              addedAt:
                  (data['addedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
            );
          }).toList();
        } catch (e) {
          // Debug log suppressed: Cache read failed for $type, will use server fallback
          // Individual type cache failure - server fallback will handle this
          favorites[type] = [];
        }
      }

      // If cache returned empty results, fall back to server
      if (favorites.values.every((list) => list.isEmpty)) {
        // Debug log suppressed: Cache empty, falling back to server...
        return await _getServerFavoritesWithMetadata();
      }

      return favorites;
    } catch (e) {
      // Debug log suppressed: Cache operation failed entirely: $e
      // If cache fails entirely, try server data
      return await _getServerFavoritesWithMetadata();
    }
  }

  // Fallback method for server data with metadata when cache fails
  Future<Map<String, List<FavoriteMetadata>>>
      _getServerFavoritesWithMetadata() async {
    if (_activeUserId == null) {
      return {};
    }

    try {
      final Map<String, List<FavoriteMetadata>> favorites = {};

      final types = [
        _offersType,
        _requestsType,
        _ownersType,
        _officesType,
        _brokersType,
        _watchmenType,
      ];

      for (final type in types) {
        if (SupabaseConfig.useSupabaseAuth) {
          final rows = await sb.Supabase.instance.client
              .from(_supabaseTable(type))
              .select('target_id, added_at')
              .eq('owner_id', _activeUserId!)
              .order('added_at', ascending: false);
          favorites[type] = rows
              .map((row) => FavoriteMetadata(
                    itemId: row['target_id']?.toString() ?? '',
                    type: type,
                    addedAt: DateTime.tryParse(
                          row['added_at']?.toString() ?? '',
                        ) ??
                        DateTime.now(),
                  ))
              .where((item) => item.itemId.isNotEmpty)
              .toList(growable: false);
          continue;
        }
        final snapshot = await _firestore
            .collection(_collectionName)
            .doc(_currentUserId!)
            .collection('favorites')
            .doc(type)
            .collection('items')
            .orderBy('addedAt', descending: true)
            .get(const GetOptions(source: Source.server));

        favorites[type] = snapshot.docs.map((doc) {
          final data = doc.data();
          return FavoriteMetadata(
            itemId: doc.id,
            type: type,
            addedAt:
                (data['addedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          );
        }).toList();
      }

      return favorites;
    } catch (e) {
      // Debug log suppressed: Error getting server favorites with metadata: $e
      return {};
    }
  }

  // Keep old method for backward compatibility
  Future<Map<String, List<String>>> getAllFavorites() async {
    final metadata = await getAllFavoritesWithMetadata();
    final Map<String, List<String>> favorites = {};

    metadata.forEach((type, metadataList) {
      favorites[type] = metadataList.map((meta) => meta.itemId).toList();
    });

    return favorites;
  }

  // Stream for real-time favorite updates
  Stream<Map<String, List<String>>> get favoritesStream {
    if (_activeUserId == null) {
      return Stream.value({});
    }

    final types = [
      _offersType,
      _requestsType,
      _ownersType,
      _officesType,
      _brokersType,
      _watchmenType,
    ];

    if (SupabaseConfig.useSupabaseAuth) {
      return Stream.periodic(const Duration(seconds: 2))
          .asyncMap((_) async => getAllFavorites())
          .distinct((previous, next) => _areFavoritesEqual(previous, next));
    }

    // Combine all type streams into one
    return Stream.periodic(const Duration(milliseconds: 100))
        .asyncMap((_) async {
      final Map<String, List<String>> favorites = {};

      for (final type in types) {
        try {
          final snapshot = await _firestore
              .collection(_collectionName)
              .doc(_currentUserId!)
              .collection('favorites')
              .doc(type)
              .collection('items')
              .orderBy('addedAt', descending: true)
              .get(const GetOptions(source: Source.cache));

          favorites[type] = snapshot.docs.map((doc) => doc.id).toList();
        } catch (e) {
          favorites[type] = [];
        }
      }

      return favorites;
    }).distinct((previous, next) => _areFavoritesEqual(previous, next));
  }

  // Helper to compare favorites for stream optimization
  bool _areFavoritesEqual(
      Map<String, List<String>> a, Map<String, List<String>> b) {
    if (a.length != b.length) return false;

    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (a[key]!.length != b[key]!.length) return false;
      if (!a[key]!.toSet().containsAll(b[key]!)) return false;
    }

    return true;
  }

  // Convenience methods for specific types
  Future<void> addOfferToFavorites(String offerId) =>
      addToFavorites(offerId, _offersType);

  Future<void> removeOfferFromFavorites(String offerId) =>
      removeFromFavorites(offerId, _offersType);

  Future<bool> isOfferFavorite(String offerId) =>
      isFavorite(offerId, _offersType);

  Future<bool> toggleOfferFavorite(String offerId) =>
      toggleFavorite(offerId, _offersType);

  Future<void> addRequestToFavorites(String requestId) =>
      addToFavorites(requestId, _requestsType);

  Future<void> removeRequestFromFavorites(String requestId) =>
      removeFromFavorites(requestId, _requestsType);

  Future<bool> isRequestFavorite(String requestId) =>
      isFavorite(requestId, _requestsType);

  Future<bool> toggleRequestFavorite(String requestId) =>
      toggleFavorite(requestId, _requestsType);

  Future<void> addOwnerToFavorites(String ownerId) =>
      addToFavorites(ownerId, _ownersType);

  Future<void> removeOwnerFromFavorites(String ownerId) =>
      removeFromFavorites(ownerId, _ownersType);

  Future<bool> isOwnerFavorite(String ownerId) =>
      isFavorite(ownerId, _ownersType);

  Future<bool> toggleOwnerFavorite(String ownerId) =>
      toggleFavorite(ownerId, _ownersType);

  Future<void> addOfficeToFavorites(String officeId) =>
      addToFavorites(officeId, _officesType);

  Future<void> removeOfficeFromFavorites(String officeId) =>
      removeFromFavorites(officeId, _officesType);

  Future<bool> isOfficeFavorite(String officeId) =>
      isFavorite(officeId, _officesType);

  Future<bool> toggleOfficeFavorite(String officeId) =>
      toggleFavorite(officeId, _officesType);

  Future<void> addBrokerToFavorites(String brokerId) =>
      addToFavorites(brokerId, _brokersType);

  Future<void> removeBrokerFromFavorites(String brokerId) =>
      removeFromFavorites(brokerId, _brokersType);

  Future<bool> isBrokerFavorite(String brokerId) =>
      isFavorite(brokerId, _brokersType);

  Future<bool> toggleBrokerFavorite(String brokerId) =>
      toggleFavorite(brokerId, _brokersType);

  Future<void> addWatchmenToFavorites(String watchmenId) =>
      addToFavorites(watchmenId, _watchmenType);

  Future<void> removeWatchmenFromFavorites(String watchmenId) =>
      removeFromFavorites(watchmenId, _watchmenType);

  Future<bool> isWatchmenFavorite(String watchmenId) =>
      isFavorite(watchmenId, _watchmenType);

  Future<bool> toggleWatchmenFavorite(String watchmenId) =>
      toggleFavorite(watchmenId, _watchmenType);

  // Stream methods for real-time updates
  Stream<List<String>> get favoriteOfferIds =>
      getFavoriteIdsByType(_offersType);

  Stream<List<String>> get favoriteRequestIds =>
      getFavoriteIdsByType(_requestsType);

  Stream<List<String>> get favoriteOwnerIds =>
      getFavoriteIdsByType(_ownersType);

  Stream<List<String>> get favoriteOfficeIds =>
      getFavoriteIdsByType(_officesType);

  Stream<List<String>> get favoriteBrokerIds =>
      getFavoriteIdsByType(_brokersType);

  Stream<List<String>> get favoriteWatchmenIds =>
      getFavoriteIdsByType(_watchmenType);
}
