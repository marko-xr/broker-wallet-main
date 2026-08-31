import 'package:flutter/foundation.dart';
import '../Views/Screens/home/favorites/favorites_service.dart';

/// Optimistic favorites manager with offline support and error rollback
class OptimisticFavoritesService extends ChangeNotifier {
  final FavoriteService _favoriteService = FavoriteService();

  // Local state for optimistic updates
  final Map<String, bool> _optimisticState = {};
  final Map<String, bool> _pendingOperations = {};
  final Set<String> _offlineQueue = {};

  // Track network connectivity (simplified - in real app use connectivity_plus)
  bool _isOnline = true;

  /// Get current favorite status with optimistic state
  bool isFavorite(String itemId, String type) {
    final key = _getKey(itemId, type);
    return _optimisticState[key] ?? false;
  }

  /// Check if operation is in progress
  bool isLoading(String itemId, String type) {
    final key = _getKey(itemId, type);
    return _pendingOperations[key] ?? false;
  }

  /// Initialize with current server state
  Future<void> initializeFavoriteStatus(String itemId, String type) async {
    final key = _getKey(itemId, type);

    try {
      final serverState = await _favoriteService.isFavorite(itemId, type);
      _optimisticState[key] = serverState;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to initialize favorite status: $e');
      // Keep optimistic state if server fails
    }
  }

  /// Optimistically toggle favorite with rollback on error
  Future<bool> toggleFavorite(String itemId, String type) async {
    final key = _getKey(itemId, type);
    final currentState = _optimisticState[key] ?? false;
    final newState = !currentState;

    // Prevent concurrent operations on same item
    if (_pendingOperations[key] == true) {
      return currentState;
    }

    // 1. Optimistic update (immediate UI feedback)
    _optimisticState[key] = newState;
    _pendingOperations[key] = true;
    notifyListeners();

    try {
      if (_isOnline) {
        // 2. Attempt server update
        final actualState = newState
            ? await _favoriteService
                .addToFavorites(itemId, type)
                .then((_) => true)
            : await _favoriteService
                .removeFromFavorites(itemId, type)
                .then((_) => false);

        // 3. Confirm optimistic state matches server
        _optimisticState[key] = actualState;
        _pendingOperations[key] = false;
        notifyListeners();

        return actualState;
      } else {
        // 4. Offline: queue for later sync
        _offlineQueue.add(key);
        _pendingOperations[key] = false;
        notifyListeners();

        return newState;
      }
    } catch (e) {
      // 5. Rollback on error
      debugPrint('Failed to toggle favorite: $e');
      _optimisticState[key] = currentState; // Revert to original state
      _pendingOperations[key] = false;
      notifyListeners();

      // Notify error to UI
      rethrow;
    }
  }

  /// Sync offline queue when network returns
  Future<void> syncOfflineQueue() async {
    if (!_isOnline || _offlineQueue.isEmpty) return;

    final queueCopy = Set<String>.from(_offlineQueue);
    _offlineQueue.clear();

    for (final key in queueCopy) {
      final parts = key.split('_');
      if (parts.length >= 2) {
        final type = parts[0];
        final itemId = parts.sublist(1).join('_');

        try {
          final currentOptimisticState = _optimisticState[key] ?? false;

          if (currentOptimisticState) {
            await _favoriteService.addToFavorites(itemId, type);
          } else {
            await _favoriteService.removeFromFavorites(itemId, type);
          }
        } catch (e) {
          debugPrint('Failed to sync favorite $key: $e');
          // Re-queue failed items
          _offlineQueue.add(key);
        }
      }
    }

    notifyListeners();
  }

  /// Update network status
  void setOnlineStatus(bool isOnline) {
    if (_isOnline != isOnline) {
      _isOnline = isOnline;
      if (isOnline) {
        syncOfflineQueue();
      }
    }
  }

  /// Clear all local state (useful for logout)
  void clearState() {
    _optimisticState.clear();
    _pendingOperations.clear();
    _offlineQueue.clear();
    notifyListeners();
  }

  /// Batch initialize multiple items (performance optimization)
  Future<void> batchInitializeFavorites(
      List<String> itemIds, String type) async {
    try {
      // Get all favorites of this type from server
      final serverFavorites = await _favoriteService.getAllFavorites();
      final typeFavorites = serverFavorites[type] ?? [];

      // Update local state for all requested items
      for (final itemId in itemIds) {
        final key = _getKey(itemId, type);
        _optimisticState[key] = typeFavorites.contains(itemId);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Failed to batch initialize favorites: $e');
    }
  }

  /// Bulk update optimistic state for loaded favorites (used by FavoritesViewModel)
  void updateLoadedFavorites(Map<String, List<String>> favoritesByType) {
    for (final entry in favoritesByType.entries) {
      for (final itemId in entry.value) {
        final key = _getKey(itemId, entry.key);
        _optimisticState[key] = true;
      }
    }
    notifyListeners();
  }

  String _getKey(String itemId, String type) => '${type}_$itemId';

  /// Convenience methods for specific types
  Future<bool> toggleOfferFavorite(String offerId) =>
      toggleFavorite(offerId, 'offers');

  Future<bool> toggleRequestFavorite(String requestId) =>
      toggleFavorite(requestId, 'requests');

  Future<bool> toggleOwnerFavorite(String ownerId) =>
      toggleFavorite(ownerId, 'owners');

  Future<bool> toggleOfficeFavorite(String officeId) =>
      toggleFavorite(officeId, 'offices');

  Future<bool> toggleBrokerFavorite(String brokerId) =>
      toggleFavorite(brokerId, 'brokers');

  Future<bool> toggleWatchmenFavorite(String watchmenId) =>
      toggleFavorite(watchmenId, 'watchmen');

  bool isOfferFavorite(String offerId) => isFavorite(offerId, 'offers');
  bool isRequestFavorite(String requestId) => isFavorite(requestId, 'requests');
  bool isOwnerFavorite(String ownerId) => isFavorite(ownerId, 'owners');
  bool isOfficeFavorite(String officeId) => isFavorite(officeId, 'offices');
  bool isBrokerFavorite(String brokerId) => isFavorite(brokerId, 'brokers');
  bool isWatchmenFavorite(String watchmenId) =>
      isFavorite(watchmenId, 'watchmen');

  bool isOfferLoading(String offerId) => isLoading(offerId, 'offers');
  bool isRequestLoading(String requestId) => isLoading(requestId, 'requests');
  bool isOwnerLoading(String ownerId) => isLoading(ownerId, 'owners');
  bool isOfficeLoading(String officeId) => isLoading(officeId, 'offices');
  bool isBrokerLoading(String brokerId) => isLoading(brokerId, 'brokers');
  bool isWatchmenLoading(String watchmenId) =>
      isLoading(watchmenId, 'watchmen');
}
