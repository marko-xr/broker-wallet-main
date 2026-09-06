import 'dart:async';
import 'dart:convert';

import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/email_verification_completion.dart';
import 'package:broker_wallet/src/Views/Screens/Sign-Up-Log-In/email_verification_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const uuid = '550e8400-e29b-41d4-a716-446655440000';

UserModel profile({bool verified = true}) => UserModel(
      uid: uuid,
      name: 'Device test',
      email: 'device@example.test',
      createdAt: DateTime(2026),
      isEmailVerified: verified,
      subscription:
          UserSubscription(plan: 'test', isActive: false, features: []),
    );

class RouteAuth extends Fake implements AuthRepository {
  final events = StreamController<UserModel?>.broadcast();
  UserModel? user;
  String? sessionId;
  Completer<bool>? verification;

  @override
  Stream<UserModel?> get authStateChanges => events.stream;
  @override
  UserModel? get currentUser => user;
  @override
  String? get currentUserId => sessionId;
  @override
  Future<bool> isEmailVerified() async => verification == null
      ? user?.isEmailVerified ?? false
      : verification!.future;

  void emit(UserModel? next, {String? id}) {
    user = next;
    sessionId = id;
    events.add(next);
  }
}

class RouteProfiles extends Fake implements UserRepository {
  @override
  Stream<UserModel?> getUserStream(String uid) => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'real screen exits on repository callback while a check is pending',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var successToasts = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('PonnamKarthik/fluttertoast'),
      (call) async {
        if (call.method == 'showToast') successToasts++;
        return true;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('PonnamKarthik/fluttertoast'), null));
    final repo = RouteAuth();
    final auth =
        AuthViewModel(authRepository: repo, userRepository: RouteProfiles());
    final router = GoRouter(initialLocation: '/email-verification', routes: [
      GoRoute(
          path: '/email-verification',
          builder: (context, state) =>
              const EmailVerificationView(email: 'device@example.test')),
      GoRoute(
          path: '/home',
          builder: (context, state) => const Scaffold(body: Text('Home'))),
    ]);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: auth,
      child: MaterialApp.router(routerConfig: router),
    ));
    repo.emit(null);
    await tester.pump();
    expect(auth.currentUserId, isNull);
    expect(find.text('Verify Your Email'), findsOneWidget);

    repo.verification = Completer<bool>();
    await tester.tap(find.text("I've verified my email"));
    await tester.pump();
    repo.emit(profile(), id: uuid);
    await tester.pumpAndSettle();
    expect(auth.currentUserId, uuid);
    expect(auth.currentUser?.uid, uuid);
    expect(auth.isEmailVerified, isTrue);
    expect(find.text('Home'), findsOneWidget);
    repo.verification!.complete(true);
    repo.emit(profile(), id: uuid);
    await tester.pump(const Duration(seconds: 6));
    expect(successToasts, 1);
    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    auth.dispose();
    await repo.events.close();
  });

  testWidgets('completion requires matching verified session and claims once',
      (tester) async {
    final repo = RouteAuth();
    final auth =
        AuthViewModel(authRepository: repo, userRepository: RouteProfiles());
    final completion = EmailVerificationCompletion();
    repo.emit(profile(verified: false));
    await tester.pump();
    expect(completion.tryClaim(auth), isFalse);
    repo.emit(profile());
    await tester.pump();
    expect(completion.tryClaim(auth), isFalse);
    repo.emit(profile(), id: 'different-id');
    await tester.pump();
    expect(completion.tryClaim(auth), isFalse);
    repo.emit(profile(), id: uuid);
    await tester.pump();
    expect(completion.tryClaim(auth), isTrue);
    expect(
        completion.tryClaim(auth), isFalse); // polling after auth notification
    expect(completion.tryClaim(auth), isFalse); // manual check after polling
    auth.dispose();
    await repo.events.close();
    await tester.pump(const Duration(seconds: 3));
  });

  test('Supabase pending signup and resend use the canonical redirect',
      () async {
    final requests = <http.Request>[];
    final client = sb.SupabaseClient(
      'https://example.test',
      'test-publishable-key',
      authOptions: const sb.AuthClientOptions(
          authFlowType: sb.AuthFlowType.implicit, autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/signup')) {
          return http.Response(
              jsonEncode({
                'id': uuid,
                'aud': 'authenticated',
                'email': 'device@example.test',
                'created_at': '2026-09-06T00:00:00Z',
                'app_metadata': {'provider': 'email'},
                'user_metadata': {'name': 'Device test'},
              }),
              200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('{}', 200,
            headers: {'content-type': 'application/json'});
      }),
    );
    final repo =
        SupabaseAuthRepository(userRepository: RouteProfiles(), client: client);
    final pending = await repo.signUpWithEmailAndPassword(
        email: 'device@example.test',
        password: 'local-test-only',
        name: 'Device test');
    expect(pending.uid, uuid);
    expect(repo.currentUserId, isNull);
    expect(requests.single.url.queryParameters['redirect_to'],
        'brokerwallet://auth/callback');
    requests.clear();
    expect(await repo.isEmailVerified(), isFalse);
    expect(requests, isEmpty); // no anonymous profile query before resend
    await repo.sendEmailVerification(email: ' Device@Example.Test ');
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/auth/v1/resend');
    expect(requests.single.url.queryParameters['redirect_to'],
        'brokerwallet://auth/callback');
    expect(jsonDecode(requests.single.body), containsPair('type', 'signup'));
    expect(jsonDecode(requests.single.body),
        containsPair('email', 'device@example.test'));
    await client.dispose();
  });
}
