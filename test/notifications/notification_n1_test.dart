// Notification plan N1 (2026-11-20): settings keys, row parsing, keyset
// paging, stale-account guarding, offline/error states, delete rollback and
// the route allowlist. Pure Dart tests; no Supabase, no device.
import 'dart:async';

import 'package:broker_wallet/src/data/models/notification_model.dart';
import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/notification_repository.dart';
import 'package:broker_wallet/src/repositories/supabase_notification_repository.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/notification_settings_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/notification_viewmodel.dart';
import 'package:broker_wallet/src/views/Screens/home/notifications/notifications_list_view.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _base = DateTime.utc(2026, 11, 20, 12);

String _uuid(int n) =>
    '00000000-0000-0000-0000-${n.toRadixString(16).padLeft(12, '0')}';

NotificationModel _n(
  int id, {
  int minutesAgo = 0,
  DateTime? at,
  NotificationCategory category = NotificationCategory.reminder,
  bool isRead = false,
  String? offerId,
  String? requestId,
  String? actionRoute,
  Map<String, dynamic> data = const {},
}) =>
    NotificationModel(
      id: _uuid(id),
      title: 'title $id',
      body: 'body $id',
      category: category,
      isRead: isRead,
      createdAt: at ?? _base.subtract(Duration(minutes: minutesAgo)),
      data: data,
      offerId: offerId,
      requestId: requestId,
      actionRoute: actionRoute,
    );

UserModel _user(Map<String, dynamic> preferences) => UserModel(
      uid: 'user-a',
      name: 'A',
      email: 'a@example.test',
      createdAt: _base,
      subscription: UserSubscription(
        plan: 'free',
        isActive: false,
        features: const [],
      ),
      preferences: preferences,
    );

class _Auth implements AuthViewModel {
  _Auth(this._user);
  final UserModel? _user;

  @override
  UserModel? get currentUser => _user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Users implements UserRepository {
  _Users(this.user);
  final UserModel? user;
  Object? saveError;
  final List<Map<String, dynamic>> saved = [];

  @override
  Future<UserModel?> getUserById(String uid) async => user;

  @override
  Future<void> updateUserPreferences(
    String uid,
    Map<String, dynamic> preferences,
  ) async {
    final error = saveError;
    if (error != null) throw error;
    saved.add(preferences);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FetchCall {
  _FetchCall(this.userId, this.limit, this.startAfter);
  final String userId;
  final int limit;
  final NotificationModel? startAfter;
  final Completer<List<NotificationModel>> answer = Completer();
}

class _Repo implements NotificationRepository {
  final Map<String, StreamController<List<NotificationModel>>> live = {};
  final Map<String, StreamController<int>> unread = {};
  final List<_FetchCall> fetches = [];
  final List<String> deletes = [];
  int watchCalls = 0;
  int countCalls = 0;
  int unreadValue = 0;
  Object? deleteError;

  @override
  Stream<List<NotificationModel>> watchLatestNotifications(
    String userId, {
    int limit = 20,
  }) {
    watchCalls++;
    live[userId]?.close();
    return (live[userId] = StreamController.broadcast(sync: true)).stream;
  }

  @override
  Stream<int> watchUnreadCount(String userId) {
    watchCalls++;
    unread[userId]?.close();
    return (unread[userId] = StreamController.broadcast(sync: true)).stream;
  }

  @override
  Future<int> countUnread(String userId) async {
    countCalls++;
    return unreadValue;
  }

  @override
  Future<List<NotificationModel>> fetchNotifications(
    String userId, {
    int limit = 25,
    NotificationModel? startAfter,
  }) {
    final call = _FetchCall(userId, limit, startAfter);
    fetches.add(call);
    return call.answer.future;
  }

  @override
  Future<void> deleteNotification(String userId, String notificationId) async {
    final error = deleteError;
    if (error != null) throw error;
    deletes.add(notificationId);
  }

  @override
  Future<void> markAsRead(String userId, String notificationId) async {}

  @override
  Future<void> markAllAsRead(String userId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<String> _ids(NotificationViewModel vm) =>
    vm.notifications.map((item) => item.id).toList();

void main() {
  group('notification settings keys', () {
    const kept = [
      'matchAlerts',
      'requestReminders',
      'offerReminders',
      'planAlerts',
      'push',
    ];

    test('the screen offers exactly the approved keys', () {
      expect(NotificationSettingsViewModel.settingKeys, kept);
    });

    test('every kept key is restored from the stored preferences', () async {
      final users = _Users(_user({
        'notificationsEnabled': false,
        'notifications': {
          'matchAlerts': false,
          'requestReminders': true,
          'offerReminders': false,
          'planAlerts': false,
          'push': false,
        },
      }));
      final vm = NotificationSettingsViewModel(
        authViewModel: _Auth(users.user),
        userRepository: users,
      );
      await vm.initialize();
      expect(vm.notificationsEnabled, isFalse);
      expect(vm.toggles, {
        'matchAlerts': false,
        'requestReminders': true,
        'offerReminders': false,
        'planAlerts': false,
        'push': false,
      });
    });

    test('a save writes the kept keys only and drops the retired ones',
        () async {
      final users = _Users(_user({
        'theme': 'dark',
        'notifications': {'statusReminders': false, 'systemUpdates': false},
      }));
      final vm = NotificationSettingsViewModel(
        authViewModel: _Auth(users.user),
        userRepository: users,
      );
      await vm.initialize();
      await vm.toggleSetting('planAlerts', false);
      expect(users.saved, hasLength(1));
      final saved = users.saved.single;
      expect(saved.keys,
          unorderedEquals(['notificationsEnabled', 'notifications']));
      expect((saved['notifications'] as Map).keys, unorderedEquals(kept));
      expect((saved['notifications'] as Map)['planAlerts'], isFalse);
      expect(vm.toggles['planAlerts'], isFalse);
    });

    test('a failed save puts the switch back', () async {
      final users = _Users(_user(const {}))..saveError = StateError('down');
      final vm = NotificationSettingsViewModel(
        authViewModel: _Auth(users.user),
        userRepository: users,
      );
      await vm.initialize();
      await vm.toggleSetting('matchAlerts', false);
      expect(vm.toggles['matchAlerts'], isTrue);
      await vm.toggleMaster(false);
      expect(vm.notificationsEnabled, isTrue);
    });

    test('without a loaded profile nothing pretends to be saved', () async {
      final users = _Users(null);
      final vm = NotificationSettingsViewModel(
        authViewModel: _Auth(_user(const {})),
        userRepository: users,
      );
      await vm.initialize();
      await vm.toggleSetting('push', false);
      expect(vm.toggles['push'], isTrue);
      expect(users.saved, isEmpty);
    });

    test('keys the screen does not offer are ignored', () async {
      final users = _Users(_user(const {}));
      final vm = NotificationSettingsViewModel(
        authViewModel: _Auth(users.user),
        userRepository: users,
      );
      await vm.initialize();
      await vm.toggleSetting('systemUpdates', false);
      expect(vm.toggles.containsKey('systemUpdates'), isFalse);
      expect(users.saved, isEmpty);
    });
  });

  group('notification rows', () {
    Map<String, dynamic> row({
      String? id,
      Object? category = 'reminder',
      Object? createdAt = '2026-11-20T12:00:00.123456+00:00',
    }) =>
        {
          'id': id ?? _uuid(1),
          'title': 't',
          'body': 'b',
          'category': category,
          'is_read': false,
          'created_at': createdAt,
          'data': null,
        };

    test('offered categories are read, quota stays a plan alert', () {
      expect(parseNotificationRow(row(category: 'match'))?.category,
          NotificationCategory.match);
      expect(parseNotificationRow(row(category: 'quota'))?.category,
          NotificationCategory.plan);
      final parsed = parseNotificationRow(row())!;
      expect(parsed.createdAt.microsecond, 456);
      expect(parsed.data, isEmpty);
    });

    test('system, unknown and missing categories are not shown', () {
      for (final category in ['system', 'promo', '', null]) {
        expect(parseNotificationRow(row(category: category)), isNull,
            reason: '$category');
      }
    });

    test('a row without a readable time or id is not shown', () {
      expect(parseNotificationRow(row(createdAt: 'not a date')), isNull);
      expect(parseNotificationRow(row(createdAt: null)), isNull);
      expect(parseNotificationRow(row(id: '')), isNull);
      expect(
        parseNotificationRows([row(), row(category: 'system')]),
        hasLength(1),
      );
    });

    test('the page cursor breaks timestamp ties by id', () {
      final cursor = _n(7, at: DateTime.utc(2026, 1, 2, 3, 4, 5, 6, 7));
      expect(
        notificationKeysetFilter(cursor),
        'created_at.lt.2026-01-02T03:04:05.006007Z,'
        'and(created_at.eq.2026-01-02T03:04:05.006007Z,id.lt.${_uuid(7)})',
      );
    });
  });

  group('notification feed', () {
    test('offline: no feed is opened and no spinner is left', () {
      final repo = _Repo();
      final vm = NotificationViewModel(repository: repo, isOnline: () => false)
        ..attachUser('user-a');
      expect(repo.watchCalls, 0);
      expect(vm.isLoading, isFalse);
      expect(vm.isOffline, isTrue);
      vm.dispose();
    });

    test('a page answered for the previous account is dropped', () async {
      final repo = _Repo();
      final vm = NotificationViewModel(repository: repo, isOnline: () => true)
        ..attachUser('user-a');
      final refreshing = vm.refresh();
      vm.attachUser('user-b');
      repo.live['user-b']!.add([_n(2)]);
      repo.fetches.first.answer.complete([_n(1)]);
      await refreshing;
      expect(_ids(vm), [_uuid(2)]);
      vm.dispose();
    });

    test('paging after the live feed keeps every tied row exactly once',
        () async {
      final repo = _Repo();
      final vm = NotificationViewModel(repository: repo, isOnline: () => true)
        ..attachUser('user-a');
      final tie = _base.subtract(const Duration(hours: 1));
      // 20 live rows; the last two share a timestamp with rows not loaded.
      repo.live['user-a']!.add([
        for (var i = 0; i < 18; i++) _n(100 + i, minutesAgo: i),
        _n(51, at: tie),
        _n(50, at: tie),
      ]);
      expect(vm.hasMore, isTrue);

      final more = vm.loadMore();
      final first = repo.fetches.single;
      expect(first.startAfter!.createdAt, tie);
      expect(first.startAfter!.id, 'ffffffff-ffff-ffff-ffff-ffffffffffff');
      first.answer.complete(
          [_n(52, at: tie), _n(51, at: tie), _n(50, at: tie), _n(49, at: tie)]);
      await more;

      expect(vm.notifications, hasLength(22));
      expect(_ids(vm).toSet(), hasLength(22));
      expect(
        _ids(vm).sublist(18),
        [_uuid(52), _uuid(51), _uuid(50), _uuid(49)],
      );
      expect(vm.hasMore, isFalse, reason: 'a short page is the last one');
      vm.dispose();
    });

    test('the next page starts strictly after the last page read', () async {
      final repo = _Repo();
      final vm = NotificationViewModel(repository: repo, isOnline: () => true)
        ..attachUser('user-a');
      repo.live['user-a']!
          .add([for (var i = 0; i < 20; i++) _n(100 + i, minutesAgo: i)]);
      final page = [
        for (var i = 0; i < 25; i++) _n(200 - i, minutesAgo: 30 + i)
      ];
      final first = vm.loadMore();
      repo.fetches.last.answer.complete(page);
      await first;
      expect(vm.hasMore, isTrue);
      final second = vm.loadMore();
      expect(repo.fetches.last.startAfter, same(page.last));
      repo.fetches.last.answer.complete(const []);
      await second;
      expect(vm.hasMore, isFalse);
      expect(vm.notifications, hasLength(45));
      vm.dispose();
    });

    test('a live event keeps the older pages', () async {
      final repo = _Repo();
      final vm = NotificationViewModel(repository: repo, isOnline: () => true)
        ..attachUser('user-a');
      repo.live['user-a']!
          .add([for (var i = 0; i < 20; i++) _n(100 + i, minutesAgo: i)]);
      final more = vm.loadMore();
      repo.fetches.last.answer.complete([_n(1, minutesAgo: 90)]);
      await more;
      repo.live['user-a']!.add(
          [_n(300), for (var i = 0; i < 19; i++) _n(100 + i, minutesAgo: i)]);
      expect(_ids(vm), contains(_uuid(1)));
      expect(_ids(vm).first, _uuid(300));
      vm.dispose();
    });

    test('a failed older page stops automatic retries until asked', () async {
      final repo = _Repo();
      final vm = NotificationViewModel(repository: repo, isOnline: () => true)
        ..attachUser('user-a');
      repo.live['user-a']!
          .add([for (var i = 0; i < 20; i++) _n(100 + i, minutesAgo: i)]);
      final failing = vm.loadMore();
      repo.fetches.last.answer.completeError(StateError('network'));
      await failing;
      expect(vm.loadMoreFailed, isTrue);
      await vm.loadMore();
      expect(repo.fetches, hasLength(1));
      final retry = vm.retryLoadMore();
      expect(repo.fetches, hasLength(2));
      repo.fetches.last.answer.complete(const []);
      await retry;
      expect(vm.loadMoreFailed, isFalse);
      vm.dispose();
    });

    test('a feed error shows as unavailable and refresh reopens it', () async {
      final repo = _Repo();
      final vm = NotificationViewModel(repository: repo, isOnline: () => true)
        ..attachUser('user-a');
      repo.live['user-a']!.addError(StateError('channel refused'));
      expect(vm.isFeedUnavailable, isTrue);
      expect(vm.isLoading, isFalse);
      expect(repo.watchCalls, 2);
      final refreshing = vm.refresh();
      expect(repo.watchCalls, 4);
      repo.fetches.last.answer.complete([_n(1)]);
      await refreshing;
      expect(vm.isFeedUnavailable, isFalse);
      expect(_ids(vm), [_uuid(1)]);
      vm.dispose();
    });

    test('a failed refresh is reported, not shown as all caught up', () async {
      final repo = _Repo();
      final vm = NotificationViewModel(repository: repo, isOnline: () => true)
        ..attachUser('user-a');
      final refreshing = vm.refresh();
      repo.fetches.last.answer.completeError(StateError('network'));
      await refreshing;
      expect(vm.isFeedUnavailable, isTrue);
      expect(vm.isLoading, isFalse);
      vm.dispose();
    });

    test('a refused delete puts the row back in its place', () async {
      final repo = _Repo()..deleteError = StateError('refused');
      final vm = NotificationViewModel(repository: repo, isOnline: () => true)
        ..attachUser('user-a');
      repo.live['user-a']!
          .add([_n(3), _n(2, minutesAgo: 1), _n(1, minutesAgo: 2)]);
      final deleting = vm.deleteNotification(_uuid(2));
      expect(_ids(vm), [_uuid(3), _uuid(1)]);
      await deleting;
      expect(_ids(vm), [_uuid(3), _uuid(2), _uuid(1)]);
      expect(repo.countCalls, 0);
      vm.dispose();
    });

    test('a confirmed delete stays removed and recounts unread', () async {
      final repo = _Repo()..unreadValue = 4;
      final vm = NotificationViewModel(repository: repo, isOnline: () => true)
        ..attachUser('user-a');
      repo.live['user-a']!.add([_n(3), _n(2, minutesAgo: 1)]);
      await vm.deleteNotification(_uuid(2));
      await pumpEventQueue();
      expect(_ids(vm), [_uuid(3)]);
      expect(repo.deletes, [_uuid(2)]);
      expect(vm.unreadCount, 4);
      vm.dispose();
    });

    test('the unread badge takes the server count, not the loaded rows', () {
      final repo = _Repo();
      final vm = NotificationViewModel(repository: repo, isOnline: () => true)
        ..attachUser('user-a');
      repo.live['user-a']!.add([_n(1)]);
      repo.unread['user-a']!.add(731);
      expect(vm.unreadCount, 731);
      vm.dispose();
    });
  });

  group('notification tap targets', () {
    test('match opens match details only with two record ids', () {
      final target = notificationTarget(_n(1,
          category: NotificationCategory.match,
          offerId: _uuid(8),
          requestId: _uuid(9)))!;
      expect(target.location, '/match-details');
      expect(target.extra, {
        'requestId': _uuid(9),
        'offerId': _uuid(8),
        'matchScore': null,
      });
      expect(
        notificationTarget(
            _n(1, category: NotificationCategory.match, offerId: _uuid(8))),
        isNull,
      );
    });

    test('reminder opens the offer or the request by validated id', () {
      expect(
        notificationTarget(_n(1, offerId: _uuid(8)))!.location,
        '/offers-details-by-id/${_uuid(8)}',
      );
      expect(
        notificationTarget(_n(1, requestId: _uuid(9)))!.location,
        '/requested-details-by-id/${_uuid(9)}',
      );
      expect(notificationTarget(_n(1, offerId: '../delete-account')), isNull);
      expect(notificationTarget(_n(1, offerId: '1/edit')), isNull);
    });

    test('stored routes and URLs are never followed', () {
      expect(
        notificationTarget(_n(1, actionRoute: '/delete-account', data: {
          'route': '/delete-account',
          'storeUrl': 'https://example.test',
        })),
        isNull,
      );
      expect(
        notificationTarget(_n(1,
                category: NotificationCategory.plan,
                actionRoute: '/delete-account'))!
            .location,
        '/my-plan',
      );
    });
  });
}
