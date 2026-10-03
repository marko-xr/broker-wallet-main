import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/offer_media_cache_identity.dart';
import 'package:broker_wallet/src/services/share/share_format.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_source.dart';
import 'package:broker_wallet/src/services/share/share_sources.dart';

import 'share_fixtures.dart';

// The emoji that head a message's sections (see ShareEmoji).
const String _home = '\u{1F3E1}';
const String _money = '\u{1F4B0}';
const String _pin = '\u{1F4CD}';
const String _phone = '\u{1F4DE}';
const String _note = '\u{1F4DD}';
const String _person = '\u{1F464}';
const String _doc = '\u{1F4C4}';
const String _app = '\u{1F4F1}';

const String _rule = '========================';

/// A message as the app writes it.
String message(String title, List<String> sections, String signature) =>
    '$title\n$_rule\n\n${sections.join('\n\n')}\n\n$_rule\n$_app $signature';

Set<ShareSection> all(ShareSource source) => source.available.toSet();

String textOf(
        ShareSource source, Set<ShareSection> selected, String language) =>
    source.composeText(selected, labelsIn(language)) ?? '';

String l(String language, String key) => arbLookup(language, key)!;

void main() {
  group('Request', () {
    final full = request(
      type: 'rent',
      propertyType: 'residential',
      specific: 'Villa',
      rooms: 3,
      bathrooms: 2,
      squareFootage: '1800',
      min: '1000000',
      max: '1500000',
      city: 'Dubai',
      areas: <String>['jbr', 'dubaiMarina'],
      phone: '+971501234567',
      notes: 'Corner unit',
    );

    test('offers every part it has data for, and no media or document', () {
      final source = PropertyShareSource.request(full);
      expect(source.available, <ShareSection>[
        ShareSection.basicInfo,
        ShareSection.pricing,
        ShareSection.propertyDetails,
        ShareSection.locationDetails,
        ShareSection.contact,
        ShareSection.notes,
      ]);
      expect(source.media, isEmpty);
      expect(source.document, isNull);
      expect(source.titleKey, 'shareRequest');
    });

    test('starts with everything chosen, as it always has', () {
      final source = PropertyShareSource.request(full);
      expect(source.defaultSelection, all(source));
    });

    test('is written in English the way the app has always written it', () {
      final source = PropertyShareSource.request(full);
      expect(
        textOf(source, all(source), 'en'),
        message(
          'Request Details',
          <String>[
            '$_home Property Details:\n'
                '• Request Type: Rent Request\n'
                '• Property Type: Residential - Villa\n'
                '• Rooms: 3\n'
                '• Bathrooms: 2\n'
                '• Square Footage: 1,800 sq ft',
            '$_money Price: AED 1,000,000 - 1,500,000',
            '$_pin Location Details:\n'
                '• City: Dubai\n'
                '• Areas: Jumeirah Beach Residence (JBR), Dubai Marina',
            '$_phone Contact Info:\n'
                '• Phone: +971 50 123 4567',
            '$_note Notes:\nCorner unit',
          ],
          'Shared By Broker Wallet App',
        ),
      );
    });

    test('is genuinely Arabic in Arabic', () {
      final source = PropertyShareSource.request(full);
      final text = textOf(source, all(source), 'ar');

      expect(text, contains(l('ar', 'requestDetails')));
      expect(text, contains(l('ar', 'rentRequest')));
      expect(
          text,
          contains(
              '${l('ar', 'propertyType')}: ${l('ar', 'residential')} - ${l('ar', 'villa')}'));
      expect(text, contains(l('ar', 'jbr')));
      expect(text, contains(l('ar', 'dubaiMarina')));
      expect(text, contains(l('ar', 'dubai')));
      expect(text, contains(l('ar', 'sharedByBrokerWallet')));
      expect(text, contains('\u2066+971 50 123 4567\u2069'));
      // The prices keep their digits left to right, the currency is Arabic.
      expect(text,
          contains('\u20661,000,000 - 1,500,000\u2069 ${l('ar', 'aed')}'));
      // The person's own words are never translated.
      expect(text, contains('Corner unit'));

      // No English label slips in.
      for (final key in <String>[
        'requestDetails',
        'rentRequest',
        'propertyDetails',
        'locationDetails',
        'contactInfo',
        'notes',
        'phone',
        'areas',
        'city',
        'price',
        'rooms',
        'bathrooms',
        'squareFootage',
      ]) {
        expect(text.contains(l('en', key)), isFalse,
            reason: 'English "${l('en', key)}" leaked into the Arabic text');
      }
    });

    test('a sale request is not left in English in Arabic', () {
      final sale = PropertyShareSource.request(request(type: 'sell'));
      final text = textOf(sale, all(sale), 'ar');
      expect(text, contains(l('ar', 'saleRequest')));
      expect(text.contains(l('en', 'saleRequest')), isFalse);
    });

    test('writes only the parts that were chosen', () {
      final source = PropertyShareSource.request(full);
      final text = textOf(source, <ShareSection>{ShareSection.pricing}, 'en');
      expect(
        text,
        message(
            'Request Details',
            <String>['$_money Price: AED 1,000,000 - 1,500,000'],
            'Shared By Broker Wallet App'),
      );
      expect(text.contains('Phone'), isFalse);
      expect(text.contains('971'), isFalse);
      expect(text.contains('Notes'), isFalse);
    });

    test('never shares the phone number unless it is chosen', () {
      final source = PropertyShareSource.request(full);
      final without = all(source)..remove(ShareSection.contact);
      final text = textOf(source, without, 'en');
      expect(text.contains('Phone'), isFalse);
      expect(text.contains('971'), isFalse);
    });

    test('shares the Request\'s own phone number', () {
      final source =
          PropertyShareSource.request(request(phone: '0551112233', notes: 'x'));
      final text = textOf(source, <ShareSection>{ShareSection.contact}, 'en');
      expect(text, contains('+971 55 111 2233'));
    });

    test('has no message when no text part is chosen', () {
      final source = PropertyShareSource.request(full);
      expect(source.composeText(<ShareSection>{}, labelsIn('en')), isNull);
      expect(
        source.composeText(
            <ShareSection>{ShareSection.media, ShareSection.document},
            labelsIn('en')),
        isNull,
      );
    });

    test('offers nothing it has no data for', () {
      final source = PropertyShareSource.request(request(
        city: '',
        areas: const <String>[],
        phone: '',
        notes: '   ',
        min: '',
        max: '',
      ));
      expect(source.available, <ShareSection>[ShareSection.basicInfo]);
      expect(
        textOf(source, all(source), 'en'),
        message(
          'Request Details',
          <String>['$_home Property Details:\n• Request Type: Rent Request'],
          'Shared By Broker Wallet App',
        ),
      );
    });

    test('does not claim rooms for a plot of land', () {
      final source = PropertyShareSource.request(
          request(specific: 'Land', rooms: 1, bathrooms: 1));
      expect(source.available.contains(ShareSection.propertyDetails), isFalse);
      final text = textOf(
          source,
          <ShareSection>{
            ShareSection.basicInfo,
            ShareSection.propertyDetails,
          },
          'en');
      expect(text.contains('Rooms'), isFalse);
      expect(text.contains('Bathrooms'), isFalse);
    });

    test('an unknown historical area is shown safely, never as a key', () {
      final source = PropertyShareSource.request(request(
          areas: <String>['oldAreaKey', 'Some Old Area', 'dubaiMarina']));
      final text =
          textOf(source, <ShareSection>{ShareSection.locationDetails}, 'en');
      expect(
          text, contains('• Areas: Old Area Key, Some Old Area, Dubai Marina'));
      expect(text.contains('oldAreaKey'), isFalse);
      expect(text.contains('dubaiMarina'), isFalse);
    });

    test('a short line under pricing, location and contact says what is in it',
        () {
      final source = PropertyShareSource.request(full);
      final en = labelsIn('en');
      expect(source.sectionDetail(ShareSection.pricing, en),
          'AED 1,000,000 - 1,500,000');
      expect(source.sectionDetail(ShareSection.locationDetails, en),
          'Dubai · Jumeirah Beach Residence (JBR), Dubai Marina');
      expect(
          source.sectionDetail(ShareSection.contact, en), '+971 50 123 4567');
      expect(source.sectionDetail(ShareSection.notes, en), isNull);
    });
  });

  group('Offer', () {
    final home = offer(
      type: 'sell',
      propertyType: 'residential',
      specific: 'Apartment',
      rooms: 2,
      bathrooms: 2,
      min: '900000',
      max: '1100000',
      city: 'Dubai',
      areas: <String>['dubaiMarina'],
      location: 'Marina Gate, tower 2',
      phone: '+971501234567',
      notes: 'High floor',
      latitude: 25.2,
      longitude: 55.27,
      address: 'Marina Gate 2, Dubai',
    );

    test('offers a map only for a pin that can be opened', () {
      expect(PropertyShareSource.offer(home).available,
          contains(ShareSection.map));
      for (final unset in <OfferModelSpec>[
        OfferModelSpec(null, null),
        OfferModelSpec(0.0, 0.0),
        OfferModelSpec(25.2, null),
        OfferModelSpec(95, 55),
      ]) {
        final source = PropertyShareSource.offer(
            offer(latitude: unset.lat, longitude: unset.lng, address: 'x'));
        expect(source.available.contains(ShareSection.map), isFalse,
            reason: '${unset.lat}, ${unset.lng}');
      }
    });

    test('puts the map link, and the address, in the message', () {
      final source = PropertyShareSource.offer(home);
      final text = textOf(source, all(source), 'en');
      expect(
        text,
        contains('$_pin Location Details:\n'
            '• City: Dubai\n'
            '• Areas: Dubai Marina\n'
            '• Location: Marina Gate, tower 2\n'
            '• Address: Marina Gate 2, Dubai\n'
            '• Map Link: https://www.google.com/maps/search/?api=1&query=25.2,55.27'),
      );
      expect(text.contains('maps.google.com'), isFalse);
    });

    test('with only the map chosen the section is the map\'s', () {
      final source = PropertyShareSource.offer(home);
      final text = textOf(source, <ShareSection>{ShareSection.map}, 'en');
      expect(text, contains('$_pin Map Location:'));
      expect(text, contains('• Map Link: https://'));
      expect(text.contains('• City'), isFalse);
    });

    test('keeps the link left to right in Arabic', () {
      final source = PropertyShareSource.offer(home);
      final text = textOf(source, <ShareSection>{ShareSection.map}, 'ar');
      expect(
        text,
        contains(
            '${l('ar', 'mapLink')}: \u2066https://www.google.com/maps/search/?api=1&query=25.2,55.27\u2069'),
      );
    });

    test('shows a single price as one amount', () {
      final source = PropertyShareSource.offer(offer(max: '2500000'));
      expect(textOf(source, <ShareSection>{ShareSection.pricing}, 'en'),
          contains('$_money Price: AED 2,500,000'));
    });

    test('starts with the photos chosen and the videos not', () {
      final source = PropertyShareSource.offer(home,
          media: mediaItems(<OfferMediaRef>[
            mediaRef('photo-a'),
            mediaRef('video-a', video: true),
            mediaRef('photo-b'),
          ]));
      expect(source.available.contains(ShareSection.media), isTrue);
      expect(source.defaultMediaKeys, <String>{'photo-a', 'photo-b'});
      expect(source.defaultSelection.contains(ShareSection.media), isTrue);
    });

    test('a record with only videos starts with no media chosen', () {
      final source = PropertyShareSource.offer(home,
          media: mediaItems(<OfferMediaRef>[mediaRef('video-a', video: true)]));
      expect(source.available.contains(ShareSection.media), isTrue);
      expect(source.defaultMediaKeys, isEmpty);
      expect(source.defaultSelection.contains(ShareSection.media), isFalse);
    });

    test('no media option when there is nothing that can be fetched', () {
      final source = PropertyShareSource.offer(home,
          media: mediaItems(<OfferMediaRef>[
            mediaRef('queued', phase: OfferMediaUploadPhase.queued),
            mediaRef('uploading', phase: OfferMediaUploadPhase.uploading),
            mediaRef('', withCacheKey: false),
          ]));
      expect(source.media, isEmpty);
      expect(source.available.contains(ShareSection.media), isFalse);
    });

    test('a link in a media item never reaches the message', () {
      final source = PropertyShareSource.offer(home,
          media: mediaItems(<OfferMediaRef>[
            mediaRef('media-id-9c4e1',
                signedUrl:
                    'https://bucket.r2.cloudflarestorage.com/profiles/u/offers/o/m.jpg?X-Amz-Signature=abc&X-Amz-Credential=zzz'),
          ]));
      for (final language in <String>['en', 'ar']) {
        final text = textOf(source, all(source), language);
        expect(text.contains('X-Amz'), isFalse);
        expect(text.contains('cloudflare'), isFalse);
        expect(text.contains('r2.'), isFalse);
        expect(text.contains('media-id-9c4e1'), isFalse);
        expect(text.contains('profiles/'), isFalse);
      }
    });

    test('file names say no more than was chosen to share', () {
      final source = PropertyShareSource.offer(home,
          media: mediaItems(<OfferMediaRef>[mediaRef('photo-a')]));
      final item = source.media.first;
      final withPlace = <ShareSection>{
        ShareSection.media,
        ShareSection.locationDetails
      };
      expect(source.mediaBaseName(item, 1, withPlace, labelsIn('en')),
          'Offer-Dubai-Marina-01');
      // Always English, so it is plain ASCII whatever language the app is in.
      expect(source.mediaBaseName(item, 2, withPlace, labelsIn('ar')),
          'Offer-Dubai-Marina-02');
      expect(
          source.mediaBaseName(
              item, 3, <ShareSection>{ShareSection.media}, labelsIn('en')),
          'Offer-03');
    });

    test('a place with no area is named by its city', () {
      final source = PropertyShareSource.offer(offer(city: 'Abu Dhabi'),
          media: mediaItems(<OfferMediaRef>[mediaRef('photo-a')]));
      expect(
        source.mediaBaseName(source.media.first, 1,
            <ShareSection>{ShareSection.locationDetails}, labelsIn('ar')),
        'Offer-Abu-Dhabi-01',
      );
    });

    test('an Offer with nothing to say still has its type', () {
      final source = PropertyShareSource.offer(offer(city: ''));
      expect(source.available, <ShareSection>[ShareSection.basicInfo]);
    });
  });

  group('Owner', () {
    final person = owner(
      name: 'Khalid Al Mansoori',
      phone: '+971501234567',
      propertyType: 'villa',
      location: 'Dubai Marina, Dubai, Marina Gate tower 2',
      notes: 'Prefers calls after 5 pm',
      latitude: 25.2,
      longitude: 55.27,
      address: 'Marina Gate 2',
    );

    test('starts with the name and the place, never the number or the notes',
        () {
      final source = OwnerShareSource(person);
      expect(source.defaultSelection, <ShareSection>{
        ShareSection.basicInfo,
        ShareSection.locationDetails,
        ShareSection.map,
      });
      final text = textOf(source, source.defaultSelection, 'en');
      expect(text.contains('Phone'), isFalse);
      expect(text.contains('971'), isFalse);
      expect(text.contains('Prefers calls'), isFalse);
      expect(text, contains('• Name: Khalid Al Mansoori'));
    });

    test('shares the number only when it is ticked', () {
      final source = OwnerShareSource(person);
      final text = textOf(source, <ShareSection>{ShareSection.contact}, 'en');
      expect(text, contains('• Phone: +971 50 123 4567'));
      expect(source.sectionDetail(ShareSection.contact, labelsIn('en')),
          '+971 50 123 4567');
    });

    test('writes a catalog location in the language of the message', () {
      final source = OwnerShareSource(person);
      expect(
        textOf(source, <ShareSection>{ShareSection.locationDetails}, 'en'),
        contains(
            '• Property Location: Dubai Marina, Dubai, Marina Gate tower 2'),
      );
      expect(
        textOf(source, <ShareSection>{ShareSection.locationDetails}, 'ar'),
        contains(
            '${l('ar', 'propertyLocation')}: ${l('ar', 'dubaiMarina')}, ${l('ar', 'dubai')}, Marina Gate tower 2'),
      );
    });

    test('a location saved in Arabic reads in English in an English message',
        () {
      final source = OwnerShareSource(owner(
          name: 'x',
          location: '${l('ar', 'dubaiMarina')}, ${l('ar', 'dubai')}'));
      expect(
        textOf(source, <ShareSection>{ShareSection.locationDetails}, 'en'),
        contains('• Property Location: Dubai Marina, Dubai'),
      );
    });

    test('a location the owner typed is kept exactly', () {
      final source =
          OwnerShareSource(owner(name: 'x', location: 'Behind the old souk'));
      expect(
        textOf(source, <ShareSection>{ShareSection.locationDetails}, 'ar'),
        contains('Behind the old souk'),
      );
    });

    test('a suggested property type is written in the message\'s language', () {
      final source = OwnerShareSource(person);
      expect(textOf(source, <ShareSection>{ShareSection.basicInfo}, 'ar'),
          contains('${l('ar', 'propertyType')}: ${l('ar', 'villa')}'));
      final custom =
          OwnerShareSource(owner(name: 'x', propertyType: 'Castle by the sea'));
      expect(textOf(custom, <ShareSection>{ShareSection.basicInfo}, 'ar'),
          contains('Castle by the sea'));
    });

    test('names its media without the owner or the place', () {
      final source = OwnerShareSource(person,
          media: mediaItems(<OfferMediaRef>[mediaRef('photo-a')]));
      for (final selected in <Set<ShareSection>>[
        <ShareSection>{ShareSection.media},
        all(source),
      ]) {
        final name = source.mediaBaseName(
            source.media.first, 1, selected, labelsIn('en'));
        expect(name, 'Owner-Property-01');
      }
    });

    test('an Owner with no map pin and no location offers neither', () {
      final source = OwnerShareSource(owner(name: 'Khalid'));
      expect(source.available, <ShareSection>[ShareSection.basicInfo]);
    });
  });

  group('Broker', () {
    final b = broker(
        name: 'Sara Ahmed', phone: '0501112233', notes: 'Knows JVC well');

    test('offers name, contact and notes, with the notes not chosen', () {
      final source = BrokerShareSource(b);
      expect(source.available, <ShareSection>[
        ShareSection.basicInfo,
        ShareSection.contact,
        ShareSection.notes,
      ]);
      expect(source.defaultSelection, <ShareSection>{
        ShareSection.basicInfo,
        ShareSection.contact,
      });
      expect(source.titleKey, 'shareBroker');
    });

    test('writes a short, readable message', () {
      final source = BrokerShareSource(b);
      expect(
        textOf(source, source.defaultSelection, 'en'),
        message(
          'Broker details',
          <String>[
            '$_person Basic Information:\n• Name: Sara Ahmed',
            '$_phone Contact Info:\n• Phone: +971 50 111 2233',
          ],
          'Shared By Broker Wallet App',
        ),
      );
    });

    test('has no contact option for a broker with no number', () {
      final source = BrokerShareSource(broker(name: 'Sara'));
      expect(source.available, <ShareSection>[ShareSection.basicInfo]);
    });

    test('leaves the private notes out unless they are ticked', () {
      final source = BrokerShareSource(b);
      expect(textOf(source, source.defaultSelection, 'en').contains('JVC'),
          isFalse);
      expect(textOf(source, <ShareSection>{ShareSection.notes}, 'en'),
          contains('Knows JVC well'));
    });
  });

  group('Watchman', () {
    final w = watchman(
      name: 'Ali',
      building: 'Marina Heights',
      buildingLocation: 'Dubai Marina, behind the mall',
      phone: '+971521234567',
      notes: 'Night shift',
      latitude: 25.08,
      longitude: 55.14,
      address: 'Marina Walk',
    );

    test('offers name and building, place, map, contact and notes', () {
      final source = WatchmanShareSource(w);
      expect(source.available, <ShareSection>[
        ShareSection.basicInfo,
        ShareSection.locationDetails,
        ShareSection.map,
        ShareSection.contact,
        ShareSection.notes,
      ]);
      expect(source.defaultSelection.contains(ShareSection.notes), isFalse);
      expect(source.defaultSelection.contains(ShareSection.contact), isTrue);
      expect(source.titleKey, 'shareWatchman');
      expect(source.subjectKey, 'watchmenDetails');
    });

    test('writes the building and where it is', () {
      final source = WatchmanShareSource(w);
      final text = textOf(source, source.defaultSelection, 'en');
      expect(text, contains('• Name: Ali'));
      expect(text, contains('• Building Name: Marina Heights'));
      expect(
          text, contains('• Building location: Dubai Marina, behind the mall'));
      expect(text, contains('• Address: Marina Walk'));
      expect(
          text,
          contains(
              '• Map Link: https://www.google.com/maps/search/?api=1&query=25.08,55.14'));
      expect(text, contains('• Phone: +971 52 123 4567'));
      expect(text.contains('Night shift'), isFalse);
    });
  });

  group('Office', () {
    final o = office(
      name: 'Prime Properties',
      manager: 'Huda Saleh',
      phone: '+971521234567',
      location: 'Business Bay, Dubai',
      notes: 'Open until 8',
    );

    test('offers the office, where it is and how to reach it', () {
      final source = OfficeShareSource(o);
      expect(source.available, <ShareSection>[
        ShareSection.basicInfo,
        ShareSection.locationDetails,
        ShareSection.contact,
        ShareSection.notes,
      ]);
      expect(source.titleKey, 'shareOffice');
    });

    test('writes name, manager, place and number', () {
      final source = OfficeShareSource(o);
      final text = textOf(source, source.defaultSelection, 'en');
      expect(text, contains('• Office Name: Prime Properties'));
      expect(text, contains('• Manager Name: Huda Saleh'));
      expect(text, contains('• Office location: Business Bay, Dubai'));
      expect(text, contains('• Phone: +971 52 123 4567'));
      expect(text.contains('Open until 8'), isFalse);
    });

    test('an office with only a name still has its name', () {
      final source = OfficeShareSource(office(name: 'Prime'));
      expect(source.available, <ShareSection>[ShareSection.basicInfo]);
    });
  });

  group('Quotation', () {
    test('offers its summary and its PDF; the money lines start unchosen', () {
      final source = QuotationShareSource(
        quotation(
            officeName: 'Prime Offices',
            total: 120000,
            fee: 2000,
            installments: 4),
        fetchPdf: () async => throw StateError('not used'),
      );
      expect(source.available, <ShareSection>[
        ShareSection.basicInfo,
        ShareSection.pricing,
        ShareSection.document,
      ]);
      expect(source.defaultSelection, <ShareSection>{
        ShareSection.basicInfo,
        ShareSection.document,
      });
      expect(source.titleKey, 'shareQuotation');
      expect(source.sectionTitleKey(ShareSection.document), 'quotationPdf');
      expect(source.sectionTitleKey(ShareSection.pricing), 'pricing');
    });

    test('writes a summary, and the money when it is chosen', () {
      final source = QuotationShareSource(
        quotation(
            propertyType: 'Apartment',
            officeName: 'Prime Offices',
            total: 120000,
            fee: 2000,
            installments: 4),
        fetchPdf: () async => throw StateError('not used'),
      );
      expect(
        textOf(source, source.defaultSelection, 'en'),
        message(
          'Quotation Details',
          <String>[
            '$_doc Quotation:\n'
                '• Property Title: Apartment 306\n'
                '• Property Type: Apartment\n'
                '• Office Name: Prime Offices',
          ],
          'Shared By Broker Wallet App',
        ),
      );
      expect(
        textOf(source, <ShareSection>{ShareSection.pricing}, 'en'),
        message(
          'Quotation Details',
          <String>[
            '$_money Pricing:\n'
                '• Total Amount: AED 120,000\n'
                '• Professional Fee: AED 2,000\n'
                '• Number of Installments: 4',
          ],
          'Shared By Broker Wallet App',
        ),
      );
    });

    test('uses the quotation\'s own currency', () {
      final source = QuotationShareSource(
        quotation(total: 5000, currency: 'USD'),
        fetchPdf: () async => throw StateError('not used'),
      );
      expect(textOf(source, <ShareSection>{ShareSection.pricing}, 'en'),
          contains('• Total Amount: USD 5,000'));
    });

    test('has no PDF option for a quotation with no PDF', () {
      final source = QuotationShareSource(
        quotation(pdfMediaId: null),
        fetchPdf: () async => throw StateError('not used'),
      );
      expect(source.document, isNull);
      expect(source.available.contains(ShareSection.document), isFalse);
      expect(source.defaultSelection.contains(ShareSection.document), isFalse);
    });

    test('names the PDF for the property, never for an id', () {
      final source = QuotationShareSource(
        quotation(title: 'Apartment 306'),
        fetchPdf: () async => throw StateError('not used'),
      );
      expect(source.document!.fileBaseName,
          'Broker-Wallet-Quotation-Apartment-306');
      expect(source.document!.fileBaseName.contains('quotation-id'), isFalse);
      expect(source.document!.fileBaseName.contains('pdf-media'), isFalse);

      expect(
        QuotationShareSource(quotation(title: ''),
                fetchPdf: () async => throw StateError('not used'))
            .document!
            .fileBaseName,
        'Broker-Wallet-Quotation',
      );
      expect(
        QuotationShareSource(quotation(title: '../../etc/x\\y.pdf'),
                fetchPdf: () async => throw StateError('not used'))
            .document!
            .fileBaseName,
        'Broker-Wallet-Quotation-etc-x-y-pdf',
      );
    });

    test('the message never mentions an id', () {
      final source = QuotationShareSource(
        quotation(total: 1, fee: 1, installments: 1, officeName: 'Office'),
        fetchPdf: () async => throw StateError('not used'),
      );
      for (final language in <String>['en', 'ar']) {
        final text = textOf(source, all(source), language);
        expect(text.contains('quotation-id'), isFalse);
        expect(text.contains('pdf-media'), isFalse);
      }
    });
  });

  group('every label a message uses exists in both languages', () {
    test('the labels the sources write', () {
      const keys = <String>[
        // headings and titles
        'offerDetails', 'requestDetails', 'propertyOwner', 'brokerDetails',
        'watchmenDetails', 'officeDetails', 'quotationDetails', 'quotation',
        'sharedByBrokerWallet', 'shareOffer', 'shareRequest', 'shareOwner',
        'shareBroker', 'shareWatchman', 'shareOffice', 'shareQuotation',
        // sections
        'basicInformation', 'pricing', 'propertyDetails', 'locationDetails',
        'mapLocation', 'contactInfo', 'notes', 'mediaFiles', 'documents',
        'quotationPdf',
        // lines
        'offerType', 'requestType', 'rentOffer', 'saleOffer', 'rentRequest',
        'saleRequest', 'propertyType', 'rooms', 'bathrooms', 'squareFootage',
        'squareFootageUnit', 'price', 'aed', 'city', 'areas', 'location',
        'address', 'mapLink', 'phone', 'name', 'propertyLocation',
        'buildingName', 'buildingLocation', 'officeName', 'managerName',
        'officeLocation', 'propertyTitle', 'totalAmount', 'professionalFee',
        'numberOfInstallments',
        // types and cities the messages translate
        'residential', 'commercial', 'furnished', 'dubai', 'abuDhabi',
        'sharjah', 'ajman', 'rasAlKhaimah', 'fujairah', 'ummAlQuwain',
        'alAin', 'khorFakkan',
      ];
      for (final key in keys) {
        for (final language in <String>['en', 'ar']) {
          final text = arbLookup(language, key);
          expect(text, isNotNull, reason: '$key is missing in $language');
          expect(text!.trim(), isNotEmpty,
              reason: '$key is empty in $language');
        }
      }
    });

    test('every property type the forms offer has both names', () {
      for (final key in ShareFormat.propertySubTypeKeys) {
        expect(arbLookup('en', key), isNotNull, reason: '$key in English');
        expect(arbLookup('ar', key), isNotNull, reason: '$key in Arabic');
      }
    });
  });

  group('no message ever leaks developer text', () {
    final sources = <String, ShareSource>{
      'request': PropertyShareSource.request(request(
          areas: <String>['bogusKey'], city: 'noSuchCity', specific: 'Villa')),
      'offer': PropertyShareSource.offer(offer(
          areas: <String>['bogusKey'],
          city: 'noSuchCity',
          specific: 'Villa',
          phone: 'null',
          notes: 'null',
          location: 'N/A')),
      'owner': OwnerShareSource(owner(name: 'x', notes: 'undefined')),
      'broker':
          BrokerShareSource(broker(name: 'x', phone: 'null', notes: 'N/A')),
      'watchman': WatchmanShareSource(watchman(name: 'x', building: 'null')),
      'office': OfficeShareSource(office(name: 'x', manager: 'null')),
    };

    for (final entry in sources.entries) {
      for (final language in <String>['en', 'ar']) {
        test('${entry.key} in $language', () {
          final text = textOf(entry.value, all(entry.value), language);
          final lowered = text.toLowerCase();
          expect(text, isNotEmpty);
          expect(lowered.contains('null'), isFalse);
          expect(lowered.contains('undefined'), isFalse);
          expect(lowered.contains('n/a'), isFalse);
          expect(text.contains('**'), isFalse);
          expect(text.contains('not found'), isFalse);
          expect(text.contains('bogusKey'), isFalse);
          expect(text.contains('noSuchCity'), isFalse);
          // No bullet left with nothing after its label, no doubled blank line.
          expect(RegExp(r'^• .*:\s*$', multiLine: true).hasMatch(text), isFalse,
              reason: 'a label with nothing after it');
          expect(text.contains('\n\n\n'), isFalse);
          expect(text.endsWith('\n'), isFalse);
        });
      }
    }
  });
}

class OfferModelSpec {
  const OfferModelSpec(this.lat, this.lng);

  final double? lat;
  final double? lng;
}
