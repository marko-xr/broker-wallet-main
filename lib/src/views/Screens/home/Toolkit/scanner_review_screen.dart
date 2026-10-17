import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/app_colors.dart';
import 'package:broker_wallet/src/services/scanner/scan_models.dart';
import 'package:broker_wallet/src/services/scanner/scan_result.dart';
import 'package:broker_wallet/src/viewmodels/scanner/scanner_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/scanner_image_viewer.dart';

/// The step between scanning and saving: every page that will be stored, in
/// order, the real page count, and a name. Nothing is stored until Save; Discard
/// (or Back, after confirming) deletes the scan's temporary files. A failed save
/// stays on this screen with the scan intact, so Save can simply be tried again.
///
/// Pops with `true` once the scan is saved, `false` when it was discarded or the
/// account changed under it.
class ScannerReviewScreen extends StatefulWidget {
  const ScannerReviewScreen({super.key, required this.viewModel});

  final ScannerViewModel viewModel;

  @override
  State<ScannerReviewScreen> createState() => _ScannerReviewScreenState();
}

class _ScannerReviewScreenState extends State<ScannerReviewScreen> {
  late final TextEditingController _name;
  String? _error;
  bool _closing = false;

  // Save is running from this screen: the scan leaves the view model on
  // success, and that must end in this screen's own pop(true), not in the
  // "scan was dropped under us" pop(false) below.
  bool _saveInFlight = false;

  ScannerViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _vm.suggestedName);
    _vm.addListener(_onViewModelChanged);
  }

  @override
  void dispose() {
    _vm.removeListener(_onViewModelChanged);
    _name.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    // The scan was dropped under us (the signed-in account changed).
    if (!_closing &&
        !_saveInFlight &&
        _vm.draft == null &&
        !_vm.isSaving &&
        mounted) {
      _closing = true;
      Navigator.of(context).pop(false);
    }
  }

  String _failureText(AppLocalizations loc, ScannerFailure failure) {
    switch (failure) {
      case ScannerFailure.storageFull:
        return loc.translate('scannerErrStorageFull');
      case ScannerFailure.accountChanged:
        return loc.translate('scannerErrAccountChanged');
      case ScannerFailure.busy:
        return loc.translate('scannerErrBusy');
      default:
        return loc.translate('scannerErrWrite');
    }
  }

  Future<void> _save() async {
    if (_vm.isSaving) return;
    final loc = AppLocalizations.of(context);
    setState(() => _error = null);
    _saveInFlight = true;
    final ScanSaveResult result;
    try {
      result = await _vm.saveDraft(_name.text);
    } finally {
      _saveInFlight = false;
    }
    if (!mounted) return;
    if (result.isSaved) {
      _closing = true;
      Navigator.of(context).pop(true);
      return;
    }
    if (result.failure == ScannerFailure.accountChanged) {
      _closing = true;
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _error = _failureText(loc, result.failure!));
  }

  Future<bool> _confirmDiscard() async {
    final loc = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(loc.translate('scannerDiscardTitle')),
        content: Text(loc.translate('scannerDiscardMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(loc.translate('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(loc.translate('discard')),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _discard() async {
    if (_vm.isSaving) return;
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    _closing = true;
    await _vm.discardDraft();
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final draft = _vm.draft;
        if (draft == null) {
          return Scaffold(backgroundColor: colors.surface);
        }
        final saving = _vm.isSaving;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && !saving) _discard();
          },
          child: Scaffold(
            backgroundColor: colors.surface,
            appBar: AppBar(
              title: Text(loc.translate('scannerReviewTitle')),
              centerTitle: true,
              backgroundColor: colors.surface,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: saving ? null : _discard,
                tooltip: loc.translate('discard'),
              ),
            ),
            body: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: _summary(loc, colors, draft),
                  ),
                  Expanded(child: _pages(loc, colors, draft)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      loc.translate('scannerReviewHint'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.65),
                          ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: TextField(
                      controller: _name,
                      enabled: !saving,
                      maxLength: ScannerNaming.maxNameRunes,
                      decoration: InputDecoration(
                        labelText: loc.translate('documentName'),
                        border: const OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              size: 18, color: colors.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: saving ? null : _discard,
                            child: Text(loc.translate('discard')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: saving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                            icon: saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label: Text(saving
                                ? loc.translate('scannerSaving')
                                : _error != null
                                    ? loc.translate('retry')
                                    : loc.translate('saveDocument')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _summary(AppLocalizations loc, ColorScheme colors, ScanDraft draft) {
    final format = draft.format == ExportFormat.pdf
        ? loc.translate('pdf')
        : loc.translate('images');
    final pages = loc
        .translate('scannerPageCountLabel')
        .replaceAll('{count}', '${draft.pageCount}');
    return Row(
      children: [
        Icon(
          draft.format == ExportFormat.pdf ? Icons.picture_as_pdf : Icons.image,
          color: AppColors.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$format • $pages • ${_size(draft.totalBytes)}',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _pages(AppLocalizations loc, ColorScheme colors, ScanDraft draft) {
    if (draft.format == ExportFormat.pdf) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SfPdfViewer.file(
            draft.pages.first.file,
            key: ValueKey<String>(draft.id),
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.72,
      ),
      itemCount: draft.pages.length,
      itemBuilder: (context, index) {
        final page = draft.pages[index];
        return InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ScannerImageViewer(
                file: page.file,
                title: loc
                    .translate('scannerPageCountLabel')
                    .replaceAll('{count}', '${index + 1}'),
              ),
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  page.file,
                  fit: BoxFit.cover,
                  cacheWidth: 480,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stack) => Container(
                    color: colors.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              PositionedDirectional(
                top: 6,
                start: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
