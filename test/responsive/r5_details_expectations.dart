import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  expect(tester.getCenter(whatsapp).dx < tester.getCenter(call).dx, !rtl);
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
