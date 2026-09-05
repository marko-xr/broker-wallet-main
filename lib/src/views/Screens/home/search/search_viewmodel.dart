import 'dart:async';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/data/models/filter_model.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';

enum SearchResultType {
  request,
  offer,
  owner,
  office,
  broker,
  watchmen,
}

class SearchResult {
  final String id;
  final String title;
  final String subtitle;
  final String tinytitle;
  final String? imageUrl;
  final SearchResultType type;
  final dynamic data;
  final String searchQuery;

  SearchResult({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tinytitle,
    this.imageUrl,
    required this.type,
    required this.data,
    required this.searchQuery,
  });

  // Helper method to get localized badge text
  String getBadgeText(AppLocalizations localization) {
    switch (type) {
      case SearchResultType.request:
        return localization.translate('requested').toUpperCase();
      case SearchResultType.offer:
        return localization.translate('offers').toUpperCase();
      case SearchResultType.owner:
        return localization.translate('owners').toUpperCase();
      case SearchResultType.office:
        return localization.translate('offices').toUpperCase();
      case SearchResultType.broker:
        return localization.translate('brokers').toUpperCase();
      case SearchResultType.watchmen:
        return localization.translate('watchmen').toUpperCase();
    }
  }

  String get favoriteTypeKey {
    switch (type) {
      case SearchResultType.request:
        return 'requests';
      case SearchResultType.offer:
        return 'offers';
      case SearchResultType.owner:
        return 'owners';
      case SearchResultType.office:
        return 'offices';
      case SearchResultType.broker:
        return 'brokers';
      case SearchResultType.watchmen:
        return 'watchmen';
    }
  }
}

class SearchViewModel extends ChangeNotifier {
  String query = '';
  List<SearchResult> searchResults = [];
  bool isLoading = false;
  String? error;

  final List<FilterModel> filters = [
    FilterModel(label: 'All', labelKey: 'all', selected: true),
    FilterModel(label: 'Requested', labelKey: 'requested'),
    FilterModel(label: 'Offers', labelKey: 'offers'),
    FilterModel(label: 'Owners', labelKey: 'owners'),
    FilterModel(label: 'Offices', labelKey: 'offices'),
    FilterModel(label: 'Brokers', labelKey: 'brokers'),
    FilterModel(label: 'Watchmen', labelKey: 'watchmen'),
  ];

  // Use lazy getters to avoid accessing Firebase before initialization
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  Timer? _debounceTimer;

  // In-memory cache for all data
  Map<String, List<dynamic>> _dataCache = {};
  bool _cacheInitialized = false;
  DateTime? _lastCacheUpdate;
  static const Duration _cacheValidDuration = Duration(minutes: 5);

  // Pre-built search indices for faster lookups
  Map<String, List<SearchResult>> _searchIndices = {};

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void updateQuery(String q) {
    query = q;

    // Cancel previous timer
    _debounceTimer?.cancel();

    if (q.trim().isNotEmpty) {
      // Reduce debounce time for better responsiveness
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        _performOptimizedSearch();
      });
    } else {
      // Clear results immediately when query is empty
      searchResults.clear();
      error = null;
      notifyListeners();
    }
  }

  void toggleFilter(int index) {
    // If the tapped filter is already selected, deselect it
    if (filters[index].selected) {
      filters[index].selected = false;
    } else {
      // Deselect all other filters
      for (int i = 0; i < filters.length; i++) {
        filters[i].selected = false;
      }
      // Select the tapped filter
      filters[index].selected = true;
    }

    // Re-search if we have a query - this will be instant since data is cached
    if (query.trim().isNotEmpty) {
      _performOptimizedSearch();
    }
    notifyListeners();
  }

  FilterModel? get selectedFilter {
    try {
      return filters.firstWhere((filter) => filter.selected);
    } catch (e) {
      if (filters.isNotEmpty) {
        filters[0].selected = true;
        return filters[0];
      }
      return null;
    }
  }

  String? get selectedFilterKey {
    final selected = selectedFilter;
    return selected?.labelKey ?? 'all';
  }

  bool get hasResults {
    return query.isNotEmpty && searchResults.isNotEmpty;
  }

  bool get hasQuery {
    return query.trim().isNotEmpty;
  }

  // Initialize cache on first search
  Future<void> _initializeCache() async {
    if (_cacheInitialized && _isCacheValid()) {
      return; // Cache is still valid
    }

    try {
      if (SupabaseConfig.useSupabaseAuth) {
        final service = SupabaseCoreEntitiesService();
        final results = await Future.wait<List<dynamic>>([
          service.getRequests().first,
          service.getOffers().first,
          service.getOwners().first,
          service.getOffices().first,
          service.getBrokers().first,
          service.getWatchmen().first,
        ]);
        _dataCache = {
          'requests': results[0],
          'offers': results[1],
          'owners': results[2],
          'offices': results[3],
          'brokers': results[4],
          'watchmen': results[5],
        };
        _cacheInitialized = true;
        _lastCacheUpdate = DateTime.now();
        _buildSearchIndices();
        return;
      }

      final currentUserId =
          RepositoryProvider.instance.authRepository.currentUserId;
      if (currentUserId == null) return;

      // Fetch all data in parallel
      final futures = await Future.wait([
        _firestore
            .collection('users')
            .doc(currentUserId)
            .collection('requests')
            .get(),
        _firestore
            .collection('users')
            .doc(currentUserId)
            .collection('offers')
            .get(),
        _firestore
            .collection('users')
            .doc(currentUserId)
            .collection('owners')
            .get(),
        _firestore
            .collection('users')
            .doc(currentUserId)
            .collection('offices')
            .get(),
        _firestore
            .collection('users')
            .doc(currentUserId)
            .collection('brokers')
            .get(),
        _firestore
            .collection('users')
            .doc(currentUserId)
            .collection('watchmen')
            .get(),
      ]);

      // Convert to models and cache
      _dataCache['requests'] = futures[0]
          .docs
          .map((doc) => RequestModel.fromFirestore(doc))
          .toList();
      _dataCache['offers'] =
          futures[1].docs.map((doc) => OfferModel.fromFirestore(doc)).toList();
      _dataCache['owners'] =
          futures[2].docs.map((doc) => OwnerModel.fromFirestore(doc)).toList();
      _dataCache['offices'] =
          futures[3].docs.map((doc) => OfficeModel.fromFirestore(doc)).toList();
      _dataCache['brokers'] =
          futures[4].docs.map((doc) => BrokerModel.fromFirestore(doc)).toList();
      _dataCache['watchmen'] = futures[5]
          .docs
          .map((doc) => WatchmenModel.fromFirestore(doc))
          .toList();

      _cacheInitialized = true;
      _lastCacheUpdate = DateTime.now();

      // Pre-build search indices for common queries
      _buildSearchIndices();
    } catch (e) {
      // Handle initialization error silently
    }
  }

  bool _isCacheValid() {
    if (_lastCacheUpdate == null) return false;
    return DateTime.now().difference(_lastCacheUpdate!) < _cacheValidDuration;
  }

  void _buildSearchIndices() {
    // Pre-build indices for numbers 0-9 for faster phone number searches
    for (int i = 0; i <= 9; i++) {
      final digit = i.toString();
      _searchIndices[digit] = _searchInCachedData(digit);
    }

    // Pre-build indices for common two-digit combinations
    for (int i = 0; i <= 9; i++) {
      for (int j = 0; j <= 9; j++) {
        final combo = '$i$j';
        if (combo == '05' ||
            combo == '04' ||
            combo == '02' ||
            combo == '03' ||
            combo == '06' ||
            combo == '07' ||
            combo == '09') {
          _searchIndices[combo] = _searchInCachedData(combo);
        }
      }
    }
  }

  // Optimized search using cached data
  Future<void> _performOptimizedSearch() async {
    if (query.trim().isEmpty) return;

    // Set loading only for the initial cache load
    if (!_cacheInitialized) {
      isLoading = true;
      notifyListeners();
    }

    try {
      // Initialize cache if needed
      await _initializeCache();

      // Use pre-built index if available
      if (_searchIndices.containsKey(query)) {
        searchResults = _searchIndices[query]!
            .where((result) => _matchesFilter(result))
            .map((result) => SearchResult(
                  id: result.id,
                  title: result.title,
                  subtitle: result.subtitle,
                  tinytitle: result.tinytitle,
                  imageUrl: result.imageUrl,
                  type: result.type,
                  data: result.data,
                  searchQuery: query,
                ))
            .toList();
      } else {
        // Perform search in cached data
        searchResults = _searchInCachedData(query)
            .where((result) => _matchesFilter(result))
            .map((result) => SearchResult(
                  id: result.id,
                  title: result.title,
                  subtitle: result.subtitle,
                  tinytitle: result.tinytitle,
                  imageUrl: result.imageUrl,
                  type: result.type,
                  data: result.data,
                  searchQuery: query,
                ))
            .toList();
      }

      error = null;
    } catch (e) {
      error = 'Search failed: ${e.toString()}';
      searchResults.clear();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // Fast in-memory search
  List<SearchResult> _searchInCachedData(String searchQuery) {
    final results = <SearchResult>[];
    final queryLower = searchQuery.toLowerCase();

    // Search requests
    final requests = _dataCache['requests'] as List<RequestModel>? ?? [];
    for (final request in requests) {
      if (_matchesRequestQuery(request, queryLower)) {
        results.add(_createRequestSearchResult(request, searchQuery));
      }
    }

    // Search offers
    final offers = _dataCache['offers'] as List<OfferModel>? ?? [];
    for (final offer in offers) {
      if (_matchesOfferQuery(offer, queryLower)) {
        results.add(_createOfferSearchResult(offer, searchQuery));
      }
    }

    // Search owners
    final owners = _dataCache['owners'] as List<OwnerModel>? ?? [];
    for (final owner in owners) {
      if (_matchesOwnerQuery(owner, queryLower) ||
          _matchesPhoneNumberPartial(owner.phoneNumber, searchQuery)) {
        results.add(_createOwnerSearchResult(owner, searchQuery));
      }
    }

    // Search offices
    final offices = _dataCache['offices'] as List<OfficeModel>? ?? [];
    for (final office in offices) {
      if (_matchesOfficeQuery(office, queryLower) ||
          _matchesPhoneNumberPartial(office.phoneNumber, searchQuery)) {
        results.add(_createOfficeSearchResult(office, searchQuery));
      }
    }

    // Search brokers
    final brokers = _dataCache['brokers'] as List<BrokerModel>? ?? [];
    for (final broker in brokers) {
      if (_matchesBrokerQuery(broker, queryLower) ||
          _matchesPhoneNumberPartial(broker.phoneNumber, searchQuery)) {
        results.add(_createBrokerSearchResult(broker, searchQuery));
      }
    }

    // Search watchmen
    final watchmen = _dataCache['watchmen'] as List<WatchmenModel>? ?? [];
    for (final watchman in watchmen) {
      if (_matchesWatchmenQuery(watchman, queryLower) ||
          _matchesPhoneNumberPartial(watchman.phoneNumber, searchQuery)) {
        results.add(_createWatchmenSearchResult(watchman, searchQuery));
      }
    }

    return results;
  }

  // Filter results based on selected filter
  bool _matchesFilter(SearchResult result) {
    final selectedFilterKey = this.selectedFilterKey;
    if (selectedFilterKey == 'all') return true;

    switch (selectedFilterKey) {
      case 'requested':
        return result.type == SearchResultType.request;
      case 'offers':
        return result.type == SearchResultType.offer;
      case 'owners':
        return result.type == SearchResultType.owner;
      case 'offices':
        return result.type == SearchResultType.office;
      case 'brokers':
        return result.type == SearchResultType.broker;
      case 'watchmen':
        return result.type == SearchResultType.watchmen;
      default:
        return true;
    }
  }

  // Optimized query matching methods with bilingual support
  bool _matchesRequestQuery(RequestModel request, String queryLower) {
    // Basic text fields search
    final searchableFields = [
      request.location,
      request.selectedCity,
      request.propertyType ?? '',
      request.specificPropertyType,
      request.requestType,
      request.notes,
      request.squareFootage,
      request.minPrice,
      request.maxPrice,
      request.selectedAreas.join(' '),
    ];

    // Check if query matches any field in both languages
    for (final field in searchableFields) {
      if (_containsQuery(field, queryLower)) return true;
    }

    // Phone number search
    if (_matchesPhoneNumberPartial(request.phoneNumber, queryLower)) {
      return true;
    }

    // Localized property type search (for translated content)
    if (_matchesLocalizedPropertyType(request.propertyType, queryLower) ||
        _matchesLocalizedPropertyType(
            request.specificPropertyType, queryLower)) {
      return true;
    }

    // City name search in both languages
    if (_matchesLocalizedCity(request.selectedCity, queryLower)) {
      return true;
    }

    return false;
  }

  bool _matchesOfferQuery(OfferModel offer, String queryLower) {
    // Basic text fields search
    final searchableFields = [
      offer.location,
      offer.selectedCity,
      offer.propertyType ?? '',
      offer.specificPropertyType,
      offer.offerType,
      offer.notes,
      offer.squareFootage,
      offer.minPrice,
      offer.maxPrice,
      offer.pickUpLocation,
      offer.pickUpAddress,
      offer.selectedAreas.join(' '),
    ];

    // Check if query matches any field in both languages
    for (final field in searchableFields) {
      if (_containsQuery(field, queryLower)) return true;
    }

    // Phone number search
    if (_matchesPhoneNumberPartial(offer.phoneNumber, queryLower)) {
      return true;
    }

    // Localized property type search (for translated content)
    if (_matchesLocalizedPropertyType(offer.propertyType, queryLower) ||
        _matchesLocalizedPropertyType(offer.specificPropertyType, queryLower)) {
      return true;
    }

    // City name search in both languages
    if (_matchesLocalizedCity(offer.selectedCity, queryLower)) {
      return true;
    }

    return false;
  }

  bool _matchesOwnerQuery(OwnerModel owner, String queryLower) {
    // Basic text fields search
    final searchableFields = [
      owner.name,
      owner.typeOfProperties,
      owner.notes,
      owner.propertyLocation,
      owner.pickUpLocation,
      owner.pickUpAddress,
    ];

    // Check if query matches any field
    for (final field in searchableFields) {
      if (_containsQuery(field, queryLower)) return true;
    }

    // Phone number search
    if (_matchesPhoneNumberPartial(owner.phoneNumber, queryLower)) {
      return true;
    }

    return false;
  }

  bool _matchesOfficeQuery(OfficeModel office, String queryLower) {
    // Basic text fields search
    final searchableFields = [
      office.officeName,
      office.officeLocation,
      office.notes,
      office.pickUpLocation,
      office.pickUpAddress,
    ];

    // Check if query matches any field
    for (final field in searchableFields) {
      if (_containsQuery(field, queryLower)) return true;
    }

    // Phone number search
    if (_matchesPhoneNumberPartial(office.phoneNumber, queryLower)) {
      return true;
    }

    return false;
  }

  bool _matchesBrokerQuery(BrokerModel broker, String queryLower) {
    // Basic text fields search
    final searchableFields = [
      broker.name,
      broker.notes,
    ];

    // Check if query matches any field
    for (final field in searchableFields) {
      if (_containsQuery(field, queryLower)) return true;
    }

    // Phone number search
    if (_matchesPhoneNumberPartial(broker.phoneNumber, queryLower)) {
      return true;
    }

    return false;
  }

  bool _matchesWatchmenQuery(WatchmenModel watchmen, String queryLower) {
    // Basic text fields search
    final searchableFields = [
      watchmen.name,
      watchmen.buildingName,
      watchmen.notes,
      watchmen.buildingLocation,
      watchmen.pickUpLocation,
      watchmen.pickUpAddress,
    ];

    // Check if query matches any field
    for (final field in searchableFields) {
      if (_containsQuery(field, queryLower)) return true;
    }

    // Phone number search
    if (_matchesPhoneNumberPartial(watchmen.phoneNumber, queryLower)) {
      return true;
    }

    return false;
  }

  // Optimized phone number matching
  bool _matchesPhoneNumberPartial(String phoneNumber, String query) {
    if (phoneNumber.isEmpty || query.length < 2) return false;

    final cleanQuery = query.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanQuery.length < 2) return false;

    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');

    // Quick check for direct matches
    if (cleanPhone.contains(cleanQuery)) return true;

    // Check international/local format conversions
    if (phoneNumber.startsWith('+971') && cleanPhone.length == 12) {
      final localFormat = '0${cleanPhone.substring(3)}';
      if (localFormat.contains(cleanQuery)) return true;
    }

    if (cleanPhone.startsWith('0') && cleanPhone.length == 10) {
      final internationalFormat = '971${cleanPhone.substring(1)}';
      if (internationalFormat.contains(cleanQuery)) return true;
    }

    return false;
  }

  // Optimized result creation methods
  SearchResult _createRequestSearchResult(
      RequestModel request, String searchQuery) {
    String propertyDisplay = '';
    if (request.propertyType != null && request.propertyType!.isNotEmpty) {
      propertyDisplay = request.propertyType!;
      if (request.specificPropertyType.isNotEmpty) {
        propertyDisplay += ' - ${request.specificPropertyType}';
      }
    } else if (request.specificPropertyType.isNotEmpty) {
      propertyDisplay = request.specificPropertyType;
    }

    return SearchResult(
      id: request.id ?? '',
      title: request.requestType.toUpperCase(),
      subtitle: request.selectedCity,
      tinytitle: propertyDisplay.isEmpty ? 'No property type' : propertyDisplay,
      imageUrl: null,
      type: SearchResultType.request,
      data: request,
      searchQuery: searchQuery,
    );
  }

  SearchResult _createOfferSearchResult(OfferModel offer, String searchQuery) {
    String propertyDisplay = '';
    if (offer.propertyType != null && offer.propertyType!.isNotEmpty) {
      propertyDisplay = offer.propertyType!;
      if (offer.specificPropertyType.isNotEmpty) {
        propertyDisplay += ' - ${offer.specificPropertyType}';
      }
    } else if (offer.specificPropertyType.isNotEmpty) {
      propertyDisplay = offer.specificPropertyType;
    }

    return SearchResult(
      id: offer.id ?? '',
      title: offer.offerType.toUpperCase(),
      subtitle: offer.selectedCity,
      tinytitle: propertyDisplay.isEmpty ? 'No property type' : propertyDisplay,
      imageUrl:
          offer.mediaUrls.isNotEmpty ? offer.mediaUrls.first : offer.mediaUrl,
      type: SearchResultType.offer,
      data: offer,
      searchQuery: searchQuery,
    );
  }

  SearchResult _createOwnerSearchResult(OwnerModel owner, String searchQuery) {
    return SearchResult(
      id: owner.id ?? '',
      title: owner.name,
      subtitle: owner.typeOfProperties.isNotEmpty
          ? owner.typeOfProperties
          : 'No property type specified',
      tinytitle: owner.phoneNumber.isNotEmpty
          ? _formatPhoneNumberDisplay(owner.phoneNumber)
          : 'No phone number',
      imageUrl:
          owner.mediaUrls.isNotEmpty ? owner.mediaUrls.first : owner.mediaUrl,
      type: SearchResultType.owner,
      data: owner,
      searchQuery: searchQuery,
    );
  }

  SearchResult _createOfficeSearchResult(
      OfficeModel office, String searchQuery) {
    return SearchResult(
      id: office.id ?? '',
      title: office.officeName,
      subtitle: office.officeLocation,
      tinytitle: office.phoneNumber.isNotEmpty
          ? _formatPhoneNumberDisplay(office.phoneNumber)
          : 'No phone number',
      imageUrl: null,
      type: SearchResultType.office,
      data: office,
      searchQuery: searchQuery,
    );
  }

  SearchResult _createBrokerSearchResult(
      BrokerModel broker, String searchQuery) {
    return SearchResult(
      id: broker.id ?? '',
      title: broker.name,
      subtitle: broker.phoneNumber.isNotEmpty
          ? _formatPhoneNumberDisplay(broker.phoneNumber)
          : 'No phone number',
      tinytitle: '',
      imageUrl: null,
      type: SearchResultType.broker,
      data: broker,
      searchQuery: searchQuery,
    );
  }

  SearchResult _createWatchmenSearchResult(
      WatchmenModel watchmen, String searchQuery) {
    return SearchResult(
      id: watchmen.id ?? '',
      title: watchmen.name,
      subtitle: watchmen.buildingName,
      tinytitle: watchmen.phoneNumber.isNotEmpty
          ? _formatPhoneNumberDisplay(watchmen.phoneNumber)
          : 'No phone number',
      imageUrl: null,
      type: SearchResultType.watchmen,
      data: watchmen,
      searchQuery: searchQuery,
    );
  }

  String _formatPhoneNumberDisplay(String phoneNumber) {
    if (phoneNumber.isEmpty) return '';

    if (phoneNumber.startsWith('+971')) {
      String numberWithoutCountryCode = phoneNumber.substring(4);
      if (!numberWithoutCountryCode.startsWith('0')) {
        numberWithoutCountryCode = '0$numberWithoutCountryCode';
      }
      return numberWithoutCountryCode;
    }

    if (phoneNumber.startsWith('05')) {
      return phoneNumber;
    }

    if (phoneNumber.startsWith('5') && phoneNumber.length >= 8) {
      return '0$phoneNumber';
    }

    return phoneNumber;
  }

  // Public method to refresh cache manually
  void refreshCache() {
    _cacheInitialized = false;
    _dataCache.clear();
    _searchIndices.clear();
    if (query.trim().isNotEmpty) {
      _performOptimizedSearch();
    }
  }

  // Helper methods for bilingual search support

  /// Enhanced text matching that supports both Arabic and English
  bool _containsQuery(String text, String queryLower) {
    if (text.isEmpty || queryLower.isEmpty) return false;

    final textLower = text.toLowerCase();

    // Direct text matching
    if (textLower.contains(queryLower)) return true;

    // Remove diacritics and special characters for Arabic text matching
    final normalizedText = _normalizeArabicText(textLower);
    final normalizedQuery = _normalizeArabicText(queryLower);

    return normalizedText.contains(normalizedQuery);
  }

  /// Normalize Arabic text by removing diacritics and common variations
  String _normalizeArabicText(String text) {
    return text
        .replaceAll(RegExp(r'[ًٌٍَُِّْ]'), '') // Remove diacritics
        .replaceAll('أ', 'ا') // Normalize alef
        .replaceAll('إ', 'ا') // Normalize alef
        .replaceAll('آ', 'ا') // Normalize alef
        .replaceAll('ة', 'ه') // Normalize taa marbouta
        .replaceAll('ى', 'ي') // Normalize yaa
        .trim();
  }

  /// Check if query matches localized property types
  bool _matchesLocalizedPropertyType(String? propertyType, String queryLower) {
    if (propertyType == null || propertyType.isEmpty) return false;

    // Direct match
    if (_containsQuery(propertyType, queryLower)) return true;

    // Check common property type translations
    final propertyTypeLower = propertyType.toLowerCase();

    // English to Arabic common mappings
    final translations = {
      'apartment': ['شقة', 'شقه'],
      'villa': ['فيلا', 'فيله'],
      'studio': ['ستوديو', 'استوديو'],
      'townhouse': ['تاون هاوس', 'تاونهاوس'],
      'penthouse': ['بنتهاوس', 'بنت هاوس'],
      'commercial': ['تجاري', 'تجارى'],
      'residential': ['سكني', 'سكنى'],
      'office': ['مكتب', 'مكاتب'],
      'retail': ['تجزئة', 'متجر'],
      'warehouse': ['مستودع', 'مخزن'],
    };

    for (final entry in translations.entries) {
      if (propertyTypeLower.contains(entry.key)) {
        for (final arabicTranslation in entry.value) {
          if (_containsQuery(arabicTranslation, queryLower)) return true;
        }
      }

      // Check reverse (Arabic to English)
      for (final arabicTranslation in entry.value) {
        if (_containsQuery(propertyType, arabicTranslation)) {
          if (queryLower.contains(entry.key)) return true;
        }
      }
    }

    return false;
  }

  /// Check if query matches localized city names
  bool _matchesLocalizedCity(String city, String queryLower) {
    if (city.isEmpty) return false;

    // Direct match
    if (_containsQuery(city, queryLower)) return true;

    // Check city name translations
    final cityLower = city.toLowerCase();

    final cityTranslations = {
      'dubai': ['دبي', 'دبى'],
      'abu dhabi': ['أبوظبي', 'أبو ظبي', 'ابوظبي'],
      'sharjah': ['الشارقة', 'شارجة'],
      'ajman': ['عجمان', 'عجمان'],
      'fujairah': ['الفجيرة', 'فجيرة'],
      'ras al khaimah': ['رأس الخيمة', 'راس الخيمة'],
      'umm al quwain': ['أم القيوين', 'ام القيوين'],
    };

    for (final entry in cityTranslations.entries) {
      if (cityLower.contains(entry.key) || entry.key.contains(cityLower)) {
        for (final arabicTranslation in entry.value) {
          if (_containsQuery(arabicTranslation, queryLower)) return true;
        }
      }

      // Check reverse (Arabic to English)
      for (final arabicTranslation in entry.value) {
        if (_containsQuery(city, arabicTranslation)) {
          if (queryLower.contains(entry.key)) return true;
        }
      }
    }

    return false;
  }
}
