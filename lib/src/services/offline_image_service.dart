import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;

/// Service to handle offline image loading errors gracefully
class OfflineImageService {
  static final OfflineImageService _instance = OfflineImageService._internal();
  factory OfflineImageService() => _instance;
  OfflineImageService._internal();

  static bool _isOfflineImageLoggingEnabled = true;
  static bool _hasShownOfflineImageWarning = false;

  /// Initialize offline image error handling
  static void initialize() {
    if (kDebugMode) {
      // Only suppress in release mode to avoid hiding real issues during development
      return;
    }

    // Override Flutter's error reporting for specific image errors
    FlutterError.onError = (FlutterErrorDetails details) {
      if (_isImageLoadingError(details)) {
        _handleImageLoadingError(details);
      } else {
        // Let other errors pass through to default handler
        FlutterError.presentError(details);
      }
    };
  }

  /// Check if error is related to offline image loading
  static bool _isImageLoadingError(FlutterErrorDetails details) {
    final error = details.exception.toString().toLowerCase();
    final stack = details.stack.toString().toLowerCase();

    // Check for Firebase Storage related errors
    final isFirebaseStorageError =
        error.contains('firebasestorage.googleapis.com') ||
            error.contains('failed host lookup') ||
            error.contains('clientsocketexception') ||
            error.contains('socketexception');

    // Check if it's from image loading context
    final isImageContext = stack.contains('image') ||
        stack.contains('network') ||
        stack.contains('precache') ||
        details.context?.toString().toLowerCase().contains('image') == true;

    return isFirebaseStorageError && isImageContext;
  }

  /// Handle image loading errors gracefully
  static void _handleImageLoadingError(FlutterErrorDetails details) {
    if (_isOfflineImageLoggingEnabled && !_hasShownOfflineImageWarning) {
      developer.log(
        'Offline Mode: Firebase Storage images temporarily unavailable',
        name: 'OfflineImageService',
        level: 800, // Info level
      );
      _hasShownOfflineImageWarning = true;
    }

    // Don't present the error to the user - it's expected when offline
    // The CachedNetworkImage widgets will handle fallbacks appropriately
  }

  /// Disable offline image error logging (useful for testing)
  static void disableLogging() {
    _isOfflineImageLoggingEnabled = false;
  }

  /// Enable offline image error logging
  static void enableLogging() {
    _isOfflineImageLoggingEnabled = true;
    _hasShownOfflineImageWarning = false;
  }

  /// Reset warning state (useful for testing different scenarios)
  static void resetWarningState() {
    _hasShownOfflineImageWarning = false;
  }
}
