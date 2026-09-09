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
}
