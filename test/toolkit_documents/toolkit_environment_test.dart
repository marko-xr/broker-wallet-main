// Which Worker Toolkit documents talk to, and when they may use a staging gate
// key (checkpoint C3). The rules are pure functions of compile-time values, so
// they are tested with explicit inputs: a build that sets those values cannot be
// produced inside a test run.

import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/config/r2_config.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_document_models.dart';

void main() {
  const shared = 'https://media-api.brokerwallet.ae';
  const staging = 'https://r2-profile-upload-staging.example.workers.dev';

  group('the Toolkit Worker address', () {
    test('is the shared Worker unless a debug build names another', () {
      expect(
        R2Config.resolveToolkitWorkerUrl(
            shared: shared, override: '', debugBuild: true),
        shared,
      );
      expect(
        R2Config.resolveToolkitWorkerUrl(
            shared: shared, override: staging, debugBuild: true),
        staging,
      );
      expect(
        R2Config.resolveToolkitWorkerUrl(
            shared: shared, override: '$staging/', debugBuild: true),
        staging,
        reason: 'a trailing slash is dropped',
      );
    });

    test('a profile or release build ignores the override completely', () {
      expect(
        R2Config.resolveToolkitWorkerUrl(
            shared: shared, override: staging, debugBuild: false),
        shared,
      );
    });

    test('an unusable address turns Toolkit off, never to the shared Worker',
        () {
      for (final bad in [
        'not a url',
        'ftp://files.example.test',
        'https://',
        'https://user:secret@host.example.test',
        'https://host.example.test?x=1',
        'https://host.example.test#frag',
      ]) {
        expect(
          R2Config.resolveToolkitWorkerUrl(
              shared: shared, override: bad, debugBuild: true),
          isNull,
          reason: bad,
        );
      }
    });
  });

  group('the staging gate key', () {
    test('is sent only by a debug build that has its own Toolkit address', () {
      expect(
        R2Config.resolveToolkitStagingKey(
            shared: shared, toolkit: staging, key: 'k', debugBuild: true),
        'k',
      );
      expect(
        R2Config.resolveToolkitStagingKey(
            shared: shared, toolkit: staging, key: 'k', debugBuild: false),
        '',
        reason: 'profile and release builds never send it',
      );
    });

    test('is never sent to the shared Worker, however it is spelled', () {
      expect(
        R2Config.resolveToolkitStagingKey(
            shared: shared, toolkit: shared, key: 'k', debugBuild: true),
        '',
      );
      expect(
        R2Config.resolveToolkitStagingKey(
            shared: shared,
            toolkit: 'https://MEDIA-API.brokerwallet.ae/x',
            key: 'k',
            debugBuild: true),
        '',
        reason: 'the same host in another spelling',
      );
    });

    test('is not sent without a key, or when Toolkit is off', () {
      expect(
        R2Config.resolveToolkitStagingKey(
            shared: shared, toolkit: staging, key: '  ', debugBuild: true),
        '',
      );
      expect(
        R2Config.resolveToolkitStagingKey(
            shared: shared, toolkit: null, key: 'k', debugBuild: true),
        '',
      );
    });
  });

  test('a normal test run has no Toolkit override and the cloud is on', () {
    // Run with `flutter test` and no --dart-define, as the owner does: the
    // shared (production) address, no gate key, and the account copy on.
    expect(R2Config.toolkitWorkerUrl, R2Config.workerUrl);
    expect(R2Config.toolkitStagingKey, '');
    expect(ToolkitCloudDocumentsFeature.isActive, isTrue);
  });
}
