// Q-1a: the Quotations screen keeps the quotations it shows when a later
// read fails, as the six entity lists do. Before Q-1a a failed re-read put
// the load-error state in place of the list (a StreamBuilder drops its data
// on an error event).
//
// The real QuotationListView and QuotationListViewModel, with a service
// whose list stream the test drives.
import 'dart:async';
import 'dart:io';

import 'package:broker_wallet/src/Views/Screens/home/quotation/list_quotation_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/list_quotations_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/quotation_service.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/services/supabase_quotation_service.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:broker_wallet/src/views/Widgets/list_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _Quotations extends QuotationService {
  final StreamController<List<QuotationModel>> controller =
      StreamController<List<QuotationModel>>();
  int subscriptions = 0;

  @override
  Stream<List<QuotationModel>> getUserQuotations() {
    subscriptions++;
    return controller.stream;
  }
}

List<QuotationModel> _quotations(int n, {String prefix = 'Villa'}) => [
      for (var i = 0; i < n; i++)
        QuotationModel(
          id: 'q$i',
          userId: 'u1',
          propertyTitle: '$prefix $i',
          officeName: 'Realtig',
          totalAmount: 120000.0 + i,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
    ];

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final toasts = <String>[];

  setUpAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('PonnamKarthik/fluttertoast'),
      (call) async {
        if (call.method == 'showToast') {
          toasts.add((call.arguments as Map)['msg'] as String);
        }
        return true;
      },
    );
    await AppLocalizations.preloadAllLanguages();
  });

  setUp(toasts.clear);

  String t(String key) => AppLocalizations.translateFor('en', key)!;

  Future<_Quotations> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = _Quotations();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      theme: AppTheme.lightTheme,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: QuotationListView(
          viewModel: QuotationListViewModel(quotationService: source)),
    ));
    await tester.pump();
    return source;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a failed refresh keeps the shown quotations; no error state',
      (tester) async {
    final source = await open(tester);
    source.controller.add(_quotations(3));
    await settle(tester);
    expect(find.text('Villa 0'), findsOneWidget);

    source.controller
        .addError(const QuotationException(QuotationFailure.network));
    await settle(tester);

    expect(find.text('Villa 0'), findsOneWidget);
    expect(find.text('Villa 2'), findsOneWidget);
    expect(find.text(t('quotationListLoadFailed')), findsNothing);
    expect(find.byType(ListLoadingIndicator), findsNothing);
  });

  testWidgets('a failure before any list shows the existing error state',
      (tester) async {
    final source = await open(tester);
    source.controller.addError(const SocketException('offline'));
    await settle(tester);
    expect(find.text(t('quotationListLoadFailed')), findsOneWidget);
    expect(toasts, isEmpty, reason: 'the error state says it; no toast too');
  });

  testWidgets('a failed refresh is said once, with the existing toast',
      (tester) async {
    final source = await open(tester);
    source.controller.add(_quotations(3));
    await settle(tester);

    source.controller
        .addError(const QuotationException(QuotationFailure.network));
    await settle(tester);
    expect(toasts, [t('quotationListLoadFailed')]);

    // Further failures in the same run: not said again.
    source.controller
        .addError(const QuotationException(QuotationFailure.network));
    await settle(tester);
    expect(toasts, hasLength(1));
    expect(find.text('Villa 0'), findsOneWidget);

    // A successful read, then a new failure: said again.
    source.controller.add(_quotations(3));
    await settle(tester);
    source.controller
        .addError(const QuotationException(QuotationFailure.unknown));
    await settle(tester);
    expect(toasts, hasLength(2));
  });

  testWidgets('a refresh failing under another screen is not said there',
      (tester) async {
    final source = await open(tester);
    source.controller.add(_quotations(2));
    await settle(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Another screen')))));
    await tester.pumpAndSettle();

    source.controller
        .addError(const QuotationException(QuotationFailure.network));
    await settle(tester);
    expect(toasts, isEmpty);

    navigator.pop();
    await tester.pumpAndSettle();
    source.controller
        .addError(const QuotationException(QuotationFailure.network));
    await settle(tester);
    expect(toasts, [t('quotationListLoadFailed')],
        reason: 'not said yet, so the next failure on screen says it');
    expect(find.text('Villa 0'), findsOneWidget);
  });

  testWidgets('after a failure, the next list replaces what is shown',
      (tester) async {
    final source = await open(tester);
    source.controller.add(_quotations(2));
    await settle(tester);
    source.controller
        .addError(const QuotationException(QuotationFailure.unknown));
    await settle(tester);
    source.controller.add(_quotations(4, prefix: 'Office'));
    await settle(tester);
    expect(find.text('Villa 0'), findsNothing);
    expect(find.text('Office 3'), findsOneWidget);
  });

  testWidgets('an authoritative empty list shows the empty state',
      (tester) async {
    final source = await open(tester);
    source.controller.add(_quotations(2));
    await settle(tester);
    source.controller.add(const []);
    await settle(tester);
    expect(find.text('Villa 0'), findsNothing);
    expect(find.text(t('noQuotationsYet')), findsOneWidget);
  });

  testWidgets('a refresh shows no loader and subscribes once', (tester) async {
    final source = await open(tester);
    expect(find.byType(ListLoadingIndicator), findsOneWidget);
    source.controller.add(_quotations(3));
    await settle(tester);
    expect(find.byType(ListLoadingIndicator), findsNothing);
    source.controller.add(_quotations(3, prefix: 'Fresh'));
    await tester.pump();
    expect(find.byType(ListLoadingIndicator), findsNothing);
    await settle(tester);
    expect(find.text('Fresh 1'), findsOneWidget);
    expect(source.subscriptions, 1);
  });
}
