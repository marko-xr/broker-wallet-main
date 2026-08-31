import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service to check for app updates and handle version management
/// Works with Cloud Function `checkAppUpdate` and Firestore `app_config/latest_version`
class AppVersionService {
  static final AppVersionService instance = AppVersionService._internal();
  AppVersionService._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _currentVersion;
  String? _currentBuildNumber;

  /// Initialize with current app version
  Future<void> initialize() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = packageInfo.version;
      _currentBuildNumber = packageInfo.buildNumber;
      print('📱 App Version: $_currentVersion+$_currentBuildNumber');
    } catch (e) {
      print('⚠️ Failed to get package info: $e');
      _currentVersion = '1.0.0';
      _currentBuildNumber = '1';
    }
  }

  String get currentVersion => _currentVersion ?? '1.0.0';
  String get currentBuildNumber => _currentBuildNumber ?? '1';

  /// Check if an app update is available
  /// Returns [AppUpdateInfo] with update details or null if no update
  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      if (_currentVersion == null) {
        await initialize();
      }

      // Try Cloud Function first (more reliable, handles version comparison)
      try {
        final result = await _functions
            .httpsCallable('checkAppUpdate')
            .call({'currentVersion': _currentVersion});

        final data = result.data as Map<String, dynamic>;

        if (data['updateAvailable'] == true) {
          return AppUpdateInfo(
            latestVersion: data['latestVersion'] as String,
            mandatory: data['mandatory'] as bool? ?? false,
            storeUrl: data['storeUrl'] as String?,
          );
        }
        return null;
      } catch (e) {
        print('⚠️ Cloud Function check failed, falling back to Firestore: $e');
      }

      // Fallback to direct Firestore read (for offline or function unavailable)
      final doc =
          await _firestore.collection('app_config').doc('latest_version').get();

      if (!doc.exists) return null;

      final data = doc.data()!;
      final latestVersion = data['version'] as String?;

      if (latestVersion == null) return null;

      final updateAvailable =
          _compareVersions(_currentVersion!, latestVersion) < 0;

      if (updateAvailable) {
        return AppUpdateInfo(
          latestVersion: latestVersion,
          mandatory: data['mandatory'] as bool? ?? false,
          storeUrl: data['storeUrl'] as String?,
        );
      }

      return null;
    } catch (e) {
      print('❌ Error checking for update: $e');
      return null;
    }
  }

  /// Compare two semantic versions
  /// Returns: -1 if v1 < v2, 0 if equal, 1 if v1 > v2
  int _compareVersions(String v1, String v2) {
    final parts1 = v1.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final parts2 = v2.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    final maxLength =
        parts1.length > parts2.length ? parts1.length : parts2.length;

    for (int i = 0; i < maxLength; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;

      if (p1 < p2) return -1;
      if (p1 > p2) return 1;
    }

    return 0;
  }

  /// Open the app store for update
  Future<void> openAppStore({String? storeUrl}) async {
    // Use provided URL or default store URLs
    final String url = storeUrl ?? _getDefaultStoreUrl();

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      print('❌ Failed to open store: $e');
    }
  }

  String _getDefaultStoreUrl() {
    // TODO: Replace with actual app store URLs when published
    // For Android
    // return 'https://play.google.com/store/apps/details?id=com.yourcompany.brokerwallet';
    // For iOS
    // return 'https://apps.apple.com/app/id123456789';
    return 'https://play.google.com/store';
  }

  /// Stream to listen for version updates in real-time
  Stream<AppUpdateInfo?> watchForUpdates() {
    return _firestore
        .collection('app_config')
        .doc('latest_version')
        .snapshots()
        .asyncMap((snapshot) async {
      if (!snapshot.exists) return null;

      if (_currentVersion == null) {
        await initialize();
      }

      final data = snapshot.data()!;
      final latestVersion = data['version'] as String?;

      if (latestVersion == null) return null;

      final updateAvailable =
          _compareVersions(_currentVersion!, latestVersion) < 0;

      if (updateAvailable) {
        return AppUpdateInfo(
          latestVersion: latestVersion,
          mandatory: data['mandatory'] as bool? ?? false,
          storeUrl: data['storeUrl'] as String?,
        );
      }

      return null;
    });
  }
}

/// Model representing app update information
class AppUpdateInfo {
  final String latestVersion;
  final bool mandatory;
  final String? storeUrl;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.mandatory,
    this.storeUrl,
  });

  @override
  String toString() => 'AppUpdateInfo(v$latestVersion, mandatory: $mandatory)';
}
