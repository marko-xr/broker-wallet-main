import 'package:broker_wallet/src/common/data/offer_property_types.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/widgets/compact_offer_card.dart';
import 'package:broker_wallet/src/widgets/compact_property_labels.dart';
import 'package:broker_wallet/src/widgets/compact_request_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:broker_wallet/src/widgets/auto_scrolling_related_items_carousel.dart';
import 'package:intl/intl.dart';
import 'r5d_entity_cases.dart';
import 'responsive_harness.dart';

void main() {
  setUpAll(prepareResponsiveAssets);

  for (final dark in [false, true]) {
    testWidgets('Related rent badge contrast dark=$dark', (tester) async {
      final scenario = ResponsiveCase(const Size(393, 852),
          dark: dark, locale: Locale(dark ? 'ar' : 'en'));
      for (final offer in [true, false]) {
        await pumpResponsive(tester, scenario,
            home: Scaffold(
              body: AutoScrollingRelatedItemsCarousel(
                offers: offer ? [relatedOffer()] : [],
                requests: offer ? [] : [relatedRequest()],
              ),
            ));
        final context =
            tester.element(find.byType(AutoScrollingRelatedItemsCarousel));
        final rent = find.text(AppLocalizations.of(context).translate('rent'));
        final foreground = tester.widget<Text>(rent).style!.color!;
        final primary = Theme.of(context).colorScheme.primary;
        final badge = find.ancestor(
          of: rent,
          matching: find.byWidgetPredicate((widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).gradient?.colors.first ==
                  primary),
        );
        final decoration =
            tester.widget<Container>(badge).decoration! as BoxDecoration;
        final stops = decoration.gradient!.colors;
        expect(stops, hasLength(2));
        for (final stop in stops) {
          expect(stop.a, 1);
          final ratio = (stop.computeLuminance() + 0.05) /
              (foreground.computeLuminance() + 0.05);
          expect(ratio, greaterThanOrEqualTo(4.5),
              reason: 'Both opaque rent badge stops must meet the AA target');
        }
      }
    });
  }

  for (final language in ['en', 'ar']) {
    testWidgets('Related cards localize saved property and city labels $language',
        (tester) async {
      final arabic = language == 'ar';
      final scenario =
          ResponsiveCase(const Size(393, 852), locale: Locale(language));
      await pumpResponsive(tester, scenario,
          home: Scaffold(
            body: Column(children: [
              CompactOfferCard(
                offer: relatedOffer().copyWith(
                  propertyType: arabic ? 'Furnished' : 'مفروش',
                  specificPropertyType: arabic ? 'Full Floor' : 'طابق كامل',
                  selectedCity: arabic ? 'Abu-Dhabi' : 'أبوظبي',
                ),
              ),
              CompactRequestCard(
                request: relatedRequest().copyWith(
                  specificPropertyType: arabic ? 'officeSpace' : 'مساحة مكتبية',
                ),
              ),
              CompactRequestCard(
                request: relatedRequest().copyWith(specificPropertyType: ' '),
              ),
            ]),
          ));

      expect(find.text(arabic ? 'مفروش' : 'Furnished'), findsOneWidget);
      expect(find.text(arabic ? 'طابق كامل' : 'Full Floor'), findsOneWidget);
      expect(find.text(arabic ? 'أبوظبي' : 'Abu Dhabi'), findsOneWidget);
      expect(find.text(arabic ? 'مساحة مكتبية' : 'Office Space'), findsOneWidget);
      expect(find.text(arabic ? 'غير محدد' : 'Not specified'), findsOneWidget);
      expect(find.textContaining('** '), findsNothing);

      final loc =
          AppLocalizations.of(tester.element(find.byType(CompactOfferCard)));
      for (final key in OfferPropertyTypes.keys) {
        final label = AppLocalizations.translateFor(language, key);
        expect(label, isNotEmpty, reason: '$language must define $key');
        if (arabic) expect(label, matches(RegExp(r'[\u0600-\u06ff]')));
        expect(CompactPropertyLabels.subtype(key, loc), label);
      }
      expect(CompactPropertyLabels.subtype('Custom description', loc),
          'Custom description');
      expectNoLayoutException(tester, scenario);
    });

    testWidgets('Related paging and autoplay controls $language',
        (tester) async {
      final arabic = language == 'ar';
      final outer = ScrollController();
      addTearDown(outer.dispose);
      final reduceMotion = ValueNotifier(false);
      addTearDown(reduceMotion.dispose);
      final scenario = ResponsiveCase(const Size(320, 750),
          locale: Locale(language), textScale: 1.5);
      await pumpResponsive(tester, scenario,
          home: Scaffold(
              body: SingleChildScrollView(
                  controller: outer,
                  child: Column(children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: reduceMotion,
                      builder: (context, reduced, _) => MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(disableAnimations: reduced),
                        child: AutoScrollingRelatedItemsCarousel(
                          offers: List.filled(6, relatedOffer()),
                          requests: List.filled(2, relatedRequest()),
                        ),
                      ),
                    ),
                    const SizedBox(height: 1000),
                  ]))));
      final numbers = NumberFormat.decimalPattern(language);
      Finder position(int index) {
        final label = arabic
            ? 'العنصر ${numbers.format(index)} من ${numbers.format(8)}'
            : 'Item $index of 8';
        return find.byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.label == label);
      }
      Finder playback(IconData icon) => find.widgetWithIcon(IconButton, icon);
      final pager = find.byWidgetPredicate((widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal);
      Future<void> tick() async {
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
      }

      expect(find.text(arabic ? 'طلبان' : '2 requests'), findsOneWidget);
      expect(find.text(arabic ? '${numbers.format(6)} عروض' : '6 offers'),
          findsOneWidget);
      final play = playback(Icons.play_circle_outline);
      expect(tester.getSize(play).shortestSide, greaterThanOrEqualTo(48));
      await tick();
      expect(position(1), findsOneWidget);
      await tester.drag(pager, Offset(arabic ? 240 : -240, 0));
      await tester.pumpAndSettle();
      expect(position(2), findsOneWidget);
      final pageController =
          tester.widget<SingleChildScrollView>(pager).controller!;
      pageController.jumpTo(5 * pageController.position.viewportDimension);
      await tester.pumpAndSettle();
      expect(position(6), findsOneWidget);
      await tester.tap(play);
      await tick();
      expect(position(7), findsOneWidget);

      outer.jumpTo(outer.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tick();
      expect(position(7), findsOneWidget);
      outer.jumpTo(0);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tick();
      expect(position(7), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      reduceMotion.value = true;
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(play).onPressed, isNull);
      await tick();
      expect(position(7), findsOneWidget);
      reduceMotion.value = false;
      await tester.pumpAndSettle();
      await tester.tap(playback(Icons.pause_circle_outline));
      await tester.drag(pager, Offset(arabic ? 240 : -240, 0));
      await tester.pumpAndSettle();
      await tick();
      expect(position(8), findsOneWidget);
    });
  }

  for (final c in entityMatrix) {
    for (final kind in ['offer', 'request', 'both']) {
      testWidgets('Related $kind painted bounds and scrolling $c',
          (tester) async {
        final window = noKeyboard(c);
        await pumpResponsive(tester, window,
            home: Scaffold(
                body: SingleChildScrollView(
                    child: AutoScrollingRelatedItemsCarousel(
              offers: kind == 'request' ? [] : [relatedOffer()],
              requests: kind == 'offer' ? [] : [relatedRequest()],
            ))),
            settle: false);
        await tester.pump();
        await tester.pump();
        final inner = find.descendant(
            of: find.byType(AutoScrollingRelatedItemsCarousel),
            matching: find.byType(SingleChildScrollView));
        expect(inner, kind == 'both' ? findsOneWidget : findsNothing);
        final carousel = find.byType(AutoScrollingRelatedItemsCarousel);
        await tester.ensureVisible(carousel);
        await tester.pump();
        final rect = tester.getRect(carousel);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(window.size.width));
        await tester.drag(
            find.byType(SingleChildScrollView).first, const Offset(0, -400));
        await tester.pump();
        expectNoLayoutException(tester, window);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
