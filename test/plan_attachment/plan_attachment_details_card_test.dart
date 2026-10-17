import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/Views/Widgets/plan_attachment_actions.dart';
import 'package:broker_wallet/src/Views/Widgets/plan_attachment_details_card.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The land / plot plan card of the Offer and Owner Details screens: what it
/// shows for each kind of file, that a Word file says it opens in another app,
/// that View and Share are guarded while one is running, English and Arabic
/// (RTL), Light and Dark, and that it never draws a link, a storage key or an id.
///
/// The card is given recording actions, so no file is downloaded, opened or
/// shared. Local widget tests only; not device verification.

const _recordId = 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1';
const _mediaId = '11111111-1111-4111-8111-111111111111';

const _card = Key('planAttachment.details');
const _open = Key('planAttachment.details.open');
const _share = Key('planAttachment.details.share');
const _note = Key('planAttachment.details.externalNote');

late Map<String, dynamic> _en;
late Map<String, dynamic> _ar;

/// Records what the card asks for; the first call of each can be held open.
class _RecordingActions extends PlanAttachmentActions {
  _RecordingActions();

  final List<String> calls = [];
  Completer<void>? hold;

  @override
  Future<void> open(
    BuildContext context, {
    required PlanParent parent,
    required String parentId,
    required PlanAttachmentRef plan,
  }) async {
    calls.add('open ${parent.name} $parentId ${plan.mediaObjectId}');
    final gate = hold;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> share(
    BuildContext context, {
    required PlanParent parent,
    required String parentId,
    required PlanAttachmentRef plan,
  }) async {
    calls.add('share ${parent.name} $parentId ${plan.mediaObjectId}');
    final gate = hold;
    if (gate != null) await gate.future;
  }
}

PlanAttachmentRef _plan({
  PlanAttachmentKind kind = PlanAttachmentKind.pdf,
  String contentType = PlanContentTypes.pdf,
  String? name = 'Plot 14 plan.pdf',
  int? bytes = 4096,
}) =>
    PlanAttachmentRef(
      mediaObjectId: _mediaId,
      kind: kind,
      contentType: contentType,
      displayName: name,
      byteLength: bytes,
    );

Widget _app(
  Widget child, {
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) =>
    MaterialApp(
      theme: theme,
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Future<void> _show(
  WidgetTester tester,
  PlanAttachmentRef plan,
  _RecordingActions actions, {
  PlanParent parent = PlanParent.offer,
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) async {
  await tester.pumpWidget(_app(
    PlanAttachmentDetailsCard(
      parent: parent,
      parentId: _recordId,
      plan: plan,
      actions: actions,
    ),
    locale: locale,
    theme: theme,
  ));
  await tester.pump();
}

bool _enabled(WidgetTester tester, Key key) =>
    tester.widget<ButtonStyleButton>(find.byKey(key)).onPressed != null;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        final file = File(key);
        if (!file.existsSync()) return null;
        final bytes = Uint8List.fromList(file.readAsBytesSync());
        return ByteData.view(bytes.buffer);
      },
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('PonnamKarthik/fluttertoast'),
      (call) async => true,
    );
    await AppLocalizations.preloadAllLanguages();
    _en = json.decode(
      File('lib/src/common/localization/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    _ar = json.decode(
      File('lib/src/common/localization/app_ar.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  group('what the card shows', () {
    testWidgets('a PDF: its name, type and size, with View and Share',
        (tester) async {
      await _show(tester, _plan(), _RecordingActions());

      expect(find.byKey(_card), findsOneWidget);
      expect(find.text(_en['planAttachmentTitle'] as String), findsOneWidget);
      expect(find.text('Plot 14 plan.pdf'), findsOneWidget);
      expect(find.text('${_en['planAttachmentTypePdf']} · 4.0 KB'),
          findsOneWidget);
      expect(find.text(_en['planAttachmentView'] as String), findsOneWidget);
      expect(find.text(_en['share'] as String), findsOneWidget);
      expect(find.byKey(_note), findsNothing,
          reason: 'a PDF opens inside Broker Wallet');
    });

    testWidgets('an image opens inside the app as well', (tester) async {
      await _show(
        tester,
        _plan(
          kind: PlanAttachmentKind.image,
          contentType: PlanContentTypes.jpeg,
          name: 'Plan photo.jpg',
          bytes: 2 * 1024 * 1024,
        ),
        _RecordingActions(),
      );
      expect(find.text('${_en['planAttachmentTypeImage']} · 2.0 MB'),
          findsOneWidget);
      expect(find.text(_en['planAttachmentView'] as String), findsOneWidget);
      expect(find.byKey(_note), findsNothing);
    });

    testWidgets('a Word file says it opens in another app, and says Open',
        (tester) async {
      for (final contentType in [PlanContentTypes.doc, PlanContentTypes.docx]) {
        await _show(
          tester,
          _plan(
            kind: PlanAttachmentKind.word,
            contentType: contentType,
            name: 'Plot 14 plan.${PlanContentTypes.extensionOf(contentType)}',
          ),
          _RecordingActions(),
        );
        expect(find.byKey(_note), findsOneWidget, reason: contentType);
        expect(find.text(_en['planAttachmentOpensExternally'] as String),
            findsOneWidget);
        expect(find.text(_en['planAttachmentOpen'] as String), findsOneWidget);
        expect(find.text(_en['planAttachmentView'] as String), findsNothing);
        expect(find.text(_en['share'] as String), findsOneWidget,
            reason: 'a Word file can still be shared');
      }
    });

    testWidgets(
        'without a name it is called by its type, without a size '
        'only its type is shown', (tester) async {
      await _show(tester, _plan(name: null, bytes: null), _RecordingActions());
      expect(
          find.text(_en['planAttachmentTypePdf'] as String), findsNWidgets(2));
      expect(find.textContaining('KB'), findsNothing);
    });

    testWidgets('never draws a link, a storage key or an id', (tester) async {
      await _show(
        tester,
        PlanAttachmentRef(
          mediaObjectId: _mediaId,
          kind: PlanAttachmentKind.pdf,
          contentType: PlanContentTypes.pdf,
          displayName: 'Plot 14 plan.pdf',
          byteLength: 4096,
          signedUrl:
              'https://r2.example.test/bucket/key?X-Amz-Signature=secret',
          signedUrlExpiresAt: DateTime.now().add(const Duration(minutes: 10)),
        ),
        _RecordingActions(),
      );
      for (final secret in [
        'http',
        'r2.example',
        'secret',
        'profiles/',
        'offer-plans',
        _mediaId,
        _recordId,
      ]) {
        expect(find.textContaining(secret), findsNothing, reason: secret);
      }
    });
  });

  group('View and Share', () {
    testWidgets('View opens exactly this plan of this record', (tester) async {
      final actions = _RecordingActions();
      await _show(tester, _plan(), actions, parent: PlanParent.owner);

      await tester.tap(find.byKey(_open));
      await tester.pump();
      expect(actions.calls, ['open owner $_recordId $_mediaId']);
    });

    testWidgets('Share shares exactly this plan of this record',
        (tester) async {
      final actions = _RecordingActions();
      await _show(tester, _plan(), actions);

      await tester.tap(find.byKey(_share));
      await tester.pump();
      expect(actions.calls, ['share offer $_recordId $_mediaId']);
    });

    testWidgets(
        'while one runs both are disabled and a second tap does nothing',
        (tester) async {
      final actions = _RecordingActions()..hold = Completer<void>();
      await _show(tester, _plan(), actions);
      expect(_enabled(tester, _open), isTrue);
      expect(_enabled(tester, _share), isTrue);

      await tester.tap(find.byKey(_open));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_enabled(tester, _open), isFalse);
      expect(_enabled(tester, _share), isFalse);

      await tester.tap(find.byKey(_share), warnIfMissed: false);
      await tester.tap(find.byKey(_open), warnIfMissed: false);
      await tester.pump();
      expect(actions.calls, hasLength(1));

      actions.hold!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_enabled(tester, _open), isTrue);
      expect(_enabled(tester, _share), isTrue);
    });
  });

  group('presentation', () {
    testWidgets('Arabic: Arabic labels, laid out right to left',
        (tester) async {
      await _show(tester, _plan(), _RecordingActions(),
          locale: const Locale('ar'));

      expect(find.text(_ar['planAttachmentTitle'] as String), findsOneWidget);
      expect(find.text(_ar['planAttachmentView'] as String), findsOneWidget);
      expect(find.text(_ar['share'] as String), findsOneWidget);
      expect(Directionality.of(tester.element(find.byKey(_card))),
          TextDirection.rtl);
    });

    testWidgets('a Word file in Arabic carries the Arabic note',
        (tester) async {
      await _show(
        tester,
        _plan(
          kind: PlanAttachmentKind.word,
          contentType: PlanContentTypes.docx,
          name: 'مخطط.docx',
        ),
        _RecordingActions(),
        locale: const Locale('ar'),
      );
      expect(find.text(_ar['planAttachmentOpensExternally'] as String),
          findsOneWidget);
      expect(find.text(_ar['planAttachmentOpen'] as String), findsOneWidget);
    });

    testWidgets('Dark theme renders every kind without an error',
        (tester) async {
      for (final plan in [
        _plan(),
        _plan(
          kind: PlanAttachmentKind.word,
          contentType: PlanContentTypes.docx,
        ),
        _plan(
          kind: PlanAttachmentKind.image,
          contentType: PlanContentTypes.png,
        ),
      ]) {
        await _show(tester, plan, _RecordingActions(), theme: ThemeData.dark());
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('on a narrow phone nothing overflows, in either language',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final locale in const [Locale('en'), Locale('ar')]) {
        await _show(
          tester,
          _plan(
            kind: PlanAttachmentKind.word,
            contentType: PlanContentTypes.docx,
            name: 'A very long plot plan file name for the Marina tower.docx',
          ),
          _RecordingActions(),
          locale: locale,
        );
        expect(tester.takeException(), isNull, reason: locale.languageCode);
      }
    });
  });
}
