// lib/src/data/models/analytics_model.dart

/// Comprehensive analytics data model for business insights
class AnalyticsData {
  // Summary metrics
  final int totalProperties;
  final double portfolioValue;
  final int activeRequests;
  final int closedDeals;

  // Performance metrics
  final double avgResponseTime; // in days
  final double conversionRate; // percentage (0-100)
  final double avgCommission; // in AED

  // Distribution data for charts
  final Map<String, int> propertiesByType; // {'Apartment': 12, 'Villa': 5}
  final Map<String, int> propertiesByArea; // {'Downtown': 8, 'Marina': 12}
  final Map<String, double>
      revenueByMonth; // {'2025-10': 45000, '2025-09': 38000}
  final Map<String, int> addedOverTime; // {'2025-10-01': 3, '2025-10-08': 5}

  // Price distribution
  final Map<String, int> priceRanges; // {'0-1M': 10, '1M-2M': 15}

  // Smart insights data
  final String mostActiveArea;
  final int mostActiveAreaCount;
  final List<String> staleListings; // IDs of listings not updated in 30+ days

  // Timestamp
  final DateTime lastUpdated;

  const AnalyticsData({
    required this.totalProperties,
    required this.portfolioValue,
    required this.activeRequests,
    required this.closedDeals,
    required this.avgResponseTime,
    required this.conversionRate,
    required this.avgCommission,
    required this.propertiesByType,
    required this.propertiesByArea,
    required this.revenueByMonth,
    required this.addedOverTime,
    required this.priceRanges,
    required this.mostActiveArea,
    required this.mostActiveAreaCount,
    required this.staleListings,
    required this.lastUpdated,
  });

  /// Empty analytics (for offline fallback)
  factory AnalyticsData.empty() {
    return AnalyticsData(
      totalProperties: 0,
      portfolioValue: 0.0,
      activeRequests: 0,
      closedDeals: 0,
      avgResponseTime: 0.0,
      conversionRate: 0.0,
      avgCommission: 0.0,
      propertiesByType: {},
      propertiesByArea: {},
      revenueByMonth: {},
      addedOverTime: {},
      priceRanges: {},
      mostActiveArea: '',
      mostActiveAreaCount: 0,
      staleListings: [],
      lastUpdated: DateTime.now(),
    );
  }

  /// Compact summary for home screen card (3 metrics only)
  Map<String, dynamic> getSummaryMetrics() {
    return {
      'totalProperties': totalProperties,
      'portfolioValue': portfolioValue,
      'activeRequests': activeRequests,
    };
  }

  /// Convert to JSON (for caching)
  Map<String, dynamic> toJson() {
    return {
      'totalProperties': totalProperties,
      'portfolioValue': portfolioValue,
      'activeRequests': activeRequests,
      'closedDeals': closedDeals,
      'avgResponseTime': avgResponseTime,
      'conversionRate': conversionRate,
      'avgCommission': avgCommission,
      'propertiesByType': propertiesByType,
      'propertiesByArea': propertiesByArea,
      'revenueByMonth': revenueByMonth,
      'addedOverTime': addedOverTime,
      'priceRanges': priceRanges,
      'mostActiveArea': mostActiveArea,
      'mostActiveAreaCount': mostActiveAreaCount,
      'staleListings': staleListings,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  /// Create from JSON (for cache restoration)
  factory AnalyticsData.fromJson(Map<String, dynamic> json) {
    return AnalyticsData(
      totalProperties: json['totalProperties'] ?? 0,
      portfolioValue: (json['portfolioValue'] ?? 0.0).toDouble(),
      activeRequests: json['activeRequests'] ?? 0,
      closedDeals: json['closedDeals'] ?? 0,
      avgResponseTime: (json['avgResponseTime'] ?? 0.0).toDouble(),
      conversionRate: (json['conversionRate'] ?? 0.0).toDouble(),
      avgCommission: (json['avgCommission'] ?? 0.0).toDouble(),
      propertiesByType: Map<String, int>.from(json['propertiesByType'] ?? {}),
      propertiesByArea: Map<String, int>.from(json['propertiesByArea'] ?? {}),
      revenueByMonth: Map<String, double>.from(json['revenueByMonth'] ?? {}),
      addedOverTime: Map<String, int>.from(json['addedOverTime'] ?? {}),
      priceRanges: Map<String, int>.from(json['priceRanges'] ?? {}),
      mostActiveArea: json['mostActiveArea'] ?? '',
      mostActiveAreaCount: json['mostActiveAreaCount'] ?? 0,
      staleListings: List<String>.from(json['staleListings'] ?? []),
      lastUpdated: DateTime.parse(
        json['lastUpdated'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }

  /// Copy with method for updates
  AnalyticsData copyWith({
    int? totalProperties,
    double? portfolioValue,
    int? activeRequests,
    int? closedDeals,
    double? avgResponseTime,
    double? conversionRate,
    double? avgCommission,
    Map<String, int>? propertiesByType,
    Map<String, int>? propertiesByArea,
    Map<String, double>? revenueByMonth,
    Map<String, int>? addedOverTime,
    Map<String, int>? priceRanges,
    String? mostActiveArea,
    int? mostActiveAreaCount,
    List<String>? staleListings,
    DateTime? lastUpdated,
  }) {
    return AnalyticsData(
      totalProperties: totalProperties ?? this.totalProperties,
      portfolioValue: portfolioValue ?? this.portfolioValue,
      activeRequests: activeRequests ?? this.activeRequests,
      closedDeals: closedDeals ?? this.closedDeals,
      avgResponseTime: avgResponseTime ?? this.avgResponseTime,
      conversionRate: conversionRate ?? this.conversionRate,
      avgCommission: avgCommission ?? this.avgCommission,
      propertiesByType: propertiesByType ?? this.propertiesByType,
      propertiesByArea: propertiesByArea ?? this.propertiesByArea,
      revenueByMonth: revenueByMonth ?? this.revenueByMonth,
      addedOverTime: addedOverTime ?? this.addedOverTime,
      priceRanges: priceRanges ?? this.priceRanges,
      mostActiveArea: mostActiveArea ?? this.mostActiveArea,
      mostActiveAreaCount: mostActiveAreaCount ?? this.mostActiveAreaCount,
      staleListings: staleListings ?? this.staleListings,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

/// Analytics summary for quick display (home screen card)
class AnalyticsSummary {
  final int totalProperties;
  final String portfolioValueFormatted; // "12.5M AED"
  final int activeRequests;
  final bool isLoading;

  const AnalyticsSummary({
    required this.totalProperties,
    required this.portfolioValueFormatted,
    required this.activeRequests,
    this.isLoading = false,
  });

  factory AnalyticsSummary.loading() {
    return const AnalyticsSummary(
      totalProperties: 0,
      portfolioValueFormatted: '---',
      activeRequests: 0,
      isLoading: true,
    );
  }

  factory AnalyticsSummary.fromAnalyticsData(AnalyticsData data) {
    return AnalyticsSummary(
      totalProperties: data.totalProperties,
      portfolioValueFormatted: _formatCurrency(data.portfolioValue),
      activeRequests: data.activeRequests,
      isLoading: false,
    );
  }

  static String _formatCurrency(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M AED';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}K AED';
    } else {
      return '${value.toStringAsFixed(0)} AED';
    }
  }
}
