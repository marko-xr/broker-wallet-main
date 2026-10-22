import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Widgets/tool_header_card.dart';
import 'package:broker_wallet/src/Views/Widgets/tool_progress_overlay.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/image_pdf_settings_sheet.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/pdf_viewer_screen.dart';
import 'package:broker_wallet/src/constants/app_colors.dart';
import 'package:broker_wallet/src/services/share/share_live.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_engine.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_models.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_usage_gate.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_wiring.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';
import 'package:broker_wallet/src/viewmodels/image_to_pdf/image_pdf_viewmodel.dart';

/// The Images to PDF tool: pick or photograph images, arrange them, choose the
/// page layout, make the PDF (Preview shows it first) and save it in one step
/// into the signed-in account's private list to preview, rename, share, export and delete. The
/// logic lives in [ImagePdfViewModel]; this file is the screen.
class ImageToPdfView extends StatefulWidget {
  const ImageToPdfView({Key? key, this.viewModel, this.usageGate})
      : super(key: key);

  /// A ready view model, for tests. The app builds its own.
  final ImagePdfViewModel? viewModel;

  /// The plan-limit check, for tests. The app uses [ImagePdfWiring.usageGate].
  final ImagePdfUsageGate? usageGate;

  @override
  _ImageToPdfViewState createState() => _ImageToPdfViewState();
}

class _ImageToPdfViewState extends State<ImageToPdfView> {
  static const String _viewModeKey = 'image_pdf_list_view_mode';
  static const Color _green = Color(0xFF4CAF50);

  late final ImagePdfViewModel _vm;
  late final bool _ownsViewModel;
  final TextEditingController _fileNameController = TextEditingController();
  bool _isViewMode = false; // true for list view, false for grid view
  // Convert is one operation (make the PDF, then save it): the overlay stays up
  // across the two steps instead of blinking off between them.
  bool _converting = false;

  @override
  void initState() {
    super.initState();
    _ownsViewModel = widget.viewModel == null;
    _vm = widget.viewModel ?? ImagePdfWiring.createViewModel();
    _fileNameController.text = _vm.suggestedName;
    _loadViewModePreference();
    _vm.start().then((_) => _recoverLostPicks());
  }

  /// Pictures picked just before Android stopped the app come back here.
  Future<void> _recoverLostPicks() async {
    if (!mounted) return;
    final outcome = await _vm.recoverLostPicks();
    if (!mounted || outcome == null) return;
    if (outcome.added > 0) {
      _showToast(
        _localization
            .translate('i2pRecovered')
            .replaceAll('{count}', '${outcome.added}'),
        Colors.green,
      );
    }
    if (mounted) await _reportAdded(outcome);
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    if (_ownsViewModel) _vm.dispose();
    super.dispose();
  }

  AppLocalizations get _localization => AppLocalizations.of(context);

  // Load and save view mode preference (a view setting, not documents)
  Future<void> _loadViewModePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _isViewMode = prefs.getBool(_viewModeKey) ?? false;
      });
    } catch (e) {
      // The default is fine when preferences cannot be read.
    }
  }

  Future<void> _saveViewModePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_viewModeKey, _isViewMode);
    } catch (e) {
      // The choice still applies for this visit.
    }
  }

  /// The localized text for a failure.
  String _failureMessage(ImagePdfFailure failure) {
    final loc = _localization;
    switch (failure) {
      case ImagePdfFailure.signedOut:
        return loc.translate('i2pErrSignedOut');
      case ImagePdfFailure.busy:
        return loc.translate('i2pErrBusy');
      case ImagePdfFailure.cancelled:
        return loc.translate('i2pErrCancelled');
      case ImagePdfFailure.accountChanged:
        return loc.translate('i2pErrAccountChanged');
      case ImagePdfFailure.noImages:
        return loc.translate('pleaseSelectImagesFirst');
      case ImagePdfFailure.tooManyImages:
        return loc.translate('i2pErrTooMany');
      case ImagePdfFailure.imagesNotReady:
        return loc.translate('i2pErrNotReady');
      case ImagePdfFailure.missingSource:
        return loc.translate('i2pErrMissing');
      case ImagePdfFailure.emptySource:
        return loc.translate('i2pErrEmpty');
      case ImagePdfFailure.corruptSource:
        return loc.translate('i2pErrCorrupt');
      case ImagePdfFailure.unsupportedFormat:
        return loc.translate('i2pErrUnsupported');
      case ImagePdfFailure.tooLargeSource:
        return loc.translate('i2pErrFileTooLarge');
      case ImagePdfFailure.tooManyPixels:
        return loc.translate('i2pErrPixels');
      case ImagePdfFailure.sourceChanged:
        return loc.translate('i2pErrChanged');
      case ImagePdfFailure.invalidSettings:
        return loc.translate('i2pErrSettings');
      case ImagePdfFailure.invalidPassword:
        return loc.translate('i2pErrPassword');
      case ImagePdfFailure.outputInvalid:
        return loc.translate('i2pErrOutputInvalid');
      case ImagePdfFailure.buildFailed:
        return loc.translate('i2pErrBuild');
      case ImagePdfFailure.outputTooLarge:
        return loc.translate('i2pErrOutputTooLarge');
      case ImagePdfFailure.storageFull:
        return loc.translate('i2pErrStorageFull');
      case ImagePdfFailure.writeFailed:
        return loc.translate('i2pErrWrite');
      case ImagePdfFailure.notFound:
        return loc.translate('i2pErrNotFound');
      case ImagePdfFailure.invalidName:
        return loc.translate('i2pErrInvalidName');
      case ImagePdfFailure.nameInUse:
        return loc.translate('i2pErrNameInUse');
      case ImagePdfFailure.fileMissing:
        return loc.translate('documentFileNotFound');
      case ImagePdfFailure.quotaBlocked:
        return loc.translate('i2pErrBusy');
      case ImagePdfFailure.permissionDenied:
        return loc.translate('i2pErrPermission');
      case ImagePdfFailure.pickerFailed:
        return loc.translate('i2pErrPicker');
      case ImagePdfFailure.exportFailed:
        return loc.translate('i2pErrExport');
    }
  }

  // Failures a second attempt can fix (as opposed to a picture that must change).
  static const Set<ImagePdfFailure> _retryable = <ImagePdfFailure>{
    ImagePdfFailure.buildFailed,
    ImagePdfFailure.outputInvalid,
    ImagePdfFailure.writeFailed,
    ImagePdfFailure.storageFull,
  };

  // Delete a converted document
  Future<void> _deleteConvertedDocument(ImagePdfDocument document) async {
    final localization = AppLocalizations.of(context);

    // Show confirmation dialog
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localization.translate('confirmDelete')),
        content: Text(
            '${localization.translate('deleteDocumentConfirm')} "${document.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(localization.translate('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(localization.translate('delete')),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      final failed = await _vm.delete(<String>[document.id]);
      if (!mounted) return;
      if (failed.isEmpty) {
        _showToast(localization.translate('documentDeleted'), Colors.green);
      } else {
        _showToast(
            localization.translate('failedToDeleteDocument'), Colors.red);
      }
    }
  }

  // Rename a converted document
  Future<void> _renameConvertedDocument(ImagePdfDocument document) async {
    final renamed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _RenameDialog(
        initialName: document.name,
        rename: (name) => _vm.rename(document.id, name),
        messageFor: _failureMessage,
      ),
    );
    if (renamed == true && mounted) {
      _showToast(_localization.translate('documentRenamed'), Colors.green);
    }
  }

  // Share converted documents under their titles
  Future<void> _shareDocuments(List<ImagePdfDocument> documents) async {
    if (documents.isEmpty) return;
    final localization = AppLocalizations.of(context);
    try {
      final preparation =
          await _vm.prepareShare(documents.map((d) => d.id).toList());
      if (!mounted) return;
      if (!preparation.isShareable) {
        _showToast(
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
            ? documents.first.name
            : localization
                .translate('sharingDocuments')
                .replaceAll('{count}', '${documents.length}'),
      );
    } catch (e) {
      if (mounted) {
        _showToast(
            localization.translate('failedToShareDocuments'), Colors.red);
      }
    }
  }

  Future<void> _shareConvertedDocument(ImagePdfDocument document) =>
      _shareDocuments(<ImagePdfDocument>[document]);

  // Preview a converted document in the PDF viewer
  Future<void> _previewConvertedDocument(ImagePdfDocument document) async {
    final file = await _vm.openableFile(document);
    if (!mounted) return;
    if (file == null) {
      _showToast(_localization.translate('documentFileNotFound'), Colors.red);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PdfViewerScreen(
          localFile: file,
          title: document.name,
        ),
      ),
    );
  }

  Future<void> _shareBulkDocuments() async {
    final selected = _vm.selectedDocuments;
    await _shareDocuments(selected);
    if (mounted) _vm.exitSelectionMode();
  }

  Future<void> _deleteBulkDocuments() async {
    final localization = AppLocalizations.of(context);
    final selected = _vm.selectedDocuments;
    final count = selected.length;
    if (count == 0) return;

    // Show confirmation dialog
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localization.translate('confirmDelete')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              count == 1
                  ? localization.translate('areYouSureDeleteOneDocument')
                  : '${localization.translate('areYouSureDelete')} $count ${localization.translate('documents')}?',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text(
              localization.translate('cannotRestoreItems'),
              style: TextStyle(
                fontSize: 14,
                color: Colors.red[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(localization.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(localization.translate('delete')),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      final failed = await _vm.delete(selected.map((d) => d.id).toList());
      if (!mounted) return;
      _vm.exitSelectionMode();
      if (failed.isEmpty) {
        _showToast(
          '$count ${count == 1 ? localization.translate('documentDeleted') : localization.translate('documentsDeleted')}',
          Colors.green,
        );
      } else {
        _showToast(
          localization
              .translate('i2pErrDeleteSome')
              .replaceAll('{count}', '${failed.length}'),
          Colors.red,
        );
      }
    }
  }

  // ---------------------------------------------------------- selecting images

  Future<void> _pickImages() async {
    if (_vm.isBusy) return;
    final outcome = await _vm.pickFromGallery();
    if (!mounted) return;
    await _reportAdded(outcome);
  }

  Future<void> _takePhoto() async {
    if (_vm.isBusy) return;
    final outcome = await _vm.captureFromCamera();
    if (!mounted) return;
    await _reportAdded(outcome);
  }

  Future<void> _reportAdded(AddImagesOutcome outcome) async {
    final localization = AppLocalizations.of(context);
    if (outcome.cancelled) return;
    final failure = outcome.failure;
    if (failure != null) {
      _showToast(
          failure == ImagePdfFailure.permissionDenied
              ? localization.translate('i2pErrCamera')
              : _failureMessage(failure),
          Colors.red);
      return;
    }
    if (outcome.rejected.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(localization.translate('i2pRejectedTitle')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (outcome.added > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(localization
                        .translate('i2pAddedSummary')
                        .replaceAll('{count}', '${outcome.added}')),
                  ),
                for (final rejected in outcome.rejected)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rejected.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        Text(_failureMessage(rejected.failure)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(localization.translate('ok')),
            ),
          ],
        ),
      );
    }
    if (outcome.possibleDuplicates > 0 && mounted) {
      _showToast(
        localization
            .translate('i2pDuplicatesNote')
            .replaceAll('{count}', '${outcome.possibleDuplicates}'),
        Colors.orange,
      );
    }
  }

  // ------------------------------------------------------------- making the PDF

  ImagePdfTexts _coverTexts(String title) {
    final loc = _localization;
    final count = _vm.items.length;
    return ImagePdfTexts(
      coverTitle: title,
      coverLines: <String>[
        '$count ${count == 1 ? loc.translate('image') : loc.translate('images')}',
      ],
    );
  }

  /// Makes (or reuses) the draft and reports any failure. Null when there is
  /// no draft to show.
  Future<ImagePdfDraft?> _ensureDraft() async {
    if (_vm.isBusy) return null;
    final localization = AppLocalizations.of(context);
    final title =
        ImagePdfNaming.sanitizeDisplayName(_fileNameController.text) ??
            _vm.suggestedName;
    final outcome = await _vm.prepareDraft(
      title: title,
      coverTexts: _coverTexts(title),
      allowNewConversion: (uid) =>
          (widget.usageGate ?? ImagePdfWiring.usageGate)
              .allowNewConversion(context, uid),
    );
    if (!mounted) return null;
    if (outcome.isDone) return outcome.draft;
    final failure = outcome.failure!;
    // The plan-limit dialog has already told the user why.
    if (failure == ImagePdfFailure.quotaBlocked) return null;
    var message = _failureMessage(failure);
    if (outcome.sourceName != null) {
      message = '${outcome.sourceName}: $message';
    }
    if (failure == ImagePdfFailure.cancelled) {
      _showToast(message, Colors.orange);
      return null;
    }
    if (_retryable.contains(failure)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: localization.translate('retry'),
          onPressed: _convertToPDF,
        ),
      ));
      return null;
    }
    _showToast(message, Colors.red);
    return null;
  }

  Future<void> _previewDraft() async {
    final draft = await _ensureDraft();
    if (draft == null || !mounted) return;
    await _openDraftViewer();
  }

  Future<void> _openDraftViewer() async {
    final file = _vm.draftFile;
    if (file == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PdfViewerScreen(
          localFile: file,
          title: _fileNameController.text.trim().isEmpty
              ? _vm.suggestedName
              : _fileNameController.text.trim(),
        ),
      ),
    );
  }

  /// Makes the PDF and saves it in one step, like the other tools: no sheet in
  /// between. The Preview button above the list shows the real PDF beforehand.
  Future<void> _convertToPDF() async {
    if (_converting) return;
    setState(() => _converting = true);
    try {
      final draft = await _ensureDraft();
      if (draft == null || !mounted) return;
      await _saveDraft();
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  Future<void> _saveDraft() async {
    final localization = AppLocalizations.of(context);
    final outcome = await _vm.saveDraft(name: _fileNameController.text);
    if (!mounted) return;
    if (outcome.isDone) {
      _fileNameController.text = _vm.suggestedName;
      _showToast(localization.translate('i2pSaved'), Colors.green);
      return;
    }
    final failure = outcome.failure!;
    final message = _failureMessage(failure);
    if (_retryable.contains(failure)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: localization.translate('retry'),
          onPressed: _saveDraft,
        ),
      ));
      return;
    }
    _showToast(message, Colors.red);
  }

  // Export a converted document to Downloads (Android) or Files (iPhone)
  Future<void> _saveToDeviceStorage(ImagePdfDocument document) async {
    try {
      final result = await _vm.exportDocument(document.id);
      if (!mounted || result.cancelled) return;
      final key = result.destination == ScannerExportDestination.downloads
          ? 'i2pSavedToDownloads'
          : 'i2pSavedToFiles';
      _showToast(
        _localization
            .translate(key)
            .replaceAll('{name}', result.savedName ?? ''),
        Colors.green,
      );
    } on ImagePdfException catch (e) {
      if (mounted) _showToast(_failureMessage(e.kind), Colors.red);
    } catch (e) {
      if (mounted) {
        _showToast(_failureMessage(ImagePdfFailure.exportFailed), Colors.red);
      }
    }
  }

  void _showSettingsBottomSheet() {
    if (_vm.isBuilding || _vm.isSaving) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ImagePdfSettingsSheet(
        settings: _vm.settings,
        hasPassword: _vm.hasPassword,
        onApply: (result) {
          _vm.updateSettings(result.settings);
          if (result.settings.passwordProtect && result.password.isNotEmpty) {
            _vm.setPassword(result.password);
          }
        },
      ),
    );
  }

  void _showToast(String message, Color bgColor) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: bgColor,
      textColor: Colors.white,
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays} ${_localization.translate('daysAgo')}';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${_localization.translate('hoursAgo')}';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${_localization.translate('minutesAgo')}';
    } else {
      return _localization.translate('justNow');
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// "4 images • 4 pages • 1.2 MB"; parts that are unknown are left out.
  String _documentMeta(ImagePdfDocument document, AppLocalizations loc) {
    final parts = <String>[
      if (document.imageCount > 0)
        '${document.imageCount} ${document.imageCount == 1 ? loc.translate('image') : loc.translate('images')}',
      if (document.pageCount > 0)
        loc
            .translate('i2pPagesCount')
            .replaceAll('{count}', '${document.pageCount}'),
      _formatFileSize(document.fileSize),
    ];
    return parts.join(' • ');
  }

  PreferredSizeWidget _buildAdvancedAppBar(
      AppLocalizations localization, ColorScheme colors) {
    final hasItems = _vm.items.isNotEmpty;
    return AppBar(
      // BackArrowButton pads itself by 16 px unless told otherwise; with zero
      // padding and a 48 px leading slot the arrow sits on the content edge.
      leadingWidth: 48,
      leading: const BackArrowButton(
        iconColor: Colors.white, // Set to white to match the green gradient
        iconSize: 24,
        padding: EdgeInsets.zero,
        backgroundColor: Colors
            .transparent, // Make background transparent since we have gradient
        showBackground: false, // Disable the default background circle
      ),
      title: Text(
        _vm.isSelectionMode
            ? '${_vm.selectedCount} ${localization.translate('selected')}'
            : localization.translate('imageToPdf'),
        style: AppTextStyles.appBarTitle
            .copyWith(fontSize: 20, color: Colors.white),
        textAlign: TextAlign.center,
      ),
      centerTitle: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF4CAF50).withValues(alpha: 0.9),
              const Color(0xFF2E7D32).withValues(alpha: 0.7),
              Colors.transparent,
            ],
          ),
        ),
      ),
      actions: [
        if (_vm.isSelectionMode) ...[
          // Bulk actions when in selection mode
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: _vm.selectedCount > 0 ? _shareBulkDocuments : null,
            tooltip: localization.translate('shareSelected'),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.white),
            onPressed: _vm.selectedCount > 0 ? _deleteBulkDocuments : null,
            tooltip: localization.translate('deleteSelected'),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _vm.exitSelectionMode,
            tooltip: localization.translate('cancelSelection'),
          ),
        ] else if (hasItems) ...[
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: _vm.isBuilding || _vm.isSaving
                ? null
                : _showSettingsBottomSheet,
            tooltip: localization.translate('settings'),
          ),
          IconButton(
            icon: const Icon(Icons.clear_all, color: Colors.white),
            onPressed:
                _vm.isBuilding || _vm.isSaving ? null : _vm.clearSelection,
            tooltip: localization.translate('clearAll'),
          ),
        ] else if (_vm.documents.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.checklist, color: Colors.white),
            onPressed: _vm.enterSelectionMode,
            tooltip: localization.translate('selectDocuments'),
          ),
        // The last icon's glyph ends on the same 16 px edge as the content.
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildBody(AppLocalizations localization, ColorScheme colors) {
    final hasItems = _vm.items.isNotEmpty;
    return CustomScrollView(
      slivers: [
        // Header space for transparent app bar
        const SliverToBoxAdapter(child: SizedBox(height: 120)),

        // Header info card
        SliverToBoxAdapter(
          child: _buildHeaderCard(localization, colors),
        ),

        // Making and saving the PDF show the centered overlay (see build);
        // only the real count of pictures being checked is shown inline.
        if (_vm.isChecking)
          SliverToBoxAdapter(
            child: _buildCheckingIndicator(localization, colors),
          ),

        // Show creation interface when creating new PDFs
        if (hasItems) ...[
          // File name input
          SliverToBoxAdapter(
            child: _buildFileNameInput(localization, colors),
          ),
          // Selected images header
          SliverToBoxAdapter(
            child: _buildSelectedImagesHeader(localization),
          ),
          SliverToBoxAdapter(child: _buildPlanSummary(localization, colors)),
          // Selected images list
          SliverReorderableList(
            itemCount: _vm.items.length,
            onReorderItem: _vm.moveItem,
            itemBuilder: (context, index) {
              return _buildImageCard(index, colors, localization);
            },
          ),
        ] else if (_vm.documents.isEmpty) ...[
          if (_vm.loadFailed)
            SliverToBoxAdapter(
              child: _buildLoadFailed(localization, colors),
            ),
          // Empty state when no documents exist
          SliverToBoxAdapter(
            child: _buildEmptyState(localization, colors),
          ),
          if (_vm.legacyDocumentCount > 0)
            SliverToBoxAdapter(
              child: _buildNotice(
                  localization
                      .translate('i2pLegacyNote')
                      .replaceAll('{count}', '${_vm.legacyDocumentCount}'),
                  colors.onSurface.withValues(alpha: 0.6)),
            ),
        ] else ...[
          // Converted documents header
          SliverToBoxAdapter(
            child: _buildConvertedDocumentsHeader(localization),
          ),
          // Converted documents list or grid
          if (_isViewMode)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return _buildConvertedDocumentCard(
                      _vm.documents[index], colors, localization);
                },
                childCount: _vm.documents.length,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverGrid(
                // Same tile height as the scanner grid.
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  mainAxisExtent: 200 *
                      (MediaQuery.textScalerOf(context).scale(14) / 14)
                          .clamp(1.0, 1.6)
                          .toDouble(),
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return _buildConvertedDocumentGridCard(
                        _vm.documents[index], colors, localization);
                  },
                  childCount: _vm.documents.length,
                ),
              ),
            ),
          if (_vm.legacyDocumentCount > 0)
            SliverToBoxAdapter(
              child: _buildNotice(
                  localization
                      .translate('i2pLegacyNote')
                      .replaceAll('{count}', '${_vm.legacyDocumentCount}'),
                  colors.onSurface.withValues(alpha: 0.6)),
            ),
        ],

        // Bottom padding for FAB
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildHeaderCard(AppLocalizations localization, ColorScheme colors) {
    return ToolHeaderCard(
      icon: Icons.picture_as_pdf,
      title: localization.translate('imageToPdfConverter'),
      subtitle: localization.translate('convertYourImages'),
      gradient: const [Color(0xFF4CAF50), Color(0xFF2E7D32)],
    );
  }

  Widget _buildNotice(String text, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadFailed(AppLocalizations localization, ColorScheme colors) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(localization.translate('i2pErrLoad'))),
          TextButton(
            onPressed: _vm.refresh,
            child: Text(localization.translate('retry')),
          ),
        ],
      ),
    );
  }

  /// Each picture is opened completely when it is added; the bar is the real
  /// count of pictures already checked.
  Widget _buildCheckingIndicator(
      AppLocalizations localization, ColorScheme colors) {
    final items = _vm.items;
    final pending = items.where((i) => !i.isReady && i.failure == null).length;
    final done = items.length - pending;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localization
                .translate('i2pChecking')
                .replaceAll('{done}', '$done')
                .replaceAll('{total}', '${items.length}'),
            style: AppTextStyles.bodyText.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: items.isEmpty ? null : done / items.length,
            backgroundColor: colors.outline.withValues(alpha: 0.2),
            valueColor: const AlwaysStoppedAnimation<Color>(_green),
          ),
        ],
      ),
    );
  }

  Widget _buildFileNameInput(
      AppLocalizations localization, ColorScheme colors) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit, size: 20, color: _green),
              const SizedBox(width: 8),
              Text(
                localization.translate('fileName'),
                style: AppTextStyles.bodyText.copyWith(
                  fontWeight: FontWeight.w600,
                  color: _green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _fileNameController,
            maxLength: 80,
            decoration: InputDecoration(
              hintText: localization.translate('enterFileName'),
              suffixText: '.pdf',
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations localization, ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: _green,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            localization.translate('noImagesSelected'),
            style: AppTextStyles.bodyText.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.onSurface.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            localization.translate('selectImagesToConvertToPdf'),
            style: AppTextStyles.bodyText.copyWith(
              color: colors.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedImagesHeader(AppLocalizations localization) {
    final busy = _vm.isBusy;
    final canPreview = !busy && !_vm.isChecking && !_vm.hasFailedItems;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title and settings button row
          Row(
            children: [
              Expanded(
                child: Text(
                  '${localization.translate('selectedImages')} (${_vm.items.length})',
                  style: AppTextStyles.bodyText.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: busy ? null : _showSettingsBottomSheet,
                icon: const Icon(Icons.tune),
                tooltip: localization.translate('advancedPdfSettings'),
                style: IconButton.styleFrom(
                  backgroundColor: _green.withValues(alpha: 0.1),
                  foregroundColor: _green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Action buttons row
          Row(
            children: [
              // Camera button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: busy ? null : _takePhoto,
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: Text(localization.translate('camera')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Add images button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: busy ? null : _pickImages,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(localization.translate('add')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.tilePrimary,
                    foregroundColor: _green,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Preview button: makes the real PDF and opens it
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: canPreview ? _previewDraft : null,
                  icon: const Icon(Icons.preview, size: 18),
                  label: Text(localization.translate('preview')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canPreview
                        ? AppColors.tilePrimary
                        : Colors.grey.withValues(alpha: 0.2),
                    foregroundColor: canPreview ? _green : Colors.grey,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The pages the PDF will have and the page format, from the same plan the
  /// engine builds with; plus what the chosen options mean for the user.
  Widget _buildPlanSummary(AppLocalizations localization, ColorScheme colors) {
    final s = _vm.settings;
    final pages = _vm.plannedPageCount;
    final size = s.pageSize == PdfPageSize.custom
        ? '${s.customWidthMm.round()} × ${s.customHeightMm.round()} mm'
        : s.pageSize.name.toUpperCase();
    final notes = <String>[
      if (s.passwordProtect) localization.translate('i2pProtectedNote'),
    ];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _green.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.layers, size: 20, color: _green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pages == null
                      ? size
                      : '${localization.translate('i2pPagesCount').replaceAll('{count}', '$pages')} • $size',
                  style: AppTextStyles.bodyText.copyWith(
                    fontWeight: FontWeight.w600,
                    color: _green,
                  ),
                ),
              ),
              if (s.passwordProtect)
                const Icon(Icons.lock, size: 18, color: _green),
            ],
          ),
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                note,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageCard(
      int index, ColorScheme colors, AppLocalizations localization) {
    final item = _vm.items[index];
    final locked = _vm.isBuilding || _vm.isSaving;
    final Widget thumbnail;
    switch (item.status) {
      case ImageItemStatus.ready:
        thumbnail = Image.memory(
          item.analysis!.thumbnail,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      case ImageItemStatus.checking:
        thumbnail = const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case ImageItemStatus.failed:
        thumbnail = Center(
          child: Icon(Icons.broken_image_outlined, color: colors.error),
        );
    }
    final String detail;
    switch (item.status) {
      case ImageItemStatus.ready:
        detail =
            '${item.analysis!.width} × ${item.analysis!.height} px • ${_formatFileSize(item.size)}';
      case ImageItemStatus.checking:
        detail = localization.translate('i2pCheckingOne');
      case ImageItemStatus.failed:
        detail = _failureMessage(item.failure ?? ImagePdfFailure.corruptSource);
    }

    return Container(
      key: ValueKey(item.id),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.status == ImageItemStatus.failed
              ? colors.error.withValues(alpha: 0.6)
              : colors.outline.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 80,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: thumbnail,
          ),
        ),
        title: Text(
          '${localization.translate('image')} ${index + 1}',
          style: AppTextStyles.bodyText.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localization
                    .translate('positionOf')
                    .replaceAll('{position}', '${index + 1}')
                    .replaceAll('{total}', '${_vm.items.length}'),
                style: AppTextStyles.bodyText.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
              Text(
                detail,
                style: TextStyle(
                  fontSize: 12,
                  color: item.status == ImageItemStatus.failed
                      ? colors.error
                      : colors.onSurface.withValues(alpha: 0.6),
                ),
              ),
              if (item.possibleDuplicate)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    localization.translate('i2pDuplicate'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index,
              enabled: !locked,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.outline.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.drag_handle,
                  color: colors.onSurface.withValues(alpha: 0.6),
                  size: 16,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                color: colors.error,
                size: 20,
              ),
              onPressed: locked ? null : () => _vm.removeItem(item.id),
              tooltip: localization.translate('i2pRemoveImage'),
              style: IconButton.styleFrom(
                backgroundColor: colors.error.withValues(alpha: 0.1),
                foregroundColor: colors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConvertedDocumentsHeader(AppLocalizations localization) {
    // Right inset 4: the 48 px toggle's icon then ends on the 16 px edge,
    // directly under the app bar's last icon.
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 4, 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.picture_as_pdf,
              color: _green,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${localization.translate('convertedDocuments')} (${_vm.documents.length})',
            style: AppTextStyles.bodyText.copyWith(
              fontWeight: FontWeight.w600,
              color: _green,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              _isViewMode ? Icons.grid_view : Icons.view_list,
              color: _green,
            ),
            onPressed: () {
              setState(() => _isViewMode = !_isViewMode);
              _saveViewModePreference();
            },
            tooltip: _isViewMode
                ? localization.translate('gridView')
                : localization.translate('listView'),
          ),
        ],
      ),
    );
  }

  Widget _buildConvertedDocumentCard(ImagePdfDocument document,
      ColorScheme colors, AppLocalizations localization) {
    final isSelected = _vm.isSelected(document.id);
    final missing = _vm.isMissing(document.id);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? _green : colors.outline.withValues(alpha: 0.2),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _vm.isSelectionMode
            ? Checkbox(
                value: isSelected,
                onChanged: (_) => _vm.toggleSelection(document.id),
                activeColor: _green,
              )
            : Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  document.encrypted ? Icons.lock : Icons.picture_as_pdf,
                  color: _green,
                  size: 24,
                ),
              ),
        title: Text(
          document.name,
          style: AppTextStyles.bodyText.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: colors.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(
                missing ? Icons.warning_amber_rounded : Icons.info_outline,
                size: 14,
                color: missing
                    ? colors.error
                    : colors.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  missing
                      ? localization.translate('documentFileNotFound')
                      : _documentMeta(document, localization),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: missing
                        ? colors.error
                        : colors.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.visibility, color: _green, size: 20),
              onPressed: () => _previewConvertedDocument(document),
              tooltip: localization.translate('preview'),
              visualDensity: VisualDensity.compact,
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert,
                  color: colors.onSurface.withValues(alpha: 0.6)),
              onSelected: (value) {
                switch (value) {
                  case 'share':
                    _shareConvertedDocument(document);
                    break;
                  case 'download':
                    _saveToDeviceStorage(document);
                    break;
                  case 'rename':
                    _renameConvertedDocument(document);
                    break;
                  case 'delete':
                    _deleteConvertedDocument(document);
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      const Icon(Icons.share, size: 18, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(localization.translate('share')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'download',
                  child: Row(
                    children: [
                      const Icon(Icons.download, size: 18, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(localization.translate('download')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      const Icon(Icons.edit, size: 18, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(localization.translate('rename')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        localization.translate('delete'),
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: () {
          if (_vm.isSelectionMode) {
            _vm.toggleSelection(document.id);
          } else {
            _previewConvertedDocument(document);
          }
        },
      ),
    );
  }

  Widget _buildConvertedDocumentGridCard(ImagePdfDocument document,
      ColorScheme colors, AppLocalizations localization) {
    final isSelected = _vm.isSelected(document.id);
    final missing = _vm.isMissing(document.id);
    return Card(
      margin: const EdgeInsets.all(4),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? _green : _green.withValues(alpha: 0.2),
          width: isSelected ? 3 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          if (_vm.isSelectionMode) {
            _vm.toggleSelection(document.id);
          } else {
            _previewConvertedDocument(document);
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                _green.withValues(alpha: 0.02),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row with PDF icon and more options menu
              SizedBox(
                height: 28,
                child: Row(
                children: [
                  // Selection indicator or document type icon
                  _vm.isSelectionMode
                      ? Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _green
                                : Colors.grey.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            isSelected
                                ? Icons.check
                                : Icons.radio_button_unchecked,
                            color: isSelected ? Colors.white : Colors.grey,
                            size: 18,
                          ),
                        )
                      : Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            document.encrypted
                                ? Icons.lock
                                : Icons.picture_as_pdf,
                            color: _green,
                            size: 16,
                          ),
                        ),

                  const Spacer(),

                  // More options menu
                  PopupMenuButton<String>(
                    // A sized child instead of the default icon button,
                    // which would add 48 px of height to this row.
                    child: SizedBox(
                      width: 32,
                      height: 28,
                      child: Icon(
                        Icons.more_vert,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'rename':
                          _renameConvertedDocument(document);
                          break;
                        case 'delete':
                          _deleteConvertedDocument(document);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            const Icon(Icons.edit,
                                size: 18, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text(localization.translate('rename')),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(Icons.delete,
                                color: Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              localization.translate('delete'),
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                ),
              ),

              const SizedBox(height: 8),

              // Details: clipped, never overflowing, if text is scaled up.
              Flexible(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Document name
                      Text(
                        document.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              height: 1.2,
                              color: colors.onSurface,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 8),

                      // Document format and image count
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (missing ? colors.error : _green)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: (missing ? colors.error : _green)
                                .withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          missing
                              ? localization.translate('documentFileNotFound')
                              : document.imageCount > 0
                                  ? '${document.imageCount} ${localization.translate('images')} • PDF'
                                  : 'PDF',
                          style: TextStyle(
                            color: missing ? colors.error : _green,
                            fontWeight: FontWeight.w600,
                            fontSize: 9,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Date
                      Text(
                        _formatDateTime(document.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontSize: 10,
                              height: 1.2,
                            ),
                      ),

                      const SizedBox(height: 4),

                      // File size
                      Row(
                        children: [
                          Icon(
                            Icons.folder,
                            size: 10,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _formatFileSize(document.fileSize),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 10,
                                  height: 1.2,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Quick action buttons
              Row(
                children: [
                  Expanded(
                    child: _buildGridActionButton(
                      icon: Icons.visibility,
                      onTap: () => _previewConvertedDocument(document),
                      color: _green,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Tooltip(
                      message: AppLocalizations.of(context).translate('share'),
                      child: _buildGridActionButton(
                        icon: Icons.share,
                        onTap: () => _shareConvertedDocument(document),
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildGridActionButton(
                      icon: Icons.download,
                      onTap: () => _saveToDeviceStorage(document),
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: color,
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton(AppLocalizations localization) {
    final working = _vm.isBuilding || _vm.isSaving || _converting;
    final canConvert = !_vm.isBusy && !_vm.isChecking && !_vm.hasFailedItems;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: _vm.items.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: canConvert && !_converting ? _convertToPDF : null,
              // The button keeps its look while the overlay shows the work.
              icon: const Icon(Icons.picture_as_pdf),
              label: Text(localization.translate('convertToPdf')),
              backgroundColor: canConvert || working ? _green : Colors.grey,
              foregroundColor: Colors.white,
            )
          : FloatingActionButton.extended(
              onPressed: _vm.isBusy ? null : _pickImages,
              icon: const Icon(Icons.add_photo_alternate),
              label: Text(localization.translate('selectImages')),
              backgroundColor: _green,
              foregroundColor: Colors.white,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final working = _vm.isBuilding || _vm.isSaving || _converting;
        return Stack(
          children: [
            Scaffold(
              resizeToAvoidBottomInset:
                  false, // Prevent keyboard from moving the form
              backgroundColor: colors.surface,
              extendBodyBehindAppBar: true,
              appBar: _buildAdvancedAppBar(localization, colors),
              body: _buildBody(localization, colors),
              floatingActionButton: _buildFloatingActionButton(localization),
              floatingActionButtonLocation:
                  FloatingActionButtonLocation.centerDocked,
            ),
            // The one progress indicator: dims the whole screen, app bar and
            // button included, and takes the taps.
            if (working)
              Positioned.fill(
                child: ToolProgressOverlay(
                  message: localization.translate('i2pConverting'),
                  accent: _green,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The rename dialog. It owns its text controller, which is only released when
/// the dialog's route is gone: disposing it right after `showDialog` returns
/// would still be in use by the closing animation.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({
    required this.initialName,
    required this.rename,
    required this.messageFor,
  });

  final String initialName;
  final Future<ImagePdfFailure?> Function(String name) rename;
  final String Function(ImagePdfFailure failure) messageFor;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final failure = await widget.rename(_controller.text);
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _error = widget.messageFor(failure));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(loc.translate('renameDocument')),
      content: TextField(
        controller: _controller,
        maxLength: 80,
        decoration: InputDecoration(
          labelText: loc.translate('documentName'),
          errorText: _error,
          border: const OutlineInputBorder(),
          counterText: '',
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(loc.translate('cancel')),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(loc.translate('rename')),
        ),
      ],
    );
  }
}
