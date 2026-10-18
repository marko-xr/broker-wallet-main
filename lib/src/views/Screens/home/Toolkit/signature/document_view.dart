import 'package:flutter/material.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/signature/signature_models.dart';
import 'package:broker_wallet/src/services/signature/signature_page_renderer.dart';
import 'package:broker_wallet/src/services/signature/signature_usage_gate.dart';
import 'package:broker_wallet/src/services/signature/signature_wiring.dart';
import 'package:broker_wallet/src/viewmodels/signature/signature_editor_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/signature_pad_view.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/signature_page_canvas.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/signature_preview_screen.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/signature_stamp_dialogs.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/signature_ui_support.dart';

/// The editing screen of one picked PDF: its pages, with signatures, initials,
/// dates and texts placed on them.
///
/// Pages are drawn by [SignaturePageRenderer] and the items are laid over them
/// inside the same zoom-and-pan frame ([SignaturePageCanvas]), so a placement
/// is exactly where the page shows it. Save does not store anything by itself:
/// it writes the signed copy, shows it as a preview, and only the preview's own
/// Save keeps it. The logic lives in [SignatureEditorViewModel].
///
/// A drawn or typed item is a visible mark. It is not a certificate based digital
/// signature and does not identify the signer; the preview says so.
class DocumentView extends StatefulWidget {
  const DocumentView({
    super.key,
    required this.viewModel,
    this.rendererFactory,
    this.usageGate,
  });

  /// The editing session. The screen that opened it disposes it.
  final SignatureEditorViewModel viewModel;

  /// Makes a page renderer. The app uses [SignatureWiring.createPageRenderer];
  /// tests pass a fake.
  final SignaturePageRenderer Function()? rendererFactory;

  /// The plan-limit check. The app uses [SignatureWiring.usageGate].
  final SignatureUsageGate? usageGate;

  @override
  State<DocumentView> createState() => _DocumentViewState();
}

class _DocumentViewState extends State<DocumentView> {
  late final SignaturePageRenderer _renderer;
  bool _ready = false;
  SignatureFailure? _openFailure;
  bool _popped = false;
  bool _addBusy = false;

  SignatureEditorViewModel get _vm => widget.viewModel;
  AppLocalizations get _localization => AppLocalizations.of(context);

  SignaturePageRenderer Function() get _factory =>
      widget.rendererFactory ?? SignatureWiring.createPageRenderer;

  @override
  void initState() {
    super.initState();
    _renderer = _factory();
    _vm.addListener(_onModelChanged);
    _openRenderer();
  }

  @override
  void dispose() {
    _vm.removeListener(_onModelChanged);
    _renderer.dispose();
    super.dispose();
  }

  Future<void> _openRenderer() async {
    SignatureFailure? failure;
    try {
      final sizes = await _renderer.open(_vm.sourcePath);
      failure = _vm.checkRendererSizes(sizes);
    } on SignatureException catch (error) {
      failure = error.kind;
    } catch (_) {
      failure = SignatureFailure.corruptSource;
    }
    if (!mounted) return;
    setState(() {
      _openFailure = failure;
      _ready = failure == null;
    });
  }

  void _onModelChanged() {
    if (_vm.accountChanged && !_popped && mounted) {
      _popped = true;
      showSignatureToast(
          signatureFailureMessage(
              _localization, SignatureFailure.accountChanged),
          Colors.red);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(false);
      });
    }
  }

  // ------------------------------------------------------------- leaving

  Future<void> _confirmLeave() async {
    if (_vm.isBusy) return;
    if (!_vm.hasPlacements) {
      Navigator.of(context).pop(false);
      return;
    }
    final localization = _localization;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localization.translate('sigLeaveTitle')),
        content: Text(localization.translate('sigLeaveBody')),
        actions: [
          TextButton(
            key: const ValueKey<String>('leave-stay'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(localization.translate('sigStay')),
          ),
          TextButton(
            key: const ValueKey<String>('leave-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(localization.translate('sigLeave')),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop(false);
  }

  // --------------------------------------------------------------- adding

  Future<void> _addItem() async {
    if (_addBusy || _vm.isBusy) return;
    _addBusy = true;
    try {
      final selection = await showAddStampSheet(
        context,
        signatures: _vm.signatureAssets,
        initials: _vm.initialsAssets,
      );
      if (selection == null || !mounted) return;
      await _handleSelection(selection);
    } finally {
      _addBusy = false;
    }
  }

  Future<void> _handleSelection(AddStampSelection selection) async {
    switch (selection.choice) {
      case AddStampChoice.newSignature:
        final asset = await _drawAsset(StampKind.signature);
        if (asset != null) _place(asset);
      case AddStampChoice.drawInitials:
        final asset = await _drawAsset(StampKind.initials);
        if (asset != null) _place(asset);
      case AddStampChoice.reuseSignature:
      case AddStampChoice.reuseInitials:
        final asset = selection.asset;
        if (asset != null) _place(asset);
      case AddStampChoice.typeInitials:
        final typed =
            await showTypedStampDialog(context, kind: StampKind.initials);
        if (typed == null || !mounted) return;
        final asset = await _typedAsset(StampKind.initials, typed);
        if (asset != null) _place(asset);
      case AddStampChoice.date:
        final typed = await showDateStampDialog(context);
        if (typed == null || !mounted) return;
        final asset = await _typedAsset(StampKind.date, typed);
        if (asset != null) _place(asset);
      case AddStampChoice.text:
        final typed = await showTypedStampDialog(context, kind: StampKind.text);
        if (typed == null || !mounted) return;
        final asset = await _typedAsset(StampKind.text, typed);
        if (asset != null) _place(asset);
    }
  }

  Future<StampAsset?> _drawAsset(StampKind kind,
      {SignatureDrawing? initial}) async {
    final drawing = await Navigator.of(context).push<SignatureDrawing>(
      MaterialPageRoute<SignatureDrawing>(
        builder: (_) => SignaturePadView(
          initialDrawing: initial,
          isInitials: kind == StampKind.initials,
        ),
      ),
    );
    if (drawing == null || !mounted) return null;
    try {
      return await _vm.createDrawnAsset(kind, drawing);
    } on SignatureException catch (error) {
      if (mounted) _failed(error.kind);
      return null;
    }
  }

  Future<StampAsset?> _typedAsset(
      StampKind kind, TypedStampResult typed) async {
    try {
      return await _vm.createTextAsset(kind, typed.text, typed.colorValue);
    } on SignatureException catch (error) {
      if (mounted) _failed(error.kind);
      return null;
    }
  }

  void _place(StampAsset asset) {
    if (!mounted) return;
    try {
      _vm.place(asset, _vm.currentPage);
    } on SignatureException catch (error) {
      _failed(error.kind);
    }
  }

  void _failed(SignatureFailure failure) {
    showSignatureToast(
        signatureFailureMessage(_localization, failure), Colors.red);
  }

  // -------------------------------------------------------- selected item

  Future<void> _editSelected() async {
    final stamp = _vm.selectedStamp;
    if (stamp == null || _addBusy || _vm.isBusy) return;
    final asset = _vm.assetById(stamp.assetId);
    if (asset == null) return;
    _addBusy = true;
    try {
      StampAsset? replacement;
      if (asset.drawing != null) {
        replacement = await _drawAsset(asset.kind, initial: asset.drawing);
      } else if (asset.kind == StampKind.date) {
        final typed = await showDateStampDialog(context);
        if (typed == null || !mounted) return;
        replacement = await _typedAsset(StampKind.date, typed);
      } else {
        final typed = await showTypedStampDialog(
          context,
          kind: asset.kind == StampKind.initials
              ? StampKind.initials
              : StampKind.text,
          initialText: asset.label,
          initialColor: asset.colorValue,
        );
        if (typed == null || !mounted) return;
        replacement = await _typedAsset(asset.kind, typed);
      }
      if (replacement != null && mounted) {
        _vm.replaceImage(stamp.id, replacement);
      }
    } finally {
      _addBusy = false;
    }
  }

  Future<void> _applyToPages() async {
    final stamp = _vm.selectedStamp;
    if (stamp == null || _vm.pageCount < 2) return;
    final chosen = await showDialog<Set<int>>(
      context: context,
      builder: (_) => _ApplyToPagesDialog(
        pageCount: _vm.pageCount,
        sourcePage: stamp.pageIndex,
        alreadyOn: <int>{
          for (final s in _vm.placements)
            if (s.assetId == stamp.assetId) s.pageIndex
        },
      ),
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;
    try {
      final outcome = _vm.applyToPages(stamp.id, chosen);
      final localization = _localization;
      showSignatureToast(
        outcome.added == 0
            ? localization.translate('sigAppliedNone')
            : localization
                .translate('sigApplied')
                .replaceAll('{count}', '${outcome.added}'),
        outcome.added == 0 ? Colors.orange : Colors.green,
      );
    } on SignatureException catch (error) {
      _failed(error.kind);
    }
  }

  Future<void> _goToPage() async {
    if (_vm.pageCount < 2) return;
    final page = await showDialog<int>(
      context: context,
      builder: (_) => _GoToPageDialog(
        current: _vm.currentPage + 1,
        pageCount: _vm.pageCount,
      ),
    );
    if (page != null && mounted) {
      final bounded = page < 1
          ? 1
          : page > _vm.pageCount
              ? _vm.pageCount
              : page;
      _vm.selectPage(bounded - 1);
    }
  }

  // ----------------------------------------------------------- save flow

  Future<void> _review() async {
    if (_vm.isBusy) return;
    final localization = _localization;
    if (!_vm.hasPlacements) {
      showSignatureToast(
          localization.translate('sigNothingToSave'), Colors.orange);
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PreparingDialog(onCancel: _vm.cancelBuild),
    );
    final failure = await _vm.buildDraft();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (failure != null) {
      _reportBuildFailure(failure);
      return;
    }
    final saved = await Navigator.of(context).push<SignedDocument>(
      MaterialPageRoute<SignedDocument>(
        builder: (_) => SignaturePreviewScreen(
          viewModel: _vm,
          rendererFactory: _factory,
          usageGate: widget.usageGate,
        ),
      ),
    );
    if (saved != null && mounted) Navigator.of(context).pop(true);
  }

  void _reportBuildFailure(SignatureFailure failure) {
    final localization = _localization;
    final message = signatureFailureMessage(localization, failure);
    if (failure == SignatureFailure.cancelled) {
      showSignatureToast(message, Colors.orange);
      return;
    }
    if (kSignatureRetryable.contains(failure)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: localization.translate('retry'),
          onPressed: _review,
        ),
      ));
      return;
    }
    showSignatureToast(message, Colors.red);
  }

  // ------------------------------------------------------------------ UI

  Widget _toolButton(
      String key, IconData icon, String label, VoidCallback? onTap,
      {Color? color}) {
    return Tooltip(
      message: label,
      child: IconButton(
        key: ValueKey<String>(key),
        icon: Icon(icon, color: onTap == null ? Colors.grey : color),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildPageNavigator() {
    final localization = _localization;
    final page = _vm.currentPage;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            key: const ValueKey<String>('page-prev'),
            tooltip: localization.translate('sigPrevPage'),
            icon: const Icon(Icons.chevron_left),
            onPressed: page > 0 ? () => _vm.selectPage(page - 1) : null,
          ),
          InkWell(
            key: const ValueKey<String>('page-indicator'),
            onTap: _goToPage,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${page + 1} / ${_vm.pageCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey<String>('page-next'),
            tooltip: localization.translate('sigNextPage'),
            icon: const Icon(Icons.chevron_right),
            onPressed: page < _vm.pageCount - 1
                ? () => _vm.selectPage(page + 1)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildItemToolbar() {
    final localization = _localization;
    final stamp = _vm.selectedStamp!;
    final asset = _vm.assetById(stamp.assetId);
    final canApply = _vm.pageCount > 1 && (asset?.countsAsSignature ?? false);
    return Container(
      margin: const EdgeInsets.only(top: 6, left: 8, right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _toolButton(
              'tool-smaller',
              Icons.zoom_out,
              localization.translate('sigSmaller'),
              () => _vm.scaleBy(stamp.id, 1 / 1.15)),
          _toolButton(
              'tool-larger',
              Icons.zoom_in,
              localization.translate('sigLarger'),
              () => _vm.scaleBy(stamp.id, 1.15)),
          _toolButton('tool-edit', Icons.edit_outlined,
              localization.translate('sigEditItem'), _editSelected,
              color: Colors.blue),
          if (canApply)
            _toolButton('tool-pages', Icons.library_add_outlined,
                localization.translate('sigApplyToPages'), _applyToPages,
                color: Colors.green),
          _toolButton(
              'tool-delete',
              Icons.delete_outline,
              localization.translate('sigDeleteItem'),
              () => _vm.delete(stamp.id),
              color: Colors.red),
        ],
      ),
    );
  }

  Widget _buildError(SignatureFailure failure) {
    final localization = _localization;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              signatureFailureMessage(localization, failure),
              key: const ValueKey<String>('open-failure'),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(localization.translate('ok')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final failure = _openFailure;
    if (failure != null) return _buildError(failure);
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(left: 8, right: 8, top: 8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SignaturePageCanvas(
                viewModel: _vm,
                pageRenderer: _renderer,
              ),
            ),
          ),
        ),
        if (_vm.pageCount > 1) _buildPageNavigator(),
        if (_vm.selectedStamp != null) _buildItemToolbar(),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget? _buildFab() {
    if (!_ready || _vm.isBusy) return null;
    final localization = _localization;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_vm.hasPlacements) ...[
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              key: const ValueKey<String>('save-button'),
              onPressed: _review,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                elevation: 8,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              icon: const Icon(Icons.save, size: 20),
              label: Text(
                localization.translate('save'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            key: const ValueKey<String>('add-button'),
            onPressed: _addItem,
            style: ElevatedButton.styleFrom(
              backgroundColor: SignatureColors.redLight,
              foregroundColor: Colors.white,
              elevation: 8,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            icon: const Icon(Icons.draw, size: 20),
            label: Text(
              localization.translate('sigAdd'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final localization = _localization;
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _confirmLeave();
          },
          child: Scaffold(
            backgroundColor: Colors.grey[200],
            appBar: AppBar(
              title: Text(
                localization.translate('signDocument'),
                style: const TextStyle(
                  fontSize: 20,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              centerTitle: true,
              backgroundColor: SignatureColors.redLight,
              elevation: 0,
              leading: IconButton(
                key: const ValueKey<String>('editor-back'),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: _confirmLeave,
              ),
              actions: [
                if (_ready) ...[
                  IconButton(
                    key: const ValueKey<String>('undo-button'),
                    tooltip: localization.translate('sigUndo'),
                    icon: const Icon(Icons.undo, color: Colors.white),
                    disabledColor: Colors.white38,
                    onPressed: _vm.canUndo && !_vm.isBusy ? _vm.undo : null,
                  ),
                  IconButton(
                    key: const ValueKey<String>('redo-button'),
                    tooltip: localization.translate('sigRedo'),
                    icon: const Icon(Icons.redo, color: Colors.white),
                    disabledColor: Colors.white38,
                    onPressed: _vm.canRedo && !_vm.isBusy ? _vm.redo : null,
                  ),
                ],
              ],
            ),
            body: _buildBody(),
            floatingActionButton: _buildFab(),
            floatingActionButtonLocation:
                FloatingActionButtonLocation.centerFloat,
          ),
        );
      },
    );
  }
}

/// Asks for the number of the page to go to. Pops with the number typed, or null.
class _GoToPageDialog extends StatefulWidget {
  const _GoToPageDialog({required this.current, required this.pageCount});

  final int current;
  final int pageCount;

  @override
  State<_GoToPageDialog> createState() => _GoToPageDialogState();
}

class _GoToPageDialogState extends State<_GoToPageDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.current}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(localization.translate('sigGoToPage')),
      content: TextField(
        key: const ValueKey<String>('goto-field'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText:
              '${localization.translate('sigPage')} (1-${widget.pageCount})',
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (value) =>
            Navigator.of(context).pop(int.tryParse(value.trim())),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localization.translate('cancel')),
        ),
        TextButton(
          key: const ValueKey<String>('goto-ok'),
          onPressed: () =>
              Navigator.of(context).pop(int.tryParse(_controller.text.trim())),
          child: Text(localization.translate('ok')),
        ),
      ],
    );
  }
}

/// A busy indicator for writing the signed copy. It is not a progress bar: the
/// work has no honest percentage, so it only says it is working, and it can be
/// cancelled.
class _PreparingDialog extends StatelessWidget {
  const _PreparingDialog({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(localization.translate('sigPreparing')),
                const SizedBox(height: 8),
                TextButton(
                  key: const ValueKey<String>('preparing-cancel'),
                  onPressed: onCancel,
                  child: Text(localization.translate('cancel')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets the user choose the other pages an item is put on. Nothing is chosen for
/// the user: every page is an explicit tick.
class _ApplyToPagesDialog extends StatefulWidget {
  const _ApplyToPagesDialog({
    required this.pageCount,
    required this.sourcePage,
    required this.alreadyOn,
  });

  final int pageCount;
  final int sourcePage;

  /// Pages that already carry this image.
  final Set<int> alreadyOn;

  @override
  State<_ApplyToPagesDialog> createState() => _ApplyToPagesDialogState();
}

class _ApplyToPagesDialogState extends State<_ApplyToPagesDialog> {
  final Set<int> _chosen = <int>{};

  List<int> get _choices => <int>[
        for (var i = 0; i < widget.pageCount; i++)
          if (!widget.alreadyOn.contains(i) && i != widget.sourcePage) i
      ];

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final choices = _choices;
    return AlertDialog(
      title: Text(localization.translate('sigApplyTitle')),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                TextButton(
                  key: const ValueKey<String>('apply-all'),
                  onPressed: () => setState(() => _chosen
                    ..clear()
                    ..addAll(choices)),
                  child: Text(localization.translate('sigApplyAll')),
                ),
                TextButton(
                  key: const ValueKey<String>('apply-none'),
                  onPressed: () => setState(_chosen.clear),
                  child: Text(localization.translate('sigApplyNone')),
                ),
              ],
            ),
            Flexible(
              child: choices.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(localization.translate('sigApplyNothing')),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: choices.length,
                      itemBuilder: (context, index) {
                        final page = choices[index];
                        return CheckboxListTile(
                          key: ValueKey<String>('apply-page-$page'),
                          dense: true,
                          value: _chosen.contains(page),
                          title: Text(
                              '${localization.translate('sigPage')} ${page + 1}'),
                          onChanged: (value) => setState(() {
                            if (value == true) {
                              _chosen.add(page);
                            } else {
                              _chosen.remove(page);
                            }
                          }),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localization.translate('cancel')),
        ),
        TextButton(
          key: const ValueKey<String>('apply-ok'),
          onPressed:
              _chosen.isEmpty ? null : () => Navigator.of(context).pop(_chosen),
          child: Text(localization.translate('sigApply')),
        ),
      ],
    );
  }
}
