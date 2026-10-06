import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';
import 'package:broker_wallet/src/services/ScreenServices/owner_service.dart';
import 'package:broker_wallet/src/viewmodels/ListScreens/list_owners_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/ViewLists/owners_list_view.dart';
import 'package:broker_wallet/src/views/Widgets/list_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Owners list screen, as the on-screen representative of the six entity
/// lists (they share the list state and the delete progress): its loading
/// indicator can be seen, and deleting an Owner never blanks the screen.

class _Owners extends OwnerService {
  final StreamController<List<OwnerModel>> controller =
      StreamController<List<OwnerModel>>();
  int reads = 0;
  Future<void> Function() onDelete = () async {};

  @override
  Stream<List<OwnerModel>> getUserOwners() {
    reads++;
    return controller.stream;
  }

  @override
  Future<void> deleteOwner(String ownerId) => onDelete();
}

OwnerModel _owner(String id, String name) => OwnerModel(
      id: id,
      userId: 'u',
      name: name,
      phoneNumber: '',
      countryCode: '+971',
      typeOfProperties: '',
      propertyLocation: '',
      notes: '',
      pickUpLocation: '',
      pickUpLatitude: null,
      pickUpLongitude: null,
      pickUpAddress: '',
      uploadedFileName: '',
      mediaUrl: null,
      mediaUrls: const [],
      // This week, so the date separator needs no locale date data.
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('en'),
      theme: AppTheme.lightTheme,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );

final Finder _placeholder = find.byType(ListLoadingIndicator);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final toasts = <String>[];
  late Map<String, dynamic> en;

  setUpAll(() async {
    // Assets (the .arb files, icons and images) come from `flutter test`'s
    // own asset bundle, which also carries the asset manifest Image.asset
    // needs.
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
    en = json.decode(
      File('lib/src/common/localization/app_en.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  late _Owners service;
  late OwnersListViewModel vm;

  Future<void> openScreen(WidgetTester tester) async {
    toasts.clear();
    service = _Owners();
    await tester.pumpWidget(_app(OwnersListView(
      createViewModel: () => vm = OwnersListViewModel(ownerService: service),
    )));
    // One frame for the localizations to resolve, one for the screen.
    await tester.pump();
    await tester.pump();
  }

  Future<void> showOwners(WidgetTester tester, List<OwnerModel> owners) async {
    service.controller.add(owners);
    await tester.pump();
  }

  BuildContext screenContext(WidgetTester tester) =>
      tester.element(find.byType(OwnersListView));

  testWidgets(
      'a slow first list: no flash at first, then one centered indicator, never "no owners"',
      (tester) async {
    await openScreen(tester);

    expect(_placeholder, findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'a quick load must not flash a spinner');
    expect(find.text(en['noOwnersYet'] as String), findsNothing);

    await tester.pump(ListLoadingIndicator.defaultDelay);
    expect(
      find.descendant(
          of: _placeholder, matching: find.byType(CircularProgressIndicator)),
      findsOneWidget,
    );
    expect(find.text(en['noOwnersYet'] as String), findsNothing);
  });

  testWidgets('a list that arrives quickly never shows an indicator',
      (tester) async {
    await openScreen(tester);
    await showOwners(tester, [_owner('a', 'Alice')]);

    expect(_placeholder, findsNothing);
    await tester.pump(ListLoadingIndicator.defaultDelay * 2);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('an empty result shows the empty state', (tester) async {
    await openScreen(tester);
    await showOwners(tester, const []);

    expect(_placeholder, findsNothing);
    expect(find.text(en['noOwnersYet'] as String), findsOneWidget);
  });

  testWidgets('deleting one Owner keeps the screen and the other Owners',
      (tester) async {
    await openScreen(tester);
    await showOwners(tester, [_owner('a', 'Alice'), _owner('b', 'Bob')]);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);

    final remote = Completer<void>();
    service.onDelete = () => remote.future;
    final pending = vm.deleteOwner('a', screenContext(tester));
    await tester.pump();

    // While the server works: everything still on screen, one item marked.
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(_placeholder, findsNothing);
    expect(find.text(en['noOwnersYet'] as String), findsNothing);

    remote.complete();
    await pending;
    await tester.pump();

    expect(find.text('Alice'), findsNothing);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_placeholder, findsNothing);
    expect(toasts, ['Owner deleted successfully']);

    // The re-read after the delete updates the list in place.
    await showOwners(tester, [_owner('b', 'Bob')]);
    expect(find.text('Bob'), findsOneWidget);
    expect(_placeholder, findsNothing);
    expect(service.reads, 1);
  });

  testWidgets('a failed delete brings the Owner back and says so',
      (tester) async {
    await openScreen(tester);
    await showOwners(tester, [_owner('a', 'Alice'), _owner('b', 'Bob')]);

    service.onDelete = () async => throw Exception('offline');
    await vm.deleteOwner('a', screenContext(tester));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(toasts, ['Unable to delete the owner. Please try again.']);
  });

  testWidgets('deleting the last Owner shows the empty state', (tester) async {
    await openScreen(tester);
    await showOwners(tester, [_owner('a', 'Alice')]);

    await vm.deleteOwner('a', screenContext(tester));
    await tester.pump();

    expect(find.text('Alice'), findsNothing);
    expect(_placeholder, findsNothing);
    expect(find.text(en['noOwnersYet'] as String), findsOneWidget);
  });
}
