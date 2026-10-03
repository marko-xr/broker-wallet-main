// The results side of Search: highlighted text (it marks what the search matched
// and follows the system text size), the result card's room for its text on
// narrow phones and with large fonts, and guards on the screen's own source for
// what cannot be pumped without the app's providers: the four distinct states,
// that no technical error reaches a person, navigation, and that Search only
// ever reads the signed-in user's own records.
//
// Local widget and source tests; they prove the layout rules and the wiring, not
// how the screens look on a device.

import 'dart:convert';
import 'dart:io';

import 'package:broker_wallet/src/utils/text_highlighter.dart';
import 'package:broker_wallet/src/views/Screens/home/search/widgets/search_result_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

const _view = 'lib/src/views/Screens/home/search/search_view.dart';
const _viewModel = 'lib/src/views/Screens/home/search/search_viewmodel.dart';
const _dataSource = 'lib/src/views/Screens/home/search/search_data_source.dart';
const _bar = 'lib/src/views/Screens/home/search/widgets/search_bar.dart';
const _hints =
    'lib/src/views/Screens/home/search/widgets/animated_search_hints.dart';
const _chips =
    'lib/src/views/Screens/home/search/widgets/search_filter_chips.dart';
const _card =
    'lib/src/views/Screens/home/search/widgets/search_result_card.dart';

Future<void> _pumpApp(
  WidgetTester tester,
  Widget child, {
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
}) {
  return tester.pumpWidget(
    MaterialApp(
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: Directionality(textDirection: direction, child: inner!),
      ),
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );
}

/// Every leaf text span under [root], with its style.
List<TextSpan> _leaves(InlineSpan root) {
  final spans = <TextSpan>[];
  root.visitChildren((span) {
    if (span is TextSpan && (span.text ?? '').isNotEmpty) spans.add(span);
    return true;
  });
  return spans;
}

/// The texts that carry a highlight background, in order.
List<String> _highlighted(WidgetTester tester) {
  final rich = tester.widget<RichText>(find.byType(RichText).first);
  return [
    for (final span in _leaves(rich.text))
      if (span.style?.backgroundColor != null) span.text!,
  ];
}

void main() {
  group('highlighted text marks what matched', () {
    const style = TextStyle(fontSize: 14);

    testWidgets('a word, in any case', (tester) async {
      await _pumpApp(
        tester,
        TextHighlighter.searchHighlight('Dubai Marina', 'DUBAI', style: style),
      );
      expect(_highlighted(tester), ['Dubai']);
    });

    testWidgets('every word of a multi-word query', (tester) async {
      await _pumpApp(
        tester,
        TextHighlighter.searchHighlight(
          'Villa in Dubai Marina',
          'villa marina',
          style: style,
        ),
      );
      expect(_highlighted(tester), ['Villa', 'Marina']);
    });

    testWidgets('Arabic however it was typed, marking the original word',
        (tester) async {
      await _pumpApp(
        tester,
        TextHighlighter.searchHighlight('مُحَمَّد علي', 'مـحـمـد',
            style: style),
        direction: TextDirection.rtl,
      );
      expect(_highlighted(tester), ['مُحَمَّد']);
    });

    testWidgets('Alef variants and Arabic-Indic digits', (tester) async {
      await _pumpApp(
        tester,
        TextHighlighter.searchHighlight('أحمد 055 123', 'احمد ٠٥٥',
            style: style),
        direction: TextDirection.rtl,
      );
      expect(_highlighted(tester), ['أحمد', '055']);
    });

    testWidgets('a phone number across its formatting', (tester) async {
      await _pumpApp(
        tester,
        TextHighlighter.searchHighlight('050-123 4567', '0501234567',
            style: style),
      );
      expect(_highlighted(tester), ['050-123 4567']);
    });

    testWidgets('nothing matched, nothing highlighted', (tester) async {
      await _pumpApp(
        tester,
        TextHighlighter.searchHighlight('Dubai Marina', 'zzz', style: style),
      );
      expect(find.text('Dubai Marina'), findsOneWidget);
      expect(find.byType(RichText), findsWidgets);
      final rich = tester.widget<RichText>(find.byType(RichText).first);
      expect(
        _leaves(rich.text).where((s) => s.style?.backgroundColor != null),
        isEmpty,
      );
    });

    testWidgets('an empty query highlights nothing', (tester) async {
      await _pumpApp(
        tester,
        TextHighlighter.searchHighlight('Dubai', '   ', style: style),
      );
      expect(find.text('Dubai'), findsOneWidget);
    });

    testWidgets('the matched text keeps its characters exactly',
        (tester) async {
      const text = 'Arabian Ranches 3, Dubai';
      await _pumpApp(
        tester,
        TextHighlighter.searchHighlight(text, 'ranches 3', style: style),
      );
      final rich = tester.widget<RichText>(find.byType(RichText).first);
      final joined = _leaves(rich.text).map((s) => s.text).join();
      expect(joined, text, reason: 'highlighting never edits the text');
    });
  });

  group('highlighted text follows the system text size', () {
    testWidgets('it scales like plain text does', (tester) async {
      Widget highlighted() => TextHighlighter.searchHighlight(
            'Dubai Marina',
            'dubai',
            style: const TextStyle(fontSize: 14),
          );

      await _pumpApp(tester, highlighted(), textScale: 1);
      final normal = tester.getSize(find.byType(Text).first).width;
      await _pumpApp(tester, highlighted(), textScale: 2);
      final large = tester.getSize(find.byType(Text).first).width;

      expect(large, greaterThan(normal * 1.8));
    });

    testWidgets('the text carries the chosen scale', (tester) async {
      await _pumpApp(
        tester,
        TextHighlighter.searchHighlight(
          'Dubai Marina',
          'dubai',
          style: const TextStyle(fontSize: 14),
        ),
        textScale: 1.5,
      );
      final rich = tester.widget<RichText>(find.byType(RichText).first);
      expect(rich.textScaler.scale(10), closeTo(15, 0.001));
    });

    testWidgets('one line, cut with an ellipsis, never wrapped',
        (tester) async {
      await _pumpApp(
        tester,
        SizedBox(
          width: 120,
          child: TextHighlighter.searchHighlight(
            'A very long property description that cannot fit',
            'property',
            style: const TextStyle(fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
      final size = tester.getSize(find.byType(Text).first);
      expect(size.height, lessThan(30));
      expect(tester.takeException(), isNull);
    });
  });

  group('a result card has room for its text', () {
    // The card's own layout: width of a column on a phone, and the old fixed
    // 3 : 4 shape.
    double columnWidth(double screen) => (screen - 32 - 12) / 2;
    double byRatio(double screen) => columnWidth(screen) / 0.75;

    Future<double> minHeight(WidgetTester tester, double scale) async {
      late double value;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Builder(builder: (context) {
              value = SearchResultCard.minHeightForText(context);
              return const SizedBox.shrink();
            }),
          ),
        ),
      );
      return value;
    }

    testWidgets('at normal text the 3 : 4 shape already has room',
        (tester) async {
      final needed = await minHeight(tester, 1);
      expect(needed, closeTo(202.4, 0.5));
      for (final screen in [360.0, 393.0, 412.0, 600.0]) {
        expect(needed, lessThanOrEqualTo(byRatio(screen)),
            reason: '$screen px keeps its shape');
      }
    });

    testWidgets('on a 320 px phone the old fixed shape was too short',
        (tester) async {
      final needed = await minHeight(tester, 1);
      expect(byRatio(320), lessThan(needed),
          reason: 'it would have cut the third field off');
      // The list now gives the card at least what it needs.
      expect(needed > byRatio(320), isTrue);
    });

    testWidgets('a larger system font needs a taller card', (tester) async {
      final normal = await minHeight(tester, 1);
      final bigger = await minHeight(tester, 1.3);
      final largest = await minHeight(tester, 2);
      expect(bigger, greaterThan(normal));
      expect(largest, greaterThan(bigger));
      expect(bigger, greaterThan(byRatio(360)),
          reason: 'at 1.3x the fixed shape was already too short');
    });

    testWidgets('three fields at the larger size fit in the content area',
        (tester) async {
      for (final scale in [1.0, 1.3, 1.6, 2.0]) {
        final needed = await minHeight(tester, scale);
        // The content area is 4/9 of the card inside its margin and border; it
        // holds 14 padding, three fields of at least the text line, two gaps.
        final content = (needed - 2 * (1.2 + 1)) * 4 / 9;
        final line = (12 * scale * 1.33).clamp(16.0, double.infinity);
        expect(content + 0.01, greaterThanOrEqualTo(28 + 3 * line + 12),
            reason: 'scale $scale');
      }
    });

    test('the list gives each card at least that, over its own shape', () {
      final source = _read(_view);
      expect(source.contains('SearchResultCard.minHeightForText(context)'),
          isTrue);
      expect(source.contains('mainAxisExtent: extent'), isTrue);
      expect(source.contains('childAspectRatio'), isFalse,
          reason: 'a fixed ratio is what overflowed');
      expect(source.contains('math.max('), isTrue);
    });
  });

  group('the screen\'s states are distinct', () {
    final source = _read(_view);
    // Just the method that chooses the state: from its definition to the next
    // member, so the widgets that come after it are not part of the search.
    final start = source.indexOf('List<Widget> _contentSlivers(');
    final content = source.substring(
      start,
      source.indexOf('static const int _columns'),
    );

    test('loading, error, starting, no results and results, in that order', () {
      final order = [
        content.indexOf('vm.isLoading'),
        content.indexOf('vm.errorKind'),
        content.indexOf('!vm.hasQuery || !vm.hasAnswer'),
        content.indexOf('!vm.hasResults'),
        content.indexOf('vm.searchResults'),
      ];
      expect(order.every((i) => i >= 0), isTrue, reason: '$order');
      expect([...order]..sort(), order, reason: 'checked in this order');
    });

    test('"no results" is only shown for a question that was answered', () {
      expect(content.contains('!vm.hasAnswer'), isTrue);
      expect(content.contains("l.translate('noResults')"), isFalse,
          reason:
              'the text is inside _NoResults, reached only after hasAnswer');
      expect(source.contains("title: l.translate('noResults')"), isTrue);
    });

    test('a filter that hides everything offers to clear it', () {
      expect(source.contains("l.translate('clearFilter')"), isTrue);
      expect(source.contains('onClearFilter'), isTrue);
    });

    test('the results label names the query the results answer', () {
      expect(source.contains('vm.resultsQuery'), isTrue);
      expect(source.contains('\${vm.query}'), isFalse,
          reason: 'the live text can be ahead of the results');
    });
  });

  group('no technical error reaches a person', () {
    final view = _read(_view);
    final model = _read(_viewModel);

    test('the view shows a message chosen from the failure KIND', () {
      expect(view.contains('SearchErrorKind.network'), isTrue);
      expect(view.contains('SearchErrorKind.session'), isTrue);
      expect(view.contains('SearchErrorKind.generic'), isTrue);
      expect(view.contains('errorKind'), isTrue);
    });

    test('nothing shows an exception\'s text', () {
      for (final path in [
        _view,
        _viewModel,
        _dataSource,
        _chips,
        _bar,
        _hints
      ]) {
        final source = _read(path);
        expect(source.contains('Search failed'), isFalse, reason: path);
        expect(RegExp(r'\be\.toString\(\)').hasMatch(source), isFalse,
            reason: path);
        expect(RegExp(r"'\$\{?(e|error|err)\b").hasMatch(source), isFalse,
            reason: path);
        expect(source.contains('error.message'), path == _viewModel,
            reason: '$path: only the classifier reads a message, to sort it');
      }
    });

    test('the view-model keeps a kind, not a message', () {
      expect(model.contains('SearchErrorKind? errorKind'), isTrue);
      expect(RegExp(r'String\? error\b').hasMatch(model), isFalse);
    });

    test('the messages are existing, localized strings', () {
      final en = json.decode(
        _read('lib/src/common/localization/app_en.arb'),
      ) as Map<String, dynamic>;
      final ar = json.decode(
        _read('lib/src/common/localization/app_ar.arb'),
      ) as Map<String, dynamic>;
      for (final key in [
        'authNetworkFailed',
        'userSessionExpired',
        'errorOccurred',
        'tryAgain',
      ]) {
        expect(view.contains("'$key'"), isTrue, reason: key);
        expect(en[key], isA<String>(), reason: 'en $key');
        expect(ar[key], isA<String>(), reason: 'ar $key');
      }
    });

    test('every string the Search screen asks for exists in both languages',
        () {
      final en = json.decode(
        _read('lib/src/common/localization/app_en.arb'),
      ) as Map<String, dynamic>;
      final ar = json.decode(
        _read('lib/src/common/localization/app_ar.arb'),
      ) as Map<String, dynamic>;
      final keys = <String>{};
      for (final path in [_view, _chips, _bar, _hints]) {
        keys.addAll(
          RegExp(r"translate\('([A-Za-z0-9_]+)'\)")
              .allMatches(_read(path))
              .map((m) => m.group(1)!),
        );
      }
      for (final match
          in RegExp(r"labelKey: '([A-Za-z0-9_]+)'").allMatches(model)) {
        keys.add(match.group(1)!);
      }
      expect(keys, isNotEmpty);
      for (final key in keys) {
        expect(en[key], isA<String>(), reason: 'en: $key');
        expect(ar[key], isA<String>(), reason: 'ar: $key');
      }
    });
  });

  group('navigation is unchanged', () {
    final view = _read(_view);

    test('each type opens its own details screen', () {
      for (final route in [
        "'/requested-details'",
        "'/owners-details'",
        "'/offices-details'",
        "'/watchmen-details'",
        "'/brokers-details'",
        "'/offers-details-by-id/\${Uri.encodeComponent(offerId)}'",
      ]) {
        expect(view.contains(route), isTrue, reason: route);
      }
      expect(view.contains('extra: result.data'), isTrue);
    });

    test('an offer opens by id, and not without one', () {
      expect(view.contains('final offerId = result.id.trim();'), isTrue);
      expect(view.contains('if (offerId.isNotEmpty)'), isTrue);
    });

    test('the keyboard is put away before leaving, results stay', () {
      expect(view.contains('FocusManager.instance.primaryFocus?.unfocus()'),
          isTrue);
      expect(view.contains('ScrollViewKeyboardDismissBehavior.onDrag'), isTrue);
    });

    test('cards are keyed by type and id, and keep state when results reorder',
        () {
      expect(view.contains('ValueKey<String>(result.stableKey)'), isTrue);
      expect(view.contains('findChildIndexCallback'), isTrue);
    });
  });

  group('Search only reads the signed-in user\'s own records', () {
    test('the data source reads through user-scoped paths', () {
      final source = _read(_dataSource);
      expect(source.contains('SupabaseCoreEntitiesService'), isTrue,
          reason: 'its reads are owner_id scoped, with RLS');
      expect(source.contains(".collection('users').doc(userId)"), isTrue);
      expect(source.contains('authRepository.currentUserId'), isTrue);
    });

    test('Search holds no backend credential and queries nothing itself', () {
      final searchFiles = Directory('lib/src/views/Screens/home/search')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final file in searchFiles) {
        final source = file.readAsStringSync();
        final name = file.path.replaceAll('\\', '/').split('/').last;
        expect(source.contains('service_role'), isFalse, reason: name);
        expect(
            RegExp(r'sb_secret|SUPABASE_SERVICE|serviceKey').hasMatch(source),
            isFalse,
            reason: name);
        expect(source.contains(".from('"), isFalse,
            reason: '$name queries the database directly');
        expect(source.contains('rpc('), isFalse, reason: name);
      }
    });

    test('the view-model no longer talks to a backend at all', () {
      final source = _read(_viewModel);
      expect(source.contains('cloud_firestore'), isFalse);
      expect(source.contains('FirebaseFirestore'), isFalse);
      expect(source.contains('SupabaseCoreEntitiesService'), isFalse);
      expect(source.contains('RepositoryProvider'), isFalse);
    });

    test('a copy of one user\'s records is never used for another', () {
      final source = _read(_viewModel);
      expect(source.contains('_corpusUserId == _dataSource.currentUserId'),
          isTrue);
    });
  });

  group('the card', () {
    test('keeps the layout the Favorites card has, apart from the new floor',
        () {
      final source = _read(_card);
      expect(source.contains('flex: 5'), isTrue);
      expect(source.contains('flex: 4'), isTrue);
      expect(source.contains('static double minHeightForText'), isTrue);
    });
  });
}
