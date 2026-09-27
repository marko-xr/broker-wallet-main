import 'dart:io';

import 'package:broker_wallet/src/services/offer_media_session.dart';
import 'package:broker_wallet/src/services/offer_media_upload_queue.dart';
import 'package:broker_wallet/src/services/offer_media_url_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// Signed Offer-media links held in memory, and the session hook that keeps
/// them — and the upload queue — tied to the account that is signed in.

const _a = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _b = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

void main() {
  group('OfferMediaUrlCache', () {
    late DateTime now;
    late OfferMediaUrlCache cache;

    setUp(() {
      now = DateTime(2026, 9, 26, 12);
      cache = OfferMediaUrlCache(now: () => now);
    });

    test('hands out a link only while it is safely valid', () {
      cache.put('offer-media:$_a:m1', 'https://r2.test/m1?sig',
          now.add(const Duration(minutes: 15)),
          isVideo: true, durationMs: 9000);

      final entry = cache.get('offer-media:$_a:m1');
      expect(entry?.url, 'https://r2.test/m1?sig');
      expect(entry?.isVideo, isTrue);
      expect(entry?.durationMs, 9000);

      now = now.add(const Duration(minutes: 14));
      expect(cache.get('offer-media:$_a:m1'), isNull,
          reason: 'within a minute of expiry it is treated as gone');
      expect(cache.length, 0);
    });

    test('a link R2 refused can be forgotten, and everything can be', () {
      final later = now.add(const Duration(minutes: 15));
      cache.put('k1', 'https://r2.test/1', later);
      cache.put('k2', 'https://r2.test/2', later);

      cache.invalidate('k1');
      expect(cache.get('k1'), isNull);
      expect(cache.get('k2'), isNotNull);

      cache.clear();
      expect(cache.length, 0);
    });

    test('never stores an empty key or link', () {
      final later = now.add(const Duration(minutes: 15));
      cache.put('', 'https://r2.test/1', later);
      cache.put('k', '', later);
      expect(cache.length, 0);
      expect(cache.get(null), isNull);
    });
  });

  group('OfferMediaSession', () {
    late OfferMediaUploadQueue queue;

    setUpAll(() => Hive.init(
        Directory.systemTemp.createTempSync('offer_media_session_test').path));

    setUp(() {
      OfferMediaSession.reset();
      queue = OfferMediaUploadQueue(
        currentUserId: () => null,
        openBox: () => Hive.openBox<dynamic>('offer_media_session_test'),
        observeLifecycle: false,
      );
      OfferMediaUploadQueue.debugInstance = queue;
      OfferMediaUrlCache.instance.clear();
    });

    tearDown(() async {
      OfferMediaSession.reset();
      queue.dispose();
      OfferMediaUploadQueue.debugInstance = null;
      OfferMediaUrlCache.instance.clear();
    });

    tearDownAll(() async {
      await Hive.deleteBoxFromDisk('offer_media_session_test');
      await Hive.close();
    });

    test('uploads follow the signed-in account', () {
      OfferMediaSession.onAuthState(uid: _a, active: true);
      expect(queue.activeOwner, _a);

      OfferMediaSession.onAuthState(uid: _b, active: true);
      expect(queue.activeOwner, _b);

      OfferMediaSession.onAuthState(uid: null, active: false);
      expect(queue.activeOwner, isNull);
    });

    test(
        'a session that is not application-authenticated (password '
        'recovery, deletion quarantine) uploads nothing', () {
      OfferMediaSession.onAuthState(uid: _a, active: false);
      expect(queue.activeOwner, isNull);
    });

    test("an account change drops the previous account's links", () {
      final later = DateTime.now().add(const Duration(minutes: 15));
      OfferMediaSession.onAuthState(uid: _a, active: true);
      OfferMediaUrlCache.instance
          .put('offer-media:$_a:m1', 'https://r2.test/a', later);

      OfferMediaSession.onAuthState(uid: _a, active: true);
      expect(OfferMediaUrlCache.instance.length, 1,
          reason: 'the same account keeps its links');

      OfferMediaSession.onAuthState(uid: _b, active: true);
      expect(OfferMediaUrlCache.instance.length, 0);
    });

    test('signing out drops every link', () {
      final later = DateTime.now().add(const Duration(minutes: 15));
      OfferMediaSession.onAuthState(uid: _a, active: true);
      OfferMediaUrlCache.instance
          .put('offer-media:$_a:m1', 'https://r2.test/a', later);

      OfferMediaSession.onAuthState(uid: null, active: false);

      expect(OfferMediaUrlCache.instance.length, 0);
      expect(queue.activeOwner, isNull);
    });
  });
}
