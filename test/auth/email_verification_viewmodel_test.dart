import 'package:flutter_test/flutter_test.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/email_verification_viewmodel.dart';

class MockAuthRepository implements AuthRepository {
  bool emailVerified = false;
  int reloadCount = 0;
  int sendVerificationCount = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<bool> isEmailVerified() async => emailVerified;

  @override
  Future<UserModel?> reloadUser() async {
    reloadCount++;
    return UserModel(
      uid: 'user-123',
      name: 'Test',
      email: 'test@example.com',
      createdAt: DateTime.now(),
      isEmailVerified: emailVerified,
      subscription: UserSubscription(
        plan: 'free',
        isActive: true,
        features: [],
      ),
    );
  }

  @override
  Future<void> sendEmailVerification({String? email}) async {
    sendVerificationCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EmailVerificationViewModel Unit Tests', () {
    late MockAuthRepository mockRepo;
    late EmailVerificationViewModel viewModel;

    setUp(() {
      mockRepo = MockAuthRepository();
      viewModel = EmailVerificationViewModel(authRepository: mockRepo);
    });

    test('initial state has no error and not loading', () {
      expect(viewModel.isLoading, isFalse);
      expect(viewModel.isCheckingVerification, isFalse);
      expect(viewModel.isResendingEmail, isFalse);
      expect(viewModel.errorMessage, isNull);
      expect(viewModel.canResend, isTrue);
    });

    test('initialize sets email and starts check', () {
      viewModel.initialize('agent@broker.com');
      expect(viewModel.email, equals('agent@broker.com'));
    });

    test('clearError clears error message', () {
      viewModel.clearError();
      expect(viewModel.errorMessage, isNull);
    });
  });
}
