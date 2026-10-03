import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

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

  /// The query these results answer (trimmed, whitespace collapsed), used to
  /// highlight what matched.
  final String searchQuery;

  /// A key that identifies this logical record in a list: its type and id. Two
  /// different record types with the same id are different results. A record
  /// that has no id gets one made from its position, so keys never collide.
  final String stableKey;

  SearchResult({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tinytitle,
    this.imageUrl,
    required this.type,
    required this.data,
    required this.searchQuery,
    String? stableKey,
  }) : stableKey = stableKey ?? '${type.name}:$id';

  /// The same result, answering [query].
  SearchResult withQuery(String query) => SearchResult(
        id: id,
        title: title,
        subtitle: subtitle,
        tinytitle: tinytitle,
        imageUrl: imageUrl,
        type: type,
        data: data,
        searchQuery: query,
        stableKey: stableKey,
      );

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
