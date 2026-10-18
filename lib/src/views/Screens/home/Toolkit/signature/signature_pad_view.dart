import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/services/signature/signature_models.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/signature_ui_support.dart';

/// A signature capture pad: draw with a finger or stylus, pick a pen colour and
/// thickness, undo, redo and clear, and confirm.
///
/// The pad pops with a [SignatureDrawing] (the strokes, the pen and the pad's
/// size), never with an image: the editor turns the drawing into a transparent
/// image at several times the pad's resolution, and keeps the strokes so that
/// editing a signature opens the pad with the signature restored, in its colour.
///
/// The `signature` package draws and captures the strokes. Its controller cannot
/// change colour or thickness once made, so choosing another pen replaces it
/// with a new one that carries the same points; undo and redo are kept here
/// (snapshots of the points after each stroke) so they survive that.
class SignaturePadView extends StatefulWidget {
  const SignaturePadView({
    super.key,
    this.initialDrawing,
    this.isInitials = false,
  });

  /// A drawing to start from (editing a signature), or null for a blank pad.
  final SignatureDrawing? initialDrawing;

  /// The pad is for initials: the title and the hint say so.
  final bool isInitials;

  @override
  State<SignaturePadView> createState() => _SignaturePadViewState();
}

class _SignaturePadViewState extends State<SignaturePadView> {
  static const List<double> _widths = <double>[2.0, 3.5, 5.5];
  static const int _maxHistory = 100;

  late SignatureController _controller;
  late Color _color;
  late double _width;

  final List<List<Point>> _undo = <List<Point>>[];
  final List<List<Point>> _redo = <List<Point>>[];
  List<Point> _before = <Point>[];

  Size _canvasSize = Size.zero;
  bool _restored = false;
  bool _hasInk = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDrawing;
    _color =
        initial == null ? kSignaturePenColors.first : Color(initial.colorValue);
    _width = initial?.strokeWidth ?? _widths[1];
    _controller = _makeController(const <Point>[]);
  }

  SignatureController _makeController(List<Point> points) {
    final controller = SignatureController(
      points: List<Point>.of(points),
      penColor: _color,
      penStrokeWidth: _width,
      strokeCap: StrokeCap.round,
      strokeJoin: StrokeJoin.round,
      exportBackgroundColor: Colors.transparent,
      onDrawEnd: _onStrokeEnd,
    );
    controller.addListener(_onChanged);
    return controller;
  }

  void _onChanged() {
    final has = _controller.isNotEmpty;
    if (has != _hasInk && mounted) {
      setState(() => _hasInk = has);
    }
  }

  void _onStrokeEnd() {
    _undo.add(_before);
    if (_undo.length > _maxHistory) _undo.removeAt(0);
    _redo.clear();
    _before = List<Point>.of(_controller.points);
    if (mounted) setState(() {});
  }

  void _applyPoints(List<Point> points) {
    _controller.points = List<Point>.of(points);
    _before = List<Point>.of(points);
  }

  void _undoStroke() {
    if (_undo.isEmpty) return;
    _redo.add(List<Point>.of(_controller.points));
    _applyPoints(_undo.removeLast());
    setState(() {});
  }

  void _redoStroke() {
    if (_redo.isEmpty) return;
    _undo.add(List<Point>.of(_controller.points));
    _applyPoints(_redo.removeLast());
    setState(() {});
  }

  void _clear() {
    if (_controller.isEmpty) return;
    // Clearing is one undo step, so an accidental clear can be taken back.
    _undo.add(List<Point>.of(_controller.points));
    _redo.clear();
    _applyPoints(const <Point>[]);
    setState(() {});
  }

  /// A new pen replaces the controller, carrying the same points.
  void _changePen({Color? color, double? width}) {
    final points = List<Point>.of(_controller.points);
    final old = _controller;
    old.removeListener(_onChanged);
    setState(() {
      if (color != null) _color = color;
      if (width != null) _width = width;
      _controller = _makeController(points);
    });
    // The old controller may still be listened to for this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  /// Puts a drawing from an earlier edit on the pad once the pad's size is
  /// known, scaled to fit and centred if the pad is not the size it was drawn on.
  void _restore(SignatureDrawing drawing) {
    if (_restored || _canvasSize.isEmpty) return;
    _restored = true;
    final scale = drawing.canvasWidth <= 0 || drawing.canvasHeight <= 0
        ? 1.0
        : _min(_canvasSize.width / drawing.canvasWidth,
            _canvasSize.height / drawing.canvasHeight);
    final offsetX = (_canvasSize.width - drawing.canvasWidth * scale) / 2;
    final offsetY = (_canvasSize.height - drawing.canvasHeight * scale) / 2;
    final points = <Point>[
      for (final p in drawing.points)
        Point(
          Offset(p.x * scale + offsetX, p.y * scale + offsetY),
          p.isStrokeStart ? PointType.tap : PointType.move,
          1.0,
        ),
    ];
    _applyPoints(points);
    setState(() {});
  }

  double _min(double a, double b) => a < b ? a : b;

  SignatureDrawing _currentDrawing() {
    return SignatureDrawing(
      points: <InkPoint>[
        for (final p in _controller.points)
          InkPoint(p.offset.dx, p.offset.dy,
              isStrokeStart: p.type == PointType.tap),
      ],
      colorValue: _color.toARGB32(),
      strokeWidth: _width,
      canvasWidth: _canvasSize.width,
      canvasHeight: _canvasSize.height,
    );
  }

  void _confirm() {
    final drawing = _currentDrawing();
    if (!drawing.hasMeaningfulInk) {
      showSignatureToast(
        AppLocalizations.of(context).translate('sigPadTooSmall'),
        Colors.orange,
      );
      return;
    }
    Navigator.of(context).pop(drawing);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  Widget _buildColorRow(AppLocalizations localization, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      color: Colors.white,
      // A line that is too long for a narrow screen, a large text size or a long
      // translation goes on to the next line instead of running off the edge.
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 4,
        children: [
          Text(
            '${localization.translate('color')}: ',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          for (final color in kSignaturePenColors)
            Builder(builder: (context) {
              final isSelected = color.toARGB32() == _color.toARGB32();
              return GestureDetector(
                key: ValueKey<String>('pen-color-${color.toARGB32()}'),
                onTap: () => _changePen(color: color),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.grey[800]! : Colors.grey[300]!,
                      width: isSelected ? 3 : 1,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 22)
                      : null,
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildWidthRow(AppLocalizations localization, ThemeData theme) {
    final labels = <String>[
      localization.translate('sigThin'),
      localization.translate('sigMedium'),
      localization.translate('sigBold'),
    ];
    return Container(
      padding: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      // A line that is too long for a narrow screen, a large text size or a long
      // translation goes on to the next line instead of running off the edge.
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 4,
        children: [
          Text(
            '${localization.translate('sigThickness')}: ',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          for (var i = 0; i < _widths.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                key: ValueKey<String>('pen-width-$i'),
                label: Text(labels[i]),
                selected: _widths[i] == _width,
                selectedColor: SignatureColors.redLight.withValues(alpha: 0.18),
                onSelected: (_) => _changePen(width: _widths[i]),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          localization.translate(
              widget.isInitials ? 'sigDrawInitials' : 'drawSignature'),
          style: AppTextStyles.appBarTitle.copyWith(
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: SignatureColors.redLight,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          tooltip: localization.translate('cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            color: Colors.white,
            child: Text(
              localization.translate(widget.isInitials
                  ? 'sigInitialsInstructions'
                  : 'signatureInstructions'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          _buildColorRow(localization, theme),
          _buildWidthRow(localization, theme),
          const Divider(height: 1),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _canvasSize = constraints.biggest;
                    final initial = widget.initialDrawing;
                    if (initial != null && !_restored) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _restore(initial);
                      });
                    }
                    return Signature(
                      key: const ValueKey<String>('signature-pad'),
                      controller: _controller,
                      backgroundColor: Colors.white,
                      placeholder: Center(
                        child: Text(
                          localization.translate('sigSignHere'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.grey[400],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey<String>('pad-undo'),
                  tooltip: localization.translate('sigUndo'),
                  icon: const Icon(Icons.undo),
                  onPressed: _undo.isNotEmpty ? _undoStroke : null,
                ),
                IconButton(
                  key: const ValueKey<String>('pad-redo'),
                  tooltip: localization.translate('sigRedo'),
                  icon: const Icon(Icons.redo),
                  onPressed: _redo.isNotEmpty ? _redoStroke : null,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey<String>('pad-clear'),
                    onPressed: _hasInk ? _clear : null,
                    icon: const Icon(Icons.clear),
                    label: Text(localization.translate('clear')),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(
                        color: _hasInk ? Colors.red[400]! : Colors.grey[300]!,
                      ),
                      foregroundColor: Colors.red[400],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    key: const ValueKey<String>('pad-confirm'),
                    onPressed: _hasInk ? _confirm : null,
                    icon: const Icon(Icons.check),
                    label: Text(localization.translate('confirm')),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: SignatureColors.redLight,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      disabledForegroundColor: Colors.grey[500],
                      elevation: _hasInk ? 4 : 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
