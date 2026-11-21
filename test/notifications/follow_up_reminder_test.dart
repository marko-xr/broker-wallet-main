// Notifications N2/N3 client: follow-up reminder model, error mapping, view
// model and the Details section. No Supabase, no device.
import 'dart:async';

import 'package:broker_wallet/src/data/models/follow_up_reminder.dart';
import 'package:broker_wallet/src/repositories/follow_up_reminder_repository.dart';
import 'package:broker_wallet/src/viewmodels/follow_up_reminder_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/ViewDetails/widgets/follow_up_reminder_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../responsive/responsive_harness.dart';

final DateTime _now = DateTime(2026, 11, 20, 10);

class _Repo implements FollowUpReminderRepository {
  FollowUpReminder? stored;
  Object? fetchError;
  Object? scheduleError;
  Completer<FollowUpReminder?>? pendingFetch;
  final List<DateTime> scheduled = [];
  int cancels = 0;

  @override
  Future<FollowUpReminder?> fetch(FollowUpTarget target, String targetId) {
    final pending = pendingFetch;
    if (pending != null) return pending.future;
    final error = fetchError;
    if (error != null) return Future.error(error);
    return Future.value(stored);
  }

  @override
  Future<FollowUpReminder> schedule(
      FollowUpTarget target, String targetId, DateTime remindAt) async {
    final error = scheduleError;
    if (error != null) throw error;
    scheduled.add(remindAt);
    return stored = FollowUpReminder(
      id: 'r1',
      remindAt: remindAt.toUtc(),
      status: FollowUpReminderStatus.scheduled,
    );
  }

  @override
  Future<bool> cancel(FollowUpTarget target, String targetId) async {
    cancels++;
    stored = null;
    return true;
  }
}

FollowUpReminderViewModel _vm(_Repo repo) => FollowUpReminderViewModel(
      repository: repo,
      target: FollowUpTarget.request,
      targetId: 'req-1',
      now: () => _now,
    );

void main() {
  group('model and error mapping', () {
    test('rows are read only when complete', () {
      final row = FollowUpReminder.fromRow({
        'id': 'r1',
        'remind_at': '2026-11-21T08:30:00+00:00',
        'status': 'scheduled',
      })!;
      expect(row.isScheduled, isTrue);
      expect(row.remindAt, DateTime.utc(2026, 11, 21, 8, 30));
      expect(
        FollowUpReminder.fromRow({
          'reminder_id': 'r2',
          'remind_at': '2026-11-21T08:30:00Z',
          'status': 'sent',
        })!
            .isScheduled,
        isFalse,
      );
      expect(
          FollowUpReminder.fromRow(
              {'id': 'r1', 'remind_at': 'x', 'status': 'scheduled'}),
          isNull);
      expect(
          FollowUpReminder.fromRow(
              {'id': 'r1', 'remind_at': '2026-11-21T08:30:00Z', 'status': '?'}),
          isNull);
      expect(FollowUpTarget.offer.wireName, 'offer');
    });

    test('server codes map to fixed failures', () {
      expect(mapFollowUpError('session_superseded'),
          FollowUpFailureCode.sessionSuperseded);
      expect(mapFollowUpError('remind_at_in_past'), FollowUpFailureCode.inPast);
      expect(mapFollowUpError('remind_at_too_far'), FollowUpFailureCode.tooFar);
      expect(
          mapFollowUpError('target_not_found'), FollowUpFailureCode.notFound);
      expect(
          mapFollowUpError('too_many_reminders'), FollowUpFailureCode.tooMany);
      expect(
          mapFollowUpError('anything else'), FollowUpFailureCode.unavailable);
    });
  });

  group('view model', () {
    test('loads none, scheduled, offline and failed honestly', () async {
      final repo = _Repo();
      final vm = _vm(repo);
      await vm.load();
      expect(vm.state, FollowUpLoadState.ready);
      expect(vm.scheduled, isNull);

      repo.stored = FollowUpReminder(
          id: 'r1',
          remindAt: _now.toUtc(),
          status: FollowUpReminderStatus.sent);
      await vm.load();
      expect(vm.scheduled, isNull, reason: 'a sent reminder is not due');

      repo.fetchError = const FollowUpFailure(FollowUpFailureCode.offline);
      await vm.load();
      expect(vm.state, FollowUpLoadState.offline);

      repo.fetchError = StateError('network');
      await vm.load();
      expect(vm.state, FollowUpLoadState.failed);
    });

    test('a slower old load never overwrites a newer one', () async {
      final repo = _Repo();
      final vm = _vm(repo);
      final slow = Completer<FollowUpReminder?>();
      repo.pendingFetch = slow;
      final first = vm.load();
      repo.pendingFetch = null;
      repo.stored = null;
      await vm.load();
      slow.complete(FollowUpReminder(
          id: 'old',
          remindAt: _now.toUtc(),
          status: FollowUpReminderStatus.scheduled));
      await first;
      expect(vm.scheduled, isNull);
    });

    test('schedule, change and cancel go through the server', () async {
      final repo = _Repo();
      final vm = _vm(repo)..load();
      await pumpEventQueue();
      final when = _now.add(const Duration(days: 1));
      expect(await vm.schedule(when), isNull);
      expect(repo.scheduled.single, when);
      expect(vm.scheduled!.remindAt, when.toUtc());

      final later = when.add(const Duration(hours: 3));
      expect(await vm.schedule(later), isNull);
      expect(vm.scheduled!.remindAt, later.toUtc());

      expect(await vm.cancel(), isNull);
      expect(repo.cancels, 1);
      expect(vm.scheduled, isNull);
    });

    test('times the server would refuse are refused before sending', () async {
      final repo = _Repo();
      final vm = _vm(repo)..load();
      await pumpEventQueue();
      expect(await vm.schedule(_now.add(const Duration(minutes: 1))),
          FollowUpFailureCode.inPast);
      expect(await vm.schedule(_now.add(const Duration(days: 400))),
          FollowUpFailureCode.tooFar);
      expect(repo.scheduled, isEmpty);
    });

    test('a refused save keeps the previous reminder', () async {
      final repo = _Repo()
        ..stored = FollowUpReminder(
            id: 'r1',
            remindAt: _now.add(const Duration(days: 2)).toUtc(),
            status: FollowUpReminderStatus.scheduled);
      final vm = _vm(repo)..load();
      await pumpEventQueue();
      repo.scheduleError =
          const FollowUpFailure(FollowUpFailureCode.sessionSuperseded);
      expect(await vm.schedule(_now.add(const Duration(days: 1))),
          FollowUpFailureCode.sessionSuperseded);
      expect(vm.scheduled!.remindAt, _now.add(const Duration(days: 2)).toUtc());
      expect(vm.isBusy, isFalse);
    });
  });

  group('details section', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await prepareResponsiveAssets();
    });

    for (final scenario in const [
      ResponsiveCase(Size(320, 640), textScale: 2),
      ResponsiveCase(Size(393, 852), locale: Locale('ar'), dark: true),
    ]) {
      testWidgets('shows set, then change and cancel: $scenario',
          (tester) async {
        final repo = _Repo();
        await pumpResponsive(
          tester,
          scenario,
          home: Scaffold(
            body: SingleChildScrollView(
              child: FollowUpReminderSection(
                target: FollowUpTarget.offer,
                targetId: 'offer-1',
                repository: repo,
              ),
            ),
          ),
        );
        expect(find.byKey(const ValueKey('follow-up-set')), findsOneWidget);
        expect(find.byKey(const ValueKey('follow-up-change')), findsNothing);

        repo.stored = FollowUpReminder(
          id: 'r1',
          remindAt: DateTime.now().add(const Duration(days: 1)).toUtc(),
          status: FollowUpReminderStatus.scheduled,
        );
        await pumpResponsive(
          tester,
          scenario,
          home: Scaffold(
            body: SingleChildScrollView(
              child: FollowUpReminderSection(
                key: const ValueKey('second'),
                target: FollowUpTarget.offer,
                targetId: 'offer-1',
                repository: repo,
              ),
            ),
          ),
        );
        expect(find.byKey(const ValueKey('follow-up-change')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('follow-up-cancel')));
        await tester.pumpAndSettle();
        expect(repo.cancels, 1);
        expect(find.byKey(const ValueKey('follow-up-set')), findsOneWidget);
        expectNoLayoutException(tester, scenario);
      });
    }
  });
}
