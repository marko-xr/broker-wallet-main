// Firebase is initialized for FCM only (Notifications N3). The legacy
// Firestore quota code must behave exactly as it did when Firebase was not
// initialized: no Firestore read or write, the same fail-open answers.
import 'dart:io';

import 'package:broker_wallet/src/services/app_access_policy.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_usage_gate.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_usage_gate.dart';
import 'package:broker_wallet/src/services/legacy_quota_store.dart';
import 'package:broker_wallet/src/services/quota_helper.dart';
import 'package:broker_wallet/src/services/scanner/scanner_usage_gate.dart';
import 'package:broker_wallet/src/services/signature/signature_usage_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(AppAccessPolicy.debugReset);
  tearDown(AppAccessPolicy.debugReset);

  test('no code in lib/ opens the Firestore instance directly', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // The store itself names the old call in its explanation.
      if (entity.path
          .replaceAll(r'\', '/')
          .endsWith('legacy_quota_store.dart')) {
        continue;
      }
      if (entity.readAsStringSync().contains('FirebaseFirestore.instance')) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty);
  });

  test('the five legacy quota accesses all go through the store', () {
    for (final path in [
      'lib/src/services/quota_helper.dart',
      'lib/src/services/scanner/scanner_usage_gate.dart',
      'lib/src/services/combine_pdf/combine_usage_gate.dart',
      'lib/src/services/image_to_pdf/image_pdf_usage_gate.dart',
      'lib/src/services/signature/signature_usage_gate.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect('legacyQuotaFirestore()'.allMatches(source).length, 1,
          reason: path);
    }
  });

  test('the store refuses, as the app did before Firebase was initialized', () {
    expect(legacyQuotaFirestore, throwsA(isA<LegacyQuotaStoreDisconnected>()));
  });

  test('online, the usage counters still complete without writing', () async {
    expect(AppAccessPolicy.isOnline, isTrue);
    await const LegacyFirestoreScannerUsageGate().recordScan('u1');
    await const LegacyFirestoreCombineUsageGate().recordCombine('u1');
    await const LegacyFirestoreImagePdfUsageGate().recordConversion('u1');
    await const LegacyFirestoreSignatureUsageGate().recordSignedDocument('u1');
  });

  testWidgets('online, the quota check answers as before: allowed, no dialog',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(Builder(builder: (c) {
      context = c;
      return const SizedBox();
    }));
    expect(AppAccessPolicy.isOnline, isTrue);
    final allowed = await QuotaHelper.checkAndWarnQuota(
        context: context, uid: 'u1', section: 'scanner', toolName: 'scanner');
    expect(allowed, isTrue);
    await tester.pump();
    expect(find.byType(Dialog), findsNothing);
  });
}
