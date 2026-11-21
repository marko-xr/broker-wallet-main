import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:flutter/foundation.dart';

class NotificationSettingsViewModel extends ChangeNotifier {
  NotificationSettingsViewModel({
    required this.authViewModel,
    UserRepository? userRepository,
  }) : _userRepository =
            userRepository ?? RepositoryProvider.instance.userRepository;

  /// The notification preferences the app offers, in screen order. This one
  /// list drives the initial values, the load and the save, so a switch on the
  /// screen can never be shown without also being restored and persisted.
  static const List<String> settingKeys = [
    'matchAlerts',
    'requestReminders',
    'offerReminders',
    'planAlerts',
    'push',
  ];

  final AuthViewModel authViewModel;
  final UserRepository _userRepository;

  bool _isLoading = true;
  bool _notificationsEnabled = true;
  Map<String, bool> _toggles = {for (final key in settingKeys) key: true};

  /// The account whose preferences were loaded. Null when none was loaded,
  /// in which case nothing can be saved and every change is reverted.
  String? _uid;
  bool _disposed = false;

  /// Saves run one after another, each writing the state current when it
  /// starts, so a quick double tap can never persist an older value last.
  Future<void> _saves = Future<void>.value();

  /// The last values loaded or saved in this app run, per account, so the
  /// screen opens at once with them instead of a loading state.
  static final Map<String, ({bool enabled, Map<String, bool> toggles})>
      _lastKnown = {};

  @visibleForTesting
  static void debugForgetLastKnown() => _lastKnown.clear();

  /// Counts the user's changes, so a server answer that arrives after a
  /// change never overwrites it.
  int _changes = 0;

  bool get isLoading => _isLoading;
  bool get notificationsEnabled => _notificationsEnabled;
  Map<String, bool> get toggles => _toggles;

  /// Shows the values the app already has (this run's last known values,
  /// else the signed-in profile's copy) at once, then refreshes them from
  /// the server without a loading state. Only with neither is there one.
  Future<void> initialize() async {
    final uid = authViewModel.currentUser?.uid;
    if (uid == null) {
      _isLoading = false;
      _notify();
      return;
    }

    final known = _lastKnown[uid];
    final profile = authViewModel.currentUser;
    if (known != null) {
      _notificationsEnabled = known.enabled;
      _toggles = Map<String, bool>.from(known.toggles);
      _uid = uid;
      _isLoading = false;
      _notify();
    } else if (profile != null &&
        profile.uid == uid &&
        profile.preferences.isNotEmpty) {
      _apply(profile.preferences);
      _uid = uid;
      _isLoading = false;
      _notify();
    }

    final changesAtStart = _changes;
    try {
      final user = await _userRepository.getUserById(uid);
      if (user != null &&
          !_disposed &&
          _changes == changesAtStart &&
          authViewModel.currentUser?.uid == uid) {
        _apply(user.preferences);
        _uid = uid;
        _remember();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'Failed to load notification settings: ${e.runtimeType}',
        );
      }
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  void _apply(Map<String, dynamic> prefs) {
    _notificationsEnabled = prefs['notificationsEnabled'] as bool? ?? true;
    final nested = prefs['notifications'] is Map
        ? Map<String, dynamic>.from(prefs['notifications'] as Map)
        : const <String, dynamic>{};
    _toggles = {
      for (final key in settingKeys) key: nested[key] as bool? ?? true,
    };
  }

  void _remember() {
    final uid = _uid;
    if (uid == null) return;
    _lastKnown[uid] = (
      enabled: _notificationsEnabled,
      toggles: Map<String, bool>.unmodifiable(_toggles),
    );
  }

  /// Shows the new value at once and reverts it if the save fails.
  Future<void> toggleMaster(bool enabled) {
    final previous = _notificationsEnabled;
    _changes++;
    _notificationsEnabled = enabled;
    _remember();
    _notify();
    return _save(onFailure: () {
      if (_notificationsEnabled == enabled) {
        _notificationsEnabled = previous;
        _remember();
      }
    });
  }

  /// Shows the new value at once and reverts it if the save fails. Keys the
  /// screen does not offer are ignored.
  Future<void> toggleSetting(String key, bool value) {
    if (!settingKeys.contains(key)) return Future<void>.value();
    final previous = _toggles[key] ?? true;
    _changes++;
    _toggles = Map<String, bool>.from(_toggles)..[key] = value;
    _remember();
    _notify();
    return _save(onFailure: () {
      if (_toggles[key] == value) {
        _toggles = Map<String, bool>.from(_toggles)..[key] = previous;
        _remember();
      }
    });
  }

  Future<void> _save({required VoidCallback onFailure}) {
    final run = _saves.then((_) => _persist()).then<void>(
      (_) {},
      onError: (Object error) {
        if (kDebugMode) {
          debugPrint(
            'Failed to save notification settings: ${error.runtimeType}',
          );
        }
        onFailure();
        _notify();
      },
    );
    _saves = run;
    return run;
  }

  /// Writes only the two notification entries of `preferences`; the
  /// repository merges them into the stored map, so other preferences are
  /// never overwritten from an old copy of the profile.
  Future<void> _persist() async {
    final uid = _uid;
    if (uid == null) {
      throw StateError('Notification settings were not loaded.');
    }
    await _userRepository.updateUserPreferences(uid, {
      'notificationsEnabled': _notificationsEnabled,
      'notifications': {for (final key in settingKeys) key: _toggles[key]},
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
