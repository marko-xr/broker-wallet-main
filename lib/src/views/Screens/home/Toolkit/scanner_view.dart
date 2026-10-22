import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Widgets/tool_header_card.dart';
import 'package:broker_wallet/src/Views/Widgets/tool_progress_overlay.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/pdf_viewer_screen.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/scanner_image_viewer.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/scanner_review_screen.dart';
import 'package:broker_wallet/src/services/share/share_live.dart';
import 'package:broker_wallet/src/constants/app_colors.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/scanner/scan_models.dart';
import 'package:broker_wallet/src/services/scanner/scan_result.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';
import 'package:broker_wallet/src/services/scanner/scanner_wiring.dart';
import 'package:broker_wallet/src/services/toolkit_documents/toolkit_cloud_sync.dart';
import 'package:broker_wallet/src/viewmodels/scanner/scanner_viewmodel.dart';

/// The document Scanner: scan with the phone's own scanner, review, save to the
/// signed-in account's private list, then preview, rename, share, export and
/// delete. The logic lives in [ScannerViewModel]; this file is the screen.
class ScannerView extends StatefulWidget {
  const ScannerView({Key? key}) : super(key: key);

  @override
  _ScannerViewState createState() => _ScannerViewState();
}

class _ScannerViewState extends State<ScannerView> {
  late final ScannerViewModel _vm;
  bool _isGridView = true;

  static const String _gridViewPreferenceKey = 'scanner_grid_view_mode';
  static const String _maxPagesPreferenceKey = 'scanner_max_pages';

  @override
  void initState() {
    super.initState();
    _vm = ScannerWiring.createViewModel();
    _loadPreferences();
    _vm.start();
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  AppLocalizations get _localization => AppLocalizations.of(context);

  void _showToast(String message, Color color) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: color,
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }

  // View preferences (not documents): the grid/list choice and the page limit.
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pages = prefs.getInt(_maxPagesPreferenceKey);
      if (!mounted) return;
      setState(() {
        _isGridView = prefs.getBool(_gridViewPreferenceKey) ?? true;
      });
      if (pages != null && ScannerViewModel.maxPageChoices.contains(pages)) {
        _vm.maxPages = pages;
      }
    } catch (e) {
      // Defaults are fine when preferences cannot be read.
    }
  }

  Future<void> _saveViewModePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_gridViewPreferenceKey, _isGridView);
    } catch (e) {
      // The choice still applies for this visit.
    }
  }

  Future<void> _saveMaxPagesPreference(int pages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_maxPagesPreferenceKey, pages);
    } catch (e) {
      // The choice still applies for this visit.
    }
  }

  String _failureMessage(ScannerFailure failure) {
    final loc = _localization;
    switch (failure) {
      case ScannerFailure.signedOut:
        return loc.translate('scannerErrSignedOut');
      case ScannerFailure.busy:
        return loc.translate('scannerErrBusy');
      case ScannerFailure.scanAbandoned:
        return loc.translate('scannerErrAbandoned');
      case ScannerFailure.engineFailed:
        return loc.translate('scannerErrEngine');
      case ScannerFailure.malformedResult:
        return loc.translate('scannerErrMalformed');
      case ScannerFailure.wrongFormat:
        return loc.translate('scannerErrWrongFormat');
      case ScannerFailure.untrustedSource:
      case ScannerFailure.missingOutput:
        return loc.translate('scannerErrUnreadable');
      case ScannerFailure.emptyOutput:
        return loc.translate('scannerErrEmpty');
      case ScannerFailure.corruptOutput:
        return loc.translate('scannerErrCorrupt');
      case ScannerFailure.tooLarge:
        return loc.translate('scannerErrTooLarge');
      case ScannerFailure.storageFull:
        return loc.translate('scannerErrStorageFull');
      case ScannerFailure.writeFailed:
        return loc.translate('scannerErrWrite');
      case ScannerFailure.notFound:
        return loc.translate('scannerErrNotFound');
      case ScannerFailure.invalidName:
        return loc.translate('scannerErrInvalidName');
      case ScannerFailure.nameInUse:
        return loc.translate('scannerErrNameInUse');
      case ScannerFailure.fileMissing:
        return loc.translate('documentFileNotFound');
      case ScannerFailure.quotaBlocked:
        return loc.translate('quotaLimitReached');
      case ScannerFailure.accountChanged:
        return loc.translate('scannerErrAccountChanged');
      case ScannerFailure.permissionDenied:
        return loc.translate('storagePermissionDenied');
      case ScannerFailure.exportFailed:
        return loc.translate('scannerErrExport');
    }
  }

  // ---------------------------------------------------------------- scanning

  Future<void> _startScanning() async {
    if (_vm.isBusy || _vm.draft != null) return;
    final result = await _vm.startScan(
      allowNewScan: (uid) => ScannerWiring.usageGate.allowNewScan(context, uid),
    );
    if (!mounted) return;
    if (result.cancelled) {
      _showToast(_localization.translate('scanningCancelled'), Colors.orange);
      return;
    }
    final failure = result.failure;
    if (failure != null) {
      if (failure == ScannerFailure.scanAbandoned) {
        // The scan's result was lost; nothing was saved. Offer the retry.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_failureMessage(failure)),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: _localization.translate('retry'),
            onPressed: _startScanning,
          ),
        ));
        return;
      }
      // The plan-limit dialog has already told the user why.
      if (failure != ScannerFailure.quotaBlocked) {
        _showToast(_failureMessage(failure), Colors.red);
      }
      return;
    }
    final draft = result.draft!;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ScannerReviewScreen(viewModel: _vm),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      final loc = _localization;
      final text = draft.format == ExportFormat.images && draft.pageCount > 1
          ? loc
              .translate('scannerImagesSaved')
              .replaceAll('{count}', '${draft.pageCount}')
          : loc.translate('documentSavedSuccessfully');
      _showToast(text, Colors.green);
    } else {
      // Left with the system Back gesture or an account change: nothing was
      // saved, so the scan's temporary files go.
      await _vm.discardDraft();
    }
  }

  // ----------------------------------------------------------------- actions

  Future<void> _previewDocument(ScannerDocument document) async {
    final file = await _vm.openableFile(document);
    if (!mounted) return;
    if (file == null) {
      _showToast(_openFailureMessage(), Colors.red);
      return;
    }
    final Widget screen = document.format == ExportFormat.pdf
        ? PdfViewerScreen(localFile: file, title: document.name)
        : ScannerImageViewer(file: file, title: document.name);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => screen,
    ));
  }

  /// Why a document could not be opened, shared or exported: the phone could
  /// not fetch it from the account (a connection problem, or no room), or its
  /// file is simply not there.
  String _openFailureMessage() {
    switch (_vm.lastOpenFailure) {
      case ToolkitEnsureResult.unavailable:
        return _localization.translate('toolkitDocumentUnavailable');
      case ToolkitEnsureResult.storageFull:
        return _localization.translate('scannerErrStorageFull');
      case ToolkitEnsureResult.gone:
      case ToolkitEnsureResult.ready:
      case null:
        return _localization.translate('documentFileNotFound');
    }
  }

  Future<void> _shareDocuments(List<ScannerDocument> documents) async {
    if (documents.isEmpty) return;
    try {
      final preparation =
          await _vm.prepareShare(documents.map((d) => d.id).toList());
      if (!mounted) return;
      if (!preparation.isShareable) {
        _showToast(
          preparation.unavailable.isNotEmpty
              ? _openFailureMessage()
              : _localization.translate('failedToShareDocuments'),
          Colors.red,
        );
        return;
      }
      await ShareLive.sendFiles(
        context,
        preparation.paths,
        text: documents.length == 1
            ? '${_localization.translate('scannedDocument')}: ${documents.first.name}'
            : _localization
                .translate('sharingDocuments')
                .replaceAll('{count}', '${documents.length}'),
      );
    } catch (e) {
      if (mounted) {
        _showToast(
            _localization.translate('failedToShareDocuments'), Colors.red);
      }
    }
  }

  Future<void> _shareBulkDocuments() async {
    final selected = _vm.selectedDocuments;
    await _shareDocuments(selected);
    if (mounted) _vm.exitSelectionMode();
  }

  Future<void> _exportDocument(ScannerDocument document) async {
    try {
      final result = await _vm.exportDocument(document.id);
      if (!mounted || result.cancelled) return;
      final loc = _localization;
      final key = result.destination == ScannerExportDestination.downloads
          ? 'scannerExportedToDownloads'
          : 'scannerExportedToFiles';
      _showToast(
        loc.translate(key).replaceAll('{name}', result.savedName ?? ''),
        Colors.green,
      );
    } on ScannerException catch (e) {
      if (mounted) {
        _showToast(
          e.kind == ScannerFailure.fileMissing && _vm.lastOpenFailure != null
              ? _openFailureMessage()
              : _failureMessage(e.kind),
          Colors.red,
        );
      }
    } catch (e) {
      if (mounted) {
        _showToast(_failureMessage(ScannerFailure.exportFailed), Colors.red);
      }
    }
  }

  Future<void> _renameDocument(ScannerDocument document) async {
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
                maxLength: ScannerNaming.maxNameRunes,
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
                ElevatedButton(
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
      _showToast(
          _localization.translate('documentRenamedSuccessfully'), Colors.green);
    }
  }

  Future<void> _deleteDocuments(List<ScannerDocument> documents) async {
    if (documents.isEmpty) return;
    final count = documents.length;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(_localization.translate('confirmDelete')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == 1
                      ? _localization.translate('areYouSureDeleteOneDocument')
                      : '${_localization.translate('areYouSureDelete')} $count ${_localization.translate('documents')}?',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 12),
                Text(
                  _localization.translate('cannotRestoreItems'),
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
                child: Text(_localization.translate('cancel')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: Text(_localization.translate('delete')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    final failed = await _vm.delete(documents.map((d) => d.id).toList());
    if (!mounted) return;
    _vm.exitSelectionMode();
    final deleted = count - failed.length;
    if (failed.isNotEmpty) {
      _showToast(
        count == 1
            ? _localization.translate('failedToDeleteDocument')
            : _localization.translate('failedToDeleteSelected'),
        Colors.red,
      );
    } else {
      _showToast(
        count == 1
            ? _localization.translate('documentDeleted')
            : _localization
                .translate('documentsDeleted')
                .replaceAll('{count}', '$deleted'),
        Colors.green,
      );
    }
  }

  // ---------------------------------------------------------------- settings

  void _showScanSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ListenableBuilder(
        listenable: _vm,
        builder: (context, _) => _buildScanSettings(),
      ),
    );
  }

  Widget _buildScanSettings() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: colors.outline.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              _localization.translate('scanSettings'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Scan mode: a label for the document and its default name.
                  _buildSettingSection(
                    _localization.translate('scanMode'),
                    Column(
                      children: [
                        RadioGroup<ScanMode>(
                          groupValue: _vm.scanMode,
                          onChanged: (ScanMode? value) {
                            if (value != null) _vm.selectScanMode(value);
                          },
                          child: Column(
                            children: ScanMode.values.map((mode) {
                              return RadioListTile<ScanMode>(
                                title: Text(_getScanTypeLabel(mode)),
                                subtitle: Text(_getScanModeDescription(mode)),
                                value: mode,
                              );
                            }).toList(),
                          ),
                        ),
                        _buildNote(_localization.translate('scannerModeNote')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildSettingSection(
                    _localization.translate('exportFormat'),
                    RadioGroup<ExportFormat>(
                      groupValue: _vm.exportFormat,
                      onChanged: (ExportFormat? value) {
                        if (value != null) _vm.selectExportFormat(value);
                      },
                      child: Column(
                        children: ExportFormat.values.map((format) {
                          return RadioListTile<ExportFormat>(
                            title: Text(format.name.toUpperCase()),
                            subtitle: Text(_getFormatDescription(format)),
                            value: format,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildSettingSection(
                    _localization.translate('scannerMaxPages'),
                    Wrap(
                      spacing: 8,
                      children: ScannerViewModel.maxPageChoices.map((pages) {
                        return ChoiceChip(
                          label: Text('$pages'),
                          selected: _vm.maxPages == pages,
                          onSelected: (_) {
                            _vm.maxPages = pages;
                            _saveMaxPagesPreference(pages);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Quality: neither platform's scanner takes a quality from
                  // the app, so the choices are shown as unavailable.
                  _buildSettingSection(
                    _localization.translate('scanQuality'),
                    Column(
                      children: [
                        RadioGroup<ScanQuality>(
                          groupValue: null,
                          onChanged: (_) {},
                          child: Column(
                            children: ScanQuality.values.map((quality) {
                              return RadioListTile<ScanQuality>(
                                title: Text(_getScanQualityLabel(quality)
                                    .toUpperCase()),
                                value: quality,
                                enabled: false,
                              );
                            }).toList(),
                          ),
                        ),
                        _buildNote(
                            _localization.translate('scannerQualityNote')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildSettingSection(
                    _localization.translate('scannerBuiltInToolsTitle'),
                    _buildNote(
                        _localization.translate('scannerBuiltInToolsBody')),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNote(String text) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 18, color: colors.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.7),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingSection(String title, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        content,
      ],
    );
  }

  String _getScanTypeLabel(ScanMode type) {
    switch (type) {
      case ScanMode.document:
        return _localization.translate('document');
      case ScanMode.receipt:
        return _localization.translate('receipt');
      case ScanMode.businessCard:
        return _localization.translate('businessCard');
      case ScanMode.passport:
        return _localization.translate('passport');
      case ScanMode.book:
        return _localization.translate('book');
      case ScanMode.magazine:
        return _localization.translate('magazine');
    }
  }

  String _getFormatDescription(ExportFormat format) {
    switch (format) {
      case ExportFormat.pdf:
        return _localization.translate('singlePdfWithAllPages');
      case ExportFormat.images:
        return _localization.translate('individualImageFiles');
    }
  }

  String _getFormatLabel(ExportFormat format) {
    switch (format) {
      case ExportFormat.pdf:
        return _localization.translate('pdf');
      case ExportFormat.images:
        return _localization.translate('images');
    }
  }

  String _getScanQualityLabel(ScanQuality quality) {
    switch (quality) {
      case ScanQuality.low:
        return _localization.translate('low');
      case ScanQuality.medium:
        return _localization.translate('medium');
      case ScanQuality.high:
        return _localization.translate('high');
      case ScanQuality.ultra:
        return _localization.translate('ultra');
    }
  }

  // ------------------------------------------------------------------ layout

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        return Stack(
          children: [
            Scaffold(
              backgroundColor: colors.surface,
              extendBodyBehindAppBar: true,
              resizeToAvoidBottomInset: false,
              appBar: _buildAdvancedAppBar(localization, colors),
              body: _buildBody(localization, colors),
              floatingActionButton: _buildAdvancedFAB(localization),
              floatingActionButtonLocation:
                  FloatingActionButtonLocation.centerDocked,
            ),
            // A document of the account is being opened: the spinner alone,
            // and the taps wait for it.
            if (_vm.isFetchingCloud)
              const Positioned.fill(child: ToolProgressOverlay()),
          ],
        );
      },
    );
  }

  PreferredSizeWidget _buildAdvancedAppBar(
      AppLocalizations localization, ColorScheme colors) {
    final documents = _vm.documents;
    final selecting = _vm.isSelectionMode;
    return AppBar(
      // BackArrowButton pads itself by 16 px unless told otherwise; with zero
      // padding and a 48 px leading slot the arrow sits on the content edge.
      leadingWidth: 48,
      leading: const BackArrowButton(
        iconColor: Colors.white, // Set to white to match the primary gradient
        iconSize: 24,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        showBackground: false,
      ),
      title: Text(
        selecting
            ? '${_vm.selectedCount} ${_localization.translate('selected')}'
            : _localization.translate('Scanner'),
        style: AppTextStyles.appBarTitle.copyWith(fontSize: 20),
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
              AppColors.primary.withValues(alpha: 0.9),
              AppColors.primary.withValues(alpha: 0.7),
              Colors.transparent,
            ],
          ),
        ),
      ),
      actions: [
        if (selecting) ...[
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: _vm.selectedCount > 0 ? _shareBulkDocuments : null,
            tooltip: _localization.translate('shareSelected'),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.white),
            onPressed: _vm.selectedCount > 0
                ? () => _deleteDocuments(_vm.selectedDocuments)
                : null,
            tooltip: _localization.translate('deleteSelected'),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _vm.exitSelectionMode,
            tooltip: _localization.translate('cancelSelection'),
          ),
        ] else ...[
          if (documents.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.checklist, color: Colors.white),
              onPressed: _vm.enterSelectionMode,
              tooltip: _localization.translate('selectDocuments'),
            ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: _showScanSettings,
            tooltip: _localization.translate('scanSettings'),
          ),
        ],
        // The last icon's glyph ends on the same 16 px edge as the content.
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildBody(AppLocalizations localization, ColorScheme colors) {
    final documents = _vm.documents;
    return CustomScrollView(
      slivers: [
        // Header space for transparent app bar
        const SliverToBoxAdapter(child: SizedBox(height: 120)),

        SliverToBoxAdapter(
          child: _buildModeIndicator(localization, colors),
        ),

        if (_vm.legacyDocumentCount > 0)
          SliverToBoxAdapter(child: _buildLegacyNotice(colors)),

        if (documents.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _buildScannedDocumentsHeader(localization),
          ),
          _isGridView
              ? SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverGrid(
                    // A fixed height sized to the tile's content (grows with
                    // the system text size) instead of a width-based ratio,
                    // which made the tiles needlessly tall.
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
                        final document = documents[index];
                        return KeyedSubtree(
                          key: ValueKey<String>(document.id),
                          child: _buildDocumentGridCard(document),
                        );
                      },
                      childCount: documents.length,
                    ),
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final document = documents[index];
                      return KeyedSubtree(
                        key: ValueKey<String>(document.id),
                        child: _buildDocumentCard(document),
                      );
                    },
                    childCount: documents.length,
                  ),
                ),
        ] else if (_vm.isLoading || _vm.isWaitingForAccount)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (_vm.loadFailed)
          SliverToBoxAdapter(child: _buildLoadFailed())
        else
          SliverToBoxAdapter(
            child: _buildEmptyState(),
          ),

        // Bottom padding for FAB
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildModeIndicator(
      AppLocalizations localization, ColorScheme colors) {
    return ToolHeaderCard(
      icon: _getScanModeIcon(_vm.scanMode),
      title: _localization.translate('scanModeLabel').replaceAll(
          '{mode}', _getScanTypeLabel(_vm.scanMode).toUpperCase()),
      subtitle: _getScanModeDescription(_vm.scanMode),
      gradient: [
        AppColors.primary,
        Color.lerp(AppColors.primary, Colors.black, 0.25)!,
      ],
    );
  }

  Widget _buildLegacyNotice(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: _buildNote(_localization
          .translate('scannerLegacyNotice')
          .replaceAll('{count}', '${_vm.legacyDocumentCount}')),
    );
  }

  Widget _buildAdvancedFAB(AppLocalizations localization) {
    final disabled = _vm.isBusy || _vm.draft != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: FloatingActionButton.extended(
        onPressed: disabled ? null : _startScanning,
        // No spinner or changed label: the system scanner is the feedback.
        icon: const Icon(Icons.camera_alt),
        label: Text(
          _vm.documents.isEmpty
              ? _localization.translate('startScanning')
              : _localization.translate('scanMore'),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 8,
      ),
    );
  }

  IconData _getScanModeIcon(ScanMode mode) {
    switch (mode) {
      case ScanMode.document:
        return Icons.description;
      case ScanMode.receipt:
        return Icons.receipt;
      case ScanMode.businessCard:
        return Icons.credit_card;
      case ScanMode.passport:
        return Icons.person;
      case ScanMode.book:
        return Icons.menu_book;
      case ScanMode.magazine:
        return Icons.collections;
    }
  }

  String _getScanModeDescription(ScanMode mode) {
    switch (mode) {
      case ScanMode.document:
        return _localization.translate('optimizedForTextDocuments');
      case ScanMode.receipt:
        return _localization.translate('highContrastForReceipts');
      case ScanMode.businessCard:
        return _localization.translate('preservesColorsAndDetails');
      case ScanMode.passport:
        return _localization.translate('maintainsOriginalColors');
      case ScanMode.book:
        return _localization.translate('reducesShadowsImproves');
      case ScanMode.magazine:
        return _localization.translate('enhancedColorReproduction');
    }
  }

  Widget _buildLoadFailed() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.error_outline,
              size: 56, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text(
            _localization.translate('scannerLoadFailed'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _vm.refresh,
            child: Text(_localization.translate('retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.scanner,
              size: 80,
              color: AppColors.primary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _localization.translate('noDocumentsScannedYet'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
          Text(
            _localization.translate('tapScanButtonToStart'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[500],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannedDocumentsHeader(AppLocalizations localization) {
    // Right inset 4: the 48 px toggle's icon then ends on the 16 px edge,
    // directly under the app bar's last icon.
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 4, 4),
      child: Row(
        children: [
          Icon(
            Icons.scanner,
            size: 20,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Text(
            '${localization.translate('scannedDocuments')} (${_vm.documents.length})',
            style: AppTextStyles.bodyText.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const Spacer(),
          // Shows the view the tap switches to; replaces the old text label.
          IconButton(
            icon: Icon(
              _isGridView ? Icons.view_list : Icons.grid_view,
              color: AppColors.primary,
            ),
            onPressed: () {
              setState(() => _isGridView = !_isGridView);
              _saveViewModePreference();
            },
            tooltip: _isGridView
                ? _localization.translate('listView')
                : _localization.translate('gridView'),
          ),
        ],
      ),
    );
  }

  // The date and time the scan was saved, in the phone's locale.
  String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final material = MaterialLocalizations.of(context);
    return '${material.formatMediumDate(local)} '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _pagesLabel(ScannerDocument document) => _localization
      .translate('scannerPageCountLabel')
      .replaceAll('{count}', '${document.pageCount}');

  Widget _buildMissingBadge() {
    final colors = Theme.of(context).colorScheme;
    return Text(
      _localization.translate('scannerFileMissingBadge'),
      style: TextStyle(
        color: colors.error,
        fontWeight: FontWeight.w600,
        fontSize: 11,
      ),
    );
  }

  void _onCardTap(ScannerDocument document) {
    if (_vm.isSelectionMode) {
      _vm.toggleSelection(document.id);
    } else {
      _previewDocument(document);
    }
  }

  void _onCardLongPress(ScannerDocument document) {
    if (_vm.isSelectionMode) return;
    _vm.enterSelectionMode();
    _vm.toggleSelection(document.id);
  }

  Widget _buildDocumentCard(ScannerDocument document) {
    final isSelected = _vm.isSelected(document.id);
    final isSelectionMode = _vm.isSelectionMode;
    final missing = _vm.isMissing(document.id);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? AppColors.primary
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: isSelectionMode
            ? Checkbox(
                value: isSelected,
                onChanged: (_) => _vm.toggleSelection(document.id),
                activeColor: AppColors.primary,
              )
            : Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  document.format == ExportFormat.pdf
                      ? Icons.picture_as_pdf
                      : Icons.image,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
        onTap: () => _onCardTap(document),
        onLongPress: () => _onCardLongPress(document),
        title: Text(
          document.name,
          style: AppTextStyles.bodyText.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_getScanTypeLabel(document.scanType).toUpperCase()} • ${_getFormatLabel(document.format).toUpperCase()}',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${_formatDateTime(document.createdAt)} • ${_pagesLabel(document)} • ${_formatFileSize(document.fileSize)}',
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
              if (missing) _buildMissingBadge(),
            ],
          ),
        ),
        trailing: isSelectionMode
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.visibility,
                        color: AppColors.primary, size: 20),
                    onPressed: () => _previewDocument(document),
                    tooltip: _localization.translate('preview'),
                    visualDensity: VisualDensity.compact,
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6)),
                    onSelected: (value) {
                      switch (value) {
                        case 'share':
                          _shareDocuments([document]);
                          break;
                        case 'download':
                          _exportDocument(document);
                          break;
                        case 'rename':
                          _renameDocument(document);
                          break;
                        case 'delete':
                          _deleteDocuments([document]);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'share',
                        child: Row(
                          children: [
                            const Icon(Icons.share,
                                size: 20, color: Colors.blue),
                            const SizedBox(width: 12),
                            Text(_localization.translate('share')),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'download',
                        child: Row(
                          children: [
                            const Icon(Icons.download,
                                size: 20, color: Colors.green),
                            const SizedBox(width: 12),
                            Text(_localization.translate('download')),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            const Icon(Icons.edit,
                                size: 20, color: Colors.grey),
                            const SizedBox(width: 12),
                            Text(_localization.translate('rename')),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(Icons.delete,
                                size: 20, color: Colors.red),
                            const SizedBox(width: 12),
                            Text(_localization.translate('delete')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDocumentGridCard(ScannerDocument document) {
    final isSelected = _vm.isSelected(document.id);
    final isSelectionMode = _vm.isSelectionMode;
    final missing = _vm.isMissing(document.id);

    return Card(
      margin: const EdgeInsets.all(4),
      elevation: isSelected ? 8 : 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected
            ? BorderSide(color: AppColors.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _onCardTap(document),
        onLongPress: () => _onCardLongPress(document),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Theme.of(context).colorScheme.surface,
          ),
          // The tile height is fixed by the grid's aspect ratio, so the
          // content below is kept compact and the action buttons are pinned
          // to the bottom; the details clip rather than overflow.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row with selection indicator and menu
              SizedBox(
                height: 28,
                child: Row(
                children: [
                  if (isSelectionMode)
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? AppColors.primary : Colors.grey,
                          width: 2,
                        ),
                        color:
                            isSelected ? AppColors.primary : Colors.transparent,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 14)
                          : null,
                    )
                  else
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        document.format == ExportFormat.pdf
                            ? Icons.picture_as_pdf
                            : Icons.image,
                        color: AppColors.primary,
                        size: 16,
                      ),
                    ),
                  const Spacer(),
                  if (!isSelectionMode)
                    PopupMenuButton<String>(
                      // A sized child instead of the default icon button,
                      // which would add 48 px of height to this row.
                      child: SizedBox(
                        width: 32,
                        height: 28,
                        child: Icon(
                          Icons.more_vert,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      onSelected: (value) async {
                        switch (value) {
                          case 'rename':
                            await _renameDocument(document);
                            break;
                          case 'delete':
                            await _deleteDocuments([document]);
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
                              Text(_localization.translate('rename')),
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
                                _localization.translate('delete'),
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
                      Text(
                        document.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              height: 1.2,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          '${_getScanTypeLabel(document.scanType)} • ${_getFormatLabel(document.format)} • ${_pagesLabel(document)}',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatDateTime(document.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 11,
                              height: 1.2,
                            ),
                      ),
                      const SizedBox(height: 4),
                      if (missing)
                        _buildMissingBadge()
                      else
                        Row(
                          children: [
                            Icon(
                              Icons.folder,
                              size: 10,
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _formatFileSize(document.fileSize),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
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
                      onTap: () => _previewDocument(document),
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Tooltip(
                      message: AppLocalizations.of(context).translate('share'),
                      child: _buildGridActionButton(
                        icon: Icons.share,
                        onTap: () => _shareDocuments([document]),
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildGridActionButton(
                      icon: Icons.download,
                      onTap: () => _exportDocument(document),
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
      onTap: _vm.isSelectionMode ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: color,
        ),
      ),
    );
  }
}
