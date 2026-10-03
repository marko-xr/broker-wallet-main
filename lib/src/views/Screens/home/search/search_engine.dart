import 'package:broker_wallet/src/common/data/owner_location_codec.dart';
import 'package:broker_wallet/src/common/data/owner_property_types.dart';
import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/search_ranking.dart';
import 'package:broker_wallet/src/common/utils/search_text.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';

import 'search_result.dart';

/// Everything Search looks through: the signed-in user's own records, one list
/// per type. (Which records those are is the data source's business; the engine
/// only ever sees what it is given.)
class SearchData {
  const SearchData({
    this.requests = const <RequestModel>[],
    this.offers = const <OfferModel>[],
    this.owners = const <OwnerModel>[],
    this.offices = const <OfficeModel>[],
    this.brokers = const <BrokerModel>[],
    this.watchmen = const <WatchmenModel>[],
  });

  final List<RequestModel> requests;
  final List<OfferModel> offers;
  final List<OwnerModel> owners;
  final List<OfficeModel> offices;
  final List<BrokerModel> brokers;
  final List<WatchmenModel> watchmen;
}

/// One searchable record: what to show, and what it can be found by.
class SearchDocument {
  SearchDocument._(this.result, this._entry);

  final SearchResult result;
  final RankedEntry<SearchResult> _entry;
}

/// A built index of [SearchData], ready to be searched. It is built once per
/// load of the data, not per keystroke.
class SearchCorpus {
  SearchCorpus._(this.documents);

  final List<SearchDocument> documents;

  int get length => documents.length;
}

/// Turns the user's records into something searchable, and searches it.
///
/// Matching and ranking are [SearchRanking]'s (every word must match, in any
/// field, in any order; best match first, a stable order). What this adds is
/// WHAT each record can be found by:
///
///  * the fields Search has always looked at, folded for comparison;
///  * names in BOTH languages: a stored city, area, property type or deal type
///    is searchable by its English and its Arabic name, whichever language was
///    saved — the names come from the app's own strings and the shared UAE
///    area catalog, so there is no second list to keep in step;
///  * a phone number in every way it is commonly written (as stored, with the
///    leading zero, with the country code).
class SearchEngine {
  SearchEngine({
    LocalizedLabelLookup? lookup,
    OwnerLocationCodec? ownerLocationCodec,
    List<String> languages = const <String>['en', 'ar'],
  })  : _lookup = lookup ?? AppLocalizations.translateFor,
        _languages = languages,
        _locationCodec = ownerLocationCodec ??
            OwnerLocationCodec(
              lookup: lookup ?? AppLocalizations.translateFor,
              languages: languages,
            );

  final LocalizedLabelLookup _lookup;
  final List<String> _languages;
  final OwnerLocationCodec _locationCodec;

  // ---------------------------------------------------------------------------
  // Indexing
  // ---------------------------------------------------------------------------

  /// Builds the index for [data]. A record that appears twice (the same type
  /// and id) is indexed once; records of different types are never merged, and
  /// a record without an id is kept.
  SearchCorpus index(SearchData data) {
    final documents = <SearchDocument>[];
    final seen = <String>{};

    void add(
      SearchDocument Function(int position) build,
      String id,
      SearchResultType type,
    ) {
      final trimmed = id.trim();
      if (trimmed.isNotEmpty && !seen.add('${type.name}:$trimmed')) return;
      documents.add(build(documents.length));
    }

    for (final request in data.requests) {
      add((p) => _request(request, p), request.id ?? '',
          SearchResultType.request);
    }
    for (final offer in data.offers) {
      add((p) => _offer(offer, p), offer.id ?? '', SearchResultType.offer);
    }
    for (final owner in data.owners) {
      add((p) => _owner(owner, p), owner.id ?? '', SearchResultType.owner);
    }
    for (final office in data.offices) {
      add((p) => _office(office, p), office.id ?? '', SearchResultType.office);
    }
    for (final broker in data.brokers) {
      add((p) => _broker(broker, p), broker.id ?? '', SearchResultType.broker);
    }
    for (final watchman in data.watchmen) {
      add((p) => _watchman(watchman, p), watchman.id ?? '',
          SearchResultType.watchmen);
    }
    return SearchCorpus._(List<SearchDocument>.unmodifiable(documents));
  }

  SearchDocument _request(RequestModel r, int position) {
    final fields = <RankField>[
      ..._property(r.propertyType, r.specificPropertyType),
      ..._place(r.selectedCity, r.selectedAreas),
      ..._text(r.location, FieldWeight.place),
      ..._dealType(r.requestType),
      ..._text(r.notes, FieldWeight.note),
      ..._number(r.squareFootage),
      ..._number(r.minPrice),
      ..._number(r.maxPrice),
    ];
    return _document(
      position: position,
      type: SearchResultType.request,
      id: r.id ?? '',
      title: r.requestType.toUpperCase(),
      subtitle: r.selectedCity,
      tinytitle: _propertyDisplay(r.propertyType, r.specificPropertyType),
      imageUrl: null,
      data: r,
      fields: fields,
      phones: _phoneForms(r.phoneNumber, r.countryCode),
    );
  }

  SearchDocument _offer(OfferModel o, int position) {
    final fields = <RankField>[
      ..._property(o.propertyType, o.specificPropertyType),
      ..._place(o.selectedCity, o.selectedAreas),
      ..._text(o.location, FieldWeight.place),
      ..._dealType(o.offerType),
      ..._text(o.notes, FieldWeight.note),
      ..._text(o.pickUpLocation, FieldWeight.note),
      ..._text(o.pickUpAddress, FieldWeight.note),
      ..._number(o.squareFootage),
      ..._number(o.minPrice),
      ..._number(o.maxPrice),
    ];
    return _document(
      position: position,
      type: SearchResultType.offer,
      id: o.id ?? '',
      title: o.offerType.toUpperCase(),
      subtitle: o.selectedCity,
      tinytitle: _propertyDisplay(o.propertyType, o.specificPropertyType),
      imageUrl: o.mediaUrls.isNotEmpty ? o.mediaUrls.first : o.mediaUrl,
      data: o,
      fields: fields,
      phones: _phoneForms(o.phoneNumber, o.countryCode),
    );
  }

  SearchDocument _owner(OwnerModel o, int position) {
    final fields = <RankField>[
      ..._text(o.name, FieldWeight.primary),
      ..._ownerPropertyType(o.typeOfProperties),
      ..._ownerLocation(o.propertyLocation),
      ..._text(o.notes, FieldWeight.note),
      ..._text(o.pickUpLocation, FieldWeight.note),
      ..._text(o.pickUpAddress, FieldWeight.note),
    ];
    return _document(
      position: position,
      type: SearchResultType.owner,
      id: o.id ?? '',
      title: o.name,
      subtitle: o.typeOfProperties,
      tinytitle: _displayPhone(o.phoneNumber),
      imageUrl: o.mediaUrls.isNotEmpty ? o.mediaUrls.first : o.mediaUrl,
      data: o,
      fields: fields,
      phones: _phoneForms(o.phoneNumber, o.countryCode),
    );
  }

  SearchDocument _office(OfficeModel o, int position) {
    final fields = <RankField>[
      ..._text(o.officeName, FieldWeight.primary),
      ..._text(o.officeLocation, FieldWeight.place),
      ..._text(o.notes, FieldWeight.note),
      ..._text(o.pickUpLocation, FieldWeight.note),
      ..._text(o.pickUpAddress, FieldWeight.note),
    ];
    return _document(
      position: position,
      type: SearchResultType.office,
      id: o.id ?? '',
      title: o.officeName,
      subtitle: o.officeLocation,
      tinytitle: _displayPhone(o.phoneNumber),
      imageUrl: null,
      data: o,
      fields: fields,
      phones: _phoneForms(o.phoneNumber, o.countryCode),
    );
  }

  SearchDocument _broker(BrokerModel b, int position) {
    final fields = <RankField>[
      ..._text(b.name, FieldWeight.primary),
      ..._text(b.notes, FieldWeight.note),
    ];
    return _document(
      position: position,
      type: SearchResultType.broker,
      id: b.id ?? '',
      title: b.name,
      subtitle: _displayPhone(b.phoneNumber),
      tinytitle: '',
      imageUrl: null,
      data: b,
      fields: fields,
      phones: _phoneForms(b.phoneNumber, b.countryCode),
    );
  }

  SearchDocument _watchman(WatchmenModel w, int position) {
    final fields = <RankField>[
      ..._text(w.name, FieldWeight.primary),
      ..._text(w.buildingName, FieldWeight.primary),
      ..._text(w.buildingLocation, FieldWeight.place),
      ..._text(w.notes, FieldWeight.note),
      ..._text(w.pickUpLocation, FieldWeight.note),
      ..._text(w.pickUpAddress, FieldWeight.note),
    ];
    return _document(
      position: position,
      type: SearchResultType.watchmen,
      id: w.id ?? '',
      title: w.name,
      subtitle: w.buildingName,
      tinytitle: _displayPhone(w.phoneNumber),
      imageUrl: null,
      data: w,
      fields: fields,
      phones: _phoneForms(w.phoneNumber, w.countryCode),
    );
  }

  SearchDocument _document({
    required int position,
    required SearchResultType type,
    required String id,
    required String title,
    required String subtitle,
    required String tinytitle,
    required String? imageUrl,
    required Object data,
    required List<RankField> fields,
    required List<String> phones,
  }) {
    final trimmedId = id.trim();
    final result = SearchResult(
      id: id,
      title: title,
      subtitle: subtitle,
      tinytitle: tinytitle,
      imageUrl: imageUrl,
      type: type,
      data: data,
      searchQuery: '',
      // A record with no id still needs a key of its own.
      stableKey: trimmedId.isEmpty
          ? '${type.name}:#$position'
          : '${type.name}:$trimmedId',
    );
    return SearchDocument._(
      result,
      RankedEntry<SearchResult>(
        fields: List<RankField>.unmodifiable(fields),
        phoneForms: phones,
        // Equally good matches of different types: requests, offers, owners,
        // offices, brokers, watchmen.
        group: type.index,
        titleKey: SearchText.fold(title),
        key: result.stableKey,
        item: result,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Fields: what a record is searchable by
  // ---------------------------------------------------------------------------

  List<RankField> _text(String? value, FieldWeight weight) {
    final folded = SearchText.fold(value ?? '');
    return folded.isEmpty ? const <RankField>[] : [RankField(folded, weight)];
  }

  /// A size or price as a number to match from the start. Only its whole part
  /// counts: "1,200.5" is 1200, so the digit after the point is never read as
  /// part of the number (12005).
  List<RankField> _number(String? value) {
    var whole = value ?? '';
    final point = whole.indexOf(RegExp('[.\u066B]'));
    if (point >= 0) whole = whole.substring(0, point);
    final digits = SearchText.digits(whole);
    return digits.isEmpty
        ? const <RankField>[]
        : [RankField(digits, FieldWeight.number, isNumber: true)];
  }

  /// Distinct non-empty folded texts, as fields of [weight].
  List<RankField> _distinct(Iterable<String?> values, FieldWeight weight) {
    final seen = <String>{};
    final fields = <RankField>[];
    for (final value in values) {
      final folded = SearchText.fold(value ?? '');
      if (folded.isNotEmpty && seen.add(folded)) {
        fields.add(RankField(folded, weight));
      }
    }
    return fields;
  }

  /// The name a localization [key] has in each language.
  Iterable<String> _namesOfKey(String key) sync* {
    for (final language in _languages) {
      final name = _lookup(language, key);
      if (name != null && name.isNotEmpty) yield name;
    }
  }

  List<RankField> _place(String city, List<String> areaKeys) {
    final values = <String?>[
      city,
      ..._namesOfKey(UaeAreaCatalog.cityKey(city)),
    ];
    for (final key in areaKeys) {
      final names = _namesOfKey(key).toList();
      // A stored area the catalog does not know is the user's own text.
      values.addAll(names.isEmpty ? <String>[key] : names);
    }
    return _distinct(values, FieldWeight.place);
  }

  List<RankField> _dealType(String raw) {
    final normalized = raw.trim().toLowerCase();
    final key = normalized.contains('rent')
        ? 'rent'
        : (normalized.contains('sell') || normalized.contains('sale'))
            ? 'sale'
            : null;
    return _distinct(
      [raw, if (key != null) ..._namesOfKey(key)],
      FieldWeight.place,
    );
  }

  List<RankField> _property(String? type, String specific) {
    return _distinct(
      [
        ..._propertyNames(type),
        ..._propertyNames(specific),
      ],
      FieldWeight.primary,
    );
  }

  /// A stored property type or sub-type and, when it is one the app knows, its
  /// name in every language.
  Iterable<String> _propertyNames(String? stored) sync* {
    final raw = (stored ?? '').trim();
    if (raw.isEmpty) return;
    yield raw;
    final key = _propertyTypeKeys[_propertyKeyOf(raw)];
    if (key != null) yield* _namesOfKey(key);
  }

  static String _propertyKeyOf(String raw) =>
      raw.toLowerCase().replaceAll(' ', '').replaceAll('&', 'and');

  List<RankField> _ownerPropertyType(String stored) {
    final raw = stored.trim();
    if (raw.isEmpty) return const <RankField>[];
    final match = OwnerPropertyTypes.match(
      raw,
      labelsOfKey: (key) => _namesOfKey(key),
    );
    return _distinct(
      [raw, if (match != null) ..._namesOfKey(match.key)],
      FieldWeight.primary,
    );
  }

  /// An Owner's location as typed, plus — when it starts with a city and area
  /// the app wrote — their names in every language.
  List<RankField> _ownerLocation(String stored) {
    final raw = stored.trim();
    if (raw.isEmpty) return const <RankField>[];
    final parts = _locationCodec.decode(raw);
    final values = <String?>[raw];
    if (parts != null) {
      values.addAll(_namesOfKey(UaeAreaCatalog.cityKey(parts.city)));
      final areaKey = parts.areaKey;
      if (areaKey != null && areaKey.isNotEmpty) {
        values.addAll(_namesOfKey(areaKey));
      }
    }
    return _distinct(values, FieldWeight.place);
  }

  /// The digit strings a phone number can be typed as: as stored, with the
  /// leading zero (UAE local), and with the country code (international).
  List<String> _phoneForms(String phone, String countryCode) {
    final national = SearchText.digits(phone);
    if (national.isEmpty) return const <String>[];
    final code = SearchText.digits(countryCode);
    final forms = <String>{national};

    var local = national;
    if (code.isNotEmpty &&
        national.startsWith(code) &&
        national.length > code.length) {
      // Stored with its country code: the rest is the national number.
      local = national.substring(code.length);
      forms.add(local);
    }
    final withoutZero = local.startsWith('0') ? local.substring(1) : local;
    if (withoutZero.isNotEmpty) {
      forms.add(withoutZero);
      forms.add('0$withoutZero');
      if (code.isNotEmpty) forms.add('$code$withoutZero');
    }
    return List<String>.unmodifiable(forms);
  }

  String _displayPhone(String phone) {
    final digits = SearchText.digits(phone);
    if (digits.isEmpty) return '';
    if (digits.startsWith('971') && digits.length > 9) {
      return '0${digits.substring(3)}';
    }
    if (digits.startsWith('5') && digits.length >= 8) return '0$digits';
    return digits;
  }

  String _propertyDisplay(String? type, String specific) {
    final typeText = (type ?? '').trim();
    final specificText = specific.trim();
    if (typeText.isNotEmpty) {
      return specificText.isEmpty ? typeText : '$typeText - $specificText';
    }
    return specificText;
  }

  // ---------------------------------------------------------------------------
  // Searching
  // ---------------------------------------------------------------------------

  /// The records of [corpus] that match every word of [tokens], best first.
  /// [type] limits the answer to one kind of record; [displayQuery] is what the
  /// results are stamped with, for highlighting.
  ///
  /// Nothing about the corpus changes, so the same call always gives the same
  /// answer in the same order.
  List<SearchResult> search(
    SearchCorpus corpus, {
    required List<String> tokens,
    required String displayQuery,
    SearchResultType? type,
  }) {
    if (tokens.isEmpty) return const <SearchResult>[];
    final entries = <RankedEntry<SearchResult>>[
      for (final document in corpus.documents)
        if (type == null || document.result.type == type) document._entry,
    ];
    final ranked = SearchRanking.rank<SearchResult>(entries, tokens);
    return List<SearchResult>.unmodifiable(
      ranked.map((result) => result.withQuery(displayQuery)),
    );
  }

  /// A stored property type's normalized spelling -> its localization key. The
  /// same vocabulary the Request, Offer and details screens use.
  static const Map<String, String> _propertyTypeKeys = {
    'residential': 'residential',
    'commercial': 'commercial',
    'furnished': 'furnished',
    'apartment': 'apartment',
    'villa': 'villa',
    'studio': 'studio',
    'townhouse': 'townhouse',
    'penthouse': 'penthouse',
    'compound': 'compound',
    'duplex': 'duplex',
    'fullfloor': 'fullFloor',
    'halffloor': 'halfFloor',
    'wholebuilding': 'wholeBuilding',
    'land': 'land',
    'bulkrentunit': 'bulkRentUnit',
    'bungalow': 'bungalow',
    'hotelandhotelapartment': 'hotelAndHotelApartment',
    'hotelhotelapartment': 'hotelAndHotelApartment',
    'officespace': 'officeSpace',
    'office': 'office',
    'retail': 'retail',
    'warehouse': 'warehouse',
    'shop': 'shop',
    'showroom': 'showRoom',
    'bulksaleunit': 'bulkSaleUnit',
    'factory': 'factory',
    'laborcamp': 'laborCamp',
    'staffaccommodation': 'staffAccommodation',
    'businesscentre': 'businessCentre',
    'farm': 'farm',
    'offices': 'offices',
  };

  /// The localization keys [_propertyTypeKeys] points at, for the tests that
  /// check every one exists in both languages.
  static Iterable<String> get propertyTypeLocalizationKeys =>
      _propertyTypeKeys.values.toSet();
}
