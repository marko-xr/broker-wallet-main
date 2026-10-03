import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_preparer.dart';

import 'share_fixtures.dart';

ShareAttachment fileAttachment(
  File file, {
  String key = 'item',
  ShareAttachmentKind kind = ShareAttachmentKind.image,
  String baseName = 'Offer-01',
  bool isTemporary = false,
}) =>
    ShareAttachment(
      key: key,
      kind: kind,
      baseName: baseName,
      fetch: (scratch, cancel) async =>
          FetchedShareFile(file, isTemporary: isTemporary),
    );

ShareAttachment failingAttachment(String key, Object error,
        {void Function()? onFetch}) =>
    ShareAttachment(
      key: key,
      kind: ShareAttachmentKind.image,
      baseName: 'x',
      fetch: (scratch, cancel) async {
        onFetch?.call();
        throw error;
      },
    );

Future<ShareFailure> failureOf(Future<Object?> Function() run) async {
  try {
    await run();
  } on ShareFailure catch (failure) {
    return failure;
  }
  fail('expected a ShareFailure');
}

Uint8List webpBytes() => Uint8List.fromList(<int>[
      0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, //
      ...List<int>.filled(200, 1),
    ]);

/// A video `ftyp` box with the given four-letter brand.
Uint8List videoBytes(String brand) => Uint8List.fromList(<int>[
      0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, //
      ...brand.codeUnits, 0, 0, 0, 0, //
      ...brand.codeUnits, ...brand.codeUnits,
      ...List<int>.filled(300, 3),
    ]);

void main() {
  late TempArea area;

  setUp(() => area = TempArea());
  tearDown(() => area.dispose());

  group('names and types', () {
    test('a cache file is copied under its professional name, not moved',
        () async {
      final cached =
          area.writeCacheFile('offer-media_user_media.bin', jpegBytes());
      final bundle = await newPreparer(area).prepare(
          <ShareAttachment>[fileAttachment(cached)], ShareCancelToken());

      expect(bundle.files, hasLength(1));
      final file = bundle.files.single;
      expect(file.name, 'Offer-01.jpg');
      expect(file.mimeType, 'image/jpeg');
      expect(File(file.path).readAsBytesSync(), jpegBytes());
      expect(File(file.path).parent.path, bundle.directory.path);
      expect(cached.existsSync(), isTrue, reason: 'the cache keeps its file');
    });

    test('a download is moved into place, leaving nothing behind', () async {
      Future<FetchedShareFile> download(
          Directory scratch, ShareCancelToken _) async {
        final part = File('${scratch.path}/download-0.part')
          ..writeAsBytesSync(pngBytes());
        return FetchedShareFile(part, isTemporary: true);
      }

      final bundle = await newPreparer(area).prepare(<ShareAttachment>[
        ShareAttachment(
          key: 'a',
          kind: ShareAttachmentKind.image,
          baseName: 'Offer-01',
          fetch: download,
        ),
      ], ShareCancelToken());

      expect(bundle.files.single.name, 'Offer-01.png');
      expect(bundle.files.single.mimeType, 'image/png');
      final left = bundle.directory
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .toList();
      expect(left, <String>['Offer-01.png']);
    });

    test('the extension follows the bytes, not the old name', () async {
      final cases = <String, List<Object>>{
        'jpg': <Object>[jpegBytes(), 'image/jpeg'],
        'png': <Object>[pngBytes(), 'image/png'],
        'webp': <Object>[webpBytes(), 'image/webp'],
      };
      for (final entry in cases.entries) {
        // Named as a different type on purpose.
        final wrongName = entry.key == 'png' ? 'x.jpg' : 'x.png';
        final source =
            area.writeCacheFile(wrongName, entry.value[0] as List<int>);
        final bundle = await newPreparer(area).prepare(
            <ShareAttachment>[fileAttachment(source)], ShareCancelToken());
        expect(bundle.files.single.name, 'Offer-01.${entry.key}');
        expect(bundle.files.single.mimeType, entry.value[1]);
        await bundle.discard();
      }
    });

    test('videos keep their real container', () async {
      final cases = <String, List<String>>{
        'isom': <String>['mp4', 'video/mp4'],
        'mp42': <String>['mp4', 'video/mp4'],
        'qt  ': <String>['mov', 'video/quicktime'],
        '3gp4': <String>['3gp', 'video/3gpp'],
      };
      for (final entry in cases.entries) {
        final source = area.writeCacheFile('video.bin', videoBytes(entry.key));
        final bundle = await newPreparer(area).prepare(<ShareAttachment>[
          fileAttachment(source, kind: ShareAttachmentKind.video),
        ], ShareCancelToken());
        expect(bundle.files.single.name, 'Offer-01.${entry.value[0]}',
            reason: 'brand ${entry.key}');
        expect(bundle.files.single.mimeType, entry.value[1]);
        await bundle.discard();
      }
    });

    test('a video is shared as the video, never as a poster image', () async {
      final video = area.writeCacheFile('v.bin', mp4Bytes());
      final bundle = await newPreparer(area).prepare(<ShareAttachment>[
        fileAttachment(video, kind: ShareAttachmentKind.video),
      ], ShareCancelToken());
      expect(bundle.files.single.mimeType, startsWith('video/'));
      expect(File(bundle.files.single.path).lengthSync(), mp4Bytes().length);
    });

    test('bytes nothing recognizes are refused unless the name is a media type',
        () async {
      final unknown = area.writeCacheFile('notes.txt', textBytes());
      final failure = await failureOf(() => newPreparer(area).prepare(
          <ShareAttachment>[fileAttachment(unknown, key: 'k')],
          ShareCancelToken()));
      expect(failure.kind, ShareFailureKind.unavailable);
      expect(failure.failedKeys, <String>['k']);

      // An older file whose container no detector knows but whose name is an
      // accepted media extension is kept under that extension.
      final older = area.writeCacheFile('clip.mp4', <int>[
        ...List<int>.filled(64, 9),
        ...List<int>.filled(200, 1),
      ]);
      final bundle = await newPreparer(area).prepare(<ShareAttachment>[
        fileAttachment(older, kind: ShareAttachmentKind.video),
      ], ShareCancelToken());
      expect(bundle.files.single.name, 'Offer-01.mp4');
    });

    test('a photo item whose file is a video does not pass as a photo name',
        () async {
      // The name says .mp4 but the item is an image: the name is not trusted
      // for the wrong kind.
      final older = area.writeCacheFile('clip.mp4', List<int>.filled(300, 9));
      final failure = await failureOf(() => newPreparer(area).prepare(
          <ShareAttachment>[fileAttachment(older)], ShareCancelToken()));
      expect(failure.kind, ShareFailureKind.unavailable);
    });

    test('a PDF keeps .pdf and a professional name, never its cache name',
        () async {
      final cached = area.writeCacheFile(
          'quotation_quotation-id-1b2c_pdf-media-id-7f3a.pdf', pdfBytes());
      final bundle = await newPreparer(area).prepare(<ShareAttachment>[
        fileAttachment(
          cached,
          kind: ShareAttachmentKind.pdf,
          baseName: 'Broker-Wallet-Quotation-Apartment-306',
        ),
      ], ShareCancelToken());
      final file = bundle.files.single;
      expect(file.name, 'Broker-Wallet-Quotation-Apartment-306.pdf');
      expect(file.mimeType, 'application/pdf');
      expect(file.path.contains('quotation-id'), isFalse);
      expect(file.path.contains('pdf-media'), isFalse);
      expect(File(file.path).readAsBytesSync(), pdfBytes());
    });

    test('a file that is not a PDF is refused as a PDF whatever its name',
        () async {
      final fake = area.writeCacheFile('x.pdf', jpegBytes());
      final failure = await failureOf(() => newPreparer(area).prepare(
              <ShareAttachment>[
                fileAttachment(fake, key: 'doc', kind: ShareAttachmentKind.pdf)
              ],
              ShareCancelToken()));
      expect(failure.kind, ShareFailureKind.unavailable);
      expect(failure.failedKeys, <String>['doc']);
    });

    test('two files with one name never overwrite each other', () async {
      final a = area.writeCacheFile('a.bin', jpegBytes(10));
      final b = area.writeCacheFile('b.bin', jpegBytes(20));
      final c = area.writeCacheFile('c.bin', jpegBytes(30));
      final bundle = await newPreparer(area).prepare(<ShareAttachment>[
        fileAttachment(a, key: 'a'),
        fileAttachment(b, key: 'b'),
        fileAttachment(c, key: 'c'),
      ], ShareCancelToken());
      expect(bundle.files.map((f) => f.name).toList(),
          <String>['Offer-01.jpg', 'Offer-01-2.jpg', 'Offer-01-3.jpg']);
      expect(bundle.files.map((f) => File(f.path).lengthSync()).toSet(),
          hasLength(3));
    });

    test('a name cannot reach outside the share\'s folder', () async {
      final a = area.writeCacheFile('a.bin', jpegBytes());
      for (final hostile in <String>[
        '../../evil/name',
        r'..\..\evil',
        '/etc/passwd',
        'a/../../b',
        '',
        '   ',
        'name\nwith\nbreaks',
      ]) {
        final bundle = await newPreparer(area).prepare(<ShareAttachment>[
          fileAttachment(a, baseName: hostile),
        ], ShareCancelToken());
        final file = File(bundle.files.single.path);
        expect(file.parent.path, bundle.directory.path, reason: hostile);
        expect(bundle.files.single.name.contains('/'), isFalse);
        expect(bundle.files.single.name.contains(r'\'), isFalse);
        expect(bundle.files.single.name.contains('..'), isFalse);
        expect(bundle.files.single.name, endsWith('.jpg'));
        await bundle.discard();
      }
    });

    test('an empty name becomes a plain product name', () async {
      final a = area.writeCacheFile('a.bin', jpegBytes());
      final bundle = await newPreparer(area).prepare(<ShareAttachment>[
        fileAttachment(a, baseName: '...'),
      ], ShareCancelToken());
      expect(bundle.files.single.name, 'Broker-Wallet.jpg');
    });
  });

  group('the share\'s folder', () {
    test('each share has its own, named by the moment it was made', () async {
      var now = DateTime.fromMillisecondsSinceEpoch(1760000000000);
      final preparer = newPreparer(area, now: () => now);
      final a = area.writeCacheFile('a.bin', jpegBytes());

      final first = await preparer
          .prepare(<ShareAttachment>[fileAttachment(a)], ShareCancelToken());
      now = now.add(const Duration(seconds: 5));
      final second = await preparer
          .prepare(<ShareAttachment>[fileAttachment(a)], ShareCancelToken());

      expect(first.directory.path, isNot(second.directory.path));
      expect(first.directory.parent.path, area.staging.path);
      expect(first.directory.uri.pathSegments.where((s) => s.isNotEmpty).last,
          startsWith('1760000000000-'));
      expect(File(first.files.single.path).existsSync(), isTrue,
          reason: 'a second share does not touch the first one\'s files');
    });

    test('the sweep removes folders older than six hours and nothing newer',
        () async {
      final now = DateTime.fromMillisecondsSinceEpoch(1760000000000);
      const hour = 3600 * 1000;
      Directory made(String name) {
        final dir = Directory('${area.staging.path}/$name')
          ..createSync(recursive: true);
        File('${dir.path}/file.jpg').writeAsBytesSync(jpegBytes());
        return dir;
      }

      final old = made('${now.millisecondsSinceEpoch - 7 * hour}-0');
      final borderline =
          made('${now.millisecondsSinceEpoch - 6 * hour + 1000}-1');
      final recent = made('${now.millisecondsSinceEpoch - 1 * hour}-2');
      final justNow = made('${now.millisecondsSinceEpoch - 1000}-3');
      final foreign = made('not-a-share-folder');
      final stray = File('${area.staging.path}/stray.txt')
        ..writeAsStringSync('x');

      final a = area.writeCacheFile('a.bin', jpegBytes());
      await newPreparer(area, now: () => now)
          .prepare(<ShareAttachment>[fileAttachment(a)], ShareCancelToken());

      expect(old.existsSync(), isFalse);
      expect(borderline.existsSync(), isTrue);
      expect(recent.existsSync(), isTrue);
      expect(justNow.existsSync(), isTrue);
      expect(foreign.existsSync(), isTrue, reason: 'not ours to delete');
      expect(stray.existsSync(), isTrue);
    });

    test('discard removes the folder and may be called again', () async {
      final a = area.writeCacheFile('a.bin', jpegBytes());
      final bundle = await newPreparer(area)
          .prepare(<ShareAttachment>[fileAttachment(a)], ShareCancelToken());
      expect(bundle.directory.existsSync(), isTrue);
      await bundle.discard();
      expect(bundle.directory.existsSync(), isFalse);
      await bundle.discard();
    });
  });

  group('failures', () {
    List<FileSystemEntity> folders() => area.staging.existsSync()
        ? area.staging.listSync()
        : <FileSystemEntity>[];

    test('a share that cannot be prepared leaves no folder behind', () async {
      final failure = await failureOf(() => newPreparer(area)
              .prepare(<ShareAttachment>[
            failingAttachment('a', const ShareFailure(ShareFailureKind.network))
          ], ShareCancelToken()));
      expect(failure.kind, ShareFailureKind.network);
      expect(folders(), isEmpty);
    });

    test('a network failure stops at once: the rest would fail the same way',
        () async {
      var secondFetched = 0;
      final failure =
          await failureOf(() => newPreparer(area).prepare(<ShareAttachment>[
                failingAttachment(
                    'a', const ShareFailure(ShareFailureKind.network)),
                failingAttachment('b', StateError('x'),
                    onFetch: () => secondFetched++),
              ], ShareCancelToken()));
      expect(failure.kind, ShareFailureKind.network);
      expect(secondFetched, 0);
    });

    test('a session failure stops at once and stays a session failure',
        () async {
      final failure =
          await failureOf(() => newPreparer(area).prepare(<ShareAttachment>[
                failingAttachment(
                    'a', const ShareFailure(ShareFailureKind.session)),
                failingAttachment('b', StateError('x')),
              ], ShareCancelToken()));
      expect(failure.kind, ShareFailureKind.session);
      expect(failure.failedKeys, isEmpty);
    });

    test('unavailable files are all reported together, the rest still tried',
        () async {
      final good = area.writeCacheFile('good.bin', jpegBytes());
      var goodFetched = 0;
      final failure =
          await failureOf(() => newPreparer(area).prepare(<ShareAttachment>[
                failingAttachment(
                    'gone-1', const ShareFailure(ShareFailureKind.unavailable)),
                ShareAttachment(
                  key: 'good',
                  kind: ShareAttachmentKind.image,
                  baseName: 'x',
                  fetch: (scratch, cancel) async {
                    goodFetched++;
                    return FetchedShareFile(good);
                  },
                ),
                failingAttachment(
                    'gone-2', const ShareFailure(ShareFailureKind.unavailable)),
              ], ShareCancelToken()));
      expect(failure.kind, ShareFailureKind.unavailable);
      expect(failure.failedKeys, <String>['gone-1', 'gone-2']);
      expect(goodFetched, 1);
      expect(folders(), isEmpty, reason: 'nothing is sent with files missing');
    });

    test('anything else is a generic failure that carries no text', () async {
      final failure =
          await failureOf(() => newPreparer(area).prepare(<ShareAttachment>[
                failingAttachment('a',
                    StateError('https://r2.example/x?X-Amz-Signature=secret'))
              ], ShareCancelToken()));
      expect(failure.kind, ShareFailureKind.generic);
      expect(failure.failedKeys, <String>['a']);
      expect(failure.toString().contains('X-Amz'), isFalse);
      expect(failure.toString().contains('StateError'), isFalse);
    });

    test('a file that vanished, or is empty, is unavailable', () async {
      final missing = File('${area.root.path}/nowhere.jpg');
      final empty = area.writeCacheFile('empty.jpg', <int>[]);
      for (final file in <File>[missing, empty]) {
        final failure = await failureOf(() => newPreparer(area).prepare(
            <ShareAttachment>[fileAttachment(file, key: 'k')],
            ShareCancelToken()));
        expect(failure.kind, ShareFailureKind.unavailable);
        expect(failure.failedKeys, <String>['k']);
      }
    });
  });

  group('cancelling', () {
    test('before it starts, nothing is prepared and nothing is left', () async {
      final a = area.writeCacheFile('a.bin', jpegBytes());
      final token = ShareCancelToken()..cancel();
      var thrown = false;
      try {
        await newPreparer(area)
            .prepare(<ShareAttachment>[fileAttachment(a)], token);
      } on ShareCancelled {
        thrown = true;
      }
      expect(thrown, isTrue);
      expect(area.staging.listSync(), isEmpty);
    });

    test('while a file is being fetched, the share stops and cleans up',
        () async {
      final a = area.writeCacheFile('a.bin', jpegBytes());
      final token = ShareCancelToken();
      var secondFetched = 0;
      var thrown = false;
      try {
        await newPreparer(area).prepare(<ShareAttachment>[
          ShareAttachment(
            key: 'a',
            kind: ShareAttachmentKind.image,
            baseName: 'x',
            fetch: (scratch, cancel) async {
              cancel.cancel();
              return FetchedShareFile(a);
            },
          ),
          failingAttachment('b', StateError('x'),
              onFetch: () => secondFetched++),
        ], token);
      } on ShareCancelled {
        thrown = true;
      }
      expect(thrown, isTrue);
      expect(secondFetched, 0);
      expect(area.staging.listSync(), isEmpty);
    });

    test(
        'a token tells whoever listens, once, and at once if already cancelled',
        () {
      final token = ShareCancelToken();
      var calls = 0;
      final stop = token.onCancel(() => calls++);
      token.cancel();
      token.cancel();
      expect(calls, 1);
      stop();

      var late = 0;
      token.onCancel(() => late++);
      expect(late, 1);

      final other = ShareCancelToken();
      var removed = 0;
      other.onCancel(() => removed++)();
      other.cancel();
      expect(removed, 0,
          reason: 'a listener that stopped listening is not called');
    });
  });
}
