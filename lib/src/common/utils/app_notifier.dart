import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

/// Small helper that centralizes transient user feedback.
///
/// Behavior:
/// - If a ScaffoldMessenger is available, prefers showing a SnackBar (so
///   actions like "Retry" or "Settings" work and the message is attached
///   to the UI).
/// - Otherwise falls back to a toast (works from services or background
///   contexts where a Scaffold isn't present).
class AppNotifier {
  /// Show a message to the user. If [actionLabel] and [onAction] are
  /// provided and a ScaffoldMessenger is available, a SnackBar with an
  /// action will be shown. Otherwise a simple SnackBar or a Toast will be
  /// used as a fallback.
  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);

    // Prefer SnackBar when possible (supports action and accessibility).
    if (messenger != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.check_circle,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: isError ? Colors.red : Colors.green,
          duration: duration ?? const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          action: (actionLabel != null && onAction != null)
              ? SnackBarAction(
                  label: actionLabel,
                  textColor: Colors.white,
                  onPressed: onAction,
                )
              : null,
        ),
      );
      return;
    }

    // Fallback to toast if no ScaffoldMessenger is available.
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 3,
      backgroundColor: isError ? Colors.red : Colors.green,
      textColor: Colors.white,
    );
  }
}
