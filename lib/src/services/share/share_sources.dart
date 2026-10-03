import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/common/data/owner_location_codec.dart';
import 'package:broker_wallet/src/common/data/owner_property_types.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/offices_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/watchmen_model.dart';
import 'package:broker_wallet/src/services/share/share_format.dart';
import 'package:broker_wallet/src/services/share/share_labels.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_source.dart';
import 'package:broker_wallet/src/services/share/share_text.dart';

// One ShareSource per kind of record. They differ only in which fields the
// record has and in what is chosen at first:
//
//  * An Offer or a Request is the broker's own listing, sent out to be seen, so
//    everything it has starts chosen (an Offer's photos too; its videos not).
//  * An Owner, a Broker, a Watchman or an Office is a person or business in the
//    broker's private address book. Their name and place start chosen; their
//    phone number and the broker's private notes do not, and an Owner's number
//    in particular is the broker's own business asset — it is shared only when
//    the broker ticks it.
//  * A Quotation is shared as its PDF, with a short summary; its money lines
//    start unchosen because the PDF already carries them.

/// A Request or an Offer: the property listings.
class PropertyShareSource extends ShareSource {
  PropertyShareSource._({
    required this.isOffer,
    required this.isRent,
    required this.city,
    required this.areas,
    required this.location,
    required this.phone,
    required this.minPrice,
    required this.maxPrice,
    required this.squareFootage,
    required this.notes,
    required this.propertyType,
    required this.specificType,
    required this.rooms,
    required this.bathrooms,
    this.latitude,
    this.longitude,
    this.address = '',
    super.media,
  });

  /// An Offer, with the media its screen holds. The phone number is the
  /// Offer's own — the one its detail screen shows — never the signed-in
  /// account's.
  factory PropertyShareSource.offer(
    OfferModel offer, {
    List<ShareMediaItem> media = const <ShareMediaItem>[],
  }) =>
      PropertyShareSource._(
        isOffer: true,
        isRent: offer.offerType.trim().toLowerCase() == 'rent',
        city: offer.selectedCity,
        areas: offer.selectedAreas,
        location: offer.location,
        phone: offer.phoneNumber,
        minPrice: offer.minPrice,
        maxPrice: offer.maxPrice,
        squareFootage: offer.squareFootage,
        notes: offer.notes,
        propertyType: offer.propertyType,
        specificType: offer.specificPropertyType,
        rooms: offer.rooms,
        bathrooms: offer.bathrooms,
        latitude: offer.pickUpLatitude,
        longitude: offer.pickUpLongitude,
        address: ShareFormat.clean(offer.pickUpAddress) ??
            ShareFormat.clean(offer.pickUpLocation) ??
            '',
        media: media,
      );

  /// A Request. A Request has no map and no media.
  factory PropertyShareSource.request(RequestModel request) =>
      PropertyShareSource._(
        isOffer: false,
        isRent: request.requestType.trim().toLowerCase() == 'rent',
        city: request.selectedCity,
        areas: request.selectedAreas,
        location: request.location,
        phone: request.phoneNumber,
        minPrice: request.minPrice,
        maxPrice: request.maxPrice,
        squareFootage: request.squareFootage,
        notes: request.notes,
        propertyType: request.propertyType,
        specificType: request.specificPropertyType,
        rooms: request.rooms,
        bathrooms: request.bathrooms,
      );

  final bool isOffer;
  final bool isRent;
  final String city;
  final List<String> areas;
  final String location;
  final String phone;
  final String minPrice;
  final String maxPrice;
  final String squareFootage;
  final String notes;
  final String? propertyType;
  final String specificType;
  final int rooms;
  final int bathrooms;
  final double? latitude;
  final double? longitude;
  final String address;

  @override
  String get titleKey => isOffer ? 'shareOffer' : 'shareRequest';

  @override
  String get subjectKey => isOffer ? 'offerDetails' : 'requestDetails';

  @override
  String messageTitleKey(ShareLabels labels) =>
      isOffer && labels.isRtl ? 'shareOfferMessageTitle' : subjectKey;

  @override
  String messageFooterKey(ShareLabels labels) => isOffer && labels.isRtl
      ? 'shareOfferMessageFooter'
      : super.messageFooterKey(labels);

  bool get _hasRoomsOrBathrooms =>
      ShareFormat.showsRoomsAndBathrooms(specificType) &&
      (rooms > 0 || bathrooms > 0);

  @override
  Set<ShareSection> get textAvailable => <ShareSection>{
        ShareSection.basicInfo,
        if (ShareFormat.clean(minPrice) != null ||
            ShareFormat.clean(maxPrice) != null)
          ShareSection.pricing,
        if (_hasRoomsOrBathrooms || ShareFormat.number(squareFootage) != null)
          ShareSection.propertyDetails,
        if (ShareFormat.clean(city) != null ||
            areas.any((a) => ShareFormat.clean(a) != null) ||
            ShareFormat.clean(location) != null)
          ShareSection.locationDetails,
        if (isOffer && ShareFormat.validLatLng(latitude, longitude))
          ShareSection.map,
        if (RegExp(r'\d').hasMatch(phone)) ShareSection.contact,
        if (ShareFormat.clean(notes) != null) ShareSection.notes,
      };

  @override
  Set<ShareSection> get textDefaults => textAvailable;

  @override
  String? sectionDetail(ShareSection section, ShareLabels labels) {
    switch (section) {
      case ShareSection.pricing:
        return ShareFormat.price(min: minPrice, max: maxPrice, labels: labels);
      case ShareSection.locationDetails:
        final cityName = ShareFormat.city(city, labels);
        final areaNames = ShareFormat.areas(areas, labels);
        final place = <String>[
          if (cityName != null) cityName,
          if (areaNames.isNotEmpty) areaNames.join(', '),
        ];
        return place.isEmpty ? null : place.join(' · ');
      case ShareSection.contact:
        return ShareFormat.phone(phone, labels);
      default:
        return null;
    }
  }

  @override
  void writeSections(
    ShareTextBuilder b,
    ShareLabels labels,
    Set<ShareSection> selected,
  ) {
    final basic = selected.contains(ShareSection.basicInfo);
    final details = selected.contains(ShareSection.propertyDetails);

    // Property details: what it is, then what it has.
    final arabicOffer = isOffer && labels.isRtl;
    final kind = labels.maybe(arabicOffer
        ? (isRent ? 'rent' : 'sale')
        : isOffer
            ? (isRent ? 'rentOffer' : 'saleOffer')
            : (isRent ? 'rentRequest' : 'saleRequest'));
    final mainType = ShareFormat.mainPropertyType(propertyType, labels);
    final subType = ShareFormat.propertyType(specificType, labels);
    final type = arabicOffer &&
            mainType != null &&
            subType != null &&
            subType != specificType.trim() &&
            const <String>{'residential', 'commercial', 'furnished'}
                .contains(propertyType?.trim().toLowerCase())
        ? _arabicTypeDisplay(mainType, specificType, subType)
        : <String>[
            if (mainType != null) mainType,
            if (subType != null) subType,
          ].join(' - ');
    final footage = ShareFormat.number(squareFootage);
    b.section(ShareEmoji.property, 'propertyDetails', [
      if (basic && arabicOffer) b.line('propertyType', type),
      if (basic) b.line(isOffer ? 'offerType' : 'requestType', kind),
      if (basic && !arabicOffer) b.line('propertyType', type),
      if (details && _hasRoomsOrBathrooms && rooms > 0)
        b.line('rooms', '$rooms'),
      if (details && _hasRoomsOrBathrooms && bathrooms > 0)
        b.line('bathrooms', '$bathrooms'),
      if (details && footage != null)
        b.line(
          arabicOffer ? 'shareOfferAreaSize' : 'squareFootage',
          '${ShareFormat.ltr(footage, labels)} ${labels.text('squareFootageUnit')}'
              .trim(),
        ),
    ]);

    if (selected.contains(ShareSection.pricing)) {
      b.single(
        ShareEmoji.price,
        'price',
        ShareFormat.price(min: minPrice, max: maxPrice, labels: labels),
      );
    }

    final cityName = ShareFormat.city(city, labels);
    final areaNames = ShareFormat.areas(areas, labels);
    ShareSource.writeLocation(
      b,
      labels,
      includeLocation: selected.contains(ShareSection.locationDetails),
      includeMap: selected.contains(ShareSection.map),
      locationLines: [
        b.line('city', cityName),
        b.line(
          arabicOffer && areaNames.length == 1 ? 'shareOfferArea' : 'areas',
          areaNames.join(arabicOffer ? '، ' : ', '),
        ),
        b.line('location', location),
      ],
      address: address,
      latitude: latitude,
      longitude: longitude,
    );

    if (selected.contains(ShareSection.contact)) {
      ShareSource.writeContact(b, labels, phone);
    }
    if (selected.contains(ShareSection.notes)) {
      ShareSource.writeNotes(b, notes);
    }
  }

  static String _arabicTypeDisplay(
    String category,
    String specificType,
    String localizedType,
  ) {
    const feminineTypes = <String>{
      'villa',
      'apartment',
      'land',
      'farm',
      'showroom',
      'officespace',
      'offices',
    };
    final adjective = feminineTypes.contains(specificType.trim().toLowerCase())
        ? '${category}ة'
        : category;
    final agreedAdjective =
        localizedType.startsWith('ال') ? 'ال$adjective' : adjective;
    return localizedType.endsWith(agreedAdjective)
        ? localizedType
        : '$localizedType $agreedAdjective';
  }

  @override
  String mediaBaseName(
    ShareMediaItem item,
    int position,
    Set<ShareSection> selected,
    ShareLabels labels,
  ) {
    // An offer's place is part of a file's name only when the location is shared.
    var place = '';
    if (selected.contains(ShareSection.locationDetails)) {
      final firstArea = areas
          .map(ShareFormat.clean)
          .whereType<String>()
          .map((a) => _englishPlace(a, labels))
          .firstWhere((a) => a.isNotEmpty, orElse: () => '');
      place = firstArea.isNotEmpty
          ? firstArea
          : _englishPlace(city, labels, isCity: true);
    }
    return [
      isOffer ? 'Offer' : 'Request',
      if (place.isNotEmpty) place,
      ShareSource.ordinal(position),
    ].join('-');
  }

  /// A place's English name as a file-name part: the catalog's own English name
  /// for it, never the stored key.
  static String _englishPlace(
    String stored,
    ShareLabels labels, {
    bool isCity = false,
  }) {
    final english = labels.inEnglish;
    return ShareFormat.fileStem(
      isCity
          ? ShareFormat.city(stored, english)
          : ShareFormat.area(stored, english),
      maxLength: 30,
    );
  }
}

/// A property owner.
class OwnerShareSource extends ShareSource {
  OwnerShareSource(
    this.owner, {
    super.media,
  });

  final OwnerModel owner;

  // One codec per language: building its table of every `Area, City` text is
  // the costly part, and the dialog asks again each time a choice changes.
  final Map<String, OwnerLocationCodec> _codecs =
      <String, OwnerLocationCodec>{};

  @override
  String get titleKey => 'shareOwner';

  @override
  String get subjectKey => 'propertyOwner';

  String get _address =>
      ShareFormat.clean(owner.pickUpAddress) ??
      ShareFormat.clean(owner.pickUpLocation) ??
      '';

  @override
  Set<ShareSection> get textAvailable => <ShareSection>{
        if (ShareFormat.clean(owner.name) != null ||
            ShareFormat.clean(owner.typeOfProperties) != null)
          ShareSection.basicInfo,
        if (ShareFormat.clean(owner.propertyLocation) != null)
          ShareSection.locationDetails,
        if (ShareFormat.validLatLng(
            owner.pickUpLatitude, owner.pickUpLongitude))
          ShareSection.map,
        if (RegExp(r'\d').hasMatch(owner.phoneNumber)) ShareSection.contact,
        if (ShareFormat.clean(owner.notes) != null) ShareSection.notes,
      };

  @override
  Set<ShareSection> get textDefaults => <ShareSection>{
        ShareSection.basicInfo,
        ShareSection.locationDetails,
        ShareSection.map,
      };

  @override
  String? sectionDetail(ShareSection section, ShareLabels labels) {
    switch (section) {
      case ShareSection.locationDetails:
        return _location(labels);
      case ShareSection.contact:
        return ShareFormat.phone(owner.phoneNumber, labels);
      default:
        return null;
    }
  }

  /// The saved location in the message's language: an `Area, City` the owner
  /// picked from the catalog is written in the language of the message, and
  /// anything the owner typed is kept exactly as typed.
  String? _location(ShareLabels labels) {
    final text = ShareFormat.clean(owner.propertyLocation);
    if (text == null) return null;
    final codec = _codecs.putIfAbsent(
      labels.languageCode,
      () => OwnerLocationCodec(lookup: labels.lookup),
    );
    final parts = codec.decode(text);
    if (parts == null) return text;
    return codec.encode(
      city: parts.city,
      areaKey: parts.areaKey,
      language: labels.languageCode,
      detail: parts.detail,
    );
  }

  /// The property type in the message's language when it is one of the
  /// suggestions, else exactly what the owner typed.
  String? _propertyType(ShareLabels labels) {
    final text = ShareFormat.clean(owner.typeOfProperties);
    if (text == null) return null;
    final match = OwnerPropertyTypes.match(text, labelsOfKey: labels.every);
    if (match == null) return text;
    return labels.maybe(match.key) ?? text;
  }

  @override
  void writeSections(
    ShareTextBuilder b,
    ShareLabels labels,
    Set<ShareSection> selected,
  ) {
    if (selected.contains(ShareSection.basicInfo)) {
      b.section(ShareEmoji.person, 'propertyOwner', [
        b.line('name', owner.name),
        b.line('propertyType', _propertyType(labels)),
      ]);
    }
    ShareSource.writeLocation(
      b,
      labels,
      includeLocation: selected.contains(ShareSection.locationDetails),
      includeMap: selected.contains(ShareSection.map),
      locationLines: [b.line('propertyLocation', _location(labels))],
      address: _address,
      latitude: owner.pickUpLatitude,
      longitude: owner.pickUpLongitude,
    );
    if (selected.contains(ShareSection.contact)) {
      ShareSource.writeContact(b, labels, owner.phoneNumber);
    }
    if (selected.contains(ShareSection.notes)) {
      ShareSource.writeNotes(b, owner.notes);
    }
  }

  @override
  String mediaBaseName(
    ShareMediaItem item,
    int position,
    Set<ShareSection> selected,
    ShareLabels labels,
  ) =>
      // Neither the owner's name nor their location is ever part of a file name.
      'Owner-Property-${ShareSource.ordinal(position)}';
}

/// A broker in the address book.
class BrokerShareSource extends ShareSource {
  BrokerShareSource(this.broker);

  final BrokerModel broker;

  @override
  String get titleKey => 'shareBroker';

  @override
  String get subjectKey => 'brokerDetails';

  @override
  Set<ShareSection> get textAvailable => <ShareSection>{
        if (ShareFormat.clean(broker.name) != null) ShareSection.basicInfo,
        if (RegExp(r'\d').hasMatch(broker.phoneNumber)) ShareSection.contact,
        if (ShareFormat.clean(broker.notes) != null) ShareSection.notes,
      };

  @override
  Set<ShareSection> get textDefaults => <ShareSection>{
        ShareSection.basicInfo,
        ShareSection.contact,
      };

  @override
  String? sectionDetail(ShareSection section, ShareLabels labels) =>
      section == ShareSection.contact
          ? ShareFormat.phone(broker.phoneNumber, labels)
          : null;

  @override
  void writeSections(
    ShareTextBuilder b,
    ShareLabels labels,
    Set<ShareSection> selected,
  ) {
    if (selected.contains(ShareSection.basicInfo)) {
      b.section(ShareEmoji.person, 'basicInformation', [
        b.line('name', broker.name),
      ]);
    }
    if (selected.contains(ShareSection.contact)) {
      ShareSource.writeContact(b, labels, broker.phoneNumber);
    }
    if (selected.contains(ShareSection.notes)) {
      ShareSource.writeNotes(b, broker.notes);
    }
  }

  @override
  String mediaBaseName(
    ShareMediaItem item,
    int position,
    Set<ShareSection> selected,
    ShareLabels labels,
  ) =>
      'Broker-${ShareSource.ordinal(position)}';
}

/// A building's watchman in the address book.
class WatchmanShareSource extends ShareSource {
  WatchmanShareSource(this.watchman);

  final WatchmenModel watchman;

  @override
  String get titleKey => 'shareWatchman';

  @override
  String get subjectKey => 'watchmenDetails';

  String get _address =>
      ShareFormat.clean(watchman.pickUpAddress) ??
      ShareFormat.clean(watchman.pickUpLocation) ??
      '';

  @override
  Set<ShareSection> get textAvailable => <ShareSection>{
        if (ShareFormat.clean(watchman.name) != null ||
            ShareFormat.clean(watchman.buildingName) != null)
          ShareSection.basicInfo,
        if (ShareFormat.clean(watchman.buildingLocation) != null)
          ShareSection.locationDetails,
        if (ShareFormat.validLatLng(
            watchman.pickUpLatitude, watchman.pickUpLongitude))
          ShareSection.map,
        if (RegExp(r'\d').hasMatch(watchman.phoneNumber)) ShareSection.contact,
        if (ShareFormat.clean(watchman.notes) != null) ShareSection.notes,
      };

  @override
  Set<ShareSection> get textDefaults => <ShareSection>{
        ShareSection.basicInfo,
        ShareSection.locationDetails,
        ShareSection.map,
        ShareSection.contact,
      };

  @override
  String? sectionDetail(ShareSection section, ShareLabels labels) {
    switch (section) {
      case ShareSection.locationDetails:
        return ShareFormat.clean(watchman.buildingLocation);
      case ShareSection.contact:
        return ShareFormat.phone(watchman.phoneNumber, labels);
      default:
        return null;
    }
  }

  @override
  void writeSections(
    ShareTextBuilder b,
    ShareLabels labels,
    Set<ShareSection> selected,
  ) {
    if (selected.contains(ShareSection.basicInfo)) {
      b.section(ShareEmoji.person, 'basicInformation', [
        b.line('name', watchman.name),
        b.line('buildingName', watchman.buildingName),
      ]);
    }
    ShareSource.writeLocation(
      b,
      labels,
      includeLocation: selected.contains(ShareSection.locationDetails),
      includeMap: selected.contains(ShareSection.map),
      locationLines: [b.line('buildingLocation', watchman.buildingLocation)],
      address: _address,
      latitude: watchman.pickUpLatitude,
      longitude: watchman.pickUpLongitude,
    );
    if (selected.contains(ShareSection.contact)) {
      ShareSource.writeContact(b, labels, watchman.phoneNumber);
    }
    if (selected.contains(ShareSection.notes)) {
      ShareSource.writeNotes(b, watchman.notes);
    }
  }

  @override
  String mediaBaseName(
    ShareMediaItem item,
    int position,
    Set<ShareSection> selected,
    ShareLabels labels,
  ) =>
      'Watchman-${ShareSource.ordinal(position)}';
}

/// A real-estate office in the address book.
class OfficeShareSource extends ShareSource {
  OfficeShareSource(this.office);

  final OfficeModel office;

  @override
  String get titleKey => 'shareOffice';

  @override
  String get subjectKey => 'officeDetails';

  String get _address =>
      ShareFormat.clean(office.pickUpAddress) ??
      ShareFormat.clean(office.pickUpLocation) ??
      '';

  @override
  Set<ShareSection> get textAvailable => <ShareSection>{
        if (ShareFormat.clean(office.officeName) != null ||
            ShareFormat.clean(office.managerName) != null)
          ShareSection.basicInfo,
        if (ShareFormat.clean(office.officeLocation) != null)
          ShareSection.locationDetails,
        if (ShareFormat.validLatLng(
            office.pickUpLatitude, office.pickUpLongitude))
          ShareSection.map,
        if (RegExp(r'\d').hasMatch(office.phoneNumber)) ShareSection.contact,
        if (ShareFormat.clean(office.notes) != null) ShareSection.notes,
      };

  @override
  Set<ShareSection> get textDefaults => <ShareSection>{
        ShareSection.basicInfo,
        ShareSection.locationDetails,
        ShareSection.map,
        ShareSection.contact,
      };

  @override
  String? sectionDetail(ShareSection section, ShareLabels labels) {
    switch (section) {
      case ShareSection.locationDetails:
        return ShareFormat.clean(office.officeLocation);
      case ShareSection.contact:
        return ShareFormat.phone(office.phoneNumber, labels);
      default:
        return null;
    }
  }

  @override
  void writeSections(
    ShareTextBuilder b,
    ShareLabels labels,
    Set<ShareSection> selected,
  ) {
    if (selected.contains(ShareSection.basicInfo)) {
      b.section(ShareEmoji.person, 'basicInformation', [
        b.line('officeName', office.officeName),
        b.line('managerName', office.managerName),
      ]);
    }
    ShareSource.writeLocation(
      b,
      labels,
      includeLocation: selected.contains(ShareSection.locationDetails),
      includeMap: selected.contains(ShareSection.map),
      locationLines: [b.line('officeLocation', office.officeLocation)],
      address: _address,
      latitude: office.pickUpLatitude,
      longitude: office.pickUpLongitude,
    );
    if (selected.contains(ShareSection.contact)) {
      ShareSource.writeContact(b, labels, office.phoneNumber);
    }
    if (selected.contains(ShareSection.notes)) {
      ShareSource.writeNotes(b, office.notes);
    }
  }

  @override
  String mediaBaseName(
    ShareMediaItem item,
    int position,
    Set<ShareSection> selected,
    ShareLabels labels,
  ) =>
      'Office-${ShareSource.ordinal(position)}';
}

/// A Quotation: its summary and its private PDF.
class QuotationShareSource extends ShareSource {
  QuotationShareSource(
    this.quotation, {
    required Future<File> Function() fetchPdf,
  }) : super(
          document: quotation.hasPdf
              ? ShareDocument(
                  fileBaseName: _pdfBaseName(quotation),
                  fetch: fetchPdf,
                )
              : null,
        );

  final QuotationModel quotation;

  @override
  String get titleKey => 'shareQuotation';

  @override
  String get subjectKey => 'quotationDetails';

  /// `Broker-Wallet-Quotation-Apartment-306`: the property's title, reduced to
  /// plain letters and digits. Never the quotation's id or the PDF's media id.
  static String _pdfBaseName(QuotationModel quotation) {
    final stem = ShareFormat.fileStem(quotation.propertyTitle, maxLength: 40);
    return stem.isEmpty
        ? 'Broker-Wallet-Quotation'
        : 'Broker-Wallet-Quotation-$stem';
  }

  @override
  String sectionTitleKey(ShareSection section) =>
      section == ShareSection.document ? 'quotationPdf' : section.labelKey;

  @override
  Set<ShareSection> get textAvailable => <ShareSection>{
        if (ShareFormat.clean(quotation.propertyTitle) != null ||
            ShareFormat.clean(quotation.propertyType) != null ||
            ShareFormat.clean(quotation.officeName) != null)
          ShareSection.basicInfo,
        if (quotation.totalAmount != null ||
            quotation.professionalFee != null ||
            quotation.numberOfInstallments != null)
          ShareSection.pricing,
      };

  @override
  Set<ShareSection> get textDefaults => <ShareSection>{ShareSection.basicInfo};

  @override
  String? sectionDetail(ShareSection section, ShareLabels labels) =>
      section == ShareSection.pricing
          ? ShareFormat.money(
              quotation.totalAmount,
              labels,
              currencyCode: quotation.currencyCode,
            )
          : null;

  @override
  void writeSections(
    ShareTextBuilder b,
    ShareLabels labels,
    Set<ShareSection> selected,
  ) {
    if (selected.contains(ShareSection.basicInfo)) {
      b.section(ShareEmoji.document, 'quotation', [
        b.line('propertyTitle', quotation.propertyTitle),
        b.line('propertyType', quotation.propertyType),
        b.line('officeName', quotation.officeName),
      ]);
    }
    if (selected.contains(ShareSection.pricing)) {
      final installments = quotation.numberOfInstallments;
      b.section(ShareEmoji.price, 'pricing', [
        b.line(
          'totalAmount',
          ShareFormat.money(
            quotation.totalAmount,
            labels,
            currencyCode: quotation.currencyCode,
          ),
        ),
        b.line(
          'professionalFee',
          ShareFormat.money(
            quotation.professionalFee,
            labels,
            currencyCode: quotation.currencyCode,
          ),
        ),
        b.line(
          'numberOfInstallments',
          installments == null ? null : '$installments',
        ),
      ]);
    }
  }

  @override
  String mediaBaseName(
    ShareMediaItem item,
    int position,
    Set<ShareSection> selected,
    ShareLabels labels,
  ) =>
      'Broker-Wallet-Quotation-${ShareSource.ordinal(position)}';
}
