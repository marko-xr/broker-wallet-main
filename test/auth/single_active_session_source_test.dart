import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:broker_wallet/src/services/app_session_coordinator.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart'
    show AuthViewModel;

String _jwt(Map<String, Object?> claims) =>
    '${base64Url.encode(utf8.encode('{}'))}.'
    '${base64Url.encode(utf8.encode(jsonEncode(claims)))}.signature';

void main() {
  test('auth view model session integration compiles', () {
    final Type viewModelType = AuthViewModel;
    expect(viewModelType.toString(), 'AuthViewModel');
  });

  test('only a valid session UUID is used for local Realtime correlation', () {
    const id = '11111111-1111-4111-8111-111111111111';
    expect(AppSessionCoordinator.sessionIdFromAccessToken(_jwt({'session_id': id})), id);
    expect(AppSessionCoordinator.sessionIdFromAccessToken(_jwt({'session_id': 'bad'})), isNull);
    expect(AppSessionCoordinator.sessionIdFromAccessToken(_jwt({'sub': id})), isNull);
    expect(AppSessionCoordinator.sessionIdFromAccessToken('not-a-jwt'), isNull);
  });

  test('migration gates every client-readable application table', () {
    final sql = File('supabase/migrations/20261005175500_single_active_app_session.sql')
        .readAsStringSync();
    for (final table in <String>[
      'profiles', 'requests', 'request_areas', 'offers', 'offer_areas',
      'owners', 'offices', 'brokers', 'watchmen', 'quotations',
      'quotation_downpayments', 'quotation_government_fees',
      'quotation_administrative_fees', 'media_objects', 'offer_media',
      'owner_media', 'quotation_media', 'profile_media', 'favorite_offers',
      'favorite_requests', 'favorite_owners', 'favorite_offices',
      'favorite_brokers', 'favorite_watchmen', 'feedback', 'notifications',
      'revenuecat_entitlements', 'plan_limits', 'usage_counters', 'app_versions',
    ]) {
      expect(sql, contains("'$table'"), reason: 'missing restrictive gate for $table');
    }
    expect(sql, contains('as restrictive for all to authenticated'));
    expect(sql, contains('active_session_id = (auth.jwt()->>\'session_id\')::uuid'));
    expect(sql, contains('session_superseded'));
  });

  test('Flutter uses explicit local logout and validates before publishing Home', () {
    final repository = File('lib/src/repositories/supabase_auth_repository.dart')
        .readAsStringSync();
    expect(repository, contains('signOut(scope: SignOutScope.local)'));
    expect(repository, contains('_authorizeAndPublish(restored, claim: false)'));
    expect(repository, contains('_authorizeAndPublish(session, claim: true)'));
    expect(repository, contains('if (allowed && _appSession.isAuthorized(session))'));
    expect(repository, contains('_sessionCheckUnavailableController.add(true)'));
    final coordinator = File('lib/src/services/app_session_coordinator.dart')
        .readAsStringSync();
    expect(coordinator, contains(".stream(primaryKey: const ['user_id'])"));
    expect(coordinator, contains('AppLifecycleState.resumed'));
    expect(coordinator, contains("claim ? 'claim_current_app_session' : 'is_current_app_session'"));
    final wrapper = File('lib/src/views/Screens/Sign-Up-Log-In/auth_wrapper.dart')
        .readAsStringSync();
    expect(wrapper, contains('auth.retryAppSessionValidation'));
  });
}
