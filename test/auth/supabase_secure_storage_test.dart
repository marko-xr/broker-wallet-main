import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:broker_wallet/src/services/supabase_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SupabaseSecureStorage Unit Tests', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('initializes and reads null for absent key', () async {
      final storage = SupabaseSecureStorage();
      await storage.initialize();

      final item = await storage.accessToken();
      expect(item, isNull);
    });

    test('stores and retrieves session data accurately', () async {
      final storage = SupabaseSecureStorage();
      await storage.initialize();

      await storage.persistSession('{access_token:fake-jwt}');
      final result = await storage.accessToken();

      expect(result, equals('{access_token:fake-jwt}'));
    });

    test('hasAccessToken returns true when token exists and false when absent', () async {
      final storage = SupabaseSecureStorage();
      await storage.initialize();

      expect(await storage.hasAccessToken(), isFalse);
      await storage.persistSession('token-123');
      expect(await storage.hasAccessToken(), isTrue);
    });

    test('removePersistedSession removes existing key', () async {
      final storage = SupabaseSecureStorage();
      await storage.initialize();

      await storage.persistSession('token-123');
      expect(await storage.hasAccessToken(), isTrue);

      await storage.removePersistedSession();
      expect(await storage.hasAccessToken(), isFalse);
      expect(await storage.accessToken(), isNull);
    });
  });
}
