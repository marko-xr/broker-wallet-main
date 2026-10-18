import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/combine_pages_screen.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/pdf_viewer_screen.dart';
import 'package:broker_wallet/src/services/share/share_live.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_models.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_usage_gate.dart';
import 'package:broker_wallet/src/services/combine_pdf/combine_wiring.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';
import 'package:broker_wallet/src/viewmodels/combine_pdf/combine_pdf_viewmodel.dart';

/// The Combine PDFs tool: pick PDFs, choose and order their pages, combine them
/// into one PDF kept in the signed-in account's private list, then preview,
/// rename, share, export and delete. The logic lives in [CombinePdfViewModel];
/// this file is the screen.
class CombinePdfsView extends StatefulWidget {
  const CombinePdfsView({Key? key, this.viewModel, this.usageGate})
      : super(key: key);

  /// A ready view model, for tests. The app builds its own.
  final CombinePdfViewModel? viewModel;

  /// The plan-limit check, for tests. The app uses [CombinePdfWiring.usageGate].
  final CombineUsageGate? usageGate;

  @override
  _CombinePdfsViewState createState() => _CombinePdfsViewState();
}

class _CombinePdfsViewState extends State<CombinePdfsView> {
  late final CombinePdfViewModel _vm;
  late final bool _ownsViewModel;
  final TextEditingController _fileNameController = TextEditingController();
  bool _isViewMode = false; // true for list view, false for grid view

  static const String _viewModeKey = 'combine_pdf_list_view_mode';

  @override
  void initState() {
    super.initState();
    _ownsViewModel = widget.viewModel == null;
    _vm = widget.viewModel ?? CombinePdfWiring.createViewModel();
    _fileNameController.text = _vm.suggestedName;
    _loadViewModePreference();
    _vm.start();
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

  /// The localized text for a failure; [name] fills a file name where the
  /// message has one.
  String _failureMessage(CombinePdfFailure failure, {String? name}) {
    final loc = _localization;
    switch (failure) {
      case CombinePdfFailure.signedOut:
        return loc.translate('combineErrSignedOut');
      case CombinePdfFailure.busy:
        return loc.translate('combineErrBusy');
      case CombinePdfFailure.cancelled:
        return loc.translate('combineErrCancelled');
      case CombinePdfFailure.accountChanged:
        return loc.translate('combineErrAccountChanged');
      case CombinePdfFailure.tooFewFiles:
        return loc.translate('combineErrTooFew');
      case CombinePdfFailure.noPages:
        return loc.translate('combineErrNoPages');
      case CombinePdfFailure.fileHasNoPages:
        return loc
            .translate('combineErrFileNoPages')
            .replaceAll('{name}', name ?? '');
      case CombinePdfFailure.missingSource:
        return loc.translate('combineErrMissing');
      case CombinePdfFailure.emptySource:
        return loc.translate('combineErrEmpty');
      case CombinePdfFailure.corruptSource:
        return loc.translate('combineErrCorrupt');
      case CombinePdfFailure.encryptedSource:
        return loc.translate('combineErrEncrypted');
      case CombinePdfFailure.signedSource:
        return loc.translate('combineErrSigned');
      case CombinePdfFailure.tooLargeSource:
        return loc.translate('combineErrFileTooLarge');
      case CombinePdfFailure.selectionTooLarge:
        return loc.translate('combineErrSelectionTooLarge');
      case CombinePdfFailure.sourceChanged:
        return loc.translate('combineErrChanged');
      case CombinePdfFailure.outputInvalid:
        return loc.translate('combineErrOutputInvalid');
      case CombinePdfFailure.mergeFailed:
        return loc.translate('combineErrMerge');
      case CombinePdfFailure.storageFull:
        return loc.translate('combineErrStorageFull');
      case CombinePdfFailure.writeFailed:
        return loc.translate('combineErrWrite');
      case CombinePdfFailure.notFound:
        return loc.translate('combineErrNotFound');
      case CombinePdfFailure.invalidName:
        return loc.translate('combineErrInvalidName');
      case CombinePdfFailure.nameInUse:
        return loc.translate('combineErrNameInUse');
      case CombinePdfFailure.fileMissing:
        return loc.translate('documentFileNotFound');
      case CombinePdfFailure.quotaBlocked:
        return loc.translate('combineErrBusy');
      case CombinePdfFailure.permissionDenied:
        return loc.translate('combineErrPermission');
      case CombinePdfFailure.exportFailed:
        return loc.translate('combineErrExport');
    }
  }

  // Failures a second attempt can fix (as opposed to a file that must change).
  static const Set<CombinePdfFailure> _retryable = <CombinePdfFailure>{
    CombinePdfFailure.mergeFailed,
    CombinePdfFailure.outputInvalid,
    CombinePdfFailure.writeFailed,
    CombinePdfFailure.storageFull,
  };

  // Delete a combined document
  Future<void> _deleteCombinedDocument(CombinedPdf document) async {
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

  // Rename a combined document
  Future<void> _renameCombinedDocument(CombinedPdf document) async {
    final controller = TextEditingController(text: document.name);
    String? error;
    final renamed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(_localization.translate('renameDocument')),
              content: TextField(
                controller: controller,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: _localization.translate('documentName'),
                  errorText: error,
                  border: const OutlineInputBorder(),
                  counterText: '',
                ),
                autofocus: true,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(_localization.translate('cancel')),
                ),
                TextButton(
                  onPressed: () async {
                    final failure =
                        await _vm.rename(document.id, controller.text);
                    if (failure == null) {
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(true);
                      }
                      return;
                    }
                    if (!dialogContext.mounted) return;
                    setDialogState(() => error = _failureMessage(failure));
                  },
                  child: Text(_localization.translate('rename')),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    if (renamed == true && mounted) {
      _showToast(_localization.translate('documentRenamed'), Colors.green);
    }
  }

  // Share combined documents under their titles
  Future<void> _shareDocuments(List<CombinedPdf> documents) async {
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
            ? '${localization.translate('combinedDocument')}: ${documents.first.name}'
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

  Future<void> _shareCombinedDocument(CombinedPdf document) =>
      _shareDocuments(<CombinedPdf>[document]);

  // Preview a combined document in the PDF viewer
  Future<void> _previewCombinedDocument(CombinedPdf document) async {
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

  // Preview a selected source file before combining
  void _previewSource(CombineSource source) {
    final file = File(source.path);
    if (!file.existsSync()) {
      _showToast(_localization.translate('documentFileNotFound'), Colors.red);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            PdfViewerScreen(localFile: file, title: source.displayName),
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
              .translate('combineErrDeleteSome')
              .replaceAll('{count}', '${failed.length}'),
          Colors.red,
        );
      }
    }
  }

  Future<void> _pickPDFs() async {
    if (_vm.isBusy) return;
    final outcome = await _vm.pickFiles();
    if (!mounted) return;
    await _reportAdded(outcome);
  }

  Future<void> _reportAdded(AddFilesOutcome outcome) async {
    final localization = AppLocalizations.of(context);
    if (outcome.cancelled) return;
    final failure = outcome.failure;
    if (failure != null) {
      _showToast(_failureMessage(failure), Colors.red);
      return;
    }
    if (outcome.rejected.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(localization.translate('combineRejectedTitle')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (outcome.added > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(localization
                        .translate('combineAddedSummary')
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
      return;
    }
    if (outcome.duplicates > 0) {
      _showToast(
        localization
            .translate('combineDuplicatesNote')
            .replaceAll('{count}', '${outcome.duplicates}'),
        Colors.orange,
      );
    }
  }

  Future<void> _combinePDFs() async {
    if (_vm.isBusy) return;
    final localization = AppLocalizations.of(context);
    final outcome = await _vm.combine(
      name: _fileNameController.text,
      allowNewCombine: (uid) => (widget.usageGate ?? CombinePdfWiring.usageGate)
          .allowNewCombine(context, uid),
    );
    if (!mounted) return;
    if (outcome.isDone) {
      _fileNameController.text = _vm.suggestedName;
      _showToast(
          localization.translate('pdfsCombinedSuccessfully'), Colors.green);
      return;
    }
    final failure = outcome.failure!;
    // The plan-limit dialog has already told the user why.
    if (failure == CombinePdfFailure.quotaBlocked) return;
    final message = _failureMessage(failure, name: outcome.sourceName);
    if (failure == CombinePdfFailure.cancelled) {
      _showToast(message, Colors.orange);
      return;
    }
    if (_retryable.contains(failure)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: localization.translate('retry'),
          onPressed: _combinePDFs,
        ),
      ));
      return;
    }
    _showToast(message, Colors.red);
  }

  // Export a combined document to Downloads (Android) or Files (iPhone)
  Future<void> _saveToDeviceStorage(CombinedPdf document) async {
    try {
      final result = await _vm.exportDocument(document.id);
      if (!mounted || result.cancelled) return;
      final key = result.destination == ScannerExportDestination.downloads
          ? 'combineSavedToDownloads'
          : 'combineSavedToFiles';
      _showToast(
        _localization
            .translate(key)
            .replaceAll('{name}', result.savedName ?? ''),
        Colors.green,
      );
    } on CombinePdfException catch (e) {
      if (mounted) _showToast(_failureMessage(e.kind), Colors.red);
    } catch (e) {
      if (mounted) {
        _showToast(_failureMessage(CombinePdfFailure.exportFailed), Colors.red);
      }
    }
  }

  // Choose the first and last page to use from one file
  Future<void> _selectPages(CombineSource source) async {
    final loc = _localization;
    final pages = _vm.plan.pagesOf(source.id).map((p) => p.pageIndex + 1);
    final fromController = TextEditingController(
        text: pages.isEmpty ? '1' : '${pages.reduce((a, b) => a < b ? a : b)}');
    final toController = TextEditingController(
        text: pages.isEmpty
            ? '${source.pageCount}'
            : '${pages.reduce((a, b) => a > b ? a : b)}');
    String? error;
    final applied = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(loc.translate('combineSelectPages')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(source.displayName,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    loc
                        .translate('combinePagesOfFile')
                        .replaceAll(
                            '{selected}', '${_vm.plan.selectedCount(source.id)}')
                        .replaceAll('{total}', '${source.pageCount}'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: fromController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: loc.translate('combineFromPage'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: toController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: loc.translate('combineToPage'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error!,
                          style: const TextStyle(color: Colors.red)),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _vm.useAllPages(source.id);
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: Text(loc.translate('combineUseAllPages')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(loc.translate('cancel')),
                ),
                TextButton(
                  onPressed: () {
                    final from = int.tryParse(fromController.text.trim());
                    final to = int.tryParse(toController.text.trim());
                    if (from == null ||
                        to == null ||
                        from < 1 ||
                        to > source.pageCount ||
                        from > to) {
                      setDialogState(() => error = loc
                          .translate('combineRangeInvalid')
                          .replaceAll('{count}', '${source.pageCount}'));
                      return;
                    }
                    _vm.selectRange(source.id, from, to);
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: Text(loc.translate('combineApply')),
                ),
              ],
            );
          },
        );
      },
    );
    fromController.dispose();
    toController.dispose();
    if (applied != true) return;
  }

  void _openPageReview() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CombinePagesScreen(viewModel: _vm),
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

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) => Scaffold(
        backgroundColor: colors.surface,
        extendBodyBehindAppBar: true,
        resizeToAvoidBottomInset: false,
        appBar: _buildAdvancedAppBar(localization, colors),
        body: _buildBody(localization, colors),
        floatingActionButton: _buildFloatingActionButton(localization),
        floatingActionButtonLocation:
            FloatingActionButtonLocation.centerDocked,
      ),
    );
  }

  PreferredSizeWidget _buildAdvancedAppBar(
      AppLocalizations localization, ColorScheme colors) {
    return AppBar(
      // BackArrowButton pads itself by 16 px unless told otherwise; with zero
      // padding and a 48 px leading slot the arrow sits on the content edge.
      leadingWidth: 48,
      leading: const BackArrowButton(
        iconColor: Colors.white, // Set to white to match the orange gradient
        iconSize: 24,
        padding: EdgeInsets.zero,
        backgroundColor: Colors
            .transparent, // Make background transparent since we have gradient
        showBackground: false, // Disable the default background circle
      ),
      title: Text(
        _vm.isSelectionMode
            ? '${_vm.selectedCount} ${localization.translate('selected')}'
            : localization.translate('combinePdfs'),
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
              const Color(0xFFFF9800).withValues(alpha: 0.9),
              const Color(0xFFFF6F00).withValues(alpha: 0.7),
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
            onPressed:
                _vm.selectedCount > 0 ? _shareBulkDocuments : null,
            tooltip: localization.translate('shareSelected'),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.white),
            onPressed:
                _vm.selectedCount > 0 ? _deleteBulkDocuments : null,
            tooltip: localization.translate('deleteSelected'),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _vm.exitSelectionMode,
            tooltip: localization.translate('cancelSelection'),
          ),
        ] else ...[
          if (!_vm.plan.isEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all, color: Colors.white),
              onPressed: _vm.isMerging ? null : _vm.clearSelection,
              tooltip: localization.translate('clearAll'),
            )
          else if (_vm.documents.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.checklist, color: Colors.white),
              onPressed: _vm.enterSelectionMode,
              tooltip: localization.translate('selectDocuments'),
            ),
        ],
        // The last icon's glyph ends on the same 16 px edge as the content.
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildBody(AppLocalizations localization, ColorScheme colors) {
    return CustomScrollView(
      slivers: [
        // Header space for transparent app bar
        const SliverToBoxAdapter(child: SizedBox(height: 120)),

        // Header info card
        SliverToBoxAdapter(
          child: _buildHeaderCard(localization, colors),
        ),

        // Notices about the account's list
        if (_vm.loadFailed)
          SliverToBoxAdapter(
            child: _buildNotice(
                localization.translate('combineLoadFailed'), colors.error),
          ),
        if (_vm.legacyDocumentCount > 0 && _vm.plan.isEmpty)
          SliverToBoxAdapter(
            child: _buildNotice(
              localization
                  .translate('combineLegacyNotice')
                  .replaceAll('{count}', '${_vm.legacyDocumentCount}'),
              colors.onSurface.withValues(alpha: 0.7),
            ),
          ),

        // Processing indicator
        if (_vm.isMerging)
          SliverToBoxAdapter(
            child: _buildProcessingIndicator(localization, colors),
          ),

        // Show creation interface when creating new PDFs
        if (!_vm.plan.isEmpty) ...[
          // File name input
          SliverToBoxAdapter(
            child: _buildFileNameInput(localization, colors),
          ),
          // Selected files header
          SliverToBoxAdapter(
            child: _buildSelectedFilesHeader(localization),
          ),
          // Total pages and the final order review
          SliverToBoxAdapter(
            child: _buildSelectionSummary(localization, colors),
          ),
          // Selected files list
          SliverReorderableList(
            itemCount: _vm.plan.sources.length,
            onReorderItem: _vm.moveSource,
            itemBuilder: (context, index) {
              return _buildFileCard(index, colors, localization);
            },
          ),
        ] else if (_vm.documents.isEmpty) ...[
          // Empty state when no documents exist
          SliverToBoxAdapter(
            child: _buildEmptyState(localization, colors),
          ),
        ] else ...[
          // Combined documents header
          SliverToBoxAdapter(
            child: _buildCombinedDocumentsHeader(localization),
          ),
          // Combined documents list/grid
          if (_isViewMode)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildCombinedDocumentCard(
                    _vm.documents[index], index, colors, localization),
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
                  (context, index) => _buildCombinedDocumentGridCard(
                      _vm.documents[index], index, colors, localization),
                  childCount: _vm.documents.length,
                ),
              ),
            ),
        ],

        // Bottom padding for FAB
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildHeaderCard(AppLocalizations localization, ColorScheme colors) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9800), Color(0xFFFF6F00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF9800).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.merge_type,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localization.translate('combineMultiplePdfs'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  localization.translate('combineDescription'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

  // Total pages of the pending combine and the way into the final order review.
  Widget _buildSelectionSummary(
      AppLocalizations localization, ColorScheme colors) {
    final plan = _vm.plan;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.layers, size: 20, color: Color(0xFFFF9800)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localization
                      .translate('combineTotalPages')
                      .replaceAll('{count}', '${plan.totalPages}'),
                  style: AppTextStyles.bodyText.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFFF9800),
                  ),
                ),
                Text(
                  localization
                      .translate('combineFilesAndPages')
                      .replaceAll('{files}', '${plan.sources.length}')
                      .replaceAll('{pages}', '${plan.totalPages}'),
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _vm.isMerging ? null : _openPageReview,
            icon: const Icon(Icons.reorder, size: 18),
            label: Text(localization.translate('combineReviewPages')),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF9800),
            ),
          ),
        ],
      ),
    );
  }

  // The combine reports no percentage: the PDF library gives no progress, so
  // the card says what is happening and offers Cancel instead of a made-up bar.
  Widget _buildProcessingIndicator(
      AppLocalizations localization, ColorScheme colors) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9800)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localization
                          .translate('combineProcessing')
                          .replaceAll('{pages}', '${_vm.plan.totalPages}'),
                      style: AppTextStyles.bodyText.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      localization.translate('combineProcessingNote'),
                      style: TextStyle(
                        color: colors.onSurface.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: _vm.cancelCombine,
              child: Text(localization.translate('combineCancelButton')),
            ),
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
            color: colors.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit, size: 20, color: const Color(0xFFFF9800)),
              const SizedBox(width: 8),
              Text(
                localization.translate('fileName'),
                style: AppTextStyles.bodyText.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFFF9800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _fileNameController,
            decoration: InputDecoration(
              hintText: localization.translate('enterFileName'),
              suffixText: '.pdf',
              suffixStyle: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: colors.outline.withValues(alpha: 0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFFFF9800), width: 2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              filled: true,
              fillColor: colors.surface,
            ),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
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
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.picture_as_pdf,
              size: 64,
              color: const Color(0xFFFF9800).withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            localization.translate('noCombinedDocuments'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            localization.translate('createFirstCombinedPdf'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[500],
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCombinedDocumentsHeader(AppLocalizations localization) {
    // Right inset 4: the 48 px toggle's icon then ends on the 16 px edge,
    // directly under the app bar's last icon.
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 4, 4),
      child: Row(
        children: [
          Icon(
            Icons.folder_copy,
            size: 20,
            color: const Color(0xFFFF9800),
          ),
          const SizedBox(width: 8),
          Text(
            '${localization.translate('combinedDocuments')} (${_vm.documents.length})',
            style: AppTextStyles.bodyText.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFFFF9800),
            ),
          ),
          const Spacer(),
          if (_vm.documents.isNotEmpty)
            IconButton(
              icon: Icon(
                _isViewMode ? Icons.grid_view : Icons.view_list,
                color: const Color(0xFFFF9800),
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

  Widget _buildCombinedDocumentCard(CombinedPdf document, int index,
      ColorScheme colors, AppLocalizations localization) {
    final isSelected = _vm.isSelected(document.id);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? const Color(0xFFFF9800)
              : colors.outline.withValues(alpha: 0.2),
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
                activeColor: const Color(0xFFFF9800),
              )
            : Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.picture_as_pdf,
                  color: const Color(0xFFFF9800),
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
                Icons.info_outline,
                size: 14,
                color: colors.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 4),
              Text(
                _vm.isMissing(document.id)
                    ? localization.translate('combineFileMissingBadge')
                    : '${document.pageCount} ${localization.translate('pages')} • ${(document.fileSize / 1024).toStringAsFixed(1)} KB',
                style: TextStyle(
                  color: colors.onSurface.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.visibility, color: Color(0xFFFF9800), size: 20),
              onPressed: () => _previewCombinedDocument(document),
              tooltip: localization.translate('preview'),
              visualDensity: VisualDensity.compact,
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert,
                  color: colors.onSurface.withValues(alpha: 0.6)),
              onSelected: (value) {
                switch (value) {
                  case 'share':
                    _shareCombinedDocument(document);
                    break;
                  case 'download':
                    _saveToDeviceStorage(document);
                    break;
                  case 'rename':
                    _renameCombinedDocument(document);
                    break;
                  case 'delete':
                    _deleteCombinedDocument(document);
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share, size: 20, color: Colors.blue),
                      const SizedBox(width: 12),
                      Text(localization.translate('share')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'download',
                  child: Row(
                    children: [
                      Icon(Icons.download, size: 20, color: Colors.green),
                      const SizedBox(width: 12),
                      Text(localization.translate('download')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20, color: Colors.grey),
                      const SizedBox(width: 12),
                      Text(localization.translate('rename')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 20, color: Colors.red),
                      const SizedBox(width: 12),
                      Text(localization.translate('delete')),
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
            _previewCombinedDocument(document);
          }
        },
      ),
    );
  }

  Widget _buildCombinedDocumentGridCard(CombinedPdf document, int index,
      ColorScheme colors, AppLocalizations localization) {
    final isSelected = _vm.isSelected(document.id);
    return Card(
      margin: const EdgeInsets.all(4),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? const Color(0xFFFF9800)
              : const Color(0xFFFF9800).withValues(alpha: 0.2),
          width: isSelected ? 3 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          if (_vm.isSelectionMode) {
            _vm.toggleSelection(document.id);
          } else {
            _previewCombinedDocument(document);
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
                const Color(0xFFFF9800).withValues(alpha: 0.02),
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
                                ? const Color(0xFFFF9800)
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
                            color:
                                const Color(0xFFFF9800).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.picture_as_pdf,
                            color: const Color(0xFFFF9800),
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
                          _renameCombinedDocument(document);
                          break;
                        case 'delete':
                          _deleteCombinedDocument(document);
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

                      // Document format and page count
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9800).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          _vm.isMissing(document.id)
                              ? localization.translate('combineFileMissingBadge')
                              : '${document.pageCount} ${localization.translate('pages')} • PDF',
                          style: TextStyle(
                            color: const Color(0xFFFF9800),
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
                            '${(document.fileSize / 1024).toStringAsFixed(1)} KB',
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

              Row(
                children: [
                  Expanded(
                    child: _buildGridActionButton(
                      icon: Icons.visibility,
                      onTap: () => _previewCombinedDocument(document),
                      color: const Color(0xFFFF9800),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Tooltip(
                      message: AppLocalizations.of(context).translate('share'),
                      child: _buildGridActionButton(
                        icon: Icons.share,
                        onTap: () => _shareCombinedDocument(document),
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

  Widget _buildSelectedFilesHeader(AppLocalizations localization) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.folder_copy,
            size: 20,
            color: const Color(0xFFFF9800),
          ),
          const SizedBox(width: 8),
          Text(
            '${localization.translate('selectedPdfs')} (${_vm.plan.sources.length})',
            style: AppTextStyles.bodyText.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFFFF9800),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _pickPDFs,
            icon: const Icon(Icons.add, size: 18),
            label: Text(localization.translate('addMore')),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF9800),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileCard(
      int index, ColorScheme colors, AppLocalizations localization) {
    final source = _vm.plan.sources[index];
    final selected = _vm.plan.selectedCount(source.id);
    final notes = <String>[
      if (source.features.hasFormFields)
        localization.translate('combineNoteForms'),
      if (source.features.hasAnnotations)
        localization.translate('combineNoteAnnotations'),
      if (source.features.hasBookmarks)
        localization.translate('combineNoteBookmarks'),
    ];
    final mutedStyle = TextStyle(
      color: colors.onSurface.withValues(alpha: 0.6),
      fontSize: 12,
    );

    return Container(
      key: ValueKey(source.id),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected == 0
              ? colors.error
              : colors.outline.withValues(alpha: 0.2),
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
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFF9800).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.picture_as_pdf,
            color: const Color(0xFFFF9800),
            size: 24,
          ),
        ),
        title: Text(
          source.displayName,
          style: AppTextStyles.bodyText.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: colors.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${localization.translate('combinePagesOfFile').replaceAll('{selected}', '$selected').replaceAll('{total}', '${source.pageCount}')} • ${(source.size / 1024).toStringAsFixed(1)} KB',
                      style: mutedStyle,
                    ),
                  ),
                ],
              ),
              for (final note in notes)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(note,
                      style: mutedStyle.copyWith(color: Colors.orange[800])),
                ),
              Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: () => _previewSource(source),
                    icon: const Icon(Icons.visibility, size: 16),
                    label: Text(localization.translate('combinePreviewFile')),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFF9800),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                  ),
                  TextButton.icon(
                    onPressed:
                        _vm.isMerging ? null : () => _selectPages(source),
                    icon: const Icon(Icons.tune, size: 16),
                    label: Text(localization.translate('combineSelectPages')),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFF9800),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Order indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: const Color(0xFFFF9800),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ReorderableDragStartListener(
              index: index,
              enabled: !_vm.isMerging,
              child: Icon(
                Icons.drag_handle,
                color: colors.onSurface.withValues(alpha: 0.4),
                size: 20,
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: colors.error, size: 20),
              onPressed:
                  _vm.isMerging ? null : () => _vm.removeSource(source.id),
              tooltip: localization.translate('remove'),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton(AppLocalizations localization) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: !_vm.plan.isEmpty
          ? FloatingActionButton.extended(
              onPressed: _vm.isMerging ? null : _combinePDFs,
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: Colors.white,
              elevation: 8,
              icon: _vm.isMerging
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.merge_type),
              label: Text(
                _vm.isMerging
                    ? localization.translate('combining')
                    : localization.translate('combinePdfsButton'),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            )
          : FloatingActionButton.extended(
              onPressed: _pickPDFs,
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: Colors.white,
              elevation: 8,
              icon: const Icon(Icons.add_circle_outline),
              label: Text(
                _vm.documents.isEmpty
                    ? localization.translate('createFirstPdf')
                    : localization.translate('createNewPdf'),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
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
}
