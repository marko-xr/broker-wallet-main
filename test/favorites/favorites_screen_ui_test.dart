// The Favorites screen's look: laid out the way Search is — an avatar header,
// flat pinned filter chips, a two-column grid with the same spacing and card
// shape — and nothing between the chips and the cards: no counts and no sync
// pills.
//
// Source guards read the files; the widget tests build the reusable piece, the
// chips, with the real ARB text and Flutter's test font. They prove the layout
// rules, not how a device renders.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/app_control_sizes.dart';
import 'package:broker_wallet/src/data/models/filter_model.dart';
import 'package:broker_wallet/src/views/Screens/home/favorites/favorites_filter_chips.dart';
import 'package:broker_wallet/src/views/Screens/home/search/widgets/search_filter_chips.dart';
import 'package:broker_wallet/src/views/Widgets/home_filter_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// Builds [child] on a 412 dp wide screen in [locale].
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(412, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, page) => Directionality(
        textDirection:
            locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: page!,
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
  await tester.pumpAndSettle();
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
      // The padding is whatever Search's grid has (it clears the bottom bar),
      // so a change to one that misses the other fails here.
      final favoritesPadding = RegExp(
        r'const EdgeInsetsDirectional _gridPadding = EdgeInsetsDirectional\.fromSTEB\(([\d., ]+)\);',
      ).firstMatch(favoritesSquashed);
      final searchPadding = RegExp(
        r'SliverPadding\( padding: const EdgeInsetsDirectional\.fromSTEB\(([\d., ]+)\), sliver: SliverLayoutBuilder',
      ).firstMatch(_squash(search));
      expect(favoritesPadding, isNotNull, reason: 'Favorites\' grid padding');
      expect(searchPadding, isNotNull, reason: 'Search\'s grid padding');
      expect(favoritesPadding!.group(1), searchPadding!.group(1),
          reason: 'the two grids are padded the same');
      expect(
          favoritesSquashed
              .contains('padding: _gridPadding, sliver: SliverLayoutBuilder('),
          isTrue,
          reason: 'the cards use that padding');
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

    test('nothing sits between the chips and the cards', () {
      // No "total saved" / "visible now" counts and no "synced" pill: the same
      // number twice when no filter is chosen, and a status nobody needs.
      for (final gone in [
        'FavoritesStatusRow',
        'NumberFormat',
        'showSync',
        'CircularProgressIndicator',
      ]) {
        expect(favorites.contains(gone), isFalse, reason: gone);
      }
      expect(
          favoritesSquashed.contains(
              '_buildFilterBar(context, vm), ..._buildBodySlivers(context, vm, localization),'),
          isTrue,
          reason: 'the cards follow the chips directly');
      for (final code in ['en', 'ar']) {
        final table = json.decode(
          File('lib/src/common/localization/app_$code.arb').readAsStringSync(),
        ) as Map<String, dynamic>;
        for (final key in [
          'favoritesTotalCountLabel',
          'favoritesVisibleCountLabel',
          'favoritesSyncedChip',
          'favoritesSyncingChip',
        ]) {
          expect(table.containsKey(key), isFalse,
              reason: '$code keeps no string for the removed pills: $key');
        }
      }
    });

    test('the cards use the one grid, at the real width, with no skeleton', () {
      expect(
          RegExp(r'_favoritesGridDelegate\(').allMatches(favorites).length, 2,
          reason: 'its definition and the cards');
      expect(RegExp('SliverLayoutBuilder').allMatches(favorites).length, 1,
          reason: 'the cards get the real width');
      // The shimmer placeholders were replaced by the delayed loader.
      expect(favorites.contains('Skeleton'), isFalse);
      expect(favorites.contains('Shimmer'), isFalse);
    });

    test('the header is the one Home, Search and Favorites share', () {
      final header =
          _squash(_source('lib/src/views/Widgets/user_screen_header.dart'));
      expect(
          header.contains(
              "CurrentUserAvatar( size: avatarSize, onTap: () => context.push('/edit-profile'), )"),
          isTrue);
      expect(favorites.contains('class _Header'), isFalse,
          reason: 'its own copy is gone');
      expect(
          favoritesSquashed.contains(
              "UserScreenHeader( subtitle: localization.translate('favoritesOverviewTitle'), )"),
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
        '.onSurface.withValues(alpha: subtitleOpacity)',
        'const NotificationIcon()',
        'Provider.of<AuthViewModel>(context)',
      ]) {
        expect(header.contains(same), isTrue, reason: same);
      }
      // ...and Search draws the same widget, with its own line.
      expect(
          _squash(search).contains(
              "UserScreenHeader( subtitle: l.translate('searchHeaderSubtitle'), )"),
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
      // keep-alive per card (looked for in the cards' class only).
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
      // The greeting and the guest name are drawn by the shared header.
      final header = _source('lib/src/views/Widgets/user_screen_header.dart');
      for (final key in keys) {
        expect('$favorites\n$header'.contains("'$key'"), isTrue,
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
