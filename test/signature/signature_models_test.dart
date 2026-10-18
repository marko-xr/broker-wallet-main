import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/services/signature/signature_models.dart';
import 'package:broker_wallet/src/services/signature/signature_pdf_engine.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/signature_ui_support.dart';

import 'signature_fixtures.dart';

final RegExp sigKey = RegExp(r'^sig[A-Z]');

Map<String, dynamic> arb(String language) =>
    jsonDecode(File('lib/src/common/localization/app_$language.arb')
        .readAsStringSync()) as Map<String, dynamic>;

void main() {
  group('drawing', () {
    test('strokes begin where the points say a finger went down', () {
      final one = drawingOf();
      expect(one.strokes.length, 1);
      expect(one.strokes.first.length, 5);
      final two = drawingOf(twoStrokes: true);
      expect(two.strokes.length, 2);
      expect(two.strokes.first.length, 5);
      expect(two.strokes.last.length, 2);
      expect(two.strokes.last.first.isStrokeStart, isTrue);
    });

    test('bounds hold every point', () {
      final box = drawingOf().bounds!;
      expect(box.left, 20);
      expect(box.right, 250);
      expect(box.top, 30);
      expect(box.bottom, 90);
      expect(
          const SignatureDrawing(
                  points: <InkPoint>[],
                  colorValue: 0,
                  strokeWidth: 3,
                  canvasWidth: 1,
                  canvasHeight: 1)
              .bounds,
          isNull);
    });

    test('a stray dot or a tap is not a signature', () {
      SignatureDrawing of(List<InkPoint> points) => SignatureDrawing(
          points: points,
          colorValue: 0xFF000000,
          strokeWidth: 3,
          canvasWidth: 300,
          canvasHeight: 120);
      expect(of(const <InkPoint>[]).hasMeaningfulInk, isFalse);
      expect(of(const [InkPoint(50, 50, isStrokeStart: true)]).hasMeaningfulInk,
          isFalse);
      expect(
          of(const [
            InkPoint(50, 50, isStrokeStart: true),
            InkPoint(54, 53),
          ]).hasMeaningfulInk,
          isFalse);
      expect(
          of(const [
            InkPoint(50, 50, isStrokeStart: true),
            InkPoint(90, 50),
          ]).hasMeaningfulInk,
          isTrue);
      expect(drawingOf().hasMeaningfulInk, isTrue);
    });

    test('copying a drawing changes only what is named', () {
      final base = drawingOf(colorValue: 0xFF0000FF, strokeWidth: 5.5);
      final changed = base.copyWith(colorValue: 0xFFFF0000);
      expect(changed.colorValue, 0xFFFF0000);
      expect(changed.strokeWidth, 5.5);
      expect(changed.points, base.points);
      expect(changed.canvasWidth, base.canvasWidth);
    });

    test('points compare by value', () {
      expect(const InkPoint(1, 2), const InkPoint(1, 2));
      expect(const InkPoint(1, 2),
          isNot(const InkPoint(1, 2, isStrokeStart: true)));
      expect(const InkPoint(1, 2).hashCode, const InkPoint(1, 2).hashCode);
    });
  });

  group('images', () {
    test('a stamp knows its aspect ratio and what counts as a signature', () {
      final asset = StampAsset(
        id: 'a',
        kind: StampKind.signature,
        png: stampPng(),
        pixelWidth: 240,
        pixelHeight: 80,
      );
      expect(asset.aspect, 3);
      expect(asset.countsAsSignature, isTrue);
      expect(asset.copyWith(label: 'x').kind, StampKind.signature);
      for (final kind in [StampKind.initials]) {
        expect(
            StampAsset(
                    id: 'b',
                    kind: kind,
                    png: stampPng(),
                    pixelWidth: 1,
                    pixelHeight: 1)
                .countsAsSignature,
            isTrue);
      }
      for (final kind in [StampKind.date, StampKind.text]) {
        expect(
            StampAsset(
                    id: 'c',
                    kind: kind,
                    png: stampPng(),
                    pixelWidth: 1,
                    pixelHeight: 1)
                .countsAsSignature,
            isFalse);
      }
    });

    test('the PNG header is read without decoding', () {
      final header = readPngHeader(stampPng(width: 123, height: 45))!;
      expect(header.width, 123);
      expect(header.height, 45);
      expect(header.hasAlphaChannel, isTrue);
      expect(readPngHeader(Uint8List.fromList(<int>[1, 2, 3])), isNull);
    });
  });

  group('typed text', () {
    test('control characters and bidi overrides go, spaces collapse', () {
      expect(StampText.clean('  Mohammed \n  Ali  ', maxRunes: 80),
          'Mohammed Ali');
      expect(
          StampText.clean('a\u202Eb\u200Fc\u0007d', maxRunes: 80), 'a b c d');
      expect(StampText.clean('   ', maxRunes: 80), isNull);
      expect(StampText.clean('\u202E\u200F', maxRunes: 80), isNull);
      expect(StampText.clean('', maxRunes: 80), isNull);
    });

    test('Arabic is kept exactly', () {
      expect(StampText.clean('محمد أحمد', maxRunes: 80), 'محمد أحمد');
      expect(StampText.clean('  عقد   الإيجار ', maxRunes: 80), 'عقد الإيجار');
    });

    test('the length limit counts letters, not bytes', () {
      expect(StampText.clean('ABCDEF', maxRunes: StampText.maxInitialsRunes),
          'ABCDEF');
      expect(StampText.clean('ABCDEFG', maxRunes: StampText.maxInitialsRunes),
          isNull);
      expect(StampText.clean('ح' * 80, maxRunes: StampText.maxTextRunes),
          'ح' * 80);
      expect(
          StampText.clean('ح' * 81, maxRunes: StampText.maxTextRunes), isNull);
    });

    test('direction follows the first strong letter', () {
      expect(StampText.isRightToLeft('محمد'), isTrue);
      expect(StampText.isRightToLeft('Mohammed'), isFalse);
      expect(StampText.isRightToLeft('12/10/2026 مرحبا'), isTrue);
      expect(StampText.isRightToLeft('Hello مرحبا'), isFalse);
      expect(StampText.isRightToLeft('مرحبا Hello'), isTrue);
      expect(StampText.isRightToLeft('123'), isFalse);
      expect(StampText.isRightToLeft(''), isFalse);
      expect(StampText.isRightToLeft('שלום'), isTrue);
    });
  });

  group('date', () {
    test('numeric and long forms, in digits', () {
      final date = DateTime(2026, 10, 18);
      expect(StampDate.numeric(date), '18/10/2026');
      expect(StampDate.numeric(DateTime(2026, 3, 5)), '05/03/2026');
      expect(StampDate.long(date, arabic: false), '18 Oct 2026');
      expect(StampDate.long(DateTime(2026, 3, 5), arabic: true), '5 مارس 2026');
      expect(
          StampDate.long(DateTime(2026, 12, 31), arabic: false), '31 Dec 2026');
    });
  });

  group('stored record', () {
    SignedDocument sample() => SignedDocument(
          id: 'id1',
          fileName: 'id1.pdf',
          name: 'عقد الإيجار - موقّع',
          createdAt: DateTime.utc(2026, 10, 18, 9, 30),
          fileSize: 1234,
          pageCount: 3,
          signatureCount: 2,
          itemCount: 4,
        );

    test('it survives a round trip, Arabic title included', () {
      final back =
          SignedDocument.fromJson(jsonDecode(jsonEncode(sample().toJson())));
      expect(back.name, sample().name);
      expect(back.createdAt.isAtSameMomentAs(sample().createdAt), isTrue);
      expect(back.signatureCount, 2);
      expect(back.itemCount, 4);
      expect(back.exportFileName, 'عقد الإيجار - موقّع.pdf');
    });

    test('a damaged record is refused, never half trusted', () {
      Map<String, dynamic> withField(String key, Object? value) =>
          <String, dynamic>{...sample().toJson(), key: value};
      for (final bad in <Object?>[
        null,
        'text',
        withField('fileName', '../x.pdf'),
        withField('fileName', 'a/b.pdf'),
        withField('fileName', 'x.PDF'),
        withField('fileName', ''),
        withField('name', ''),
        withField('id', null),
        withField('pageCount', 0),
        withField('fileSize', -1),
        withField('signatureCount', -1),
        withField('itemCount', 'many'),
        withField('createdAt', 'yesterday'),
      ]) {
        expect(() => SignedDocument.fromJson(bad), throwsA(anything),
            reason: '$bad');
      }
    });
  });

  group('names', () {
    final now = DateTime(2026, 10, 18, 9, 30);

    test('the default title keeps the picked name and says it is signed', () {
      expect(SignatureNaming.defaultName('Lease Agreement.pdf', 'signed', now),
          'Lease Agreement - signed');
      expect(SignatureNaming.defaultName('عقد الإيجار.PDF', 'موقّع', now),
          'عقد الإيجار - موقّع');
      expect(SignatureNaming.defaultName('a/b:c.pdf', 'signed', now),
          'a b c - signed');
    });

    test('without a usable name it falls back to a dated one', () {
      expect(SignatureNaming.defaultName(null, 'signed', now),
          'signed_20261018_0930');
      expect(SignatureNaming.defaultName('...pdf', 'signed', now),
          'signed_20261018_0930');
      expect(SignatureNaming.defaultName('', 'signed', now),
          'signed_20261018_0930');
    });

    test('a title is unique among the account\'s, whatever the case', () {
      expect(SignatureNaming.uniqueName('Lease', const <String>[]), 'Lease');
      expect(SignatureNaming.uniqueName('Lease', const ['lease']), 'Lease (2)');
      expect(SignatureNaming.uniqueName('Lease', const ['Lease', 'Lease (2)']),
          'Lease (3)');
    });

    test('only the store\'s own file names are accepted', () {
      expect(SignatureNaming.isStoredFileName('abc-123_X.pdf'), isTrue);
      for (final bad in [
        '../a.pdf',
        'a b.pdf',
        '',
        'a.pdf.exe',
        '.pdf',
        r'a\b.pdf'
      ]) {
        expect(SignatureNaming.isStoredFileName(bad), isFalse, reason: bad);
      }
    });
  });

  group('messages', () {
    final en = arb('en');
    final ar = arb('ar');

    test('every failure has a message in English and in Arabic', () {
      for (final failure in SignatureFailure.values) {
        final key = kSignatureFailureKeys[failure];
        expect(key, isNotNull, reason: '$failure has no message key');
        expect(en[key], isA<String>(), reason: '$key (en)');
        expect(ar[key], isA<String>(), reason: '$key (ar)');
        expect((en[key] as String).trim(), isNotEmpty);
        expect((ar[key] as String).trim(), isNotEmpty);
      }
    });

    test('Arabic messages are Arabic and English ones are not', () {
      final arabic = RegExp(r'[؀-ۿ]');
      for (final key in en.keys.where((k) => sigKey.hasMatch(k))) {
        expect(ar.containsKey(key), isTrue, reason: '$key missing in Arabic');
        expect(arabic.hasMatch(en[key] as String), isFalse,
            reason: '$key (en)');
        expect(arabic.hasMatch(ar[key] as String), isTrue, reason: '$key (ar)');
      }
      for (final key in ar.keys.where((k) => sigKey.hasMatch(k))) {
        expect(en.containsKey(key), isTrue, reason: '$key missing in English');
      }
    });

    test('placeholders are the same in both languages', () {
      final token = RegExp(r'\{[a-zA-Z]+\}');
      for (final key in en.keys.where((k) => sigKey.hasMatch(k))) {
        final a = token.allMatches(en[key] as String).map((m) => m[0]).toSet();
        final b = token.allMatches(ar[key] as String).map((m) => m[0]).toSet();
        expect(b, a, reason: key);
      }
      expect(en['sigApplied'], contains('{count}'));
      expect(en['sigSavedToDownloads'], contains('{name}'));
      expect(en['sigShareText'], contains('{name}'));
    });

    test('a digital signature is never claimed', () {
      // The note on the preview and the refusal of a signed PDF say plainly what
      // the marks are.
      expect(en['sigVisibleNote'],
          contains('not a certificate-based digital signature'));
      expect(en['sigVisibleNote'], contains('do not verify who signed'));
      for (final key in en.keys.where((k) => sigKey.hasMatch(k))) {
        final text = (en[key] as String).toLowerCase();
        expect(text.contains('legally binding'), isFalse, reason: key);
        expect(text.contains('verified signature'), isFalse, reason: key);
        expect(text.contains('uae pass'), isFalse, reason: key);
        expect(text.contains('accredited'), isFalse, reason: key);
      }
    });
  });
}
