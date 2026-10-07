import '../data/models/unified_item_model.dart';

/// The Home filters, in the order their chips appear.
enum HomeFilterKind {
  /// Records created in the last 12 hours.
  recentlyAdded('recentlyAdded', 'Recently Added'),

  /// The lowest-priced Offers and Requests.
  lessPrice('lessPrice', 'Less Price'),

  /// Records created in the last 7 days.
  thisWeek('thisWeek', 'This Week'),

  /// The highest-priced Offers and Requests.
  highestPrice('highestPrice', 'Highest Price'),

  /// Records changed, after they were created, in the last 12 hours.
  recentlyUpdated('recentlyUpdated', 'Recently Updated');

  const HomeFilterKind(this.labelKey, this.label, {this.isImplemented = true});

  /// The localization key of the chip's label.
  final String labelKey;

  /// The English text the chip falls back to.
  final String label;

  /// Whether the filter behind the chip exists. A chip whose filter is not built
  /// yet is shown, can be chosen, and says so; it never reads a record and never
  /// answers with a list, an empty list or an error.
  final bool isImplemented;
}

/// What each Home filter means, as pure functions of the records and the time.
///
/// Nothing here reads a clock, a backend or a screen: the records and "now" are
/// handed in, so the same input always gives the same list, in the same order.
///
/// **Time.** A window is elapsed time before [apply]'s `now` — 12 hours, or
/// 7 x 24 hours — not calendar days, not a calendar week and not anchored to
/// midnight. A record counts only when it was created (Recently Updated: last
/// changed) strictly after the start of the window, so one exactly at the start
/// is out. The comparison is between instants, so it makes no difference
/// whether a timestamp is held in UTC or local time, and no offset (the UAE's
/// included) is applied anywhere. A record whose own creation time is unknown
/// ([UnifiedItemModel.hasCreatedAt] is false) is never inside a creation
/// window, and one whose own last-change time is unknown
/// ([UnifiedItemModel.hasUpdatedAt] is false) never counts as updated: nothing
/// proves it is recent.
///
/// **Updated.** A record counts as updated only when it was changed *after* it
/// was created: its last-change time is strictly later than its creation time.
/// The database stamps both with the same instant when a record is created, so
/// a record that was never edited is not "updated" however new it is.
///
/// **Scope.** Quotations are not part of the Home filters: the filtered list has
/// no tile for them, so they are never read for a filter and one that turns up
/// anyway is dropped here rather than reaching a screen that cannot draw it.
abstract final class HomeFilterRules {
  /// How far back Recently Added looks.
  static const Duration recentlyAddedWindow = Duration(hours: 12);

  /// How far back This Week looks.
  static const Duration thisWeekWindow = Duration(days: 7);

  /// How far back Recently Updated looks: the same "recent" as Recently Added.
  static const Duration recentlyUpdatedWindow = recentlyAddedWindow;

  /// How many records Less Price keeps.
  static const int lessPriceLimit = 6;

  /// How many records Highest Price keeps: as many as Less Price.
  static const int highestPriceLimit = 6;

  /// The kinds of record the filters look through, in the order Home lists them:
  /// Requested, Offers, Brokers, Owners, Offices, Watchmen. Quotations are not
  /// among them.
  static const List<ItemType> filterable = <ItemType>[
    ItemType.request,
    ItemType.offer,
    ItemType.broker,
    ItemType.owner,
    ItemType.office,
    ItemType.watchmen,
  ];

  /// The kinds that carry a price: the only ones Less Price and Highest Price
  /// look through.
  static const List<ItemType> priced = <ItemType>[
    ItemType.request,
    ItemType.offer,
  ];

  /// The kinds of record [kind] has to read, and no more.
  ///
  /// Throws [UnsupportedError] for a kind that is not implemented: it has no
  /// answer to look for.
  static List<ItemType> typesFor(HomeFilterKind kind) {
    if (!kind.isImplemented) {
      throw UnsupportedError('The ${kind.name} filter is not built yet.');
    }
    switch (kind) {
      case HomeFilterKind.recentlyAdded:
      case HomeFilterKind.thisWeek:
      case HomeFilterKind.recentlyUpdated:
        return filterable;
      case HomeFilterKind.lessPrice:
      case HomeFilterKind.highestPrice:
        return priced;
    }
  }

  /// The records [kind] keeps, in the order the screen shows them.
  ///
  /// Recently Added and This Week list the records created inside the window,
  /// grouped by kind in the order of [filterable] and newest first inside a
  /// group. Recently Updated lists the records changed inside the window after
  /// they were created, grouped the same way and most recently changed first
  /// inside a group (then by id). Less Price lists the [lessPriceLimit]
  /// cheapest Offers and Requests by [UnifiedItemModel.averagePrice], cheapest
  /// first; Highest Price lists the [highestPriceLimit] dearest, dearest first.
  /// Records with the same price go newest first, then by kind, then by id.
  ///
  /// Throws [UnsupportedError] for a kind that is not implemented, rather than
  /// returning a list that would pass for an answer.
  static List<UnifiedItemModel> apply(
    HomeFilterKind kind,
    Iterable<UnifiedItemModel> items, {
    required DateTime now,
  }) {
    if (!kind.isImplemented) {
      throw UnsupportedError('The ${kind.name} filter is not built yet.');
    }
    final candidates = items.where((item) => filterable.contains(item.type));
    switch (kind) {
      case HomeFilterKind.recentlyAdded:
        return _createdAfter(candidates, now.subtract(recentlyAddedWindow));
      case HomeFilterKind.thisWeek:
        return _createdAfter(candidates, now.subtract(thisWeekWindow));
      case HomeFilterKind.recentlyUpdated:
        return _updatedAfter(candidates, now.subtract(recentlyUpdatedWindow));
      case HomeFilterKind.lessPrice:
        return _cheapest(candidates);
      case HomeFilterKind.highestPrice:
        return _dearest(candidates);
    }
  }

  static List<UnifiedItemModel> _createdAfter(
    Iterable<UnifiedItemModel> items,
    DateTime windowStart,
  ) {
    final inside = items
        .where(
            (item) => item.hasCreatedAt && item.createdAt.isAfter(windowStart))
        .toList();
    inside.sort(_byTypeThenNewest);
    return inside;
  }

  static List<UnifiedItemModel> _updatedAfter(
    Iterable<UnifiedItemModel> items,
    DateTime windowStart,
  ) {
    final inside = items
        .where((item) =>
            _wasChangedAfterCreation(item) &&
            item.updatedAt.isAfter(windowStart))
        .toList();
    inside.sort(_byTypeThenLatestChange);
    return inside;
  }

  /// Whether the record's own times prove it was changed after it was created.
  static bool _wasChangedAfterCreation(UnifiedItemModel item) =>
      item.hasCreatedAt &&
      item.hasUpdatedAt &&
      item.updatedAt.isAfter(item.createdAt);

  static List<UnifiedItemModel> _cheapest(Iterable<UnifiedItemModel> items) {
    final ranked = items
        .where((item) => priced.contains(item.type))
        .where(_hasUsablePrice)
        .toList();
    ranked.sort(_byPriceThenNewest);
    return ranked.take(lessPriceLimit).toList();
  }

  static List<UnifiedItemModel> _dearest(Iterable<UnifiedItemModel> items) {
    final ranked = items
        .where((item) => priced.contains(item.type))
        .where(_hasUsablePrice)
        .toList();
    ranked.sort(_byPriceDescendingThenNewest);
    return ranked.take(highestPriceLimit).toList();
  }

  /// A price that can rank a record: a real amount above zero. (The model
  /// already refuses text that is not a finite, non-negative number.)
  static bool _hasUsablePrice(UnifiedItemModel item) {
    final price = item.averagePrice;
    return price != null && price.isFinite && price > 0;
  }

  static int _typeOrder(ItemType type) => filterable.indexOf(type);

  static int _byType(UnifiedItemModel a, UnifiedItemModel b) =>
      _typeOrder(a.type).compareTo(_typeOrder(b.type));

  /// Records with a known creation time first, the latest of them first.
  static int _byNewest(UnifiedItemModel a, UnifiedItemModel b) {
    if (a.hasCreatedAt != b.hasCreatedAt) return a.hasCreatedAt ? -1 : 1;
    if (!a.hasCreatedAt) return 0;
    return b.createdAt.compareTo(a.createdAt);
  }

  /// The most recently changed first. Only for records whose change time is
  /// known (every record [_updatedAfter] keeps).
  static int _byLatestChange(UnifiedItemModel a, UnifiedItemModel b) =>
      b.updatedAt.compareTo(a.updatedAt);

  static int _byId(UnifiedItemModel a, UnifiedItemModel b) =>
      a.id.compareTo(b.id);

  static int _firstDifference(List<int> comparisons) {
    for (final comparison in comparisons) {
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  static int _byTypeThenNewest(UnifiedItemModel a, UnifiedItemModel b) =>
      _firstDifference([_byType(a, b), _byNewest(a, b), _byId(a, b)]);

  static int _byTypeThenLatestChange(UnifiedItemModel a, UnifiedItemModel b) =>
      _firstDifference([_byType(a, b), _byLatestChange(a, b), _byId(a, b)]);

  static int _byPriceDescendingThenNewest(
          UnifiedItemModel a, UnifiedItemModel b) =>
      _firstDifference([
        b.averagePrice!.compareTo(a.averagePrice!),
        _byNewest(a, b),
        _byType(a, b),
        _byId(a, b),
      ]);

  static int _byPriceThenNewest(UnifiedItemModel a, UnifiedItemModel b) =>
      _firstDifference([
        a.averagePrice!.compareTo(b.averagePrice!),
        _byNewest(a, b),
        _byType(a, b),
        _byId(a, b),
      ]);
}
