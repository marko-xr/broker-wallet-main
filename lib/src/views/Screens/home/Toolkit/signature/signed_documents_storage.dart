import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/share/share_live.dart';
import 'package:broker_wallet/src/services/signature/signature_models.dart';
import 'package:broker_wallet/src/viewmodels/signature/signature_library_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/signature_ui_support.dart';

/// The one preference this tool keeps outside the signed-in account: whether the
/// library is shown as a list or a grid. It is a view setting, not a document, so
/// it is not account-scoped.
///
/// Signed documents themselves live in the account-scoped
/// [SignatureStore]. The old device-wide `signed_documents_list` preference and
/// the `signed_documents/` folder it pointed at carried no owner; they are left
/// exactly as they were and are neither read, shown, moved nor deleted (see
/// `docs/DECISIONS.md`).
class SignedDocumentsStorage {
  const SignedDocumentsStorage._();

  static const String _viewModeKey = 'signed_docs_list_view_mode';

  /// Load view mode preference (true = list view, false = grid view).
  static Future<bool> loadViewMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_viewModeKey) ?? false; // grid view by default
    } catch (e) {
      return false;
    }
  }

  /// Save view mode preference.
  static Future<void> saveViewMode(bool isListView) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_viewModeKey, isListView);
    } catch (e) {
      // The choice still applies for this visit.
    }
  }
}

/// Helper functions for the signed documents screen.
class SignedDocumentsHelper {
  const SignedDocumentsHelper._();

  /// Format file size in human-readable format.
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Show toast message.
  static void showToast(String message, Color bgColor) {
    showSignatureToast(message, bgColor);
  }

  /// Share signed documents together, in one share sheet. Each is copied under
  /// its title first, so the receiving app sees "Lease.pdf", never an internal
  /// id, and only documents whose stored file is intact are shared. Nothing in
  /// the share text names a path or an id.
  static Future<void> shareDocuments(
    BuildContext context,
    SignatureLibraryViewModel viewModel,
    List<SignedDocument> documents,
  ) async {
    if (documents.isEmpty) return;
    final localization = AppLocalizations.of(context);
    try {
      final preparation =
          await viewModel.prepareShare(documents.map((d) => d.id).toList());
      if (!context.mounted) return;
      if (!preparation.isShareable) {
        showToast(
          preparation.unavailable.isNotEmpty
              ? localization.translate('documentFileNotFound')
              : localization.translate('failedToShareDocuments'),
          Colors.red,
        );
        return;
      }
      await ShareLive.sendFiles(
        context,
        preparation.paths,
        text: documents.length == 1
            ? localization
                .translate('sigShareText')
                .replaceAll('{name}', documents.first.name)
            : localization
                .translate('sharingDocuments')
                .replaceAll('{count}', '${documents.length}'),
      );
    } catch (e) {
      if (!context.mounted) return;
      showToast(localization.translate('failedToShareDocuments'), Colors.red);
    }
  }
}
