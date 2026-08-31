import 'package:broker_wallet/src/data/models/user_model.dart';
import 'package:broker_wallet/src/repositories/repository_provider.dart';
import 'package:broker_wallet/src/repositories/user_repository.dart';
import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
import 'package:flutter/foundation.dart';

class NotificationSettingsViewModel extends ChangeNotifier {
  NotificationSettingsViewModel({required this.authViewModel})
      : _userRepository = RepositoryProvider.instance.userRepository;

  final AuthViewModel authViewModel;
  final UserRepository _userRepository;

  bool _isLoading = true;
  bool _notificationsEnabled = true;
  Map<String, bool> _toggles = {
    'matchAlerts': true,
    'requestReminders': true,
    'offerReminders': true,
    'statusReminders': true,
    'push': true,
  };

  bool get isLoading => _isLoading;
  bool get notificationsEnabled => _notificationsEnabled;
  Map<String, bool> get toggles => _toggles;

  UserModel? _user;

  Future<void> initialize() async {
    final uid = authViewModel.currentUser?.uid;
    if (uid == null) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      _user = await _userRepository.getUserById(uid);
      final prefs = _user?.preferences ?? {};
      _notificationsEnabled = prefs['notificationsEnabled'] as bool? ?? true;
      final nested = Map<String, dynamic>.from(prefs['notifications'] ?? {});
      _toggles = {
        'matchAlerts': nested['matchAlerts'] as bool? ?? true,
        'requestReminders': nested['requestReminders'] as bool? ?? true,
        'offerReminders': nested['offerReminders'] as bool? ?? true,
        'statusReminders': nested['statusReminders'] as bool? ?? true,
        'push': nested['push'] as bool? ?? true,
      };
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Failed to load notification settings: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleMaster(bool enabled) async {
    _notificationsEnabled = enabled;
    await _persist();
    notifyListeners();
  }

  Future<void> toggleSetting(String key, bool value) async {
    _toggles = Map<String, bool>.from(_toggles)..[key] = value;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    if (_user == null) return;
    final prefs = Map<String, dynamic>.from(_user!.preferences);
    prefs['notificationsEnabled'] = _notificationsEnabled;
    prefs['notifications'] = {
      ..._toggles,
    };

    _user = _user!.copyWith(preferences: prefs);
    await _userRepository.updateUser(_user!);
  }
}
