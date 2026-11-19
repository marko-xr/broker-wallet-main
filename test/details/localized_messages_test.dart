import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/utils/core_entity_error_message.dart';
import 'package:broker_wallet/src/common/utils/phone_number_normalizer.dart';
import 'package:broker_wallet/src/data/models/property_status.dart';
import 'package:broker_wallet/src/services/core_entity_payload_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The messages a user sees after saving, updating, deleting or changing the
/// status of a record follow the app language: Arabic shows Arabic, never
/// the old hard-coded English sentences.
Map<String, String> _arb(String lang) =>
    (jsonDecode(File('lib/src/common/localization/app_$lang.arb')
            .readAsStringSync()) as Map<String, dynamic>)
        .map((key, value) => MapEntry(key, '$value'));

final _arabic = RegExp(r'[\u0600-\u06FF]');
final _latinWord = RegExp(r'[A-Za-z]{3,}');

void main() {
  final en = _arb('en');
  final ar = _arb('ar');
  String translateAr(String key) => ar[key] ?? '** $key not found';

  const newKeys = [
    'recordLoadFailedOffer',
    'recordLoadFailedRequest',
    'recordLoadFailedOwner',
    'recordLoadFailedBroker',
    'recordLoadFailedOffice',
    'recordLoadFailedWatchman',
    'requestsLoadFailed',
    'requiredFieldsMissing',
    'offerSavedSuccessfully',
    'offerUpdatedSuccessfully',
    'ownerSavedSuccessfully',
    'ownerUpdatedSuccessfully',
    'requestSavedSuccessfully',
    'requestUpdatedSuccessfully',
    'unableToDeleteOffer',
    'unableToDeleteRequest',
    'unableToDeleteOwner',
    'unableToDeleteBroker',
    'unableToDeleteOffice',
    'unableToDeleteWatchman',
    'offerStatusUpdatedTo',
    'requestStatusUpdatedTo',
    'unableToUpdateOffer',
    'unableToUpdateRequest',
    'mediaFilesAdded',
    'unableToSelectMedia',
    'discardChangesCancelMessage',
    'stay',
    'saveErrorInvalidPhone',
    'saveErrorSessionExpired',
    'saveErrorNoPermission',
    'saveErrorNoConnection',
    'saveErrorInvalidData',
    'saveErrorGeneric',
    'updateErrorGeneric',
    'validationInvalidNumber',
    'validationIncompleteLocation',
    'validationInvalidLatitude',
    'validationInvalidLongitude',
    'validationSelectRentOrSell',
    'validationInvalidOfferStatus',
    'validationInvalidRequestStatus',
    'validationPriceRange',
    'validationNegative',
    'validationNameRequired',
    'mediaNoFiles',
    'mediaFilesCountOne',
    'mediaFilesCount',
    'mediaTapToViewOrRemove',
    'mediaUnsupportedImageUrl',
    'mediaNoImageData',
    'mediaFailedToLoad',
    'mediaErrorLoadingVideo',
    'mediaVideoFailedToLoad',
    'mediaImageFailedToLoad',
    'mediaUnsupportedType',
    'mediaOpenExternally',
    'mediaVideoWithoutAudio',
  ];

  test('every new message has an English and an Arabic text', () {
    for (final key in newKeys) {
      expect(en[key], isNotNull, reason: 'en $key');
      expect(ar[key], isNotNull, reason: 'ar $key');
      expect(ar[key], matches(_arabic), reason: 'ar $key is not Arabic');
      // {placeholders} are filled by the app, not shown as they are.
      expect(ar[key]!.replaceAll(RegExp(r'\{\w+\}'), ''),
          isNot(matches(_latinWord)),
          reason: 'ar $key still has English words');
    }
  });

  test('reused message keys exist in both languages', () {
    for (final key in [
      'offerDeletedSuccessfully',
      'requestDeletedSuccessfully',
      'ownerDeletedSuccessfully',
      'brokerDeletedSuccessfully',
      'officeDeletedSuccessfully',
      'watchmenDeletedSuccessfully',
      'couldNotOpenWhatsApp',
      'discardChanges',
      'areYouSureDiscard',
      'keepEditing',
      'discard',
      'watchmanNotFound',
      'requestNotFound',
      'goBack',
      'failedToLoadImage',
      'offerSavedMediaUploading',
      'ownerSavedMediaUploading',
      'offerUpdatedMediaUploading',
    ]) {
      expect(ar[key], matches(_arabic), reason: key);
      expect(en[key], isNotNull, reason: key);
    }
  });

  test('every status name used in the status message is translated', () {
    for (final status in PropertyStatus.values) {
      expect(ar[status.name], matches(_arabic), reason: status.name);
    }
  });

  group('save errors in Arabic', () {
    final failures = <String, Object>{
      'phone': PhoneValidationException('bad'),
      'session': StateError('session expired'),
      'permission': const PostgrestException(message: 'x', code: '42501'),
      'auth': const AuthException('x'),
      'invalid data': const PostgrestException(message: 'x', code: '23514'),
      'unknown': Exception('boom'),
    };
    for (final entry in failures.entries) {
      for (final isUpdate in [false, true]) {
        test('${entry.key} (${isUpdate ? 'update' : 'save'})', () {
          final message = CoreEntityErrorMessage.save(entry.value, 'offer',
              isUpdate: isUpdate, translate: translateAr);
          expect(message, matches(_arabic));
          expect(message, isNot(matches(_latinWord)));
        });
      }
    }

    test('form validation messages are Arabic', () {
      final errors = <Object>[];
      void capture(void Function() run) {
        try {
          run();
        } catch (e) {
          errors.add(e);
        }
      }

      capture(() => CoreEntityPayloadBuilder.optionalNumber('abc', 'price'));
      capture(() => CoreEntityPayloadBuilder.coordinates(1, null));
      capture(() => CoreEntityPayloadBuilder.coordinates(200, 0));
      capture(() => CoreEntityPayloadBuilder.coordinates(0, 200));
      expect(errors, hasLength(4));
      for (final error in errors) {
        expect(error, isA<CoreEntityValidationException>());
        final message = CoreEntityErrorMessage.save(error, 'offer',
            isUpdate: false, translate: translateAr);
        expect(message, matches(_arabic), reason: '$error');
        expect(message, isNot(matches(_latinWord)), reason: '$error');
      }
    });

    test('without a translator the English text is unchanged', () {
      expect(
          CoreEntityErrorMessage.save(Exception('boom'), 'offer',
              isUpdate: false),
          'Unable to save the offer. Please try again.');
      expect(
          CoreEntityErrorMessage.save(
              const CoreEntityValidationException('Invalid latitude.',
                  messageKey: 'validationInvalidLatitude'),
              'offer',
              isUpdate: false),
          'Invalid latitude.');
    });

    test('English placeholders are filled', () {
      String translateEn(String key) => en[key]!;
      expect(
          CoreEntityErrorMessage.save(const AuthException('x'), 'broker',
              isUpdate: false, translate: translateEn),
          'You do not have permission to save this broker.');
      expect(
          CoreEntityErrorMessage.save(Exception('boom'), 'owner',
              isUpdate: true, translate: translateEn),
          'Unable to update the owner. Please try again.');
    });
  });

  test('record screens no longer hard-code English messages', () {
    const files = [
      'lib/src/viewmodels/AddScreens/add_brokers_viewmodel.dart',
      'lib/src/viewmodels/AddScreens/add_offices_viewmodel.dart',
      'lib/src/viewmodels/AddScreens/add_watchmen_viewmodel.dart',
      'lib/src/viewmodels/AddScreens/add_owners_viewmodel.dart',
      'lib/src/viewmodels/AddScreens/add_requested_viewmodel.dart',
      'lib/src/viewmodels/AddScreens/add_offers_viewmodel.dart',
      'lib/src/viewmodels/ListScreens/list_brokers_viewmodel.dart',
      'lib/src/viewmodels/ListScreens/list_offices_viewmodel.dart',
      'lib/src/viewmodels/ListScreens/list_watchmen_viewmodel.dart',
      'lib/src/viewmodels/ListScreens/list_owners_viewmodel.dart',
      'lib/src/viewmodels/ListScreens/list_requests_viewmodel.dart',
      'lib/src/viewmodels/ListScreens/list_offers_viewmodel.dart',
      'lib/src/views/Screens/ViewLists/brokers_list_view.dart',
      'lib/src/views/Screens/ViewLists/offices_list_view.dart',
      'lib/src/views/Screens/ViewLists/owners_list_view.dart',
      'lib/src/views/Screens/ViewLists/watchmen_list_view.dart',
      'lib/src/views/Widgets/unified_media_preview_grid.dart',
      'lib/src/views/Screens/ViewDetails/widgets/media_gallery_widget.dart',
      'lib/src/views/Screens/ViewDetails/widgets/full_screen_media_viewer.dart',
    ];
    final banned = RegExp(
        r"""(_showToast|msg:|_error =|Text)\(?\s*['"](Unable to|Please fill|"""
        r"""Added |Watchmen not|Offer |Owner |Request |Broker |Office |"""
        r"""Could not open|Discard|Keep Editing|Stay|You have unsaved|"""
        r"""Are you sure|No Media|Tap to view|Failed to load|No image|"""
        r"""Unsupported|Error loading|Video failed|Image failed|Open Ext)""");
    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(banned.allMatches(source).map((m) => m.group(0)), isEmpty,
          reason: path);
    }
  });
}
