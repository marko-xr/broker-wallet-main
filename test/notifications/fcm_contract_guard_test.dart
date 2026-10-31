// FCM stays as the future push transport (Firebase removal phase 7B, option A).
// These guards pin what is true today: the repository contract that a future
// push client will use exists, Supabase owns the device table, no Firestore is
// left in the notification layer, and push registration is NOT claimed to work.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  const contract = 'lib/src/repositories/notification_repository.dart';
  const supabase = 'lib/src/repositories/supabase_notification_repository.dart';
  const model = 'lib/src/data/models/notification_model.dart';

  test('the repository contract keeps the device-token operations', () {
    final source = _read(contract);
    expect(source.contains('upsertFcmToken'), isTrue);
    expect(source.contains('deleteFcmToken'), isTrue);
  });

  test('Supabase owns the device table and logout can delete a token', () {
    final source = _read(supabase);
    expect(source.contains("'push_devices'"), isTrue);
    expect(source.contains('deleteFcmToken'), isTrue);
  });

  test('push registration is not claimed to work until it is configured', () {
    final source = _read(supabase);
    expect(source.contains('UnsupportedError'), isTrue);
    expect(
        source.contains('Push device registration is not configured'), isTrue);
  });

  test('the notification layer holds no Firestore', () {
    for (final path in [contract, supabase, model]) {
      final source = _read(path);
      expect(source.contains('cloud_firestore'), isFalse, reason: path);
      expect(source.contains('FirebaseFirestore'), isFalse, reason: path);
      expect(source.contains('Timestamp.fromDate'), isFalse, reason: path);
    }
    expect(
        File('lib/src/repositories/firestore_notification_repository.dart')
            .existsSync(),
        isFalse);
  });
}
