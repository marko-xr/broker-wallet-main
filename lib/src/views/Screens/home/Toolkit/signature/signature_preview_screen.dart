import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/signature/signature_models.dart';
import 'package:broker_wallet/src/services/signature/signature_page_renderer.dart';
import 'package:broker_wallet/src/services/signature/signature_usage_gate.dart';
import 'package:broker_wallet/src/services/signature/signature_wiring.dart';
import 'package:broker_wallet/src/viewmodels/signature/signature_editor_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/signature_ui_support.dart';

/// The last step before a signed document is kept: the signed copy itself, drawn
/// page by page by the same renderer that draws every PDF, with a name field and
/// Save.
///
/// What is shown is the file that Save stores (the editor wrote it to the
/// account's private work folder; Save copies those very bytes and checks the
/// copy against them), so the preview and the saved document cannot differ. Going
/// back keeps the editor as it was. Nothing is stored or counted until Save.
///
/// The screen says plainly what the marks are: visible, not a certificate based
/// digital signature, and not proof of who signed.
class SignaturePreviewScreen extends StatefulWidget {
  const SignaturePreviewScreen({
    super.key,
    required this.viewModel,
    required this.rendererFactory,
    this.usageGate,
  });

  final SignatureEditorViewModel viewModel;

  /// Makes a page renderer for the signed copy.
  final SignaturePageRenderer Function() rendererFactory;

  /// The plan-limit check. The app uses [SignatureWiring.usageGate].
  final SignatureUsageGate? usageGate;

  @override
  State<SignaturePreviewScreen> createState() => _SignaturePreviewScreenState();
}

class _SignaturePreviewScreenState extends State<SignaturePreviewScreen> {
  late final SignaturePageRenderer _renderer;
  final TextEditingController _name = TextEditingController();
  bool _nameSet = false;
  bool _ready = false;
  SignatureFailure? _openFailure;
  List<RenderedPageSize> _sizes = const <RenderedPageSize>[];

  SignatureEditorViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _renderer = widget.rendererFactory();
    _openDraft();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_nameSet) {
      _nameSet = true;
      _name.text = _vm.suggestedName(
          AppLocalizations.of(context).translate('sigSignedSuffix'));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _renderer.dispose();
    super.dispose();
  }

  Future<void> _openDraft() async {
    final draft = _vm.draft;
    if (draft == null) {
      // Called from initState: the first build has not happened yet.
      _openFailure = SignatureFailure.noPlacements;
      return;
    }
    try {
      final sizes = await _renderer.open(draft.file.path);
      if (!mounted) return;
      setState(() {
        _sizes = sizes;
        _ready = true;
      });
    } on SignatureException catch (error) {
      if (mounted) setState(() => _openFailure = error.kind);
    } catch (_) {
      if (mounted) {
        setState(() => _openFailure = SignatureFailure.outputInvalid);
      }
    }
  }

  Future<void> _save() async {
    if (_vm.isSaving) return;
    final localization = AppLocalizations.of(context);
    final outcome = await _vm.save(
      name: _name.text,
      allowNew: (uid) => (widget.usageGate ?? SignatureWiring.usageGate)
          .allowNewSignedDocument(context, uid),
    );
    if (!mounted) return;
    if (outcome.isDone) {
      showSignatureToast(
          localization.translate('documentSavedSuccessfully'), Colors.green);
      Navigator.of(context).pop(outcome.document);
      return;
    }
    final failure = outcome.failure!;
    // The plan-limit dialog has already told the user why.
    if (failure == SignatureFailure.quotaBlocked) return;
    final message = signatureFailureMessage(localization, failure);
    if (kSignatureRetryable.contains(failure)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: localization.translate('retry'),
          onPressed: _save,
        ),
      ));
      return;
    }
    showSignatureToast(message, Colors.red);
    if (failure == SignatureFailure.accountChanged && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _openZoom(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ZoomPageScreen(
          renderer: _renderer,
          pageIndex: index,
          size: _sizes[index],
        ),
      ),
    );
  }

  Widget _buildNote(AppLocalizations localization) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              localization.translate('sigVisibleNote'),
              key: const ValueKey<String>('visible-note'),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPages() {
    final failure = _openFailure;
    final localization = AppLocalizations.of(context);
    if (failure != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            signatureFailureMessage(localization, failure),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: _sizes.length,
      itemBuilder: (context, index) {
        final size = _sizes[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            key: ValueKey<String>('preview-page-$index'),
            onTap: () => _openZoom(index),
            child: AspectRatio(
              aspectRatio: size.width / size.height,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final dpr = MediaQuery.devicePixelRatioOf(context);
                  return _PageBitmap(
                    renderer: _renderer,
                    pageIndex: index,
                    pixelWidth: math.min(4096,
                        math.max(64, (constraints.maxWidth * dpr).ceil())),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final saving = _vm.isSaving;
        return PopScope(
          canPop: !saving,
          child: Scaffold(
            backgroundColor: Colors.grey[200],
            appBar: AppBar(
              title: Text(
                localization.translate('sigPreviewTitle'),
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
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: saving ? null : () => Navigator.of(context).pop(),
              ),
            ),
            body: Column(
              children: [
                _buildNote(localization),
                Expanded(child: _buildPages()),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 6,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          key: const ValueKey<String>('preview-name'),
                          controller: _name,
                          enabled: !saving,
                          maxLength: 80,
                          decoration: InputDecoration(
                            labelText: localization.translate('documentName'),
                            border: const OutlineInputBorder(),
                            counterText: '',
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                key: const ValueKey<String>('preview-back'),
                                onPressed: saving
                                    ? null
                                    : () => Navigator.of(context).pop(),
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                    localization.translate('sigBackToEdit')),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                key: const ValueKey<String>('preview-save'),
                                onPressed: saving || !_ready ? null : _save,
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
                                label: Text(localization.translate('save')),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One page of the signed copy, drawn at [pixelWidth] pixels wide.
class _PageBitmap extends StatefulWidget {
  const _PageBitmap({
    required this.renderer,
    required this.pageIndex,
    required this.pixelWidth,
  });

  final SignaturePageRenderer renderer;
  final int pageIndex;
  final int pixelWidth;

  @override
  State<_PageBitmap> createState() => _PageBitmapState();
}

class _PageBitmapState extends State<_PageBitmap> {
  ui.Image? _image;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_PageBitmap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.pixelWidth != widget.pixelWidth ||
        oldWidget.renderer != widget.renderer) {
      _load();
    }
  }

  Future<void> _load() async {
    final id = ++_request;
    final image = await widget.renderer
        .render(widget.pageIndex, pixelWidth: widget.pixelWidth);
    if (!mounted || id != _request) {
      image?.dispose();
      return;
    }
    final old = _image;
    setState(() => _image = image);
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  @override
  void dispose() {
    _request++;
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: image == null
          ? Center(
              child: Icon(Icons.description_outlined,
                  color: Colors.grey[300], size: 48),
            )
          : RawImage(
              image: image,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
            ),
    );
  }
}

/// One page of the signed copy at full screen, with pinch zoom.
class _ZoomPageScreen extends StatelessWidget {
  const _ZoomPageScreen({
    required this.renderer,
    required this.pageIndex,
    required this.size,
  });

  final SignaturePageRenderer renderer;
  final int pageIndex;
  final RenderedPageSize size;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${AppLocalizations.of(context).translate('sigPage')} '
            '${pageIndex + 1}'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final fitted = math.min(constraints.maxWidth,
              constraints.maxHeight * size.width / size.height);
          return InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: SizedBox(
                width: fitted,
                height: fitted * size.height / size.width,
                child: _PageBitmap(
                  renderer: renderer,
                  pageIndex: pageIndex,
                  pixelWidth:
                      math.min(4096, math.max(64, (fitted * dpr * 3).ceil())),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
