import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/pdf_viewer_screen.dart';

/// Model class to represent a signed document
class SignedDocument {
  final String id;
  final String name;
  final String filePath;
  final DateTime createdAt;
  final int fileSize;
  final int pageCount;
  final int signatureCount;

  SignedDocument({
    required this.id,
    required this.name,
    required this.filePath,
    required this.createdAt,
    required this.fileSize,
    required this.pageCount,
    required this.signatureCount,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'filePath': filePath,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'fileSize': fileSize,
      'pageCount': pageCount,
      'signatureCount': signatureCount,
    };
  }

  factory SignedDocument.fromJson(Map<String, dynamic> json) {
    return SignedDocument(
      id: json['id'],
      name: json['name'],
      filePath: json['filePath'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']),
      fileSize: json['fileSize'],
      pageCount: json['pageCount'],
      signatureCount: json['signatureCount'],
    );
  }
}

/// Storage manager for signed documents
class SignedDocumentsStorage {
  static const String _storageKey = 'signed_documents_list';
  static const String _viewModeKey = 'signed_docs_list_view_mode';

  /// Load all signed documents from storage
  static Future<List<SignedDocument>> loadDocuments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final documentsJson = prefs.getStringList(_storageKey) ?? [];

      final documents = <SignedDocument>[];
      for (final docJson in documentsJson) {
        try {
          final doc = SignedDocument.fromJson(json.decode(docJson));
          // Verify file still exists
          if (await File(doc.filePath).exists()) {
            documents.add(doc);
          }
        } catch (e) {}
      }

      return documents;
    } catch (e) {
      return [];
    }
  }

  /// Save all signed documents to storage
  static Future<void> saveDocuments(List<SignedDocument> documents) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final documentsJson =
          documents.map((doc) => json.encode(doc.toJson())).toList();
      await prefs.setStringList(_storageKey, documentsJson);
    } catch (e) {}
  }

  /// Load view mode preference
  static Future<bool> loadViewMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_viewModeKey) ??
          false; // false = grid view (default)
    } catch (e) {
      return false; // default to grid view
    }
  }

  /// Save view mode preference
  static Future<void> saveViewMode(bool isListView) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_viewModeKey, isListView);
    } catch (e) {}
  }

  /// Get application documents directory for saving PDFs
  static Future<String> getDocumentsPath() async {
    final directory = await getApplicationDocumentsDirectory();
    final signedDocsDir = Directory('${directory.path}/signed_documents');
    if (!await signedDocsDir.exists()) {
      await signedDocsDir.create(recursive: true);
    }
    return signedDocsDir.path;
  }
}

/// Helper functions for signed documents
class SignedDocumentsHelper {
  /// Format file size in human-readable format
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Format date time in relative format
  static String formatDateTime(
      DateTime dateTime, AppLocalizations localization) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays} ${localization.translate('daysAgo')}';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${localization.translate('hoursAgo')}';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${localization.translate('minutesAgo')}';
    } else {
      return localization.translate('justNow');
    }
  }

  /// Show toast message
  static void showToast(String message, Color bgColor) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: bgColor,
      textColor: Colors.white,
    );
  }

  /// Preview a signed document
  static void previewDocument(BuildContext context, SignedDocument document) {
    try {
      final file = File(document.filePath);
      if (!file.existsSync()) {
        final localization = AppLocalizations.of(context);
        showToast(localization.translate('documentFileNotFound'), Colors.red);
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PdfViewerScreen(
            localFile: file,
            title: document.name,
          ),
        ),
      );
    } catch (e) {
      final localization = AppLocalizations.of(context);
      showToast(localization.translate('failedToOpenDocument'), Colors.red);
    }
  }

  /// Share a signed document
  static Future<void> shareDocument(
      BuildContext context, SignedDocument document) async {
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(document.filePath)]),
      );
    } catch (e) {
      final localization = AppLocalizations.of(context);
      showToast(localization.translate('failedToShareDocument'), Colors.red);
    }
  }

  /// Rename a signed document
  static Future<bool> renameDocument(
    BuildContext context,
    SignedDocument document,
    List<SignedDocument> allDocuments,
  ) async {
    final localization = AppLocalizations.of(context);
    final controller = TextEditingController(text: document.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localization.translate('renameDocument')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: localization.translate('documentName'),
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localization.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(localization.translate('rename')),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != document.name) {
      final index = allDocuments.indexWhere((doc) => doc.id == document.id);
      if (index != -1) {
        allDocuments[index] = SignedDocument(
          id: document.id,
          name: newName,
          filePath: document.filePath,
          createdAt: document.createdAt,
          fileSize: document.fileSize,
          pageCount: document.pageCount,
          signatureCount: document.signatureCount,
        );
        await SignedDocumentsStorage.saveDocuments(allDocuments);
        showToast(localization.translate('documentRenamed'), Colors.green);
        return true;
      }
    }
    return false;
  }

  /// Delete a signed document
  static Future<bool> deleteDocument(
    BuildContext context,
    SignedDocument document,
    List<SignedDocument> allDocuments,
  ) async {
    final localization = AppLocalizations.of(context);

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localization.translate('confirmDelete')),
        content: Text(
          '${localization.translate('deleteDocumentConfirm')} "${document.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(localization.translate('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(localization.translate('delete')),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        final file = File(document.filePath);
        if (await file.exists()) {
          await file.delete();
        }

        allDocuments.removeWhere((doc) => doc.id == document.id);
        await SignedDocumentsStorage.saveDocuments(allDocuments);
        showToast(localization.translate('documentDeleted'), Colors.green);
        return true;
      } catch (e) {
        showToast(
          '${localization.translate('failedToDeleteDocument')}: $e',
          Colors.red,
        );
      }
    }
    return false;
  }
}
