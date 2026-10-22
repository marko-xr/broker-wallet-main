import 'package:flutter/foundation.dart';

/// Compile-time configuration for the profile-image Worker.
///
/// The Worker owns all R2 and Supabase privileged credentials. This class only
/// contains its public HTTPS endpoint.
abstract final class R2Config {
  static const String _configuredWorkerUrl = String.fromEnvironment(
    'R2_UPLOAD_WORKER_URL',
    defaultValue: 'https://media-api.brokerwallet.ae',
  );

  static String get workerUrl {
    final value = _configuredWorkerUrl.trim();
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  static bool get isConfigured => workerUrl.trim().isNotEmpty;

  // -------------------------------------------------------------------------
  // Toolkit cloud documents: the staging overrides (debug test builds only)
  //
  // Toolkit documents may be pointed at a different Worker than the rest of the
  // app, so a staging test of the cloud documents never moves Profile images,
  // Offer media, plans or account deletion: those keep using [workerUrl].
  //
  //   --dart-define=TOOLKIT_WORKER_URL=https://<staging worker>   (Toolkit only)
  //   --dart-define=TOOLKIT_STAGING_KEY=<gate key>                (Toolkit only)
  //
  // Both are honored in a DEBUG build only. Profile and release builds ignore
  // them completely and use [workerUrl], where the staging gate does not exist.
  // The key is a development convenience compiled into a debug app: it gates a
  // staging Worker, it is not an authentication mechanism, and it is never sent
  // to the shared (production) address.
  // -------------------------------------------------------------------------

  static const String _configuredToolkitWorkerUrl = String.fromEnvironment(
    'TOOLKIT_WORKER_URL',
  );

  static const String _configuredStagingKey = String.fromEnvironment(
    'TOOLKIT_STAGING_KEY',
  );

  /// The address Toolkit documents talk to: the shared Worker, or in a debug
  /// build the one named by `TOOLKIT_WORKER_URL`. Null when an address was named
  /// but is not a usable http(s) address: Toolkit then stays off instead of
  /// quietly falling back to the shared Worker.
  static String? get toolkitWorkerUrl => resolveToolkitWorkerUrl(
        shared: workerUrl,
        override: _configuredToolkitWorkerUrl,
        debugBuild: kDebugMode,
      );

  /// The staging gate key for Toolkit requests, or an empty string.
  static String get toolkitStagingKey => resolveToolkitStagingKey(
        shared: workerUrl,
        toolkit: toolkitWorkerUrl,
        key: _configuredStagingKey,
        debugBuild: kDebugMode,
      );

  /// Whether Toolkit documents have an address to use.
  static bool get isToolkitConfigured {
    final url = toolkitWorkerUrl;
    return url != null && url.isNotEmpty;
  }

  /// The pure rule behind [toolkitWorkerUrl].
  @visibleForTesting
  static String? resolveToolkitWorkerUrl({
    required String shared,
    required String override,
    required bool debugBuild,
  }) {
    final named = override.trim();
    if (!debugBuild || named.isEmpty) return shared;
    final uri = Uri.tryParse(named);
    final usable = uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
    if (!usable) return null;
    return named.endsWith('/') ? named.substring(0, named.length - 1) : named;
  }

  /// The pure rule behind [toolkitStagingKey]: only a debug build, only when
  /// Toolkit has its own address, and never for the shared address's host.
  @visibleForTesting
  static String resolveToolkitStagingKey({
    required String shared,
    required String? toolkit,
    required String key,
    required bool debugBuild,
  }) {
    final value = key.trim();
    if (!debugBuild || value.isEmpty || toolkit == null || toolkit == shared) {
      return '';
    }
    final toolkitHost = Uri.tryParse(toolkit)?.host.toLowerCase();
    final sharedHost = Uri.tryParse(shared)?.host.toLowerCase();
    if (toolkitHost == null ||
        toolkitHost.isEmpty ||
        toolkitHost == sharedHost) {
      return '';
    }
    return value;
  }
}
