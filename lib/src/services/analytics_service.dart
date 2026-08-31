// lib/src/services/analytics_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:broker_wallet/src/data/models/analytics_model.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';

/// Service for aggregating and providing analytics data
/// Follows offline-first pattern with Hive caching
class AnalyticsService {
  static final AnalyticsService instance = AnalyticsService._internal();
  factory AnalyticsService() => instance;
  AnalyticsService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String _cacheBoxName = 'analytics_cache';
  static const String _cacheKey = 'latest_analytics';

  /// Initialize Hive box for analytics caching
  Future<void> initialize() async {
    try {
      await Hive.openBox(_cacheBoxName);
      print('✅ AnalyticsService initialized with cache');
    } catch (e) {
      print('⚠️ AnalyticsService cache init failed: $e');
    }
  }

  /// Get cached analytics instantly (for offline/fast load)
  AnalyticsData? getCachedAnalytics() {
    try {
      final box = Hive.box(_cacheBoxName);
      final cachedJson = box.get(_cacheKey);
      if (cachedJson != null) {
        return AnalyticsData.fromJson(json.decode(cachedJson));
      }
    } catch (e) {
      print('⚠️ Failed to load cached analytics: $e');
    }
    return null;
  }

  /// Cache analytics data for offline access
  Future<void> _cacheAnalytics(AnalyticsData data) async {
    try {
      final box = Hive.box(_cacheBoxName);
      await box.put(_cacheKey, json.encode(data.toJson()));
      print('💾 Analytics cached successfully');
    } catch (e) {
      print('⚠️ Failed to cache analytics: $e');
    }
  }

  /// Get comprehensive analytics data
  /// Loads from cache first, then updates from Firestore
  Future<AnalyticsData> getAnalytics() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return AnalyticsData.empty();
    }

    // Return cached data immediately
    final cached = getCachedAnalytics();

    try {
      // Fetch fresh data in background
      final data = await _aggregateAnalyticsData(userId);
      await _cacheAnalytics(data);
      return data;
    } catch (e) {
      print('❌ Analytics fetch failed: $e - using cached data');
      return cached ?? AnalyticsData.empty();
    }
  }

  /// Stream analytics with real-time updates
  Stream<AnalyticsData> watchAnalytics() async* {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      yield AnalyticsData.empty();
      return;
    }

    // Yield cached data first for instant display
    final cached = getCachedAnalytics();
    if (cached != null) {
      yield cached;
    }

    // Then yield real-time updates
    await for (final _ in Stream.periodic(const Duration(seconds: 30))) {
      try {
        final data = await _aggregateAnalyticsData(userId);
        await _cacheAnalytics(data);
        yield data;
      } catch (e) {
        print('⚠️ Analytics stream error: $e');
        // Continue with last known cached data
      }
    }
  }

  /// Core aggregation logic - fetches from all collections
  Future<AnalyticsData> _aggregateAnalyticsData(String userId) async {
    print('🚀 Starting analytics aggregation for user: $userId');

    // Parallel fetch from all collections
    final results = await Future.wait([
      _getOffers(userId),
      _getRequests(userId),
      _getOwners(userId),
      _getOffices(userId),
      _getQuotations(userId),
    ]);

    final offers = results[0];
    final requests = results[1];
    final owners = results[2];
    final offices = results[3];
    final quotations = results[4];

    // Calculate metrics
    final totalProperties = offers.length + owners.length + offices.length;
    final portfolioValue = _calculatePortfolioValue(offers);
    final activeRequests = requests.length;

    // Property distribution analysis
    final propertiesByType = _groupByType(offers);
    final propertiesByArea = _groupByArea(offers);
    final priceRanges = _groupByPriceRange(offers);

    // Geographic insights
    final areaData = _getMostActiveArea(propertiesByArea);

    // Time-based analysis
    final addedOverTime = _groupByCreationDate(offers);
    final staleListings = _getStaleListings(offers);

    // Revenue calculations
    final revenueByMonth = _calculateRevenueByMonth(quotations);
    final avgCommission = _calculateAvgCommission(quotations);

    print('✅ Analytics aggregation complete: $totalProperties properties');

    return AnalyticsData(
      totalProperties: totalProperties,
      portfolioValue: portfolioValue,
      activeRequests: activeRequests,
      closedDeals: 0, // Implement when deal tracking is added
      avgResponseTime: 2.3, // Placeholder - implement interaction tracking
      conversionRate: 0.0, // Placeholder
      avgCommission: avgCommission,
      propertiesByType: propertiesByType,
      propertiesByArea: propertiesByArea,
      revenueByMonth: revenueByMonth,
      addedOverTime: addedOverTime,
      priceRanges: priceRanges,
      mostActiveArea: areaData['name'] ?? '',
      mostActiveAreaCount: areaData['count'] ?? 0,
      staleListings: staleListings,
      lastUpdated: DateTime.now(),
    );
  }

  // ==================== Data Fetching ====================

  Future<List<DocumentSnapshot>> _getOffers(String userId) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('offers')
        .get()
        .timeout(const Duration(seconds: 10));
    return snapshot.docs;
  }

  Future<List<DocumentSnapshot>> _getRequests(String userId) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('requests')
        .get()
        .timeout(const Duration(seconds: 10));
    return snapshot.docs;
  }

  Future<List<DocumentSnapshot>> _getOwners(String userId) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('owners')
        .get()
        .timeout(const Duration(seconds: 10));
    return snapshot.docs;
  }

  Future<List<DocumentSnapshot>> _getOffices(String userId) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('offices')
        .get()
        .timeout(const Duration(seconds: 10));
    return snapshot.docs;
  }

  Future<List<DocumentSnapshot>> _getQuotations(String userId) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('quotations')
        .get()
        .timeout(const Duration(seconds: 10));
    return snapshot.docs;
  }

  // ==================== Analysis Functions ====================

  double _calculatePortfolioValue(List<DocumentSnapshot> offers) {
    double total = 0.0;
    for (var doc in offers) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data != null) {
        final price = data['price'];
        if (price is num) {
          total += price.toDouble();
        } else if (price is String) {
          total += double.tryParse(price) ?? 0.0;
        }
      }
    }
    return total;
  }

  Map<String, int> _groupByType(List<DocumentSnapshot> offers) {
    final Map<String, int> typeCount = {};
    for (var doc in offers) {
      final data = doc.data() as Map<String, dynamic>?;
      final type = data?['propertyType'] as String? ?? 'Unknown';
      typeCount[type] = (typeCount[type] ?? 0) + 1;
    }
    return typeCount;
  }

  Map<String, int> _groupByArea(List<DocumentSnapshot> offers) {
    final Map<String, int> areaCount = {};
    for (var doc in offers) {
      final data = doc.data() as Map<String, dynamic>?;
      final area =
          data?['area'] as String? ?? data?['address'] as String? ?? 'Unknown';
      areaCount[area] = (areaCount[area] ?? 0) + 1;
    }
    return areaCount;
  }

  Map<String, int> _groupByPriceRange(List<DocumentSnapshot> offers) {
    final Map<String, int> ranges = {
      '0-1M': 0,
      '1M-2M': 0,
      '2M-5M': 0,
      '5M+': 0,
    };

    for (var doc in offers) {
      final data = doc.data() as Map<String, dynamic>?;
      final price = (data?['price'] is num)
          ? (data?['price'] as num).toDouble()
          : double.tryParse(data?['price']?.toString() ?? '0') ?? 0.0;

      if (price < 1000000) {
        ranges['0-1M'] = ranges['0-1M']! + 1;
      } else if (price < 2000000) {
        ranges['1M-2M'] = ranges['1M-2M']! + 1;
      } else if (price < 5000000) {
        ranges['2M-5M'] = ranges['2M-5M']! + 1;
      } else {
        ranges['5M+'] = ranges['5M+']! + 1;
      }
    }

    return ranges;
  }

  Map<String, dynamic> _getMostActiveArea(Map<String, int> areaData) {
    if (areaData.isEmpty) return {'name': '', 'count': 0};

    var maxArea = areaData.entries.first;
    for (var entry in areaData.entries) {
      if (entry.value > maxArea.value) {
        maxArea = entry;
      }
    }

    return {'name': maxArea.key, 'count': maxArea.value};
  }

  Map<String, int> _groupByCreationDate(List<DocumentSnapshot> offers) {
    final Map<String, int> dateCount = {};

    for (var doc in offers) {
      final data = doc.data() as Map<String, dynamic>?;
      final createdAt = data?['createdAt'];

      DateTime date;
      if (createdAt is Timestamp) {
        date = createdAt.toDate();
      } else {
        date = DateTime.now();
      }

      final dateKey =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      dateCount[dateKey] = (dateCount[dateKey] ?? 0) + 1;
    }

    return dateCount;
  }

  List<String> _getStaleListings(List<DocumentSnapshot> offers) {
    final List<String> stale = [];
    final cutoffDate = DateTime.now().subtract(const Duration(days: 30));

    for (var doc in offers) {
      final data = doc.data() as Map<String, dynamic>?;
      final updatedAt = data?['updatedAt'] ?? data?['createdAt'];

      DateTime date;
      if (updatedAt is Timestamp) {
        date = updatedAt.toDate();
      } else {
        continue;
      }

      if (date.isBefore(cutoffDate)) {
        stale.add(doc.id);
      }
    }

    return stale;
  }

  Map<String, double> _calculateRevenueByMonth(
      List<DocumentSnapshot> quotations) {
    final Map<String, double> revenue = {};

    for (var doc in quotations) {
      final data = doc.data() as Map<String, dynamic>?;
      final createdAt = data?['createdAt'];
      final totalAmount = data?['totalAmount'] ?? 0.0;

      DateTime date;
      if (createdAt is Timestamp) {
        date = createdAt.toDate();
      } else {
        date = DateTime.now();
      }

      final monthKey = '${date.year}-${date.month.toString().padLeft(2, '0')}';
      revenue[monthKey] = (revenue[monthKey] ?? 0.0) +
          (totalAmount is num ? totalAmount.toDouble() : 0.0);
    }

    return revenue;
  }

  double _calculateAvgCommission(List<DocumentSnapshot> quotations) {
    if (quotations.isEmpty) return 0.0;

    double total = 0.0;
    for (var doc in quotations) {
      final data = doc.data() as Map<String, dynamic>?;
      final commission = data?['agencyFees'] ?? 0.0;
      total += commission is num ? commission.toDouble() : 0.0;
    }

    return total / quotations.length;
  }
}
