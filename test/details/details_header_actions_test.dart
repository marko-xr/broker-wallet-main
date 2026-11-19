import 'dart:io';

import 'package:broker_wallet/src/common/data/room_count.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/details_page.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/details_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../responsive/responsive_harness.dart';

String _read(String path) => File(path).readAsStringSync();

class _Calls {
  int edit = 0;
  int delete = 0;
}

Widget _page(_Calls calls, {DateTime? createdAt, DateTime? updatedAt}) =>
    DetailsPage(
      title: 'Request Details',
      favorite: const Icon(Icons.favorite_border, key: ValueKey('fav')),
      onShare: () {},
      onEdit: () => calls.edit++,
      onDelete: () => calls.delete++,
      deleteLabel: 'Delete Request',
      onWhatsApp: null,
      onCall: null,
      scrollController: ScrollController(),
      fade: const AlwaysStoppedAnimation(1),
      slide: const AlwaysStoppedAnimation(0),
      contactFade: const AlwaysStoppedAnimation(1),
      content: (context) => DetailsFields(
        title: 'Request Requirements',
        rows: [
          const DetailsField(
              icon: Icons.sell_outlined, label: 'Request', value: 'Rent'),
          ...DetailsDates.fields(context,
              createdAt: createdAt, updatedAt: updatedAt),
        ],
      ),
    );

void main() {
  group('RoomCount', () {
    test('7 reads "7+", every other count as itself', () {
      expect(RoomCount.orMore, 7);
      expect(RoomCount.label(7), '7+');
      expect(RoomCount.label(1), '1');
      expect(RoomCount.label(6), '6');
      expect(RoomCount.label(0), '0');
      expect(RoomCount.label(9), '9');
    });

    test('the on-screen "7+" is kept left-to-right inside Arabic', () {
      expect(RoomCount.display(7), '\u20667+\u2069');
      expect(RoomCount.display(3), '3');
    });
  });

  group('DetailsDates.showsUpdate', () {
    final added = DateTime(2026, 11, 3, 9);
    test('no row for a save on the same day as the record was added', () {
      expect(
          DetailsDates.showsUpdate(added, DateTime(2026, 11, 3, 23)), isFalse);
      expect(DetailsDates.showsUpdate(added, added), isFalse);
    });
    test('a row for a change on a later day', () {
      expect(DetailsDates.showsUpdate(added, DateTime(2026, 11, 4, 1)), isTrue);
    });
    test('no row without an update time or with one before the add', () {
      expect(DetailsDates.showsUpdate(added, null), isFalse);
      expect(DetailsDates.showsUpdate(added, DateTime(2026, 11, 1)), isFalse);
    });
  });

  group('Details header', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await prepareResponsiveAssets();
    });

    for (final locale in const [Locale('en'), Locale('ar')]) {
      testWidgets(
          'Edit and Delete are in the header, after Favorite and Share '
          '(${locale.languageCode})', (tester) async {
        final calls = _Calls();
        await pumpResponsive(
            tester, ResponsiveCase(const Size(360, 780), locale: locale),
            home: _page(calls));

        final header = find.byType(SliverAppBar);
        final menu = find.byKey(const ValueKey('details-actions'));
        expect(find.descendant(of: header, matching: menu), findsOneWidget);
        expect(find.descendant(of: find.byType(DetailsFields), matching: menu),
            findsNothing,
            reason: 'the section card no longer carries the record menu');
        expect(
            find.descendant(of: menu, matching: find.byIcon(Icons.more_vert)),
            findsOneWidget);

        // Leading to trailing: Favorite, Share, then the menu at the edge.
        final fav = tester.getCenter(find.byKey(const ValueKey('fav'))).dx;
        final share = tester.getCenter(find.byIcon(Icons.share_outlined)).dx;
        final more = tester.getCenter(menu).dx;
        if (locale.languageCode == 'ar') {
          expect(fav > share && share > more, isTrue,
              reason: '$fav $share $more');
        } else {
          expect(fav < share && share < more, isTrue,
              reason: '$fav $share $more');
        }
        expect(tester.getSize(menu).shortestSide,
            greaterThanOrEqualTo(kMinInteractiveDimension));

        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('details-edit')));
        await tester.pumpAndSettle();
        expect(calls.edit, 1);

        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('details-delete')));
        await tester.pumpAndSettle();
        expect(calls.delete, 1);
        expectNoLayoutException(
            tester, ResponsiveCase(const Size(360, 780), locale: locale));
      });
    }

    testWidgets('the added date shows; the update date only on a later day',
        (tester) async {
      final calls = _Calls();
      const scenario = ResponsiveCase(Size(360, 780));
      await pumpResponsive(tester, scenario,
          home: _page(calls,
              createdAt: DateTime(2026, 11, 3, 9),
              updatedAt: DateTime(2026, 11, 3, 18)));
      final loc = AppLocalizations.of(
          tester.element(find.byKey(const ValueKey('details-date-added'))));
      expect(find.text(loc.translate('dateAdded')), findsOneWidget);
      expect(find.text('Nov 3, 2026'), findsOneWidget);
      expect(find.byKey(const ValueKey('details-last-updated')), findsNothing);

      await pumpResponsive(tester, scenario,
          home: _page(calls,
              createdAt: DateTime(2026, 11, 3, 9),
              updatedAt: DateTime(2026, 11, 18, 10)));
      expect(
          find.byKey(const ValueKey('details-last-updated')), findsOneWidget);
      expect(find.text(loc.translate('lastUpdated')), findsOneWidget);
      expect(find.text('Nov 18, 2026'), findsOneWidget);
    });

    testWidgets('no date rows when the record has no added date',
        (tester) async {
      await pumpResponsive(tester, const ResponsiveCase(Size(360, 780)),
          home: _page(_Calls()));
      expect(find.byKey(const ValueKey('details-date-added')), findsNothing);
      expect(find.byKey(const ValueKey('details-last-updated')), findsNothing);
    });
  });

  group('the six Details screens', () {
    const screens = {
      'offers': 'deleteOffer',
      'requested': 'deleteRequest',
      'owners': 'deleteOwner',
      'brokers': 'deleteBroker',
      'offices': 'deleteOffice',
      'watchmen': 'deleteWatchmen',
    };
    for (final MapEntry(key: name, value: deleteKey) in screens.entries) {
      final path =
          'lib/src/views/Screens/ViewDetails/${name}_view_details.dart';
      test('$name: one record menu, in the header, with its own Delete', () {
        final source = _read(path);
        expect(source.contains('PopupMenuButton'), isFalse,
            reason: 'no menu of its own inside a section');
        expect(source.contains("translate('$deleteKey')"), isTrue);
        if (name == 'offers') {
          expect(source.contains('DetailsActionsMenu('), isTrue);
        } else {
          expect(source.contains('onEdit: _edit'), isTrue);
          expect(source.contains('onDelete: _showDeleteConfirmation'), isTrue);
        }
      });
      test('$name: shows when the record was added', () {
        final source = _read(path);
        expect(
            source.contains('DetailsDates.fields(') ||
                source.contains('DetailsDates.format('),
            isTrue);
      });
    }

    test('no section repeats its screen title', () {
      for (final (screen, title, section) in const [
        ('brokers', 'brokerDetails', 'contactInformation'),
        ('offices', 'officeDetails', 'basicInformation'),
        ('owners', 'propertyOwner', 'basicInformation'),
        ('watchmen', 'watchmenDetails', 'basicInformation'),
        ('offers', 'propertyDetails', 'basicInformation'),
      ]) {
        final source = _read(
            'lib/src/views/Screens/ViewDetails/${screen}_view_details.dart');
        expect(
            RegExp("title: (Text\\()?loc\\.translate\\('$title'\\)")
                .hasMatch(source),
            isTrue,
            reason: '$screen: the header keeps its title');
        expect(
            RegExp("DetailsFields\\(\\s*title: loc\\.translate\\('$title'\\)")
                .hasMatch(source),
            isFalse,
            reason: '$screen: the section no longer repeats it');
        expect(source.contains("translate('$section')"), isTrue,
            reason: screen);
      }
    });

    test('Offer and Request status badges show they can be changed', () {
      for (final screen in ['offers', 'requested']) {
        final source = _read(
            'lib/src/views/Screens/ViewDetails/${screen}_view_details.dart');
        expect(source.contains('Icons.keyboard_arrow_down'), isTrue,
            reason: screen);
      }
    });
  });

  group('the add forms', () {
    String form(String name) =>
        _read('lib/src/views/Screens/ViewAdd/add_${name}_view.dart');

    test('each new-record title names the action', () {
      for (final (name, key) in const [
        ('offers', 'addOffer'),
        ('requested', 'addRequest'),
        ('owners', 'addOwner'),
        ('brokers', 'addBroker'),
        ('offices', 'addOffice'),
        ('watchmen', 'addWatchman'),
      ]) {
        expect(form(name).contains("'$key'"), isTrue, reason: name);
      }
      expect(form('owners').contains("'editOwner'"), isTrue,
          reason: 'editing an Owner says so, as the other forms do');
    });

    test('Offer and Request forms ask what, size, price, where, then contact',
        () {
      for (final (name, typeKey) in const [
        ('offers', 'typeOfOfferPropertiesAlt'),
        ('requested', 'typeOfRequestPropertiesAlt'),
      ]) {
        final source = form(name);
        final order = [
          typeKey,
          'numberOfRooms',
          'squareFootage',
          'priceRange',
          'selectTheCity',
          'phoneNumber',
          'notes',
        ].map((key) => source.indexOf(
            RegExp("_Label\\(\\s*localization\\s*\\.translate\\('$key'\\)")));
        expect(order.every((i) => i > 0), isTrue, reason: '$name $order');
        expect(order.toList(), [...order]..sort(), reason: name);
      }
    });

    test('rooms offer "7+" as their last choice; bathrooms stay 1 to 6', () {
      for (final name in ['offers', 'requested']) {
        final source = form(name);
        expect(
            RegExp(r'count: RoomCount\.orMore,\s*selected: vm\.rooms,\s*'
                    r'onSelect: vm\.selectRooms,\s*lastIsOrMore: true,')
                .hasMatch(source),
            isTrue,
            reason: name);
        expect(RegExp(r'count: 6,\s*selected: vm\.baths,').hasMatch(source),
            isTrue,
            reason: name);
      }
    });
  });
}
