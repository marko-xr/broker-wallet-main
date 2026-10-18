import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:broker_wallet/src/services/signature/signature_geometry.dart';
import 'package:broker_wallet/src/services/signature/signature_models.dart';
import 'package:broker_wallet/src/services/signature/signature_page_renderer.dart';
import 'package:broker_wallet/src/viewmodels/signature/signature_editor_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/signature_ui_support.dart';

/// A scale recognizer that claims the gesture the moment a finger lands on it, so
/// a drag or a pinch that starts on a placed item belongs to the item and never
/// to the zoom and pan around it.
class _EagerScaleRecognizer extends ScaleGestureRecognizer {
  _EagerScaleRecognizer();

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

typedef _ScaleHandlers = ({
  GestureScaleStartCallback onStart,
  GestureScaleUpdateCallback onUpdate,
  GestureScaleEndCallback onEnd,
});

Widget _eagerGestures({
  required _ScaleHandlers handlers,
  required Widget child,
}) {
  return RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: <Type, GestureRecognizerFactory>{
      _EagerScaleRecognizer:
          GestureRecognizerFactoryWithHandlers<_EagerScaleRecognizer>(
        () => _EagerScaleRecognizer(),
        (recognizer) {
          recognizer
            ..onStart = handlers.onStart
            ..onUpdate = handlers.onUpdate
            ..onEnd = handlers.onEnd;
        },
      ),
    },
    child: child,
  );
}

/// One page of the document with the items placed on it, zoomable and pannable.
///
/// The page is drawn by [SignaturePageRenderer] as a bitmap of exactly the
/// page's visible size, and the items are children of the same box inside the
/// same zoom-and-pan transform. An item's rectangle is stored in the page's own
/// points and drawn at `points x scale`; a finger position is turned back into
/// points through the box's own transform (`globalToLocal`), so the page, the
/// items and the fingers all share one coordinate frame and nothing here depends
/// on the zoom, the scroll position, the screen's orientation or its pixel
/// density.
class SignaturePageCanvas extends StatefulWidget {
  const SignaturePageCanvas({
    super.key,
    required this.viewModel,
    required this.pageRenderer,
  });

  final SignatureEditorViewModel viewModel;
  final SignaturePageRenderer pageRenderer;

  @override
  State<SignaturePageCanvas> createState() => _SignaturePageCanvasState();
}

class _SignaturePageCanvasState extends State<SignaturePageCanvas> {
  static const double _maxZoom = 5;
  static const int _maxBitmapPixels = 4096;

  final TransformationController _transform = TransformationController();
  final GlobalKey _surfaceKey = GlobalKey();

  ui.Image? _image;
  int _imagePage = -1;
  int _imagePixelWidth = 0;
  int _requestId = 0;
  String? _pendingKey;
  // A render the renderer could not make is not asked for again until the size
  // or the page changes, so a drag does not hammer a failing renderer.
  String? _failedKey;
  double _zoom = 1;
  int _shownPage = -1;
  Size _viewport = Size.zero;

  @override
  void dispose() {
    _requestId++;
    _transform.dispose();
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  void _scheduleRender(int page, PageViewport viewport) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final wanted = math.min(_maxBitmapPixels,
        math.max(64, (viewport.displayWidth * dpr * _zoom).ceil()));
    if (_imagePage == page && _imagePixelWidth >= wanted * 0.85) return;
    final key = '$page:$wanted';
    if (_pendingKey == key || _failedKey == key) return;
    _pendingKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _render(page, wanted, key);
    });
  }

  Future<void> _render(int page, int wanted, String key) async {
    final id = ++_requestId;
    final image = await widget.pageRenderer.render(page, pixelWidth: wanted);
    if (!mounted || id != _requestId) {
      image?.dispose();
      return;
    }
    if (_pendingKey == key) _pendingKey = null;
    if (image == null) {
      _failedKey = key;
      return;
    }
    final old = _image;
    setState(() {
      _image = image;
      _imagePage = page;
      _imagePixelWidth = wanted;
    });
    if (old != null) {
      // Dispose after the frame that stops drawing it.
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  void _zoomTo(double zoom) {
    final z = zoom.clamp(1.0, _maxZoom).toDouble();
    final cx = _viewport.width / 2;
    final cy = _viewport.height / 2;
    _transform.value = Matrix4(
        z, 0, 0, 0, 0, z, 0, 0, 0, 0, 1, 0, cx * (1 - z), cy * (1 - z), 0, 1);
    setState(() => _zoom = z);
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    final z = _transform.value.getMaxScaleOnAxis();
    if ((z - _zoom).abs() > 0.05) setState(() => _zoom = z);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final page = vm.currentPage;
        final geometry = vm.pages[page];
        if (_shownPage != page) {
          final first = _shownPage == -1;
          _shownPage = page;
          if (!first) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _transform.value = Matrix4.identity();
              setState(() => _zoom = 1);
            });
          }
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            _viewport = constraints.biggest;
            final viewport = PageViewport.fit(
              pageWidth: geometry.width,
              pageHeight: geometry.height,
              maxWidth: math.max(1, constraints.maxWidth - 16),
              maxHeight: math.max(1, constraints.maxHeight - 16),
            );
            _scheduleRender(page, viewport);
            return Stack(
              children: [
                InteractiveViewer(
                  key: const ValueKey<String>('page-viewer'),
                  transformationController: _transform,
                  minScale: 1,
                  maxScale: _maxZoom,
                  onInteractionEnd: _onInteractionEnd,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: Center(
                      child: SizedBox(
                        width: viewport.displayWidth,
                        height: viewport.displayHeight,
                        child: _buildSurface(vm, page, viewport),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: _buildZoomButtons(),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildZoomButtons() {
    Widget button(String key, IconData icon, VoidCallback onTap) {
      return SizedBox(
        width: 36,
        height: 36,
        child: IconButton(
          key: ValueKey<String>(key),
          padding: EdgeInsets.zero,
          iconSize: 20,
          icon: Icon(icon),
          onPressed: onTap,
        ),
      );
    }

    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      elevation: 2,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          button('zoom-in', Icons.add, () => _zoomTo(_zoom * 1.5)),
          button('zoom-out', Icons.remove, () => _zoomTo(_zoom / 1.5)),
          button('zoom-reset', Icons.fit_screen, () => _zoomTo(1)),
        ],
      ),
    );
  }

  Widget _buildSurface(
      SignatureEditorViewModel vm, int page, PageViewport viewport) {
    final image = _imagePage == page ? _image : null;
    final stamps = vm.stampsOnPage(page);
    final selected = vm.selectedStamp;
    return Stack(
      key: _surfaceKey,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: DecoratedBox(
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
                    key: const ValueKey<String>('page-bitmap'),
                    image: image,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey<String>('page-background'),
            behavior: HitTestBehavior.translucent,
            onTap: () => vm.select(null),
          ),
        ),
        for (final stamp in stamps)
          if (vm.assetById(stamp.assetId) != null)
            _StampOverlay(
              key: ValueKey<String>('stamp-${stamp.id}'),
              stamp: stamp,
              asset: vm.assetById(stamp.assetId)!,
              viewport: viewport,
              selected: stamp.id == vm.selectedId,
              surfaceKey: _surfaceKey,
              viewModel: vm,
            ),
        if (selected != null && selected.pageIndex == page)
          for (final corner in StampCorner.values)
            _CornerHandle(
              key: ValueKey<String>('handle-${corner.name}'),
              corner: corner,
              stamp: selected,
              viewport: viewport,
              surfaceKey: _surfaceKey,
              viewModel: vm,
            ),
      ],
    );
  }
}

PagePoint _pagePoint(
    GlobalKey surfaceKey, PageViewport viewport, Offset global) {
  final box = surfaceKey.currentContext?.findRenderObject() as RenderBox?;
  final local = box == null ? global : box.globalToLocal(global);
  return viewport.toPage(local.dx, local.dy);
}

/// One placed item: its image, and the gestures that move and resize it.
class _StampOverlay extends StatefulWidget {
  const _StampOverlay({
    super.key,
    required this.stamp,
    required this.asset,
    required this.viewport,
    required this.selected,
    required this.surfaceKey,
    required this.viewModel,
  });

  final PlacedStamp stamp;
  final StampAsset asset;
  final PageViewport viewport;
  final bool selected;
  final GlobalKey surfaceKey;
  final SignatureEditorViewModel viewModel;

  @override
  State<_StampOverlay> createState() => _StampOverlayState();
}

class _StampOverlayState extends State<_StampOverlay> {
  PageRect _startRect = const PageRect(0, 0, 1, 1);
  PageRect _baseRect = const PageRect(0, 0, 1, 1);
  PagePoint _startPointer = const PagePoint(0, 0);
  double _scaleBase = 1;
  int _lastCount = 0;

  PageRect get _rect =>
      widget.viewModel.stampById(widget.stamp.id)?.rect ?? widget.stamp.rect;

  void _onStart(ScaleStartDetails details) {
    final vm = widget.viewModel;
    vm.select(widget.stamp.id);
    vm.beginEdit();
    _startRect = _rect;
    _baseRect = _rect;
    _startPointer =
        _pagePoint(widget.surfaceKey, widget.viewport, details.focalPoint);
    _scaleBase = 1;
    _lastCount = details.pointerCount;
  }

  void _onUpdate(ScaleUpdateDetails details) {
    final vm = widget.viewModel;
    final geometry = vm.pages[widget.stamp.pageIndex];
    if (details.pointerCount != _lastCount) {
      // A finger came or went: carry on from where the item is now.
      _lastCount = details.pointerCount;
      _startRect = _rect;
      _baseRect = _rect;
      _scaleBase = details.scale;
      _startPointer =
          _pagePoint(widget.surfaceKey, widget.viewport, details.focalPoint);
      return;
    }
    if (details.pointerCount >= 2) {
      final factor = details.scale / _scaleBase;
      vm.updateRect(
        widget.stamp.id,
        StampLayout.scaleAroundCenter(
            _baseRect, factor, geometry.width, geometry.height),
      );
      return;
    }
    final pointer =
        _pagePoint(widget.surfaceKey, widget.viewport, details.focalPoint);
    vm.updateRect(
      widget.stamp.id,
      StampLayout.move(_startRect, pointer.x - _startPointer.x,
          pointer.y - _startPointer.y, geometry.width, geometry.height),
    );
  }

  void _onEnd(ScaleEndDetails details) => widget.viewModel.endEdit();

  @override
  Widget build(BuildContext context) {
    final display = widget.viewport.rectToDisplay(widget.stamp.rect);
    // A small item (a date) still gets a finger-sized place to grab.
    final hitWidth = math.max(display.width, 44.0);
    final hitHeight = math.max(display.height, 44.0);
    return Positioned(
      left: display.centerX - hitWidth / 2,
      top: display.centerY - hitHeight / 2,
      width: hitWidth,
      height: hitHeight,
      child: _eagerGestures(
        handlers: (onStart: _onStart, onUpdate: _onUpdate, onEnd: _onEnd),
        child: Center(
          child: SizedBox(
            width: display.width,
            height: display.height,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: widget.selected
                    ? Border.all(color: SignatureColors.redLight, width: 1.5)
                    : null,
              ),
              child: Image.memory(
                widget.asset.png,
                fit: BoxFit.fill,
                gaplessPlayback: true,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A round handle on a corner of the selected item: dragging it resizes the item
/// about the opposite corner, keeping its proportions.
class _CornerHandle extends StatefulWidget {
  const _CornerHandle({
    super.key,
    required this.corner,
    required this.stamp,
    required this.viewport,
    required this.surfaceKey,
    required this.viewModel,
  });

  final StampCorner corner;
  final PlacedStamp stamp;
  final PageViewport viewport;
  final GlobalKey surfaceKey;
  final SignatureEditorViewModel viewModel;

  @override
  State<_CornerHandle> createState() => _CornerHandleState();
}

class _CornerHandleState extends State<_CornerHandle> {
  PageRect _base = const PageRect(0, 0, 1, 1);
  PagePoint _grab = const PagePoint(0, 0);

  PagePoint _cornerOf(PageRect rect) {
    switch (widget.corner) {
      case StampCorner.topLeft:
        return PagePoint(rect.left, rect.top);
      case StampCorner.topRight:
        return PagePoint(rect.right, rect.top);
      case StampCorner.bottomLeft:
        return PagePoint(rect.left, rect.bottom);
      case StampCorner.bottomRight:
        return PagePoint(rect.right, rect.bottom);
    }
  }

  void _onStart(ScaleStartDetails details) {
    final vm = widget.viewModel;
    vm.beginEdit();
    _base = vm.stampById(widget.stamp.id)?.rect ?? widget.stamp.rect;
    final pointer =
        _pagePoint(widget.surfaceKey, widget.viewport, details.focalPoint);
    final corner = _cornerOf(_base);
    _grab = PagePoint(corner.x - pointer.x, corner.y - pointer.y);
  }

  void _onUpdate(ScaleUpdateDetails details) {
    final vm = widget.viewModel;
    final geometry = vm.pages[widget.stamp.pageIndex];
    final pointer =
        _pagePoint(widget.surfaceKey, widget.viewport, details.focalPoint);
    vm.updateRect(
      widget.stamp.id,
      StampLayout.resizeFromCorner(
        rect: _base,
        corner: widget.corner,
        pointer: PagePoint(pointer.x + _grab.x, pointer.y + _grab.y),
        pageW: geometry.width,
        pageH: geometry.height,
      ),
    );
  }

  void _onEnd(ScaleEndDetails details) => widget.viewModel.endEdit();

  /// How far outside its corner a handle sits, and its touch size. Outside, so
  /// that the handles of a small item (a date, typed initials) never cover the
  /// item itself: its middle stays free for moving it.
  static const double _outside = 16;
  static const double _hit = 36;

  @override
  Widget build(BuildContext context) {
    final rect = widget.viewport.rectToDisplay(
        widget.viewModel.stampById(widget.stamp.id)?.rect ?? widget.stamp.rect);
    final corner = _cornerOf(rect);
    final onLeft = widget.corner == StampCorner.topLeft ||
        widget.corner == StampCorner.bottomLeft;
    final onTop = widget.corner == StampCorner.topLeft ||
        widget.corner == StampCorner.topRight;
    // A handle that falls outside the page is out of reach; the item's opposite
    // corners still are, and clamping it onto the page would put it over the
    // item and take away the grip for moving it.
    final centerX = corner.x + (onLeft ? -_outside : _outside);
    final centerY = corner.y + (onTop ? -_outside : _outside);
    const hit = _hit;
    return Positioned(
      left: centerX - hit / 2,
      top: centerY - hit / 2,
      width: hit,
      height: hit,
      child: _eagerGestures(
        handlers: (onStart: _onStart, onUpdate: _onUpdate, onEnd: _onEnd),
        child: Center(
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: SignatureColors.redLight, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}
