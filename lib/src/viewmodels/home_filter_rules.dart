import '../data/models/unified_item_model.dart';

/// The Home filters, in the order their chips appear.
enum HomeFilterKind {
  /// Records created in the last 12 hours.
  recentlyAdded('recentlyAdded', 'Recently Added'),

  /// The lowest-priced Offers and Requests.
  lessPrice('lessPrice', 'Less Price'),

  /// Records created in the last 7 days.
  thisWeek('thisWeek', 'This Week'),

  /// The highest-priced Offers and Requests. Only its chip exists so far.
  highestPrice('highestPrice', 'Highest Price', isImplemented: false),

  /// Records changed after they were created. Only its chip exists so far.
  recentlyUpdated('recentlyUpdated', 'Recently Updated', isImplemented: false);

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
/// midnight. A record counts only when it was created strictly after the start
/// of the window, so one created exactly at the start is out. The comparison is
/// between instants, so it makes no difference whether a timestamp is held in
/// UTC or local time, and no offset (the UAE's included) is applied anywhere.
/// A record whose own creation time is unknown ([UnifiedItemModel.hasCreatedAt]
/// is false) is never inside a window: nothing proves it is recent.
///
/// **Scope.** Quotations are not part of the Home filters: the filtered list has
/// no tile for them, so they are never read for a filter and one that turns up
/// anyway is dropped here rather than reaching a screen that cannot draw it.
abstract final class HomeFilterRules {
  /// How far back Recently Added looks.
  static const Duration recentlyAddedWindow = Duration(hours: 12);

  /// How far back This Week looks.
  static const Duration thisWeekWindow = Duration(days: 7);

  /// How many records Less Price keeps.
  static const int lessPriceLimit = 6;

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

  /// The kinds that carry a price: the only ones Less Price looks through.
  static const List<ItemType> priced = <ItemType>[
    ItemType.request,
    ItemType.offer,
  ];

  /// The kinds of record [kind] has to read, and no more.
  ///
  /// Throws [UnsupportedError] for a kind that is not implemented: it has no
  /// answer to look for.
  static List<ItemType> typesFor(HomeFilterKind kind) {
    switch (kind) {
      case HomeFilterKind.recentlyAdded:
      case HomeFilterKind.thisWeek:
        return filterable;
      case HomeFilterKind.lessPrice:
        return priced;
      case HomeFilterKind.highestPrice:
      case HomeFilterKind.recentlyUpdated:
        throw UnsupportedError('The ${kind.name} filter is not built yet.');
    }
  }

  /// The records [kind] keeps, in the order the screen shows them.
  ///
  /// Recently Added and This Week list the records created inside the window,
  /// grouped by kind in the order of [filterable] and newest first inside a
  /// group. Less Price lists the [lessPriceLimit] cheapest Offers and Requests
  /// by [UnifiedItemModel.averagePrice], cheapest first; records with the same
  /// price go newest first, then by kind, then by id.
  ///
  /// Throws [UnsupportedError] for a kind that is not implemented, rather than
  /// returning a list that would pass for an answer.
  static List<UnifiedItemModel> apply(
    HomeFilterKind kind,
    Iterable<UnifiedItemModel> items, {
    required DateTime now,
  }) {
    final candidates = items.where((item) => filterable.contains(item.type));
    switch (kind) {
      case HomeFilterKind.recentlyAdded:
        return _createdAfter(candidates, now.subtract(recentlyAddedWindow));
      case HomeFilterKind.thisWeek:
        return _createdAfter(candidates, now.subtract(thisWeekWindow));
      case HomeFilterKind.lessPrice:
        return _cheapest(candidates);
      case HomeFilterKind.highestPrice:
      case HomeFilterKind.recentlyUpdated:
        throw UnsupportedError('The ${kind.name} filter is not built yet.');
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

  static List<UnifiedItemModel> _cheapest(Iterable<UnifiedItemModel> items) {
    final ranked = items
        .where((item) => priced.contains(item.type))
        .where(_hasUsablePrice)
        .toList();
    ranked.sort(_byPriceThenNewest);
    return ranked.take(lessPriceLimit).toList();
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

  static int _byPriceThenNewest(UnifiedItemModel a, UnifiedItemModel b) =>
      _firstDifference([
        a.averagePrice!.compareTo(b.averagePrice!),
        _byNewest(a, b),
        _byType(a, b),
        _byId(a, b),
      ]);
}
