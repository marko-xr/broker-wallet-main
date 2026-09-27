import 'package:broker_wallet/src/services/video_player_resource_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// The format check that runs before any player is created.
///
/// Regression (Samsung, 2026-09-26): every ready private Offer video was
/// refused here in ~20 ms, before a player existed or a byte was requested.
/// The extension was read from the log-redacted form of the URL, which
/// re-appends `?<signature-hidden>`, so a signed R2 link ending in `.mp4?…`
/// was read as extension `mp4?<signature-hidden>` and declared unsupported.
/// A local file (no query) passed, which is why only network playback failed.

// The exact shape the Media Worker signs (`createPresignedR2Url`): path-style
// endpoint, bucket, per-segment encoded key, SigV4 query. Placeholder values.
const _signedR2Get = 'https://ACCOUNT.r2.cloudflarestorage.com/'
    'broker-wallet-media/profiles/OWNER/offers/OFFER/'
    'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeed0dd9.mp4'
    '?X-Amz-Expires=900&X-Amz-Date=20260926T123900Z'
    '&X-Amz-Algorithm=AWS4-HMAC-SHA256'
    '&X-Amz-Credential=KEY%2F20260926%2Fauto%2Fs3%2Faws4_request'
    '&X-Amz-SignedHeaders=host&X-Amz-Signature=0123abcd';

void main() {
  group('isVideoFormatSupported', () {
    test('a signed private R2 link to an MP4 is playable', () {
      expect(VideoPlayerResourceManager.isVideoFormatSupported(_signedR2Get),
          isTrue);
    });

    test('a signed link keeps each container it names', () {
      for (final extension in ['mp4', 'mov', '3gp']) {
        final url = _signedR2Get.replaceFirst('.mp4?', '.$extension?');
        expect(VideoPlayerResourceManager.isVideoFormatSupported(url), isTrue,
            reason: extension);
      }
    });

    test('a link whose query carries a token (Firebase media) is playable', () {
      const url = 'https://firebasestorage.googleapis.com/v0/b/app/o/'
          'owners%2Fclip.mp4?alt=media&token=abc.def';
      expect(VideoPlayerResourceManager.isVideoFormatSupported(url), isTrue);
    });

    test('a local file is playable', () {
      expect(
          VideoPlayerResourceManager.isVideoFormatSupported(
              '/data/user/0/app/app_flutter/offer_media/x_pending.mp4'),
          isTrue);
    });

    test('a dot inside the query is never taken for the extension', () {
      const url = 'https://r2.example.test/bucket/clip.bin'
          '?X-Amz-Credential=a.mp4&X-Amz-Signature=b';
      expect(VideoPlayerResourceManager.isVideoFormatSupported(url), isFalse);
    });

    test('a link with no extension, or an unknown one, is refused', () {
      expect(
          VideoPlayerResourceManager.isVideoFormatSupported(
              'https://r2.example.test/bucket/clip?X-Amz-Signature=b'),
          isFalse);
      expect(
          VideoPlayerResourceManager.isVideoFormatSupported(
              'https://r2.example.test/bucket/clip.bin#t=3'),
          isFalse);
    });
  });
}
