import 'package:broker_wallet/src/Views/Screens/home/quotation/add_quotation_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/list_quotation_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/list_quotations_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/Views/Widgets/save_cancel_buttons.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:broker_wallet/src/views/Widgets/list_loading_indicator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'r6b_quotation_fakes.dart';
import 'responsive_harness.dart';

const _sizes = [
  Size(280, 600),
  Size(320, 568),
  Size(360, 640),
  Size(393, 852),
  Size(430, 932),
  Size(640, 360),
  Size(600, 800),
  Size(800, 1280)
];
const _sections = [
  'generalInformation',
  'moneyAndTerms',
  'downpayments',
  'governmentFees',
  'administrativeFees',
  'officeInformation'
];

ResponsiveCase _case(int i, {Locale? locale, double keyboard = 0}) =>
    ResponsiveCase(_sizes[i],
        locale: locale ?? Locale(i.isEven ? 'ar' : 'en'),
        dark: i.isOdd,
        textScale: const [2.0, 1.6, 1.3, 1.0, 2.0, 2.0, 1.3, 1.0][i],
        safeArea: const EdgeInsets.only(top: 24, bottom: 16),
        keyboard: keyboard);

AppLocalizations _loc(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(Scaffold).first));
Future<void> _reach(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

Future<void> _section(WidgetTester t, String key) async {
  final title = find.text(_loc(t).translate(key));
  await _reach(t, title);
  final header = find.ancestor(of: title, matching: find.byType(InkWell)).first;
  final media = MediaQuery.of(t.element(find.byType(Scaffold).first));
  final visible = t.getRect(header).intersect(Rect.fromLTRB(
      0,
      t.getRect(find.byType(AppBar)).bottom,
      media.size.width,
      media.size.height - media.viewInsets.bottom));
  expect(visible.height, greaterThan(0));
  await t.tapAt(visible.center);
  await t.pumpAndSettle();
}

Future<LayoutQuotationForm> _form(WidgetTester t, ResponsiveCase c,
    {bool populated = true, bool edit = false, String state = ''}) async {
  final service = LocalQuotationService();
  final vm = LayoutQuotationForm(service, edit: edit);
  if (populated) {
    fillQuotationForm(vm);
  } else {
    vm.currencyCode = '';
  }
  vm.busy = state == 'busy';
  vm.processing = state == 'processing';
  vm.loadingEdit = state == 'loading';
  vm.failedEdit = state == 'error';
  addTearDown(() async {
    expect(service.unexpectedCalls, 0);
    await service.events.close();
  });
  await pumpResponsive(t, c,
      home: AddQuotationView(viewModel: vm),
      settle: !['busy', 'processing', 'loading'].contains(state));
  return vm;
}

Future<LocalQuotationService> _list(
    WidgetTester t, ResponsiveCase c, String state) async {
  final service = LocalQuotationService();
  final vm = localQuotationList(service);
  addTearDown(() async {
    expect(service.unexpectedCalls, 0);
    await service.events.close();
  });
  await pumpResponsive(t, c,
      home: QuotationListView(viewModel: vm), settle: false);
  if (state == 'error') {
    service.events.addError(StateError('local fixture error'));
  } else if (state != 'loading') {
    service.events.add(state == 'empty' ? [] : quotationFixtures());
  }
  await t.pump();
  if (state != 'loading') await t.pumpAndSettle();
  expectNoLayoutException(t, c);
  expect(service.streamReads, 1);
  expect(service.subscriptions, 1);
  return service;
}

void _editableTextFits(WidgetTester t) {
  for (final e in find.byType(EditableText).evaluate()) {
    final RenderEditable editable =
        ((e as StatefulElement).state as EditableTextState).renderEditable;
    final painter = TextPainter(
        text: editable.text,
        textDirection: editable.textDirection,
        textScaler: editable.textScaler,
        maxLines: 1)
      ..layout();
    expect(editable.size.height,
        greaterThanOrEqualTo(painter.preferredLineHeight - .1),
        reason: 'scaled input line must fit without vertical clipping');
    painter.dispose();
  }
  final dropdowns = find.byWidgetPredicate((w) => w is DropdownButton<String>);
  for (final e in find
      .descendant(of: dropdowns, matching: find.byType(RichText))
      .evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    if (p.size.width <= 0) continue;
    final painter = TextPainter(
        text: p.text,
        textDirection: p.textDirection,
        textScaler: p.textScaler,
        maxLines: p.maxLines)
      ..layout(maxWidth: p.size.width);
    expect(p.size.height, greaterThanOrEqualTo(painter.height - .1),
        reason:
            'selected payment method must not clip vertically: ${p.text.toPlainText()}');
    painter.dispose();
  }
}

void main() {
  setUpAll(prepareResponsiveAssets);
  for (var i = 0; i < _sizes.length; i++) {
    final c = _case(i);
    for (final section in _sections) {
      testWidgets('quotation form $section $c', (t) async {
        final vm = await _form(t, c, edit: i.isOdd);
        await _section(t, section);
        expectNoLayoutException(t, c);
        _editableTextFits(t);
        final loc = _loc(t);
        if (section == 'generalInformation') {
          await _reach(t, find.text(loc.translate('customMessage')));
          await t.tap(find.text(loc.translate('customMessage')));
          await t.pumpAndSettle();
          expect(vm.welcomeMessageMode, WelcomeMessageMode.custom);
          await _reach(
              t, find.widgetWithText(TextField, vm.customWelcomeMessage));
          await _reach(t, find.text(loc.translate('hideWelcomeMessage')));
          await t.tap(find.text(loc.translate('hideWelcomeMessage')));
          await t.pumpAndSettle();
          expect(vm.welcomeMessageMode, WelcomeMessageMode.hidden);
        }
        if (section == 'moneyAndTerms') {
          final chip = find.widgetWithText(ChoiceChip, loc.translate('cash'));
          await _reach(t, chip);
          await t.tap(chip);
          await t.pumpAndSettle();
          expect(vm.paymentType, 'cash');
          final amount = find.byWidgetPredicate(
              (w) => w is TextField && w.controller?.text == vm.totalAmount);
          await _reach(t, amount);
          await t.enterText(amount, 'invalid');
          expect(vm.totalAmount, 'invalid');
          await t.enterText(amount, '100000.50');
          expect(vm.totalAmount, '100000.50');
        }
        if (section == 'downpayments') {
          final add = find.widgetWithText(TextButton, loc.translate('addRow'));
          await _reach(t, add);
          await t.tap(add);
          await t.pumpAndSettle();
          expect(vm.downpayments.length, 5);
          final remove = find.byTooltip(loc.translate('remove')).last;
          await _reach(t, remove);
          await t.tap(remove);
          await t.pumpAndSettle();
          expect(vm.downpayments.length, 4);
        }
        if (section == 'administrativeFees') {
          final add = find.text(loc.translate('addAdministrativeFee'));
          await _reach(t, add);
          await t.tap(add);
          await t.pumpAndSettle();
          expect(vm.administrativeFees.length, 4);
          final remove =
              find.widgetWithIcon(IconButton, Icons.delete_outline).last;
          await _reach(t, remove);
          await t.tap(remove);
          await t.pumpAndSettle();
          expect(vm.administrativeFees.length, 3);
        }
        if (section == 'officeInformation') {
          await _reach(t, find.text(vm.officeLogoFileName));
          expect(
              find.text(vm.officeLogoFileName).hitTestable(), findsOneWidget);
          await _reach(t, find.text(loc.translate('removeLogoBackgroundHint')));
        }
        final scroll =
            t.state<ScrollableState>(find.byType(Scrollable).first).position;
        scroll.jumpTo(scroll.maxScrollExtent / 2);
        await t.pumpAndSettle();
        scroll.jumpTo(scroll.maxScrollExtent);
        await t.pumpAndSettle();
        expect(find.byType(SaveCancelButtons), findsOneWidget);
        expectNoLayoutException(t, c);
        expect(vm.saves, 0);
        expect(vm.loads, 0);
        expect(vm.local.unexpectedCalls, 0);
      });
    }
    for (final state in ['loading', 'empty', 'error']) {
      testWidgets('quotation list $state $c', (t) async {
        await _list(t, c, state);
        if (state == 'loading') {
          expect(find.byType(ListLoadingIndicator), findsOneWidget);
          await t.pump(const Duration(milliseconds: 500));
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
        }
      });
    }
    for (final locale in const [Locale('en'), Locale('ar')]) {
      final lc = _case(i, locale: locale);
      testWidgets('quotation populated cards/delete cancel $lc', (t) async {
        final service = await _list(t, lc, 'populated');
        for (final index in [0, 1, 2, 4]) {
          final card = find.byKey(Key('quotation_local-$index'));
          final view = find.descendant(
              of: card, matching: find.byIcon(Icons.visibility_outlined));
          await _reach(t, view);
          expect(view.hitTestable(), findsOneWidget);
          final action =
              find.ancestor(of: view, matching: find.byType(InkWell)).first;
          expect(t.widget<InkWell>(action).onTap,
              index.isEven ? isNotNull : isNull);
          final share = find.descendant(
              of: card, matching: find.byIcon(Icons.share_outlined));
          expect(share.hitTestable(), findsOneWidget);
          expect(
              t
                  .widget<InkWell>(find
                      .ancestor(of: share, matching: find.byType(InkWell))
                      .first)
                  .onTap,
              index.isEven ? isNotNull : isNull);
          expectNoLayoutException(t, lc);
        }
        final card = find.byKey(const Key('quotation_local-4'));
        final visible = t.getRect(card).intersect(
            Rect.fromLTRB(0, 100, lc.size.width, lc.size.height - 80));
        await t.dragFrom(
            visible.center,
            Offset((locale.languageCode == 'ar' ? 1 : -1) * lc.size.width * .8,
                0));
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expectNoLayoutException(t, lc);
        final cancel =
            find.widgetWithText(ElevatedButton, _loc(t).translate('cancel'));
        await _reach(t, cancel);
        await t.tap(cancel);
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(service.streamReads, 1);
        expect(service.unexpectedCalls, 0);
      });
    }
    testWidgets('quotation keyboard fields $c', (t) async {
      final kc = _case(i, keyboard: 240);
      final vm = await _form(t, kc);
      await _section(t, 'generalInformation');
      final field = find.byType(TextField).first;
      await _reach(t, field);
      await t.enterText(field, 'edited title قيمة طويلة');
      expect(vm.propertyTitle, 'edited title قيمة طويلة');
      expect(field.hitTestable(), findsOneWidget);
      expect(find.byType(SaveCancelButtons), findsNothing);
      expectNoLayoutException(t, kc);
    });
  }
  for (final locale in const [Locale('en'), Locale('ar')]) {
    testWidgets('quotation office placeholder and disabled background $locale',
        (t) async {
      final c =
          ResponsiveCase(const Size(280, 600), locale: locale, textScale: 2);
      final vm = await _form(t, c, populated: false);
      await _section(t, 'officeInformation');
      final placeholder = find.text(_loc(t).translate('uploadOfficeLogo'));
      await _reach(t, placeholder);
      expect(placeholder.hitTestable(), findsOneWidget);
      expect(find.byIcon(Icons.clear), findsNothing);
      await _reach(t, find.byType(Switch));
      expect(t.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(vm.officeLogoFileName, isEmpty);
      expect(vm.saves, 0);
      expectNoLayoutException(t, c);
    });
    testWidgets('quotation list resize/locale keeps one subscription $locale',
        (t) async {
      final service = await _list(
          t, ResponsiveCase(const Size(393, 852), locale: locale), 'populated');
      final vm = Provider.of<QuotationListViewModel>(
          t.element(find.byType(CustomScrollView)),
          listen: false);
      for (final size in [const Size(640, 360), const Size(280, 600)]) {
        final c = ResponsiveCase(size,
            locale: Locale(locale.languageCode == 'ar' ? 'en' : 'ar'),
            textScale: 2);
        await pumpResponsive(t, c, home: QuotationListView(viewModel: vm));
        expect(service.streamReads, 1);
        expect(service.subscriptions, 1);
        expect(find.byType(Dismissible), findsNWidgets(5));
      }
    });
    testWidgets('quotation resize retains input focus options and rows $locale',
        (t) async {
      final vm =
          await _form(t, ResponsiveCase(const Size(393, 852), locale: locale));
      await _section(t, 'generalInformation');
      await _section(t, 'downpayments');
      await _section(t, 'administrativeFees');
      final custom = find.text(_loc(t).translate('customMessage'));
      await _reach(t, custom);
      await t.tap(custom);
      await t.pumpAndSettle();
      expect(vm.welcomeMessageMode, WelcomeMessageMode.custom);
      final field = find.byType(TextField).first;
      await _reach(t, field);
      await t.enterText(field, 'retained quotation');
      final controller = t.widget<TextField>(field).controller;
      final focus =
          t.widget<EditableText>(find.byType(EditableText).first).focusNode;
      for (final size in [
        const Size(640, 360),
        const Size(280, 600),
        const Size(393, 852)
      ]) {
        await pumpResponsive(
            t, ResponsiveCase(size, locale: locale, textScale: 2),
            home: AddQuotationView(viewModel: vm));
        expect(t.widget<TextField>(find.byType(TextField).first).controller,
            same(controller));
        expect(controller!.text, 'retained quotation');
        expect(focus.hasFocus, isTrue);
        expect(vm.welcomeMessageMode, WelcomeMessageMode.custom);
        expect(vm.downpayments.length, 4);
        expect(vm.administrativeFees.length, 3);
        expect(vm.adminAdds, 0);
        expect(vm.smartOpens, 1);
        expect(vm.loads, 0);
        expect(vm.saves, 0);
      }
    });
    testWidgets('quotation save/cancel callbacks and empty tint $locale',
        (t) async {
      final vm = await _form(
          t, ResponsiveCase(const Size(280, 600), locale: locale, textScale: 2),
          populated: false);
      final loc = _loc(t);
      final save = find.widgetWithText(ElevatedButton, loc.translate('save'));
      expect(
          t.widget<SaveCancelButtons>(find.byType(SaveCancelButtons)).isEnabled,
          isFalse);
      vm.setPropertyTitle('local form title');
      await t.pumpAndSettle();
      await t.tap(save);
      await t.pumpAndSettle();
      expect(vm.saves, 1);
      await t.tap(find.widgetWithText(OutlinedButton, loc.translate('cancel')));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await _reach(t, find.text('Keep Editing'));
      await t.tap(find.text('Keep Editing'));
      await t.pumpAndSettle();
      expect(vm.propertyTitle, 'local form title');
      expect(vm.saves, 1);
    });
  }
  for (final state in ['busy', 'processing', 'loading', 'error']) {
    testWidgets('quotation edit/save presentation $state', (t) async {
      final c = _case(0);
      final vm = await _form(t, c, edit: true, state: state);
      if (state == 'processing') {
        final title = find.text(_loc(t).translate('officeInformation'));
        await _reach(t, title);
        await t.tap(title);
        await t.pump(const Duration(milliseconds: 300));
      }
      if (['busy', 'processing', 'loading'].contains(state))
        expect(find.byType(CircularProgressIndicator), findsWidgets);
      if (state == 'busy')
        expect(
            t
                .widget<SaveCancelButtons>(find.byType(SaveCancelButtons))
                .isLoading,
            isTrue);
      if (state == 'error') {
        expect(find.byType(TextButton), findsOneWidget);
        await t.tap(find.byType(TextButton));
        await t.pumpAndSettle();
        expect(vm.loads, 1);
      }
      expect(vm.saves, 0);
      expect(vm.loads, state == 'error' ? 1 : 0);
      expectNoLayoutException(t, c);
    });
  }
}
