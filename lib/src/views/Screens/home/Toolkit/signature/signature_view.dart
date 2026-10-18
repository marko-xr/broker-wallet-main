import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:flutter/material.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/pdf_viewer_screen.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/document_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/signed_documents_storage.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/signature_ui_support.dart';
import 'package:broker_wallet/src/services/scanner/scanner_platform.dart';
import 'package:broker_wallet/src/services/signature/signature_models.dart';
import 'package:broker_wallet/src/services/signature/signature_page_renderer.dart';
import 'package:broker_wallet/src/services/signature/signature_usage_gate.dart';
import 'package:broker_wallet/src/services/signature/signature_wiring.dart';
import 'package:broker_wallet/src/viewmodels/signature/signature_library_viewmodel.dart';

class SignatureScreenPreview extends StatelessWidget {
  const SignatureScreenPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const SignatureScreen();
  }
}

/// The Document Signature tool: pick a PDF, place signatures, initials, dates and
/// texts on its pages, preview the signed copy, and keep it in the signed-in
/// account's private list, where it can be previewed, renamed, shared, exported
/// and deleted. The logic lives in [SignatureLibraryViewModel] and the editing
/// session it opens; this file is the library screen.
class SignatureScreen extends StatefulWidget {
  const SignatureScreen({
    super.key,
    this.viewModel,
    this.usageGate,
    this.rendererFactory,
  });

  /// A ready view model, for tests. The app builds its own.
  final SignatureLibraryViewModel? viewModel;

  /// The plan-limit check, for tests. The app uses [SignatureWiring.usageGate].
  final SignatureUsageGate? usageGate;

  /// Makes a page renderer for the editor, for tests. The app uses
  /// [SignatureWiring.createPageRenderer].
  final SignaturePageRenderer Function()? rendererFactory;

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  // Color palette used in the screenshot
  static const Color redLight = SignatureColors.redLight;
  static const Color redDark = SignatureColors.redDark;
  static const Color redDarker = SignatureColors.redDarker;
  static const double horizontalPadding = 16.0;

  late final SignatureLibraryViewModel _vm;
  late final bool _ownsViewModel;

  // View mode: true = list view, false = grid view
  bool _isListView = false;

  AppLocalizations get _localization => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    _ownsViewModel = widget.viewModel == null;
    _vm = widget.viewModel ?? SignatureWiring.createViewModel();
    _loadViewMode();
    _vm.start();
  }

  @override
  void dispose() {
    if (_ownsViewModel) _vm.dispose();
    super.dispose();
  }

  /// Load view mode preference
  Future<void> _loadViewMode() async {
    final isListView = await SignedDocumentsStorage.loadViewMode();
    if (mounted) {
      setState(() {
        _isListView = isListView;
      });
    }
  }

  /// Toggle view mode
  void _toggleViewMode() {
    setState(() {
      _isListView = !_isListView;
    });
    SignedDocumentsStorage.saveViewMode(_isListView);
  }

  void _showToast(String message, Color bgColor) {
    showSignatureToast(message, bgColor);
  }

  // ----------------------------------------------------------- selection

  void _enterSelectionMode() => _vm.enterSelectionMode();

  void _exitSelectionMode() => _vm.exitSelectionMode();

  void _toggleSelection(String id) => _vm.toggleSelection(id);

  // -------------------------------------------------------------- delete

  Future<bool> _confirmDelete(Widget content) async {
    final localization = _localization;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localization.translate('confirmDelete')),
        content: content,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(localization.translate('cancel')),
          ),
          ElevatedButton(
            key: const ValueKey<String>('confirm-delete'),
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(localization.translate('delete')),
          ),
        ],
      ),
    );
    return shouldDelete == true;
  }

  /// Delete selected documents
  Future<void> _deleteSelectedDocuments() async {
    final localization = _localization;
    final selected = _vm.selectedDocuments;
    final count = selected.length;
    if (count == 0) return;

    final confirmed = await _confirmDelete(Column(
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
    ));
    if (!confirmed || !mounted) return;

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
            .translate('sigDeleteSomeFailed')
            .replaceAll('{count}', '${failed.length}'),
        Colors.red,
      );
    }
  }

  Future<void> _deleteDocument(SignedDocument document) async {
    final localization = _localization;
    final confirmed = await _confirmDelete(Text(
      '${localization.translate('deleteDocumentConfirm')} "${document.name}"?',
    ));
    if (!confirmed || !mounted) return;
    final failed = await _vm.delete(<String>[document.id]);
    if (!mounted) return;
    if (failed.isEmpty) {
      _showToast(localization.translate('documentDeleted'), Colors.green);
    } else {
      _showToast(localization.translate('failedToDeleteDocument'), Colors.red);
    }
  }

  // -------------------------------------------------------------- rename

  Future<void> _renameDocument(SignedDocument document) async {
    final renamed = await showDialog<bool>(
      context: context,
      builder: (_) => _RenameDialog(viewModel: _vm, document: document),
    );
    if (renamed == true && mounted) {
      _showToast(_localization.translate('documentRenamed'), Colors.green);
    }
  }

  // ------------------------------------------------------------- preview

  Future<void> _previewDocument(SignedDocument document) async {
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

  // -------------------------------------------------------------- export

  /// Save document to device storage (Downloads on Android, Files on iPhone)
  Future<void> _saveToDeviceStorage(SignedDocument document) async {
    final localization = _localization;
    try {
      final result = await _vm.exportDocument(document.id);
      if (!mounted || result.cancelled) return;
      final key = result.destination == ScannerExportDestination.downloads
          ? 'sigSavedToDownloads'
          : 'sigSavedToFiles';
      _showToast(
        localization
            .translate(key)
            .replaceAll('{name}', result.savedName ?? ''),
        Colors.green,
      );
    } on SignatureException catch (e) {
      if (mounted) {
        _showToast(signatureFailureMessage(localization, e.kind), Colors.red);
      }
    } catch (e) {
      if (mounted) {
        _showToast(
          signatureFailureMessage(localization, SignatureFailure.exportFailed),
          Colors.red,
        );
      }
    }
  }

  // ------------------------------------------------------------- opening

  /// Handle document upload: pick a PDF and open it for signing.
  Future<void> _uploadDocument() async {
    if (_vm.isBusy) return;
    final outcome = await _vm.pickAndOpen();
    if (!mounted) {
      outcome.session?.dispose();
      return;
    }
    if (outcome.cancelled) return;
    final failure = outcome.failure;
    if (failure != null) {
      await _reportOpenFailure(failure);
      return;
    }
    final session = outcome.session!;
    try {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (context) => DocumentView(
            viewModel: session,
            rendererFactory: widget.rendererFactory,
            usageGate: widget.usageGate,
          ),
        ),
      );
    } finally {
      session.dispose();
    }
  }

  Future<void> _reportOpenFailure(SignatureFailure failure) async {
    final localization = _localization;
    final message = signatureFailureMessage(localization, failure);
    // Refusals the user can act on get a dialog; the rest a short message.
    const explained = <SignatureFailure>{
      SignatureFailure.signedSource,
      SignatureFailure.encryptedSource,
      SignatureFailure.corruptSource,
      SignatureFailure.geometryUnsupported,
      SignatureFailure.tooLargeSource,
      SignatureFailure.tooManyPages,
      SignatureFailure.emptySource,
    };
    if (!explained.contains(failure)) {
      _showToast(message, Colors.red);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localization.translate('sigCannotOpenTitle')),
        content: Text(message, key: const ValueKey<String>('open-refusal')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(localization.translate('ok')),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    final localization = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [redLight, redDarker],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
              Icons.draw,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localization.translate('documentSignature'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  localization.translate('uploadAndSignDocuments'),
                  style: const TextStyle(
                    color: Colors.white70,
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

  /// Build document card for list view
  Widget _buildDocumentCard(
    SignedDocument document,
    AppLocalizations localization,
  ) {
    final isSelected = _vm.isSelected(document.id);
    final isMissing = _vm.isMissing(document.id);
    final isSelectionMode = _vm.isSelectionMode;

    final colors = Theme.of(context).colorScheme;

    return Container(
      key: ValueKey<String>('document-${document.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? redLight : colors.outline.withValues(alpha: 0.2),
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
      // A tile paints its ink on the nearest Material, which here would be
      // behind the card's own colour; this one keeps the ink visible.
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: isSelectionMode
              ? Checkbox(
                  value: isSelected,
                  onChanged: (_) => _toggleSelection(document.id),
                  activeColor: redLight,
                )
              : Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: redLight.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf,
                    color: redLight,
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
                  isMissing ? Icons.warning_amber_rounded : Icons.info_outline,
                  size: 14,
                  color: isMissing ? Colors.red : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    isMissing
                        ? localization.translate('documentFileNotFound')
                        : '${document.pageCount} ${localization.translate('pages')} • ${SignedDocumentsHelper.formatFileSize(document.fileSize)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isMissing ? Colors.red : colors.onSurfaceVariant,
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
                icon: const Icon(Icons.visibility, color: redLight, size: 20),
                onPressed: () => _previewDocument(document),
                tooltip: localization.translate('preview'),
                visualDensity: VisualDensity.compact,
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: colors.onSurfaceVariant),
                onSelected: (value) async {
                  if (value == 'rename') {
                    await _renameDocument(document);
                  } else if (value == 'share') {
                    await SignedDocumentsHelper.shareDocuments(
                        context, _vm, <SignedDocument>[document]);
                  } else if (value == 'download') {
                    await _saveToDeviceStorage(document);
                  } else if (value == 'delete') {
                    await _deleteDocument(document);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        const Icon(Icons.share, size: 20, color: Colors.blue),
                        const SizedBox(width: 12),
                        Text(localization.translate('share')),
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
                        Text(localization.translate('download')),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        const Icon(Icons.edit, size: 20, color: Colors.grey),
                        const SizedBox(width: 12),
                        Text(localization.translate('rename')),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete, size: 20, color: Colors.red),
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
            if (isSelectionMode) {
              _toggleSelection(document.id);
            } else {
              _previewDocument(document);
            }
          },
        ),
      ),
    );
  }

  /// Build document card for grid view
  Widget _buildDocumentGridCard(
    SignedDocument document,
    AppLocalizations localization,
  ) {
    final isSelected = _vm.isSelected(document.id);
    final isMissing = _vm.isMissing(document.id);
    final isSelectionMode = _vm.isSelectionMode;
    final colors = Theme.of(context).colorScheme;

    return Card(
      key: ValueKey<String>('document-${document.id}'),
      margin: const EdgeInsets.all(4),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? redLight : redLight.withValues(alpha: 0.2),
          width: isSelected ? 3 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          if (isSelectionMode) {
            _toggleSelection(document.id);
          } else {
            _previewDocument(document);
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
                colors.surface,
                redLight.withValues(alpha: 0.02),
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
                  isSelectionMode
                      ? Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? redLight
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
                            color: redLight.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.picture_as_pdf,
                            color: redLight,
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
                        color: Colors.grey[600],
                      ),
                    ),
                    onSelected: (value) async {
                      if (value == 'rename') {
                        await _renameDocument(document);
                      } else if (value == 'share') {
                        await SignedDocumentsHelper.shareDocuments(
                            context, _vm, <SignedDocument>[document]);
                      } else if (value == 'download') {
                        await _saveToDeviceStorage(document);
                      } else if (value == 'delete') {
                        await _deleteDocument(document);
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
                        value: 'download',
                        child: Row(
                          children: [
                            const Icon(Icons.download,
                                size: 18, color: Colors.green),
                            const SizedBox(width: 8),
                            Text(localization.translate('download')),
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
                          color: redLight.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: redLight.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          '${document.pageCount} ${localization.translate('pages')} • PDF',
                          style: const TextStyle(
                            color: redLight,
                            fontWeight: FontWeight.w600,
                            fontSize: 9,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Signature count (not known for a document recovered
                      // from files); the line keeps its height when empty.
                      SizedBox(
                        height: 12,
                        child: Text(
                          isMissing
                              ? localization.translate('documentFileNotFound')
                              : document.itemCount == 0
                                  ? ''
                                  : '${document.signatureCount} ${localization.translate('signatures')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: isMissing
                                    ? Colors.red
                                    : colors.onSurfaceVariant,
                                fontSize: 10,
                                height: 1.2,
                              ),
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
                            SignedDocumentsHelper.formatFileSize(
                                document.fileSize),
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
                      onTap: () => _previewDocument(document),
                      color: redLight,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Tooltip(
                      message: AppLocalizations.of(context).translate('share'),
                      child: _buildGridActionButton(
                        icon: Icons.share,
                        onTap: () => SignedDocumentsHelper.shareDocuments(
                            context, _vm, <SignedDocument>[document]),
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
          size: 16,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = Theme.of(context).colorScheme;
    final documents = _vm.documents;
    final isSelectionMode = _vm.isSelectionMode;
    final isOpening = _vm.isOpening;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBodyBehindAppBar: true,
      backgroundColor: colors.surface,
      appBar: AppBar(
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
          localization.translate('signDocument'),
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
                const Color(0xFFF44336).withValues(alpha: 0.9),
                const Color(0xFFB71C1C).withValues(alpha: 0.7),
                Colors.transparent,
              ],
            ),
          ),
        ),
        actions: [
          if (documents.isNotEmpty && !isSelectionMode)
            IconButton(
              icon: const Icon(Icons.checklist, color: Colors.white),
              onPressed: _enterSelectionMode,
              tooltip: localization.translate('selectDocuments'),
            )
          else if (isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.share, color: Colors.white),
              onPressed: _vm.selectedCount > 0
                  ? () async {
                      final selectedDocs = _vm.selectedDocuments;
                      await SignedDocumentsHelper.shareDocuments(
                          context, _vm, selectedDocs);
                      if (mounted) _exitSelectionMode();
                    }
                  : null,
              tooltip: localization.translate('shareSelected'),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.white),
              onPressed:
                  _vm.selectedCount > 0 ? _deleteSelectedDocuments : null,
              tooltip: localization.translate('deleteSelected'),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: _exitSelectionMode,
              tooltip: localization.translate('cancelSelection'),
            ),
          ],
          // The last icon's glyph ends on the same 16 px edge as the content.
          const SizedBox(width: 4),
        ],
      ),

      body: CustomScrollView(
        slivers: [
          // Header space for transparent app bar
          const SliverToBoxAdapter(child: SizedBox(height: 120)),

          // Header card
          SliverToBoxAdapter(
            child: _buildHeaderCard(),
          ),

          // Show signed documents if available
          if (documents.isNotEmpty) ...[
            // Documents header
            SliverToBoxAdapter(
              // Right inset 4: the 48 px toggle's icon then ends on the 16 px
              // edge, directly under the app bar's last icon.
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 4, 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.folder_copy,
                      size: 20,
                      color: redLight,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${localization.translate('signedDocuments')} (${documents.length})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyText.copyWith(
                          fontWeight: FontWeight.w600,
                          color: redLight,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _isListView ? Icons.grid_view : Icons.view_list,
                        color: redLight,
                      ),
                      onPressed: _toggleViewMode,
                      tooltip: _isListView
                          ? localization.translate('gridView')
                          : localization.translate('listView'),
                    ),
                  ],
                ),
              ),
            ),

            // Documents list or grid
            if (_isListView)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildDocumentCard(
                    documents[index],
                    localization,
                  ),
                  childCount: documents.length,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverGrid(
                  // A fixed height sized to the tile's content (it grows with the
                  // system text size). A width-based ratio made the tile too short
                  // on a 360 dp phone, where its column overflowed. Same tile
                  // height as the scanner grid.
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
                    (context, index) => _buildDocumentGridCard(
                      documents[index],
                      localization,
                    ),
                    childCount: documents.length,
                  ),
                ),
              ),
          ] else ...[
            // Empty state
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: redLight.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(
                          Icons.draw,
                          size: 56,
                          color: redLight.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      localization.translate('noSignedDocuments'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      localization.translate('uploadAndSignDocuments'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[500],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Bottom padding for FAB
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),

      // Floating button centered docked
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Container(
        margin: const EdgeInsets.only(bottom: 18),
        child: FloatingActionButton.extended(
          key: const ValueKey<String>('upload-document'),
          onPressed: _vm.isBusy ? null : _uploadDocument,
          elevation: 12,
          backgroundColor: isOpening ? Colors.grey : redDark,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          icon: isOpening
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.upload_file),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            child: Text(
              isOpening
                  ? localization.translate('loading')
                  : localization.translate('uploadDocument'),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for a new title. It owns its text field, so the field outlives the
/// dialog's closing animation. A rename that the store refuses (empty, already
/// used) is shown inside the dialog and the dialog stays open.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.viewModel, required this.document});

  final SignatureLibraryViewModel viewModel;
  final SignedDocument document;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.document.name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final failure =
        await widget.viewModel.rename(widget.document.id, _controller.text);
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = signatureFailureMessage(AppLocalizations.of(context), failure);
    });
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(localization.translate('renameDocument')),
      content: TextField(
        key: const ValueKey<String>('rename-field'),
        controller: _controller,
        maxLength: 80,
        autofocus: true,
        decoration: InputDecoration(
          labelText: localization.translate('documentName'),
          errorText: _error,
          border: const OutlineInputBorder(),
          counterText: '',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(localization.translate('cancel')),
        ),
        TextButton(
          key: const ValueKey<String>('rename-ok'),
          onPressed: _busy ? null : _submit,
          child: Text(localization.translate('rename')),
        ),
      ],
    );
  }
}
