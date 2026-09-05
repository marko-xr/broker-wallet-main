import 'package:flutter_test/flutter_test.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/auth_repository.dart';

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

  group('AuthRepository Contract Unit Tests', () {
    late MockAuthRepository mockRepo;

    setUp(() {
      mockRepo = MockAuthRepository();
    });

    test('isEmailVerified returns expected state', () async {
      mockRepo.emailVerified = false;
      expect(await mockRepo.isEmailVerified(), isFalse);

      mockRepo.emailVerified = true;
      expect(await mockRepo.isEmailVerified(), isTrue);
    });

    test('reloadUser increments count and returns updated model', () async {
      mockRepo.emailVerified = true;
      final reloaded = await mockRepo.reloadUser();
      expect(mockRepo.reloadCount, equals(1));
      expect(reloaded?.isEmailVerified, isTrue);
    });

    test('sendEmailVerification records call', () async {
      await mockRepo.sendEmailVerification(email: 'test@example.com');
      expect(mockRepo.sendVerificationCount, equals(1));
    });
  });
}
