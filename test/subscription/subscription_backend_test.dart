import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/utils/core_entity_error_message.dart';
import 'package:broker_wallet/src/config/supabase_config.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';
import 'package:broker_wallet/src/services/r2_offer_media_upload_service.dart';
import 'package:broker_wallet/src/services/subscription/subscription_backend.dart';
import 'package:broker_wallet/src/services/subscription/subscription_server_state.dart';
import 'package:broker_wallet/src/services/supabase_core_entities_service.dart';
import 'package:broker_wallet/src/viewmodels/subscription_state_controller.dart';
import 'package:broker_wallet/src/views/Screens/home/Profile/SubscriptionPlan/subscription_presentation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _sections = [
  'requests',
  'offers',
  'owners',
  'offices',
  'brokers',
  'watchmen',
  'quotations',
  'scanner',
  'signature',
  'image_to_pdf',
  'combine_pdfs',
];

Map<String, Object?> _json({
  String plan = 'free',
  String status = 'free',
  bool readOnly = false,
  bool isTest = false,
  Map<String, int> usage = const {},
  List<Object?> items = const [],
  bool available = false,
  String? scenario,
  String? cycle,
}) =>
    {
      'plan': plan,
      'status': status,
      'read_only': readOnly,
      'is_test': isTest,
      'cycle': cycle,
      'provider': null,
      'auto_renew': false,
      'started_at': null,
      'paid_through': null,
      'next_charge_at': null,
      'server_now': '2026-11-23T10:00:00Z',
      'limits': {'creations': 5, 'edits_per_item': 3},
      'usage': {for (final s in _sections) s: usage[s] ?? 0},
      'items': items,
      'test_mode': {
        'available': available,
        'scenario': scenario,
        'expires_at': null,
      },
    };

SubscriptionServerState _state({
  String plan = 'free',
  String status = 'free',
  bool readOnly = false,
  bool isTest = false,
  Map<String, int> usage = const {},
  bool available = false,
  String? scenario,
  String? cycle,
}) =>
    SubscriptionServerState.fromJson(_json(
      plan: plan,
      status: status,
      readOnly: readOnly,
      isTest: isTest,
      usage: usage,
      available: available,
      scenario: scenario,
      cycle: cycle,
    ));

class _Backend implements SubscriptionBackend {
  final List<Completer<SubscriptionServerState>> reads = [];
  final List<String> actions = [];
  Object? actionError;
  SubscriptionServerState? actionResult;

  @override
  Future<SubscriptionServerState> fetchState() {
    final completer = Completer<SubscriptionServerState>();
    reads.add(completer);
    return completer.future;
  }

  @override
  Future<StoreSyncResult> syncWithStore() async => StoreSyncResult.synced;

  @override
  Future<SubscriptionServerState> testControl(String action) async {
    actions.add(action);
    final error = actionError;
    if (error != null) throw error;
    return actionResult!;
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

Iterable<File> _dartFiles(String root) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

void main() {
  group('the server answer is parsed strictly', () {
    test('a valid Free answer', () {
      final state = _state(usage: {'offers': 3});
      expect(state.status, SubscriptionStatus.free);
      expect(state.isPlus, isFalse);
      expect(state.created[UsageCategory.offers], 3);
      expect(state.created.length, 11);
    });

    test('anything unexpected is not a state', () {
      final bad = <Object?>[
        null,
        'free',
        <String, Object?>{},
        _json(status: 'lifetime_plus'),
        _json(plan: 'gold'),
        // A plan and a status that disagree.
        _json(plan: 'plus', status: 'free'),
        _json(plan: 'free', status: 'plus_renewing'),
        _json(plan: 'plus', status: 'plus_renewing', readOnly: true),
        {..._json(), 'read_only': 'false'},
        {..._json(), 'is_test': null},
        {..._json(), 'usage': null},
        {
          ..._json(),
          'usage': {'offers': 1}
        },
        _json(usage: {'offers': -1}),
        {..._json(), 'items': null},
        _json(items: [
          {'section': 'nope', 'edits_used': 1}
        ]),
        {..._json(), 'test_mode': null},
      ];
      for (final raw in bad) {
        expect(
            () => SubscriptionServerState.fromJson(raw), throwsFormatException,
            reason: '$raw');
      }
    });

    test('the switch is ON only for the server\'s active plus scenario', () {
      expect(_state(available: true, scenario: 'plus').testPlusOn, isTrue);
      expect(_state(available: true).testPlusOn, isFalse);
      expect(_state(available: true, scenario: 'expired').testPlusOn, isFalse);
      expect(_state(available: false, scenario: 'plus').testPlusOn, isFalse);
    });
  });

  group('the create decision', () {
    test('four of five is allowed, five of five is not', () {
      expect(_state(usage: {'brokers': 4}).decideCreate('brokers'),
          QuotaDecision.allowed);
      expect(_state(usage: {'brokers': 5}).decideCreate('brokers'),
          QuotaDecision.limitReached);
    });

    test('sections are independent', () {
      expect(_state(usage: {'brokers': 5}).decideCreate('offers'),
          QuotaDecision.allowed);
    });

    test('the Toolkit\'s app section names resolve', () {
      final state = _state(usage: {'image_to_pdf': 5, 'combine_pdfs': 5});
      expect(state.decideCreate('imageToPdf'), QuotaDecision.limitReached);
      expect(state.decideCreate('combinePdfs'), QuotaDecision.limitReached);
    });

    test('Plus is allowed past the limit', () {
      final state = _state(
        plan: 'plus',
        status: 'plus_renewing',
        usage: {'brokers': 9},
      );
      expect(state.decideCreate('brokers'), QuotaDecision.allowed);
    });

    test('read-only blocks every section', () {
      final state = _state(
        status: 'expired_over_limit',
        readOnly: true,
        usage: {'brokers': 8},
      );
      expect(state.decideCreate('brokers'), QuotaDecision.readOnly);
      expect(state.decideCreate('scanner'), QuotaDecision.readOnly);
    });

    test('an unknown section is never allowed', () {
      expect(_state().decideCreate('mystery'), QuotaDecision.unavailable);
    });
  });

  group('the presentation', () {
    test('a test entitlement shows no price', () {
      final p = _state(
        plan: 'plus',
        status: 'plus_renewing',
        isTest: true,
        cycle: 'annual',
      ).toPresentation();
      expect(p.hasVerifiedPlus, isTrue);
      expect(p.renewalPrice, isNull);
    });

    test('a real plan shows its approved price', () {
      final p = _state(plan: 'plus', status: 'plus_renewing', cycle: 'monthly')
          .toPresentation();
      expect(p.renewalPrice?.fils, 2000);
    });

    test('verified zero usage is empty, not unknown', () {
      final p = _state().toPresentation();
      expect(p.usage.state, UsageDataState.empty);
      expect(p.usage.createdFor(UsageCategory.offers), 0);
    });

    test('expired over limit maps to its own screen state', () {
      final p =
          _state(status: 'expired_over_limit', readOnly: true).toPresentation();
      expect(p.status, SubscriptionStatus.expiredOverLimit);
      expect(p.hasVerifiedPlus, isFalse);
    });
  });

  group('the controller', () {
    late _Backend backend;
    late SubscriptionStateController controller;

    setUp(() {
      backend = _Backend();
      controller = SubscriptionStateController(backend: () => backend);
    });
    tearDown(() => controller.dispose());

    Future<void> signIn(String user, SubscriptionServerState state) async {
      controller.attachUser(user);
      await _settle();
      backend.reads.last.complete(state);
      await _settle();
    }

    test('before any answer it is loading, never Free', () async {
      controller.attachUser('a');
      await _settle();
      expect(controller.presentation.status, SubscriptionStatus.loading);
    });

    test('a failed read is unavailable, never Free', () async {
      controller.attachUser('a');
      await _settle();
      backend.reads.last.completeError(StateError('down'));
      await _settle();
      expect(controller.presentation.status, SubscriptionStatus.unavailable);
    });

    test('a failed refresh does not keep a previous Plus', () async {
      await signIn('a', _state(plan: 'plus', status: 'plus_renewing'));
      expect(controller.presentation.hasVerifiedPlus, isTrue);
      final refresh = controller.refresh();
      backend.reads.last.completeError(StateError('down'));
      await refresh;
      expect(controller.presentation.hasVerifiedPlus, isFalse);
      expect(controller.presentation.status, SubscriptionStatus.unavailable);
    });

    test('an account switch clears the state at once', () async {
      await signIn('a', _state(plan: 'plus', status: 'plus_renewing'));
      controller.attachUser('b');
      expect(controller.serverState, isNull);
      expect(controller.presentation.hasVerifiedPlus, isFalse);
    });

    test('a late answer for the previous account is dropped', () async {
      controller.attachUser('a');
      await _settle();
      final late = backend.reads.last;
      controller.attachUser('b');
      await _settle();
      late.complete(_state(plan: 'plus', status: 'plus_renewing'));
      await _settle();
      expect(controller.serverState, isNull);
      backend.reads.last.complete(_state());
      await _settle();
      expect(controller.presentation.status, SubscriptionStatus.free);
    });

    test('signing out clears the state', () async {
      await signIn('a', _state(plan: 'plus', status: 'plus_renewing'));
      controller.attachUser(null);
      await _settle();
      expect(controller.serverState, isNull);
      expect(controller.presentation.status, SubscriptionStatus.unavailable);
    });

    test('the switch moves only when the server confirms', () async {
      await signIn('a', _state(available: true));
      backend.actionResult = _state(
        plan: 'plus',
        status: 'plus_renewing',
        isTest: true,
        available: true,
        scenario: 'plus',
      );
      await controller.runTestAction('plus_on');
      expect(backend.actions, ['plus_on']);
      expect(controller.serverState!.testPlusOn, isTrue);
    });

    test('a refusal keeps the last verified state and says so', () async {
      await signIn('a', _state(available: true));
      backend.actionError = const SubscriptionTestControlRefused('not_staging');
      await controller.runTestAction('plus_on');
      expect(controller.serverState!.testPlusOn, isFalse);
      expect(controller.presentation.status, SubscriptionStatus.free);
      expect(controller.testError, 'not_staging');
      expect(controller.testBusy, isFalse);
    });

    test('a network failure on the switch also keeps the state', () async {
      await signIn('a', _state(available: true));
      backend.actionError = StateError('down');
      await controller.runTestAction('plus_on');
      expect(controller.serverState!.testPlusOn, isFalse);
      expect(controller.testError, 'unavailable');
    });

    test('a create check asks the server every time', () async {
      await signIn('a', _state(plan: 'plus', status: 'plus_renewing'));
      final check = controller.checkCreate('brokers');
      // The cached Plus is not the answer: the plan ended on the server.
      backend.reads.last.complete(_state(
        status: 'expired_over_limit',
        readOnly: true,
        usage: {'brokers': 8},
      ));
      expect(await check, QuotaDecision.readOnly);
    });

    test('a create check that cannot reach the server fails closed', () async {
      await signIn('a', _state(plan: 'plus', status: 'plus_renewing'));
      final check = controller.checkCreate('brokers');
      backend.reads.last.completeError(StateError('down'));
      expect(await check, QuotaDecision.unavailable);
    });

    test('with no account a create check is unavailable', () async {
      expect(
          await controller.checkCreate('brokers'), QuotaDecision.unavailable);
    });
  });

  group('refusals reach the user exactly', () {
    String message(String code) => CoreEntityErrorMessage.save(
          sb.PostgrestException(message: 'x', code: code),
          'broker',
          isUpdate: false,
        );

    test('each code has its own message', () {
      expect(message('PBQ01'), contains('5 Free creations'));
      expect(message('PBQ02'), contains('3 Free edits'));
      expect(message('PBQ03'), contains('paused'));
      expect(message('PBQ06'), contains('could not be verified'));
    });

    test('other database errors keep their existing message', () {
      expect(message('42501'), contains('permission'));
      expect(message('23514'), contains('could not be validated'));
    });

    test('both languages carry every new message', () {
      final en = jsonDecode(
        File('lib/src/common/localization/app_en.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      final ar = jsonDecode(
        File('lib/src/common/localization/app_ar.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      final keys = en.keys.where(
        (k) => k.startsWith('stagingTest') || k.startsWith('quotaC'),
      );
      expect(keys.length, greaterThanOrEqualTo(12));
      for (final key in [
        ...keys,
        'quotaEditLimitReached',
        'quotaAccountReadOnly',
      ]) {
        expect(ar[key], isA<String>(), reason: key);
        expect((ar[key] as String).trim(), isNotEmpty, reason: key);
      }
    });
  });

  group('nothing in the app can grant Plus', () {
    final lib = _dartFiles('lib').toList();

    test('no client flag, service key or provider secret exists', () {
      final banned = RegExp(
        r'isPlus\s*=\s*true|service_role|SERVICE_ROLE|SUPABASE_SECRET'
        r'|REVENUECAT_WEBHOOK|TAP_SECRET|staging_test_control'
        r'|apply_subscription_provider_event',
      );
      for (final file in lib) {
        expect(banned.hasMatch(file.readAsStringSync()), isFalse,
            reason: file.path);
      }
    });

    test('the test endpoint has one caller, which names no account', () {
      final callers = lib
          .where(
              (f) => f.readAsStringSync().contains('subscription-test-control'))
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(callers, ['subscription_backend.dart']);
      final source = File('lib/src/services/subscription/'
              'subscription_backend.dart')
          .readAsStringSync();
      expect(source, contains("body: {'action': action}"));
      expect(source, isNot(contains('user_id')));
    });

    test('the control is drawn only from My Plan', () {
      final users = lib
          .where((f) =>
              f.readAsStringSync().contains('SubscriptionTestModeSection('))
          .map((f) => f.uri.pathSegments.last)
          .toSet();
      expect(users, {
        'my_plan_view.dart',
        'subscription_test_mode_section.dart',
      });
    });

    test('the control needs a debug build on a Staging backend', () {
      final source = File('lib/src/views/Screens/home/Profile/'
              'subscription_test_mode_section.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      expect(
        source,
        contains('kDebugMode &&\n'
            '      SupabaseConfig.subscriptionBackendEnabled &&\n'
            '      SupabaseConfig.isStagingBackend'),
      );
      expect(source, contains('state.testModeAvailable'));
    });

    test('no route leads to the control', () {
      for (final path in [
        'lib/app.dart',
        'lib/src/views/Screens/home/Profile/SubscriptionPlan/'
            'subscription_routes.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains('SubscriptionTestMode')), reason: path);
        expect(source, isNot(contains('test-mode')), reason: path);
      }
    });

    test('the plan state is never persisted', () {
      for (final path in [
        'lib/src/viewmodels/subscription_state_controller.dart',
        'lib/src/services/subscription/subscription_server_state.dart',
        'lib/src/services/subscription/subscription_backend.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains('SharedPreferences')), reason: path);
        expect(source, isNot(contains('Hive.')), reason: path);
      }
    });

    test('the production project can never count as Staging', () {
      expect(SupabaseConfig.productionProjectRef, 'rbvcnvqpdqrhywcgxkne');
      if (SupabaseConfig.url.contains(SupabaseConfig.productionProjectRef)) {
        expect(SupabaseConfig.isStagingBackend, isFalse);
      }
    });
  });

  group(
    'saves through the server functions',
    skip: SupabaseConfig.subscriptionBackendEnabled
        ? false
        : 'needs --dart-define=SUBSCRIPTION_BACKEND=true',
    () {
      const uid = '11111111-1111-4111-8111-111111111111';
      late List<http.Request> requests;
      late http.Response Function(http.Request) answer;
      late SupabaseCoreEntitiesService service;

      String b64(Map<String, Object?> value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

      String session() {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        return jsonEncode({
          'access_token': '${b64({'alg': 'HS256', 'typ': 'JWT'})}.'
              '${b64({'sub': uid, 'exp': now + 3600})}.sig',
          'token_type': 'bearer',
          'expires_in': 3600,
          'expires_at': now + 3600,
          'refresh_token': 'refresh-1',
          'user': {
            'id': uid,
            'aud': 'authenticated',
            'role': 'authenticated',
            'email': 'session@example.test',
            'app_metadata': {'provider': 'email'},
            'user_metadata': <String, Object?>{},
            'created_at': '2026-01-01T00:00:00Z',
          },
        });
      }

      http.Response ok(String body) => http.Response(body, 200,
          headers: {'content-type': 'application/json'});

      setUp(() async {
        requests = [];
        answer = (_) => ok('{"outcome":"created"}');
        final client = sb.SupabaseClient(
          'https://unit-test.supabase.co',
          'unit-test-publishable-key',
          httpClient: MockClient((request) async {
            requests.add(request);
            final response = answer(request);
            // The Postgrest client reads the method from the answer's request.
            return http.Response(
              response.body,
              response.statusCode,
              headers: response.headers,
              request: request,
            );
          }),
          authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
        );
        await client.auth.setInitialSession(session());
        service = SupabaseCoreEntitiesService(
          client: client,
          offerMedia: R2OfferMediaUploadService(supabaseClient: client),
          ownerMedia: R2OfferMediaUploadService(supabaseClient: client),
        );
      });

      BrokerModel broker() => BrokerModel(
            name: 'Sara',
            countryCode: '+971',
            phoneNumber: '501234567',
            notes: 'n',
          );

      test('a create is one call that names no owner', () async {
        final id = await service.saveBroker(broker());
        expect(requests.length, 1);
        expect(requests.single.url.path, '/rest/v1/rpc/create_core_entity');
        final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
        expect(body['p_section'], 'brokers');
        expect(body['p_id'], id);
        final payload = body['p_payload'] as Map<String, dynamic>;
        expect(payload.containsKey('owner_id'), isFalse);
        expect(payload.containsKey('id'), isFalse);
        expect(payload['name'], 'Sara');
      });

      test('the form\'s id is reused on a retry', () async {
        const id = '22222222-2222-4222-8222-222222222222';
        await service.saveBroker(broker(), recordId: id);
        await service.saveBroker(broker(), recordId: id);
        final ids = requests
            .map((r) => (jsonDecode(r.body) as Map<String, dynamic>)['p_id']);
        expect(ids, [id, id]);
      });

      test('an update is one call with its own request id', () async {
        const id = '22222222-2222-4222-8222-222222222222';
        await service.updateBroker(id, broker());
        await service.updateBroker(id, broker());
        expect(requests.map((r) => r.url.path).toSet(),
            {'/rest/v1/rpc/update_core_entity'});
        final first = jsonDecode(requests[0].body) as Map<String, dynamic>;
        final second = jsonDecode(requests[1].body) as Map<String, dynamic>;
        expect(first['p_request_id'], isNot(second['p_request_id']));
      });

      test('a Request and its areas are a single call', () async {
        final now = DateTime(2026, 11, 23);
        await service.saveRequest(RequestModel(
          userId: uid,
          requestType: 'rent',
          selectedCity: 'Dubai',
          selectedAreas: const ['Marina', 'JBR'],
          location: 'x',
          phoneNumber: '501234567',
          countryCode: '+971',
          minPrice: '',
          maxPrice: '',
          notes: '',
          specificPropertyType: '',
          rooms: 0,
          bathrooms: 0,
          createdAt: now,
          updatedAt: now,
        ));
        expect(requests.length, 1);
        final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
        expect(body['p_areas'], ['Marina', 'JBR']);
      });

      test('a changed retry of a create that landed becomes its edit',
          () async {
        const id = '22222222-2222-4222-8222-222222222222';
        answer = (request) => request.url.path.endsWith('create_core_entity')
            ? http.Response(
                '{"code":"PBQ05","message":"item_id_conflict"}',
                409,
                headers: {'content-type': 'application/json'},
              )
            : ok('{"outcome":"updated"}');
        await service.saveBroker(broker(), recordId: id);
        expect(requests.map((r) => r.url.path), [
          '/rest/v1/rpc/create_core_entity',
          '/rest/v1/rpc/update_core_entity',
        ]);
        final update = jsonDecode(requests.last.body) as Map<String, dynamic>;
        expect(update['p_id'], id);
      });

      test('a refusal reaches the caller and nothing else is sent', () async {
        answer = (_) => http.Response(
              '{"code":"PBQ01","message":"creation_limit_reached"}',
              400,
              headers: {'content-type': 'application/json'},
            );
        await expectLater(
          service.saveBroker(broker()),
          throwsA(isA<sb.PostgrestException>()
              .having((e) => e.code, 'code', 'PBQ01')),
        );
        expect(requests.length, 1);
      });
    },
  );
}
