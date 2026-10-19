import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broker_wallet/src/data/models/uae_links_catalogue.dart';
import 'package:broker_wallet/src/data/models/uae_links_model.dart';
import 'package:broker_wallet/src/services/uae_links/uae_link_launcher.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/uae_links_view.dart';

import 'uae_links_test_support.dart';

const String ejariId = 'dubai-ejari-register-renew';

class _Rig {
  final List<Uri> launched = [];
  final List<String> copied = [];
  final List<String> shared = [];
  bool launchSucceeds = true;
  bool launchThrows = false;
  bool copyThrows = false;
  bool shareThrows = false;

  Widget screen({Locale locale = const Locale('en'), ThemeData? theme}) {
    return uaeLinksApp(
      UAELinksView(
        launcher: UaeLinkLauncher(launch: (uri) async {
          if (launchThrows) throw StateError('no browser');
          launched.add(uri);
          return launchSucceeds;
        }),
        copyToClipboard: (value) async {
          if (copyThrows) throw StateError('clipboard');
          copied.add(value);
        },
        shareText: (value, subject) async {
          if (shareThrows) throw StateError('share');
          shared.add(value);
        },
        now: () => DateTime.utc(2026, 10, 19, 8, 30),
      ),
      locale: locale,
      theme: theme,
    );
  }
}

Future<void> search(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(const Key('uaeLinksSearchField')), query);
  await tester.pump();
}

Finder card(String id) => find.byKey(Key('uaeLink-$id'));

/// Scrolls the results list until [id]'s card is built.
Future<void> showCard(WidgetTester tester, String id) async {
  await tester.scrollUntilVisible(
    card(id),
    300,
    scrollable: find
        .descendant(
            of: find.byType(ListView), matching: find.byType(Scrollable))
        .first,
  );
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  // The list is lazy: a control scrolled far away is not built, so go back up.
  for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView), const Offset(0, 800));
    await tester.pump();
  }
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Future<int> shownCount(WidgetTester tester) async {
  final finder = find.byKey(const Key('uaeLinksResultCount'));
  for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView), const Offset(0, 800));
    await tester.pump();
  }
  final label = tester.widget<Text>(finder).data!;
  return int.parse(RegExp(r'[0-9]+').firstMatch(label)!.group(0)!);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final total = UAELinksData.published.length;

  setUpAll(() async => setUpUaeLinksWidgetTests(binding));

  testWidgets('shows the whole directory with the search and both filters',
      (tester) async {
    useScreen(tester);
    await tester.pumpWidget(_Rig().screen());
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('uaeLinksSearchField')), findsOneWidget);
    expect(find.byKey(const Key('uaeLinksEmirateChips')), findsOneWidget);
    expect(find.byKey(const Key('uaeLinksTaskChips')), findsOneWidget);
    expect(await shownCount(tester), total);
    expect(find.byKey(const Key('uaeLinksReset')), findsNothing);
    expect(find.text(text('ulxHeaderTitle')), findsOneWidget);
  });

  testWidgets('searching narrows the list and clearing restores it',
      (tester) async {
    useScreen(tester);
    await tester.pumpWidget(_Rig().screen());
    await tester.pump();
    await search(tester, 'ejari');

    expect(await shownCount(tester), lessThan(total));
    expect(await shownCount(tester), greaterThan(0));
    expect(card(ejariId), findsOneWidget);

    await tester.tap(find.byKey(const Key('uaeLinksSearchClear')));
    await tester.pump();
    expect(await shownCount(tester), total);
  });

  testWidgets('an Arabic search finds the service whatever the app language',
      (tester) async {
    useScreen(tester);
    await tester.pumpWidget(_Rig().screen());
    await tester.pump();
    await search(tester, 'إيجاري');
    expect(card(ejariId), findsOneWidget);
    // The card is in the app's English even though the search was Arabic.
    expect(find.text('Register or renew a tenancy contract (Ejari)'),
        findsOneWidget);
  });

  testWidgets('the emirate chip filters, and UAE-wide stays reachable',
      (tester) async {
    useScreen(tester);
    await tester.pumpWidget(_Rig().screen());
    await tester.pump();

    await tapKey(tester, 'uaeLinksEmirate-ajman');
    final ajman = UAELinksData.published
        .where((e) => e.emirates.contains(UaeLinkEmirate.ajman))
        .length;
    final federal = UAELinksData.published.where((e) => e.isFederal).length;
    expect(await shownCount(tester), ajman + federal);
    expect(find.byKey(const Key('uaeLinksReset')), findsOneWidget);

    await tapKey(tester, 'uaeLinksEmirate-uae');
    expect(await shownCount(tester), federal);
  });

  testWidgets('Tasdeeq appears under Ajman and has no Sharjah result',
      (tester) async {
    useScreen(tester);
    await tester.pumpWidget(_Rig().screen());
    await tester.pump();
    await search(tester, 'tasdeeq');
    await tapKey(tester, 'uaeLinksEmirate-sharjah');
    expect(find.byKey(const Key('uaeLinksEmpty')), findsOneWidget);

    await tapKey(tester, 'uaeLinksEmirate-ajman');
    await showCard(tester, 'ajman-tasdeeq-home');
    expect(card('ajman-tasdeeq-home'), findsOneWidget);
    expect(find.byKey(const Key('uaeLinksEmpty')), findsNothing);
  });

  testWidgets('the task chip filters and reset clears everything',
      (tester) async {
    useScreen(tester);
    await tester.pumpWidget(_Rig().screen());
    await tester.pump();

    await tapKey(tester, 'uaeLinksTask-utilities');
    final utilities = UAELinksData.published
        .where((e) => e.tasks.contains(UaeLinkTask.utilities))
        .length;
    expect(await shownCount(tester), utilities);

    await search(tester, 'dewa');
    await tapKey(tester, 'uaeLinksEmirate-dubai');
    expect(await shownCount(tester), lessThan(utilities));

    await tapKey(tester, 'uaeLinksReset');
    expect(await shownCount(tester), total);
    expect(find.byKey(const Key('uaeLinksReset')), findsNothing);
    final field =
        tester.widget<TextField>(find.byKey(const Key('uaeLinksSearchField')));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('no match shows a helpful empty state with a reset button',
      (tester) async {
    useScreen(tester);
    await tester.pumpWidget(_Rig().screen());
    await tester.pump();
    await search(tester, 'qzxwvnothing');

    expect(find.byKey(const Key('uaeLinksEmpty')), findsOneWidget);
    expect(find.text(text('noLinksFound')), findsOneWidget);
    expect(find.text(text('ulxEmptyHint')), findsOneWidget);
    expect(await shownCount(tester), 0);

    await tapKey(tester, 'uaeLinksEmptyReset');
    expect(find.byKey(const Key('uaeLinksEmpty')), findsNothing);
    expect(await shownCount(tester), total);
  });

  testWidgets('a card names the authority and what the service is',
      (tester) async {
    useScreen(tester);
    await tester.pumpWidget(_Rig().screen());
    await tester.pump();
    await search(tester, 'ejari');

    final ejari = card(ejariId);
    expect(
        find.descendant(
            of: ejari, matching: find.text('Dubai Land Department (DLD)')),
        findsOneWidget);
    expect(
        find.descendant(of: ejari, matching: find.text(text('ulxTypeAction'))),
        findsOneWidget);
    expect(
        find.descendant(
            of: ejari, matching: find.text(text('ulxLoginRequired'))),
        findsOneWidget);
  });

  testWidgets('a destination that needs a manual check says so',
      (tester) async {
    useScreen(tester);
    await tester.pumpWidget(_Rig().screen());
    await tester.pump();
    await search(tester, 'noqodi');
    expect(
        find.descendant(
            of: card('dubai-noqodi'),
            matching: find.text(text('ulxCheckOnSite'))),
        findsOneWidget);
    expect(
        find.descendant(
            of: card('dubai-noqodi'),
            matching: find.text(text('ulxTypePayment'))),
        findsOneWidget);
  });

  testWidgets('open hands the exact official address to the launcher',
      (tester) async {
    useScreen(tester);
    final rig = _Rig();
    await tester.pumpWidget(rig.screen());
    await tester.pump();
    await search(tester, 'ejari');

    await tapKey(tester, 'uaeLinkOpen-$ejariId');
    final entry = UAELinksData.published.firstWhere((e) => e.id == ejariId);
    expect(rig.launched.map((u) => u.toString()), [entry.url]);
    expect(find.byType(SnackBar), findsNothing,
        reason: 'opening a page is not a success to announce');
  });

  testWidgets('tapping the card body also opens it', (tester) async {
    useScreen(tester);
    final rig = _Rig();
    await tester.pumpWidget(rig.screen());
    await tester.pump();
    await search(tester, 'ejari');
    await tapKey(tester, 'uaeLinkOpenArea-$ejariId');
    expect(rig.launched, hasLength(1));
  });

  testWidgets('a failed launch shows an error and never a success',
      (tester) async {
    useScreen(tester);
    final rig = _Rig()..launchSucceeds = false;
    await tester.pumpWidget(rig.screen());
    await tester.pump();
    await search(tester, 'ejari');
    await tapKey(tester, 'uaeLinkOpen-$ejariId');
    await tester.pump();

    expect(find.text(text('ulxOpenFailed')), findsOneWidget);
    expect(find.text(text('linkCopiedToClipboard')), findsNothing);
  });

  testWidgets('a platform exception while opening is reported, not thrown',
      (tester) async {
    useScreen(tester);
    final rig = _Rig()..launchThrows = true;
    await tester.pumpWidget(rig.screen());
    await tester.pump();
    await search(tester, 'ejari');
    await tapKey(tester, 'uaeLinkOpen-$ejariId');
    await tester.pump();
    expect(find.text(text('ulxOpenFailed')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy puts the official address on the clipboard',
      (tester) async {
    useScreen(tester);
    final rig = _Rig();
    await tester.pumpWidget(rig.screen());
    await tester.pump();
    await search(tester, 'ejari');
    await tapKey(tester, 'uaeLinkCopy-$ejariId');
    await tester.pump();

    final entry = UAELinksData.published.firstWhere((e) => e.id == ejariId);
    expect(rig.copied, [entry.url]);
    expect(find.text(text('linkCopiedToClipboard')), findsOneWidget);
  });

  testWidgets('a failed copy shows an error, not "copied"', (tester) async {
    useScreen(tester);
    final rig = _Rig()..copyThrows = true;
    await tester.pumpWidget(rig.screen());
    await tester.pump();
    await search(tester, 'ejari');
    await tapKey(tester, 'uaeLinkCopy-$ejariId');
    await tester.pump();

    expect(find.text(text('ulxCopyFailed')), findsOneWidget);
    expect(find.text(text('linkCopiedToClipboard')), findsNothing);
  });

  group('report a broken link', () {
    Future<_Rig> openSheet(WidgetTester tester) async {
      useScreen(tester);
      final rig = _Rig();
      await tester.pumpWidget(rig.screen());
      await tester.pump();
      await search(tester, 'ejari');
      await tapKey(tester, 'uaeLinkReport-$ejariId');
      await tester.pumpAndSettle();
      return rig;
    }

    testWidgets('shows exactly the text that would be copied or shared',
        (tester) async {
      await openSheet(tester);
      expect(find.text(text('ulxReportTitle')), findsOneWidget);
      final preview = tester
          .widget<SelectableText>(find.byKey(const Key('uaeLinkReportPreview')))
          .data!;
      expect(preview, contains('Service ID: $ejariId'));
      expect(preview, contains('The link does not open'));
      expect(preview, contains('2026-10-19T08:30:00.000Z'));

      await tester
          .tap(find.byKey(const Key('uaeLinkIssue-wrongOrOutdatedPage')));
      await tester.pump();
      final changed = tester
          .widget<SelectableText>(find.byKey(const Key('uaeLinkReportPreview')))
          .data!;
      expect(changed, contains('The page is wrong or out of date'));
    });

    testWidgets('copy puts the report on the clipboard and nothing is sent',
        (tester) async {
      final rig = await openSheet(tester);
      await tester.tap(find.byKey(const Key('uaeLinkReportCopy')));
      await tester.pumpAndSettle();

      expect(rig.copied, hasLength(1));
      expect(rig.copied.single, contains('Service ID: $ejariId'));
      expect(rig.shared, isEmpty);
      expect(find.text(text('ulxReportCopied')), findsOneWidget);
    });

    testWidgets('share hands the report to the share sheet only on request',
        (tester) async {
      final rig = await openSheet(tester);
      expect(rig.shared, isEmpty);
      await tester.tap(find.byKey(const Key('uaeLinkReportShare')));
      await tester.pumpAndSettle();
      expect(rig.shared, hasLength(1));
      expect(rig.shared.single, contains('Service ID: $ejariId'));
      expect(rig.copied, isEmpty);
    });

    testWidgets('a failing share sheet is reported', (tester) async {
      final rig = await openSheet(tester);
      rig.shareThrows = true;
      await tester.tap(find.byKey(const Key('uaeLinkReportShare')));
      await tester.pumpAndSettle();
      expect(find.text(text('ulxReportShareFailed')), findsOneWidget);
    });

    testWidgets('a failing clipboard is reported', (tester) async {
      final rig = await openSheet(tester);
      rig.copyThrows = true;
      await tester.tap(find.byKey(const Key('uaeLinkReportCopy')));
      await tester.pumpAndSettle();
      expect(find.text(text('ulxReportCopyFailed')), findsOneWidget);
      expect(find.text(text('ulxReportCopied')), findsNothing);
    });
  });

  group('locale, direction and size', () {
    testWidgets('Arabic shows Arabic content, right to left', (tester) async {
      useScreen(tester);
      await tester.pumpWidget(_Rig().screen(locale: const Locale('ar')));
      await tester.pump();
      await tester.pump();

      final direction =
          Directionality.of(tester.element(find.byType(UAELinksView)));
      expect(direction, TextDirection.rtl);
      expect(find.text(text('ulxHeaderTitle', language: 'ar')), findsOneWidget);

      await search(tester, 'ejari');
      expect(find.text('تسجيل أو تجديد عقد إيجار (إيجاري)'), findsOneWidget);
      expect(find.text('دائرة الأراضي والأملاك في دبي'), findsWidgets);
      expect(find.text('Register or renew a tenancy contract (Ejari)'),
          findsNothing);
    });

    testWidgets('switching the language changes the texts', (tester) async {
      useScreen(tester);
      final rig = _Rig();
      await tester.pumpWidget(rig.screen());
      await tester.pump();
      await search(tester, 'ejari');
      expect(find.text('Register or renew a tenancy contract (Ejari)'),
          findsOneWidget);

      await tester.pumpWidget(rig.screen(locale: const Locale('ar')));

      await tester.pump();
      await tester.pump();
      expect(find.text('تسجيل أو تجديد عقد إيجار (إيجاري)'), findsOneWidget);
    });

    for (final language in ['en', 'ar']) {
      testWidgets(
          'a 320 px wide phone shows every card without overflow ($language)',
          (tester) async {
        useScreen(tester, width: 320, height: 640);
        await tester.pumpWidget(_Rig().screen(locale: Locale(language)));
        await tester.pump();
        await tester.pump();

        // Walk the whole list: building each row lays it out at 320 px.
        final list = find.byType(ListView);
        for (var i = 0; i < 60; i++) {
          await tester.drag(list, const Offset(0, -500));
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('dark theme renders the directory', (tester) async {
      useScreen(tester);
      await tester.pumpWidget(_Rig().screen(theme: ThemeData.dark()));
      await tester.pump();
      await tester.pump();
      await search(tester, 'noqodi');
      expect(card('dubai-noqodi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('larger text still fits a card', (tester) async {
      useScreen(tester, width: 320, height: 700);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_Rig().screen());
      await tester.pump();
      await tester.pump();
      await search(tester, 'ejari');
      await showCard(tester, ejariId);
      expect(card(ejariId), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the footer says the app only opens the official site',
      (tester) async {
    useScreen(tester);
    await tester.pumpWidget(_Rig().screen());
    await tester.pump();
    await search(tester, 'dewa');
    await tester.scrollUntilVisible(
      find.byKey(const Key('uaeLinksFooter')),
      300,
      scrollable: find
          .descendant(
              of: find.byType(ListView), matching: find.byType(Scrollable))
          .first,
    );
    final footer =
        tester.widget<Text>(find.byKey(const Key('uaeLinksFooter'))).data!;
    expect(footer, contains('does not sign in for you'));
    expect(footer, contains('2026-10-19'));
  });
}
