import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/app.dart' show resolveAuthRedirect;
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/services/account_deletion_service.dart';
import 'package:broker_wallet/src/services/deleted_account_local_data_cleaner.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/delete_account_viewmodel.dart';
import 'package:broker_wallet/src/views/Widgets/delete_account_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _alice = '11111111-1111-4111-8111-111111111111';
const _password = 'Correct-Horse-9';

class _Session implements AccountDeletionSession {
  @override
  String? currentUserId = _alice;

  @override
  bool isPasswordRecoveryActive = false;

  final List<String> completed = [];

  @override
  Future<void> completeAccountDeletion(String deletedUid) async {
    completed.add(deletedUid);
  }

  @override
  Future<AccountDeletionConvergence> reconcileAccountDeletion(
    String uid,
  ) async =>
      AccountDeletionConvergence.none;
}

class _Gateway implements AccountDeletionGateway {
  AccountDeletionFailure? failWith;
  Completer<void>? hold;
  int calls = 0;

  @override
  Future<void> deleteAccount({
    required String expectedUid,
    required String password,
  }) async {
    calls++;
    if (hold != null) await hold!.future;
    if (failWith != null) throw failWith!;
  }
}

class _AuthRepository implements AuthRepository {
  final StreamController<UserModel?> _controller =
      StreamController<UserModel?>.broadcast();
  UserModel? _currentUser;

  @override
  Stream<UserModel?> get authStateChanges => _controller.stream;

  @override
  UserModel? get currentUser => _currentUser;

  @override
  String? get currentUserId => _currentUser?.uid;

  void emit(UserModel? user) {
    _currentUser = user;
    _controller.add(user);
  }

  @override
  Future<void> signOut() async => emit(null);

  Future<void> dispose() => _controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UserRepository implements UserRepository {
  @override
  Future<UserModel?> getUserById(String uid) async => null;

  @override
  Stream<UserModel?> getUserStream(String uid) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(
  Widget child, {
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
}) {
  return MaterialApp(
    locale: locale,
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: themeMode,
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, inner) => Directionality(
      textDirection:
          locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: inner ?? const SizedBox.shrink(),
    ),
    home: Scaffold(body: child),
  );
}

late final Map<String, dynamic> en;
late final Map<String, dynamic> ar;

String _en(String key) => en[key] as String;

Future<void> _openConfirm(
    WidgetTester tester, DeleteAccountViewModel vm) async {
  await tester.pumpWidget(
    _app(SingleChildScrollView(
      child: DeleteAccountSheet(viewModel: vm, email: 'alice@example.test'),
    )),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(_en('deleteAccountContinue')));
  await tester.pumpAndSettle();
}

FilledButton _deleteButton(WidgetTester tester) => tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(_en('deleteAccountConfirmButton')),
        matching: find.byType(FilledButton),
      ),
    );

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final toasts = <String>[];

  setUpAll(() async {
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        final file = File(key);
        if (!file.existsSync()) return null;
        final bytes = Uint8List.fromList(file.readAsBytesSync());
        return ByteData.view(bytes.buffer);
      },
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('PonnamKarthik/fluttertoast'),
      (call) async {
        if (call.method == 'showToast') {
          toasts.add((call.arguments as Map)['msg'] as String);
        }
        return true;
      },
    );
    await AppLocalizations.preloadAllLanguages();
    en = json.decode(
      File('lib/src/common/localization/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    ar = json.decode(
      File('lib/src/common/localization/app_ar.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  setUp(() {
    toasts.clear();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the first step explains what is deleted and deletes nothing',
      (tester) async {
    final gateway = _Gateway();
    final vm = DeleteAccountViewModel(gateway: gateway, session: _Session());
    addTearDown(vm.dispose);

    await tester.pumpWidget(_app(SingleChildScrollView(
      child: DeleteAccountSheet(viewModel: vm, email: 'alice@example.test'),
    )));
    await tester.pumpAndSettle();

    for (final key in [
      'deleteAccountTitle',
      'deleteAccountIntro',
      'deleteAccountItemProfile',
      'deleteAccountItemListings',
      'deleteAccountItemActivity',
      'deleteAccountIrreversible',
      'deleteAccountSubscriptionNote',
    ]) {
      expect(find.text(_en(key)), findsOneWidget, reason: key);
    }
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text(_en('deleteAccountContinue')));
    await tester.pumpAndSettle();

    expect(find.text(_en('deleteAccountConfirmTitle')), findsOneWidget);
    expect(gateway.calls, 0);
  });

  testWidgets(
      'the final button stays disabled until a password is entered and the '
      'deletion is acknowledged', (tester) async {
    final gateway = _Gateway();
    final vm = DeleteAccountViewModel(gateway: gateway, session: _Session());
    addTearDown(vm.dispose);
    await _openConfirm(tester, vm);

    expect(_deleteButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), _password);
    await tester.pumpAndSettle();
    expect(_deleteButton(tester).onPressed, isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(_deleteButton(tester).onPressed, isNotNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(_deleteButton(tester).onPressed, isNull);
    expect(gateway.calls, 0);
  });

  testWidgets('a wrong password shows a localized message and clears the field',
      (tester) async {
    final gateway = _Gateway()
      ..failWith = const AccountDeletionFailure(
        AccountDeletionFailureCode.reauthenticationFailed,
      );
    final session = _Session();
    final vm = DeleteAccountViewModel(gateway: gateway, session: session);
    addTearDown(vm.dispose);
    await _openConfirm(tester, vm);

    await tester.enterText(find.byType(TextField), 'wrong-password');
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en('deleteAccountConfirmButton')));
    await tester.pumpAndSettle();

    expect(gateway.calls, 1);
    expect(find.text(_en('deleteAccountErrorPassword')), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(session.completed, isEmpty);
  });

  testWidgets('while deleting, nothing can be changed, repeated or dismissed',
      (tester) async {
    final gateway = _Gateway()..hold = Completer<void>();
    final vm = DeleteAccountViewModel(gateway: gateway, session: _Session());
    addTearDown(vm.dispose);
    await _openConfirm(tester, vm);

    await tester.enterText(find.byType(TextField), _password);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en('deleteAccountConfirmButton')));
    await tester.pump();

    expect(vm.isDeleting, isTrue);
    expect(find.text(_en('deleteAccountDeleting')), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
    expect(
      tester
          .widget<TextButton>(find.ancestor(
            of: find.text(_en('deleteAccountBack')),
            matching: find.byType(TextButton),
          ))
          .onPressed,
      isNull,
    );
    final popScope = tester.widget<PopScope>(find.byType(PopScope));
    expect(popScope.canPop, isFalse);

    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    expect(gateway.calls, 1);

    gateway.hold!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'a server failure shows a fixed localized message, never raw text',
      (tester) async {
    final gateway = _Gateway()
      ..failWith = const AccountDeletionFailure(
        AccountDeletionFailureCode.mediaCleanupFailed,
      );
    final vm = DeleteAccountViewModel(gateway: gateway, session: _Session());
    addTearDown(vm.dispose);
    await _openConfirm(tester, vm);

    await tester.enterText(find.byType(TextField), _password);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en('deleteAccountConfirmButton')));
    await tester.pumpAndSettle();

    expect(find.text(_en('deleteAccountErrorNotDeleted')), findsOneWidget);
    expect(find.textContaining('media_cleanup'), findsNothing);
    expect(find.textContaining('R2'), findsNothing);
    expect(_deleteButton(tester).onPressed, isNotNull, reason: 'retry allowed');
  });

  for (final variant in [
    (locale: const Locale('ar'), theme: ThemeMode.light),
    (locale: const Locale('ar'), theme: ThemeMode.dark),
    (locale: const Locale('en'), theme: ThemeMode.dark),
  ]) {
    testWidgets(
        'renders both steps in ${variant.locale.languageCode} / '
        '${variant.theme.name} without overflow', (tester) async {
      final vm =
          DeleteAccountViewModel(gateway: _Gateway(), session: _Session());
      addTearDown(vm.dispose);
      final strings = variant.locale.languageCode == 'ar' ? ar : en;

      await tester.pumpWidget(_app(
        SingleChildScrollView(
          child: DeleteAccountSheet(viewModel: vm, email: 'alice@example.test'),
        ),
        locale: variant.locale,
        themeMode: variant.theme,
      ));
      await tester.pumpAndSettle();
      expect(
          find.text(strings['deleteAccountTitle'] as String), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text(strings['deleteAccountContinue'] as String));
      await tester.pumpAndSettle();
      expect(
        find.text(strings['deleteAccountConfirmButton'] as String),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      if (variant.locale.languageCode == 'ar') {
        expect(find.text(en['deleteAccountConfirmButton'] as String),
            findsNothing);
      }
    });
  }

  testWidgets(
      'a completed deletion ends on the logged-out entry and never shows Home',
      (tester) async {
    final repo = _AuthRepository();
    final authVM = AuthViewModel(
      authRepository: repo,
      userRepository: _UserRepository(),
      deletedAccountCleaner: DeletedAccountLocalDataCleaner(
        forgetProfileMedia: ({mediaIds}) async {},
      ),
    );
    final gateway = _Gateway();
    var homeBuilds = 0;

    repo.emit(UserModel(
      uid: _alice,
      name: 'Alice',
      email: 'alice@example.test',
      createdAt: DateTime.utc(2026),
      isEmailVerified: true,
      isPhoneVerified: false,
      subscription: UserSubscription(
        plan: 'test',
        isActive: false,
        features: const [],
      ),
      preferences: const {},
    ));
    await tester.pump();
    expect(authVM.isAuthenticated, isTrue);

    final router = GoRouter(
      initialLocation: '/profile',
      refreshListenable: authVM,
      redirect: (context, state) => resolveAuthRedirect(
        authVM.status,
        state.uri.path,
        passwordRecoveryActive: authVM.isPasswordRecoveryActive,
      ),
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('BOOTSTRAP')),
        ),
        GoRoute(
          path: '/home',
          builder: (_, __) {
            homeBuilds++;
            return const Scaffold(body: Text('HOME_SCREEN'));
          },
        ),
        GoRoute(
          path: '/welcome',
          builder: (_, __) => const Scaffold(body: Text('WELCOME_SCREEN')),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, __) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    showDeleteAccountFlow(context, gateway: gateway),
                child: const Text('OPEN_DELETE'),
              ),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(ChangeNotifierProvider<AuthViewModel>.value(
      value: authVM,
      child: MaterialApp.router(
        routerConfig: router,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('OPEN_DELETE'), findsOneWidget);
    final homeBuildsBefore = homeBuilds;

    await tester.tap(find.text('OPEN_DELETE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en('deleteAccountContinue')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), _password);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en('deleteAccountConfirmButton')));
    await tester.pumpAndSettle();

    expect(gateway.calls, 1);
    expect(authVM.isAuthenticated, isFalse);
    expect(find.text('WELCOME_SCREEN'), findsOneWidget);
    expect(find.text('HOME_SCREEN'), findsNothing);
    expect(homeBuilds, homeBuildsBefore);
    expect(find.text(_en('deleteAccountConfirmTitle')), findsNothing);
    expect(toasts, [_en('deleteAccountDeletedToast')]);

    router.dispose();
    authVM.dispose();
    await repo.dispose();
  });
}
