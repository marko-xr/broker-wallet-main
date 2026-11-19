import 'package:broker_wallet/src/Views/Widgets/save_cancel_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// With the keyboard open, the record forms keep Save and Cancel on screen,
/// resting right on the keyboard, and both can be tapped — unless that would
/// leave the form less than [SaveCancelButtons.minFormRoomAboveKeyboard]
/// (a phone on its side, very large text): then they step aside.
void expectFormActionsAboveKeyboard(WidgetTester tester,
    {required double windowHeight, required double keyboard}) {
  final actions = find.byType(SaveCancelButtons);
  // The form body: the closest LayoutBuilder around the form's scroll view.
  final body = tester.getRect(find
      .ancestor(
          of: find.byType(SingleChildScrollView).first,
          matching: find.byType(LayoutBuilder))
      .first);
  final room = body.height -
      keyboard -
      SaveCancelButtons.heightOf(tester.element(find.byType(Scaffold).first));
  if (room < SaveCancelButtons.minFormRoomAboveKeyboard) {
    expect(actions, findsNothing, reason: 'room above the keyboard: $room');
    return;
  }
  expect(actions, findsOneWidget);
  expect(tester.getRect(actions).bottom,
      moreOrLessEquals(windowHeight - keyboard, epsilon: 0.5));
  for (final button in [ElevatedButton, OutlinedButton]) {
    expect(
        find
            .descendant(of: actions, matching: find.byType(button))
            .hitTestable(),
        findsOneWidget);
  }
}

/// Where a form field stops being visible: the top of the form actions when
/// they are on screen (the keyboard is open), else the keyboard's top.
double formVisibleBottom(WidgetTester tester,
    {required double windowHeight, required double keyboard}) {
  final actions = find.byType(SaveCancelButtons);
  if (keyboard == 0 || actions.evaluate().isEmpty) {
    return windowHeight - keyboard;
  }
  return tester.getRect(actions).top;
}

Future<void> tapExpandedStatusBadge(WidgetTester tester, String key) async {
  final badge = find.byKey(ValueKey(key));
  final target = find.descendant(of: badge, matching: find.byType(InkWell));
  final pill = find.descendant(of: badge, matching: find.byType(Ink));
  final targetRect = tester.getRect(target);
  final pillRect = tester.getRect(pill);
  expect(targetRect.size.shortestSide, greaterThanOrEqualTo(48));
  expect(pillRect.height, lessThan(targetRect.height));
  await tester.tapAt(
      Offset(pillRect.center.dx, (pillRect.bottom + targetRect.bottom) / 2));
}

void expectPinnedDetailsControls(WidgetTester tester, {bool hasPhone = true}) {
  final toolbar = find.byType(SliverAppBar);
  expect(tester.widget<SliverAppBar>(toolbar).pinned, isTrue);
  expect(tester.widget<SliverAppBar>(toolbar).centerTitle, isTrue);
  final call = find.byKey(const ValueKey('details-call')).hitTestable();
  final whatsapp = find.byKey(const ValueKey('details-whatsapp')).hitTestable();
  expect(call, findsOneWidget);
  expect(whatsapp, findsOneWidget);
  expect(tester.widget<OutlinedButton>(call).onPressed != null, hasPhone);
  expect(tester.widget<FilledButton>(whatsapp).onPressed != null, hasPhone);
  final rtl = Directionality.of(tester.element(toolbar)) == TextDirection.rtl;
  // Call first, then WhatsApp (reading order), as DetailsContactBar lays
  // them out since the contact bar was unified with the list cards.
  expect(tester.getCenter(call).dx < tester.getCenter(whatsapp).dx, !rtl);
}

Future<void> openDetailsDeleteConfirmation(WidgetTester tester) async {
  final menu = find.byKey(const ValueKey('details-actions'));
  await tester.ensureVisible(menu);
  await tester.pumpAndSettle();
  expect(menu.hitTestable(), findsOneWidget);
  await tester.tap(menu);
  await tester.pumpAndSettle();
  expect(
      find.byKey(const ValueKey('details-edit')).hitTestable(), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('details-delete')));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
}
