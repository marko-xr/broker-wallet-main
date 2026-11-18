import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import '../common/localization/localization_delegate.dart';
import '../data/models/ScreensModel/offers_model.dart';
import '../data/models/ScreensModel/request_model.dart';
import '../widgets/compact_offer_card.dart';
import '../widgets/compact_request_card.dart';

/// Related records in Details, with manual paging and optional autoplay.
class AutoScrollingRelatedItemsCarousel extends StatefulWidget {
  const AutoScrollingRelatedItemsCarousel({
    super.key,
    required this.offers,
    required this.requests,
    this.title,
  });

  final List<OfferModel> offers;
  final List<RequestModel> requests;
  final String? title;

  @override
  State<AutoScrollingRelatedItemsCarousel> createState() =>
      _AutoScrollingRelatedItemsCarouselState();
}

class _AutoScrollingRelatedItemsCarouselState
    extends State<AutoScrollingRelatedItemsCarousel>
    with WidgetsBindingObserver {
  final _controller = ScrollController(keepScrollOffset: false);
  final _cardsKey = GlobalKey();
  Timer? _timer;
  bool _playing = false;
  bool _animating = false;
  bool _active = true;
  bool _reducedMotion = false;
  int _index = 0;
  double? _pageWidth;

  int get _total => widget.offers.length + widget.requests.length;

  @override
  void initState() {
    super.initState();
    final binding = WidgetsBinding.instance;
    _active = binding.lifecycleState == null ||
        binding.lifecycleState == AppLifecycleState.resumed;
    binding.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _syncTimer();
  }

  @override
  void didUpdateWidget(AutoScrollingRelatedItemsCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_total != oldWidget.offers.length + oldWidget.requests.length) {
      _index = _total == 0 ? 0 : _index.clamp(0, _total - 1);
      _restorePosition();
      _syncTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _syncTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _restorePosition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients || _pageWidth == null) return;
      _controller.jumpTo(_index * _pageWidth!);
    });
  }

  bool get _visible {
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final cards = _cardsKey.currentContext?.findRenderObject();
    if (cards is! RenderBox || !cards.hasSize) return false;
    final viewport = RenderAbstractViewport.maybeOf(cards.parent);
    if (viewport == null) return true;
    final bounds = MatrixUtils.transformRect(
        cards.getTransformTo(viewport), cards.paintBounds);
    return bounds.overlaps(viewport.paintBounds);
  }

  void _syncTimer() {
    if (!_playing || !_active || _reducedMotion || _total < 2) {
      _timer?.cancel();
      _timer = null;
      if (_animating) {
        // Settings can change during build. Stop the in-flight motion after it.
        scheduleMicrotask(() {
          if (mounted && _animating && _controller.hasClients) {
            _controller.jumpTo(_index * _controller.position.viewportDimension);
          }
        });
      }
      return;
    }
    _timer ??= Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (!mounted || !_controller.hasClients || !_visible) return;
      final position = _controller.position;
      if (position.isScrollingNotifier.value ||
          position.viewportDimension <= 0) {
        return;
      }
      final next = (_index + 1) % _total;
      if (next == 0) {
        _controller.jumpTo(0);
      } else {
        _animating = true;
        unawaited(_controller
            .animateTo(next * position.viewportDimension,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOut)
            .whenComplete(() => _animating = false));
      }
    });
  }

  void _togglePlayback() {
    setState(() => _playing = !_playing);
    _syncTimer();
  }

  bool _updatePage(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.horizontal ||
        notification.metrics.viewportDimension <= 0 ||
        _total < 2) return false;
    final page =
        (notification.metrics.pixels / notification.metrics.viewportDimension)
            .round()
            .clamp(0, _total - 1);
    if (_index != page) setState(() => _index = page);
    return false;
  }

  String _count(AppLocalizations loc, String key, int count) {
    final locale = loc.locale.toString();
    return Intl.plural(
      count,
      locale: locale,
      zero: loc.translate('${key}Zero'),
      one: loc.translate('${key}One'),
      two: loc.translate('${key}Two'),
      few: loc.translate('${key}Few'),
      many: loc.translate('${key}Many'),
      other: loc.translate('${key}Other'),
    ).replaceAll('{count}', NumberFormat.decimalPattern(locale).format(count));
  }

  Widget _card(int index) => index < widget.offers.length
      ? CompactOfferCard(offer: widget.offers[index])
      : CompactRequestCard(
          request: widget.requests[index - widget.offers.length]);

  @override
  Widget build(BuildContext context) {
    if (_total == 0) return const SizedBox.shrink();
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final numbers = NumberFormat.decimalPattern(loc.locale.toString());
    final position = loc
        .translate('relatedItemPosition')
        .replaceAll('{position}', numbers.format(_index + 1))
        .replaceAll('{total}', numbers.format(_total));

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        widget.title ??
                            loc.translate('relatedOffersAndRequests'),
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        Text(
                            _count(
                                loc, 'relatedOfferCount', widget.offers.length),
                            style: theme.textTheme.bodySmall),
                        Text(
                            _count(loc, 'relatedRequestCount',
                                widget.requests.length),
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
              if (_total > 1)
                IconButton(
                  tooltip: loc.translate(_reducedMotion
                      ? 'relatedAutoplayReducedMotion'
                      : _playing
                          ? 'relatedAutoplayPause'
                          : 'relatedAutoplayPlay'),
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(kMinInteractiveDimension),
                  ),
                  onPressed: _reducedMotion ? null : _togglePlayback,
                  icon: Icon(_playing && !_reducedMotion
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline),
                ),
            ],
          ),
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth;
            if (_pageWidth != null && _pageWidth != width) _restorePosition();
            _pageWidth = width;
            Widget page(int index) => SizedBox(
                  width: width,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: _card(index),
                    ),
                  ),
                );
            if (_total == 1) return page(0);

            // Full-width pages snap horizontally. The tallest card sets the
            // natural row height and the outer Details scroll handles height.
            return NotificationListener<ScrollNotification>(
              onNotification: _updatePage,
              child: SingleChildScrollView(
                key: _cardsKey,
                controller: _controller,
                scrollDirection: Axis.horizontal,
                physics: const PageScrollPhysics(),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(_total, page),
                ),
              ),
            );
          }),
          if (_total > 1)
            Text(position,
                textAlign: TextAlign.center, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}
