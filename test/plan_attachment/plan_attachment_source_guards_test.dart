// Source guards for the land / plot plan attachment: the properties that no
// single behavior test can see — that the plan stays out of the photo and video
// gallery, keeps no link, key or secret anywhere, is sent only after its record
// was saved, is wired the same way for Offers and Owners, and agrees with the
// Media Worker and the database it talks to.
//
// These read files; they do not run the Worker or SQL. Pure Dart.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _services = 'lib/src/services/plan_attachment';

const _serviceFiles = <String>[
  '$_services/plan_attachment_models.dart',
  '$_services/plan_attachment_policy.dart',
  '$_services/plan_attachment_screening.dart',
  '$_services/plan_attachment_transport.dart',
  '$_services/r2_plan_attachment_service.dart',
  '$_services/plan_attachment_workflow.dart',
  '$_services/plan_attachment_files.dart',
  '$_services/plan_attachment_file_picker.dart',
];

const _viewModelFiles = <String>[
  'lib/src/viewmodels/plan_attachment_form.dart',
  'lib/src/viewmodels/plan_attachment_form_factory.dart',
  'lib/src/viewmodels/plan_attachment_details_loader.dart',
];

const _widgetFiles = <String>[
  'lib/src/views/Widgets/plan_attachment_section.dart',
  'lib/src/views/Widgets/plan_attachment_actions.dart',
  'lib/src/views/Widgets/plan_attachment_details_card.dart',
  'lib/src/views/Widgets/plan_attachment_selection.dart',
];

const _allPlanFiles = <String>[
  ..._serviceFiles,
  ..._viewModelFiles,
  ..._widgetFiles,
];

const _offerViewModel =
    'lib/src/viewmodels/AddScreens/add_offers_viewmodel.dart';
const _ownerViewModel =
    'lib/src/viewmodels/AddScreens/add_owners_viewmodel.dart';
const _offerForm = 'lib/src/views/Screens/ViewAdd/add_offers_view.dart';
const _ownerForm = 'lib/src/views/Screens/ViewAdd/add_owners_view.dart';
const _offerDetails =
    'lib/src/views/Screens/ViewDetails/offers_view_details.dart';
const _ownerDetails =
    'lib/src/views/Screens/ViewDetails/owners_view_details.dart';
const _worker = 'cloudflare/workers/r2-profile-upload/worker.js';
const _migration =
    'supabase/migrations/20261012233000_offer_owner_plan_attachments.sql';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('﻿', '');

/// Dart source without whole-line comments and block comments: what the code
/// does, not what its documentation says it never does.
String _code(String path) => _read(path)
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

List<String> _imports(String path) =>
    RegExp(r"^import '([^']+)'", multiLine: true)
        .allMatches(_read(path))
        .map((m) => m.group(1)!)
        .toList();

int _at(String source, String needle, [int from = 0]) {
  final index = source.indexOf(needle, from);
  expect(index, greaterThanOrEqualTo(0), reason: 'missing: $needle');
  return index;
}

void main() {
  group('the plan is its own attachment, never a gallery item', () {
    test('no plan file touches the gallery\'s queue, store or caches', () {
      const forbidden = <String>[
        'offer_media_upload_queue',
        'offline_media_service',
        'media_pick_recovery',
        'private_media_form',
        'media_upload_widget',
        'package:hive',
        'package:shared_preferences',
      ];
      for (final path in _allPlanFiles) {
        for (final import in _imports(path)) {
          for (final name in forbidden) {
            expect(import.contains(name), isFalse,
                reason: '$path imports $name');
          }
        }
      }
    });

    test('the only gallery pieces it reuses are the image contract and pickers',
        () {
      const allowed = <String>{
        'offer_media_policy.dart',
        'offer_media_picker.dart',
        'offer_media_selection.dart',
        'offer_media_cache_identity.dart',
        'image_signature_detector.dart',
      };
      for (final path in _allPlanFiles) {
        for (final import in _imports(path)) {
          final name = import.split('/').last;
          if (!name.startsWith('offer_media_') &&
              !name.startsWith('owner_media_') &&
              !name.startsWith('image_signature')) {
            continue;
          }
          expect(allowed.contains(name), isTrue,
              reason: '$path imports the gallery\'s $name');
        }
      }
    });

    test('no gallery type or table appears in the plan\'s code', () {
      for (final path in _allPlanFiles) {
        final code = _code(path);
        for (final name in [
          'OfferMediaKind',
          'OfferMediaDraft',
          'PrivateMediaForm',
          'MediaUploadWidget',
          'offer_media',
          'owner_media',
        ]) {
          // `offer_media_policy.dart`-style import paths are checked above.
          final withoutImports = code.replaceAll(
              RegExp(r"^import '[^']*'[^;]*;", multiLine: true), '');
          expect(withoutImports.contains(name), isFalse,
              reason: '$path mentions $name');
        }
      }
    });

    test('the plan talks only to the Media Worker, never to a table', () {
      for (final path in _allPlanFiles) {
        final code = _code(path);
        expect(code.contains('.from('), isFalse, reason: path);
        expect(code.contains('.rpc('), isFalse, reason: path);
        expect(code.contains('Supabase.instance.client.from'), isFalse);
      }
    });

    test('the gallery\'s own limits are untouched', () {
      final policy = _read('lib/src/services/offer_media_policy.dart');
      expect(policy.contains('maxItemsPerOffer = 10'), isTrue);
      expect(
          _read(_worker).contains('const MAX_MEDIA_PER_OFFER = 10;'), isTrue);
      expect(
          _read(_worker).contains('const MAX_MEDIA_PER_OWNER = 10;'), isTrue);
    });

    test('a plan reuses no new dependency', () {
      final pubspec = _read('pubspec.yaml');
      final used = <String>{};
      for (final path in _allPlanFiles) {
        for (final import in _imports(path)) {
          if (import.startsWith('package:') &&
              !import.startsWith('package:broker_wallet/') &&
              !import.startsWith('package:flutter/')) {
            used.add(import.substring('package:'.length).split('/').first);
          }
        }
      }
      for (final package in used) {
        expect(pubspec.contains('  $package:'), isTrue,
            reason: '$package is not a dependency of the app');
      }
    });
  });

  group('no link, key or secret is kept', () {
    test(
        'nothing is persisted: no preferences, no database, no documents folder',
        () {
      for (final path in _allPlanFiles) {
        final code = _code(path);
        for (final name in [
          'SharedPreferences',
          'Hive',
          'getApplicationDocumentsDirectory',
          'getApplicationSupportDirectory',
          'getExternalStorageDirectory',
        ]) {
          expect(code.contains(name), isFalse, reason: '$path uses $name');
        }
      }
    });

    test('the local copy lives in the system\'s temporary folder only', () {
      final files = _code('$_services/plan_attachment_files.dart');
      expect(files.contains('getTemporaryDirectory()'), isTrue);
    });

    test('no storage key, bucket or credential exists in the plan\'s code', () {
      for (final path in _allPlanFiles) {
        final code = _code(path);
        for (final name in [
          'objectKey',
          'object_key',
          'bucket',
          'service_role',
          'SUPABASE_SECRET',
          'sb_secret',
          'R2_ACCESS',
          'R2_SECRET',
          'X-Amz',
        ]) {
          expect(code.contains(name), isFalse, reason: '$path mentions $name');
        }
      }
    });

    test('nothing is logged, so no link can reach a log', () {
      final logging = RegExp(r'\b(print|debugPrint|log|developer\.log)\s*\(');
      for (final path in _allPlanFiles) {
        expect(logging.hasMatch(_code(path)), isFalse, reason: path);
      }
    });

    test('a link is never handed to another app', () {
      final actions =
          _code('lib/src/views/Widgets/plan_attachment_actions.dart');
      expect(actions.contains('url_launcher'), isFalse);
      expect(actions.contains('launchUrl'), isFalse);
      expect(actions.contains('Share.share'), isFalse);
      expect(actions.contains('share_plus'), isFalse);
      // The system opener receives a path this app prepared and verified.
      expect(
          actions.contains('OpenFilex.open(path, type: contentType)'), isTrue);
      // Sharing goes through the app's one share boundary.
      expect(actions.contains('ShareLive.sendNamedFile('), isTrue);
    });

    test('the Worker client sends the account token only to the Worker', () {
      final service = _code('$_services/r2_plan_attachment_service.dart');
      final put = service.substring(
        _at(service, 'Future<void> uploadBytes('),
        _at(service, 'Future<PlanConfirmation> confirm('),
      );
      expect(put.contains('Authorization'), isFalse);
      final download = service.substring(
        _at(service, 'Future<void> download('),
        _at(service, 'Future<void> _discard('),
      );
      expect(download.contains('Authorization'), isFalse);
    });
  });

  group('the plan is sent only after its record was saved', () {
    // [path, the call that saves the record, the last step of the gallery's own
    // bookkeeping after it, the record kind].
    for (final entry in {
      'Offer': (
        _offerViewModel,
        'saveOfferWithMedia(',
        '_cancelledUploadIds.removeAll(cancelled);',
        'PlanParent.offer',
      ),
      'Owner': (
        _ownerViewModel,
        'saveOwnerWithMedia(',
        'media.applySaveResult(',
        'PlanParent.owner',
      ),
    }.entries) {
      final (path, save, bookkeeping, parent) = entry.value;

      test(
          '${entry.key}: the plan form exists only in Supabase queue mode, for '
          'its own kind of record', () {
        final source = _read(path);
        final queue = _at(source, 'if (_usesMediaQueue) {');
        final create = _at(source, '_plan = createPlanAttachmentForm(');
        expect(create, greaterThan(queue));
        expect(source.contains('parent: $parent,'), isTrue);
        expect(
            source.contains(
                'PlanAttachmentFormController? get planAttachment => _plan;'),
            isTrue);
        // Exactly one place creates it.
        expect('createPlanAttachmentForm('.allMatches(source).length, 1);
      });

      test('${entry.key}: Save commits the plan after the record and its media',
          () {
        final source = _read(path);
        final saved = _at(source, save);
        final applied = _at(source, bookkeeping, saved);
        final commit = _at(source, 'plan.commit(recordId:', applied);
        final gate = _at(source, '!planOutcome.isComplete', commit);
        final toast = _at(source, "'planAttachmentSavedUploadFailed'", gate);
        expect(toast, greaterThan(gate));
        // The form stays open when the plan did not complete.
        final stays = source.substring(gate, _at(source, 'return;', gate));
        expect(stays.contains('context.go('), isFalse);
        expect(stays.contains('context.pop('), isFalse);
        // And only a complete save reaches the success path.
        expect(
            source.indexOf("context.go('/home')", commit), greaterThan(gate));
        expect('plan.commit('.allMatches(source).length, 1);
      });

      test(
          '${entry.key}: the plan counts as content, and is disposed with the '
          'form', () {
        final source = _read(path);
        expect(source.contains('(_plan?.hasPlan ?? false)'), isTrue);
        expect(source.contains('_plan?.dispose();'), isTrue);
        expect(source.contains('_plan?.start(editRecordId:'), isTrue);
      });
    }

    test('a commit never throws and a failure never undoes the record', () {
      final form = _code('lib/src/viewmodels/plan_attachment_form.dart');
      final commit = form.substring(
        _at(form, 'Future<PlanCommitOutcome> commit('),
        _at(form, 'Future<PlanCommitOutcome> retry('),
      );
      expect(commit.contains('catch'), isTrue);
      expect(commit.contains('rethrow'), isFalse);
      expect(commit.contains('throw '), isFalse);
      // The record is never touched by the plan's controller.
      expect(form.contains('OfferService'), isFalse);
      expect(form.contains('OwnerService'), isFalse);
    });
  });

  group('the screens', () {
    for (final path in [_offerForm, _ownerForm]) {
      test(
          '${path.split('/').last}: the section follows the media field and '
          'precedes the actions', () {
        final source = _read(path);
        final media = _at(source, 'MediaUploadWidget(');
        final section = _at(source, 'PlanAttachmentSection(', media);
        final actions = _at(source, 'SaveCancelButtons(', section);
        expect(actions, greaterThan(section));
        expect(
            source.contains('if (vm.planAttachment case final plan?)'), isTrue,
            reason: 'only where the form has a plan (Supabase mode)');
        expect(source.contains('selectPlanAttachment(context, plan)'), isTrue);
        expect(source.contains("localization.translate('planAttachmentTitle')"),
            isTrue);
        expect(source.contains('onRemove: plan.removeSelection'), isTrue);
        expect(source.contains('onKeep: plan.keepExisting'), isTrue);
        expect(source.contains('onRetry: () => vm.save(context)'), isTrue);
      });
    }

    for (final entry in {
      _offerDetails: 'PlanParent.offer',
      _ownerDetails: 'PlanParent.owner',
    }.entries) {
      test(
          '${entry.key.split('/').last}: a separate, non-blocking read and its '
          'own card', () {
        final source = _read(entry.key);
        expect(source.contains('PlanAttachmentDetailsLoader('), isTrue);
        expect(source.contains('parent: ${entry.value},'), isTrue);
        expect(source.contains('R2PlanAttachmentService()'), isTrue);
        expect(source.contains('PlanAttachmentDetailsCard('), isTrue);
        // The card is built from what the loader has, never awaited by the screen.
        expect(source.contains('unawaited(_planLoader?.load())'), isTrue);
        expect(source.contains('_planLoader?.dispose();'), isTrue);
        // It is its own card, not an item of the media gallery.
        final build = _at(source, '_buildPlanCard()');
        final gallery = source.indexOf('MediaGalleryWidget(');
        expect(build, isNot(gallery));
        expect(source.contains('plan_attachment_details_card.dart'), isTrue);
      });
    }
  });

  group('the Word file: no in-app renderer, and it says so', () {
    test(
        'the app has one PDF viewer and one image viewer, and the plan uses them',
        () {
      final actions =
          _code('lib/src/views/Widgets/plan_attachment_actions.dart');
      expect(actions.contains('PdfViewerScreen('), isTrue);
      expect(actions.contains('FullScreenMediaViewer('), isTrue);
      expect(actions.contains('case PlanAttachmentKind.word:'), isTrue);
      final word =
          actions.substring(_at(actions, 'case PlanAttachmentKind.word:'));
      expect(
          word.contains('_openExternal(file.path, plan.contentType)'), isTrue);
    });

    test('the card says a Word file opens in another app', () {
      final card =
          _code('lib/src/views/Widgets/plan_attachment_details_card.dart');
      expect(card.contains("'planAttachmentOpensExternally'"), isTrue);
      expect(card.contains('if (isWord)'), isTrue);
    });
  });

  group('the strings', () {
    final en = json.decode(_read('lib/src/common/localization/app_en.arb'))
        as Map<String, dynamic>;
    final ar = json.decode(_read('lib/src/common/localization/app_ar.arb'))
        as Map<String, dynamic>;
    final planKeys =
        en.keys.where((k) => k.startsWith('planAttachment')).toSet();

    test('English and Arabic carry exactly the same plan strings', () {
      expect(planKeys, isNotEmpty);
      expect(ar.keys.where((k) => k.startsWith('planAttachment')).toSet(),
          planKeys);
      // The names of the formats are written the same way in Arabic.
      const sameInBoth = {'planAttachmentTypePdf', 'planAttachmentTypeWord'};
      for (final key in planKeys) {
        expect((en[key] as String).trim(), isNotEmpty, reason: 'en $key');
        expect((ar[key] as String).trim(), isNotEmpty, reason: 'ar $key');
        if (sameInBoth.contains(key)) continue;
        expect(en[key], isNot(ar[key]),
            reason: '$key must be translated, not copied');
      }
    });

    test('every plan string the code names exists, and none is dead', () {
      final named = <String>{};
      final literal = RegExp(r"'(planAttachment[A-Za-z]+)'");
      for (final path in [
        ..._allPlanFiles,
        _offerViewModel,
        _ownerViewModel,
        _offerForm,
        _ownerForm,
      ]) {
        named.addAll(literal.allMatches(_code(path)).map((m) => m.group(1)!));
      }
      for (final key in named) {
        expect(planKeys.contains(key), isTrue, reason: 'code names $key');
      }
      for (final key in planKeys) {
        expect(named.contains(key), isTrue, reason: '$key is never used');
      }
    });
  });

  group('one contract with the Worker and the database', () {
    test('the app\'s routes and id fields are the Worker\'s', () {
      final worker = _read(_worker);
      final models = _read('$_services/plan_attachment_models.dart');
      for (final (prefix, field) in [
        ('/offer-plan', 'offerId'),
        ('/owner-plan', 'ownerRecordId'),
      ]) {
        expect(models.contains("routePrefix: '$prefix'"), isTrue);
        expect(models.contains("idField: '$field'"), isTrue);
        for (final route in [
          "path === '$prefix/authorize'",
          "path === '$prefix/confirm'",
          "path === '$prefix/remove'",
          "path === '$prefix')",
        ]) {
          expect(worker.contains(route), isTrue, reason: route);
        }
        expect(worker.contains("idField: '$field',"), isTrue);
      }
    });

    test('the parent isolation the app relies on is in the Worker and the SQL',
        () {
      final worker = _read(_worker);
      final sql = _read(_migration);
      expect(worker.contains("keyPattern: 'profiles/*/offer-plans/*'"), isTrue);
      expect(worker.contains("keyPattern: 'profiles/*/owner-plans/*'"), isTrue);
      expect(sql.contains('plan_media_id'), isTrue);
      for (final fn in [
        'confirm_offer_plan_upload',
        'remove_offer_plan',
        'confirm_owner_plan_upload',
        'remove_owner_plan',
      ]) {
        expect(worker.contains('/rest/v1/rpc/$fn'), isTrue, reason: fn);
        expect(sql.contains('function public.$fn('), isTrue, reason: fn);
      }
    });

    test('no client role can run a plan function or bind a plan itself', () {
      final sql = _read(_migration).toLowerCase();
      expect(
          sql.contains(
              'grant execute on function public.confirm_offer_plan_upload'),
          isTrue);
      expect(
          RegExp(r'grant [^;]* to (anon|authenticated|public)\b').hasMatch(sql),
          isFalse);
      expect(RegExp(r'grant (insert|update)[^;]*plan_media_id').hasMatch(sql),
          isFalse);
    });
  });
}
