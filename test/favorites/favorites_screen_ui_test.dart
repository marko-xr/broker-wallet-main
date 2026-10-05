// The Favorites screen's look: laid out the way Search is — an avatar header,
// flat pinned filter chips, a two-column grid with the same spacing and card
// shape — with its own information (how many are saved, how many a filter shows,
// whether it is synced) kept, in the same pill style as Search's result count.
//
// Source guards read the files; the widget tests build the two reusable pieces,
// the chips and the status row, with the real ARB text and Flutter's test font.
// They prove the layout rules, not how a device renders.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/themes/app_theme.dart';
import 'package:broker_wallet/src/constants/app_control_sizes.dart';
import 'package:broker_wallet/src/data/models/filter_model.dart';
import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_filter_chips.dart';
import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_view.dart';
import 'package:broker_wallet/src/views/Screens/home/search/widgets/search_filter_chips.dart';
import 'package:broker_wallet/src/views/Widgets/home_filter_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
// Only the number formatter: `intl` has a `TextDirection` of its own, which
// would hide Flutter's.
import 'package:intl/intl.dart' show NumberFormat;

const List<String> _filterKeys = [
  'recentlyAdded',
  'requests',
  'offers',
  'owners',
  'offices',
  'watchmen',
  'brokers',
];

List<FilterModel> _filters({int? selected}) => [
      for (var i = 0; i < _filterKeys.length; i++)
        FilterModel(
          label: _filterKeys[i],
          labelKey: _filterKeys[i],
          selected: i == selected,
        ),
    ];

/// Builds [child] on a screen of [width] in [locale]. With [settle] false it
/// pumps a few fixed frames instead of waiting for the animations to end: a sync
/// spinner never ends, so `pumpAndSettle` would never return.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
  double width = 412,
  double textScale = 1,
  ThemeData? theme,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
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
      builder: (context, page) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: Directionality(
          textDirection: locale.languageCode == 'ar'
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: page!,
        ),
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: child,
          ),
        ),
      ),
    ),
  );
  // The localization delegates load asynchronously; nothing is drawn until they
  // finish.
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

String _t(String languageCode, String key) =>
    AppLocalizations.translateFor(languageCode, key)!;

String _source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// The same text with every run of white space made one space, so a check does
/// not depend on how the formatter wrapped a line.
String _squash(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

List<Rect> _chipRects(WidgetTester tester, Type of) => [
      for (var i = 0; i < _filterKeys.length; i++)
        tester.getRect(
          find
              .descendant(
                of: find.byType(of),
                matching: find.byType(AnimatedContainer),
              )
              .at(i),
        ),
    ];

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
    await AppLocalizations.preloadAllLanguages();
  });

  group('the filter chips are the app\'s chips', () {
    for (final entry in {
      'English': const Locale('en'),
      'Arabic (RTL)': const Locale('ar'),
    }.entries) {
      testWidgets('the same row, sizes and places as Home\'s, ${entry.key}',
          (tester) async {
        await _pump(
          tester,
          FavoriteFilterChips(filters: _filters(selected: 2), onToggle: (_) {}),
          locale: entry.value,
        );
        expect(
          find.descendant(
            of: find.byType(FavoriteFilterChips),
            matching: find.byType(HomeFilterChips),
          ),
          findsOneWidget,
        );
        final favorites = _chipRects(tester, FavoriteFilterChips);

        await _pump(
          tester,
          HomeFilterChips(filters: _filters(selected: 2), onToggle: (_) {}),
          locale: entry.value,
        );
        final home = _chipRects(tester, HomeFilterChips);

        expect(favorites, home);
        for (final rect in favorites) {
          expect(rect.height, AppControlSizes.compactChipHeight);
        }
      });
    }

    testWidgets('the row is as tall as Search\'s, so the bar fits it',
        (tester) async {
      late double normal;
      late double large;
      late double search;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (context) {
            normal = FavoriteFilterChips.rowHeightOf(context);
            search = FilterChips.rowHeightOf(context);
            return const SizedBox.shrink();
          }),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Builder(builder: (context) {
              large = FavoriteFilterChips.rowHeightOf(context);
              return const SizedBox.shrink();
            }),
          ),
        ),
      );
      expect(normal, AppControlSizes.minTouchTarget);
      expect(normal, search);
      expect(large, greaterThan(normal));
    });

    testWidgets('a tap reports the chip\'s own index', (tester) async {
      final toggled = <int>[];
      await _pump(
        tester,
        FavoriteFilterChips(filters: _filters(), onToggle: toggled.add),
      );
      for (final i in [0, 3, 6]) {
        final label = _t('en', _filterKeys[i]);
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      expect(toggled, [0, 3, 6]);
    });
  });

  group('the status row', () {
    for (final entry in {
      'English': const Locale('en'),
      'Arabic (RTL)': const Locale('ar'),
    }.entries) {
      final code = entry.value.languageCode;
      final rtl = code == 'ar';

      testWidgets(
          'says how many are saved and how many are shown, '
          '${entry.key}', (tester) async {
        await _pump(
          tester,
          const FavoritesStatusRow(
            total: 12,
            visible: 5,
            showSync: false,
            isRefreshing: false,
          ),
          locale: entry.value,
          // Wide enough for both pills to share a line even in the test font,
          // whose letters are a full em wide (the two need about 426 dp there;
          // on a phone, in a real font, they are far narrower). At 412 dp they
          // would wrap, which says nothing about the order they are read in.
          width: 700,
        );
        expect(find.text(_t(code, 'favoritesTotalCountLabel')), findsOneWidget);
        expect(
            find.text(_t(code, 'favoritesVisibleCountLabel')), findsOneWidget);
        expect(find.text(NumberFormat.compact(locale: code).format(12)),
            findsOneWidget);
        expect(find.text(NumberFormat.compact(locale: code).format(5)),
            findsOneWidget);
        // Nothing to sync: no sync pill.
        expect(find.text(_t(code, 'favoritesSyncedChip')), findsNothing);
        expect(find.text(_t(code, 'favoritesSyncingChip')), findsNothing);

        // They are read in order, the first at the reading edge: on the left in
        // English, on the right in Arabic.
        final total =
            tester.getRect(find.text(_t(code, 'favoritesTotalCountLabel')));
        final visible =
            tester.getRect(find.text(_t(code, 'favoritesVisibleCountLabel')));
        expect((total.top - visible.top).abs(), lessThan(1),
            reason: 'at this width both pills sit on one line');
        if (rtl) {
          expect(total.right, greaterThan(visible.right));
        } else {
          expect(total.left, lessThan(visible.left));
        }
      });
    }

    testWidgets('says whether it is syncing or synced', (tester) async {
      await _pump(
        tester,
        const FavoritesStatusRow(
          total: 3,
          visible: 3,
          showSync: true,
          isRefreshing: true,
        ),
        settle: false,
      );
      expect(find.text(_t('en', 'favoritesSyncingChip')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(_t('en', 'favoritesSyncedChip')), findsNothing);

      await _pump(
        tester,
        const FavoritesStatusRow(
          total: 3,
          visible: 3,
          showSync: true,
          isRefreshing: false,
        ),
      );
      expect(find.text(_t('en', 'favoritesSyncedChip')), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(_t('en', 'favoritesSyncingChip')), findsNothing);
    });

    for (final mode in ['light', 'dark']) {
      testWidgets('the pills are Search\'s result-count pill, $mode',
          (tester) async {
        final theme =
            mode == 'light' ? AppTheme.lightTheme : AppTheme.darkTheme;
        await _pump(
          tester,
          const FavoritesStatusRow(
            total: 12,
            visible: 5,
            showSync: true,
            isRefreshing: false,
          ),
          theme: theme,
        );
        final pills = tester
            .widgetList<Container>(find.descendant(
              of: find.byType(FavoritesStatusRow),
              matching: find.byWidgetPredicate((widget) =>
                  widget is Container &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration! as BoxDecoration).borderRadius ==
                      BorderRadius.circular(999)),
            ))
            .toList();
        expect(pills, hasLength(3), reason: 'saved, shown and synced');
        for (final pill in pills) {
          final decoration = pill.decoration! as BoxDecoration;
          expect(decoration.color,
              theme.colorScheme.primary.withValues(alpha: 0.08));
          expect((decoration.border! as Border).top.color,
              theme.colorScheme.primary.withValues(alpha: 0.15));
          expect(pill.padding,
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6));
        }
      });
    }

    testWidgets('wraps onto a second line instead of overflowing',
        (tester) async {
      await _pump(
        tester,
        const FavoritesStatusRow(
          total: 1200,
          visible: 30,
          showSync: true,
          isRefreshing: true,
        ),
        width: 320,
        textScale: 1.6,
        settle: false,
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(FavoritesStatusRow)).width,
          lessThanOrEqualTo(320 - 32));
    });
  });

  // --- source guards (read files only) -------------------------------------
  group('the page is laid out the way Search is', () {
    final favorites =
        _source('lib/src/views/Screens/home/favorites/favorites_view.dart');
    final search =
        _source('lib/src/views/Screens/home/search/search_view.dart');
    final favoritesSquashed = _squash(favorites);

    num numberAfter(String source, String pattern) {
      final match = RegExp(pattern).firstMatch(source);
      expect(match, isNotNull, reason: pattern);
      return num.parse(match!.group(1)!);
    }

    test('the grid has Search\'s columns, spacing and card shape', () {
      expect(numberAfter(favorites, r'const int _gridColumns = (\d+);'),
          numberAfter(search, r'static const int _columns = (\d+);'));
      expect(numberAfter(favorites, r'const double _gridSpacing = ([\d.]+);'),
          numberAfter(search, r'static const double _gridSpacing = ([\d.]+);'));
      expect(
          numberAfter(
              favorites, r'const double _gridCardAspectRatio = ([\d.]+);'),
          numberAfter(
              search, r'static const double _cardAspectRatio = ([\d.]+);'));
      expect(
          favoritesSquashed.contains(
              'const EdgeInsetsDirectional _gridPadding = EdgeInsetsDirectional.fromSTEB(16, 8, 16, 20);'),
          isTrue);
      expect(
          _squash(search).contains(
              'padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 20)'),
          isTrue,
          reason: 'Search\'s own grid padding, which this must equal');
    });

    test('and its minimum height, so no card cuts a field off', () {
      expect(favoritesSquashed.contains('mainAxisExtent: extent'), isTrue);
      expect(
          favoritesSquashed
              .contains('SearchResultCard.minHeightForText(context)'),
          isTrue);
      expect(favoritesSquashed.contains('cardWidth / _gridCardAspectRatio'),
          isTrue);
      expect(favorites.contains('childAspectRatio'), isFalse,
          reason: 'the old fixed shape');
    });

    test('the skeleton and the cards use the one grid', () {
      expect(
          RegExp(r'_favoritesGridDelegate\(').allMatches(favorites).length, 3,
          reason: 'its definition, the skeleton and the cards');
      expect(RegExp('SliverLayoutBuilder').allMatches(favorites).length, 2,
          reason: 'the skeleton and the cards each get the real width');
    });

    test('the header is the avatar, greeting and bell Search and Home have',
        () {
      expect(
          favoritesSquashed.contains(
              "CurrentUserAvatar( size: 48, onTap: () => context.push('/edit-profile'), )"),
          isTrue);
      // The rounded-square 56 dp avatar and the hero card are gone.
      expect(favorites.contains('BorderRadius.circular(18)'), isFalse);
      expect(favorites.contains('size: 56'), isFalse);
      expect(favorites.contains('_buildHeaderCard'), isFalse);
      expect(favorites.contains('LinearGradient'), isFalse);
      expect(favorites.contains('BoxShadow'), isFalse);
      expect(favorites.contains('DecoratedBox'), isFalse,
          reason: 'no gradient page and no panel');
      for (final same in [
        'AnimatedSwitcher( duration: const Duration(milliseconds: 300)',
        'style: textTheme.headlineSmall',
        '.onSurface.withValues(alpha: 0.6)',
        'const NotificationIcon()',
        'Provider.of<AuthViewModel>(context)',
      ]) {
        expect(favoritesSquashed.contains(same), isTrue, reason: same);
      }
      // ...with the same pieces in Search's header.
      final searchSquashed = _squash(search);
      expect(searchSquashed.contains('size: 48'), isTrue);
      expect(searchSquashed.contains('const NotificationIcon()'), isTrue);
      expect(
          searchSquashed.contains(
              'AnimatedSwitcher( duration: const Duration(milliseconds: 300)'),
          isTrue);
    });

    test('the filters are flat and pinned, as on Search', () {
      for (final same in [
        'SliverAppBar( pinned: true',
        'automaticallyImplyLeading: false',
        'elevation: 0',
        'scrolledUnderElevation: 0',
        'shadowColor: Colors.transparent',
        'surfaceTintColor: Colors.transparent',
        'backgroundColor: Theme.of(context).scaffoldBackgroundColor',
        'toolbarHeight: FavoriteFilterChips.rowHeightOf(context)',
      ]) {
        expect(favoritesSquashed.contains(same), isTrue, reason: same);
        expect(
            _squash(search).contains(same.replaceAll(
                'FavoriteFilterChips.rowHeightOf', 'FilterChips.rowHeightOf')),
            isTrue,
            reason: 'Search has it too: $same');
      }
      // The panel the chips used to sit in is gone.
      expect(favorites.contains('_buildFilterBackdrop'), isFalse);
      expect(favorites.contains('BorderRadius.circular(24)'), isFalse);
    });

    test('the scroll view has no oddities of its own', () {
      expect(
          favoritesSquashed.contains(
              'scrollCacheExtent: const ScrollCacheExtent.pixels(1200)'),
          isTrue);
      expect(favorites.contains(' cacheExtent:'), isFalse,
          reason: 'the deprecated parameter');
      expect(favorites.contains('displacement:'), isFalse);
      expect(favorites.contains('edgeOffset:'), isFalse);
      expect(favoritesSquashed.contains('onRefresh: vm.refresh'), isTrue);
    });

    test('what the screen does with the list is as it was', () {
      for (final kept in [
        'onRemoveFromFavorites: vm.removeFavorite',
        'isLoadingMore: vm.isRefreshing',
        'vm.updateLocalization(localization)',
      ]) {
        expect(favoritesSquashed.contains(kept), isTrue, reason: kept);
      }
      // The cards' own grid: image prefetching, one key per favorite, no
      // keep-alive per card. (The skeleton has the same two flags, so look in
      // the cards' class only.)
      final cards = favoritesSquashed.substring(
        favoritesSquashed.indexOf('class _OptimizedFavoritesGridState'),
      );
      for (final kept in [
        'AutomaticKeepAliveClientMixin',
        'prefetchImages(',
        "key: ValueKey('\${favorite.type}_\${favorite.id}')",
        'addAutomaticKeepAlives: false',
        'addRepaintBoundaries: true',
      ]) {
        expect(cards.contains(kept), isTrue, reason: kept);
      }
    });

    test('the foot of the list clears the docked add button', () {
      // The button is 56 dp and rises about 28 dp into the page; the loading
      // text and the refresh hint, which end the page, keep 56 dp below them.
      expect(
          RegExp(r'EdgeInsetsDirectional\.fromSTEB\(16, 0, 16, 56\)')
              .hasMatch(favoritesSquashed),
          isTrue,
          reason: 'the refresh hint');
      expect(favoritesSquashed.contains('EdgeInsets.fromLTRB(16, 24, 16, 56)'),
          isTrue,
          reason: 'the loading text');
    });

    test('a failure is told in the app\'s words, never as a raw error', () {
      expect(favorites.contains('vm.error!'), isFalse);
      expect(favorites.contains(r'$e'), isFalse);
      expect(favorites.contains('toString()'), isFalse);
      for (final same in [
        'Icons.error_outline',
        'ElevatedButton(',
        "localization.translate('favoritesErrorTitle')",
        "localization.translate('favoritesErrorAction')",
      ]) {
        expect(favorites.contains(same), isTrue, reason: same);
      }
    });

    test('a filter that hides everything can be cleared, as on Search', () {
      expect(
          favoritesSquashed
              .contains('vm.toggleFilter(vm.filters.indexOf(selectedFilter))'),
          isTrue);
      expect(favorites.contains("translate('clearFilter')"), isTrue);
    });

    test('every string the screen shows is still there, in both languages', () {
      final english = json.decode(
        File('lib/src/common/localization/app_en.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      final arabic = json.decode(
        File('lib/src/common/localization/app_ar.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      const keys = [
        'hiGreeting',
        'favoritesGuestUser',
        'favoritesOverviewTitle',
        'favoritesTotalCountLabel',
        'favoritesVisibleCountLabel',
        'favoritesSyncingChip',
        'favoritesSyncedChip',
        'favoritesRefreshHint',
        'favoritesLoadingPrimary',
        'favoritesLoadingSecondary',
        'favoritesErrorTitle',
        'favoritesErrorAction',
        'noFavoritesYet',
        'tapHeartToSave',
        'favoritesFilterEmptyTitlePrefix',
        'favoritesFilterEmptyFallback',
        'favoritesFilterEmptySubtitle',
        'clearFilter',
      ];
      for (final key in keys) {
        expect(favorites.contains("'$key'"), isTrue,
            reason: '$key is shown by the screen');
        expect((english[key] as String?)?.trim(), isNotEmpty,
            reason: 'en $key');
        expect((arabic[key] as String?)?.trim(), isNotEmpty, reason: 'ar $key');
      }
    });

    test('the chips are the shared ones, drawn by nothing here', () {
      final chips = _source(
          'lib/src/views/Screens/home/favorites/favorites_filter_chips.dart');
      expect(
          chips.contains(
              'HomeFilterChips(filters: filters, onToggle: onToggle)'),
          isTrue);
      for (final own in [
        'BoxDecoration',
        'InkWell',
        'fontSize',
        'Colors.',
        '.red'
      ]) {
        expect(chips.contains(own), isFalse, reason: 'no `$own` of its own');
      }
      expect(favorites.contains('FavoriteFilterChips('), isTrue);
    });
  });
  // --- end source guards ---------------------------------------------------
}
