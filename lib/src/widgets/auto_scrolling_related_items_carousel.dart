// auto_scrolling_related_items_carousel.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../common/localization/localization_delegate.dart';
import '../data/models/ScreensModel/offers_model.dart';
import '../data/models/ScreensModel/request_model.dart';
import '../widgets/compact_offer_card.dart';
import '../widgets/compact_request_card.dart';

/// 📱 Page-based auto-scrolling carousel for related offers and requests
/// - Uses a PageView for deterministic snapping and RTL support
/// - Ensures first item is fully visible (no left/right cut)
/// - Special handling when there's only one item to ensure symmetric left/right spacing
class AutoScrollingRelatedItemsCarousel extends StatefulWidget {
  final List<OfferModel> offers;
  final List<RequestModel> requests;
  final String? title;

  const AutoScrollingRelatedItemsCarousel({
    super.key,
    required this.offers,
    required this.requests,
    this.title,
  });

  @override
  State<AutoScrollingRelatedItemsCarousel> createState() =>
      _AutoScrollingRelatedItemsCarouselState();
}

class _AutoScrollingRelatedItemsCarouselState
    extends State<AutoScrollingRelatedItemsCarousel> {
  Timer? _autoScrollTimer;
  int _currentIndex = 0;
  bool _isUserScrolling = false;
  bool _isRTL = false;
  bool _isAutoScrolling = false;

  // Card dimensions: visual content (360) + spacing (12) = 372
  static const double _cardVisualWidth = 360.0;
  static const double _cardSpacing = 12.0;
  static const double _cardWidth = _cardVisualWidth + _cardSpacing;

  PageController? _pageController;
  double _viewportFraction = 1.0;
  double _singleItemSidePadding = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAutoScroll();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isRTL = Directionality.of(context) == TextDirection.rtl;

    final screenWidth = MediaQuery.of(context).size.width;

    // Calculate viewport fraction for PageView so a full card + spacing fits exactly.
    // If cardWidth is slightly bigger than screen, fraction will be 1.0 (clamped).
    _viewportFraction = (_cardWidth / screenWidth).clamp(0.05, 1.0);

    // For the single-item case, compute exact symmetric side padding so left == right.
    // If the cardVisualWidth is wider than the screen, side padding is 0.
    _singleItemSidePadding =
        ((screenWidth - _cardVisualWidth) / 2.0).clamp(0.0, double.infinity);

    // (Re)create PageController preserving current page if possible
    final currentPage = _pageController?.hasClients == true
        ? (_pageController!.page?.round() ?? 0)
        : 0;
    _pageController?.dispose();
    _pageController = PageController(
      initialPage: currentPage,
      viewportFraction: _viewportFraction,
    );
  }

  @override
  void didUpdateWidget(AutoScrollingRelatedItemsCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldCount = oldWidget.offers.length + oldWidget.requests.length;
    final newCount = widget.offers.length + widget.requests.length;
    if (oldCount != newCount) {
      _currentIndex = 0;
      try {
        _pageController?.jumpToPage(0);
      } catch (_) {}
      _stopAutoScroll();
      _startAutoScroll();
    }
  }

  @override
  void dispose() {
    _stopAutoScroll();
    _pageController?.dispose();
    super.dispose();
  }

  void _startAutoScroll() {
    _stopAutoScroll();
    final totalItems = widget.offers.length + widget.requests.length;
    if (totalItems < 2) return;

    _autoScrollTimer =
        Timer.periodic(const Duration(milliseconds: 2500), (timer) async {
      if (!mounted || _isUserScrolling) return;
      if (_pageController == null || !_pageController!.hasClients) return;

      _isAutoScrolling = true;

      try {
        final nextIndex = _isRTL ? _currentIndex - 1 : _currentIndex + 1;
        int targetIndex;
        if (_isRTL) {
          targetIndex = (nextIndex < 0) ? (totalItems - 1) : nextIndex;
        } else {
          targetIndex = (nextIndex >= totalItems) ? 0 : nextIndex;
        }

        await _pageController!.animateToPage(
          targetIndex,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );

        setState(() {
          _currentIndex = targetIndex;
        });
      } catch (e) {
        // ignore errors from animation when disposed/unavailable
      } finally {
        _isAutoScrolling = false;
      }
    });
  }

  void _stopAutoScroll() {
    if (_autoScrollTimer != null) {
      _autoScrollTimer?.cancel();
      _autoScrollTimer = null;
    }
  }

  void _onUserDragStart() {
    if (!_isUserScrolling) {
      setState(() => _isUserScrolling = true);
      _stopAutoScroll();
    }
  }

  void _onUserDragEnd() {
    if (_isUserScrolling) {
      setState(() => _isUserScrolling = false);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && !_isUserScrolling) _startAutoScroll();
      });
    }
  }

  Widget _buildSingleItem(BuildContext context, Widget child) {
    // Center the single card with exact symmetric horizontal padding
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _singleItemSidePadding),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context);

    final totalItems = widget.offers.length + widget.requests.length;

    if (totalItems == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 100),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.surface,
            colors.surface.withValues(alpha: 0.3),
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title ??
                            loc.translate('relatedOffersAndRequests'),
                        style: texts.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.offers.length} ${loc.translate('offers')}, ${widget.requests.length} ${loc.translate('requests')}',
                        style: texts.bodySmall?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                if (totalItems >= 2)
                  Container(
                    width: 110,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    decoration: BoxDecoration(
                      color: colors.secondary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colors.secondary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isUserScrolling
                              ? Icons.pause_circle_outline
                              : Icons.play_circle_outline,
                          size: 14,
                          color: colors.secondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isUserScrolling
                              ? loc.translate('paused')
                              : loc.translate('autoScroll'),
                          style: texts.labelSmall?.copyWith(
                            color: colors.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Carousel area
          SizedBox(
            height: 140,
            child: GestureDetector(
              onPanDown: (_) => _onUserDragStart(),
              onPanEnd: (_) => _onUserDragEnd(),
              child: Builder(builder: (context) {
                // Single item: show centered card with symmetric padding (no inter-card spacing)
                if (totalItems == 1) {
                  final bool isOffer = widget.offers.isNotEmpty;
                  final Widget card = SizedBox(
                    width: _cardVisualWidth,
                    child: isOffer
                        ? CompactOfferCard(
                            offer: widget.offers[0],
                            showShadow: true,
                          )
                        : CompactRequestCard(
                            request: widget.requests[0],
                            showShadow: true,
                          ),
                  );
                  return _buildSingleItem(context, card);
                }

                // Multiple items: PageView with viewportFraction and symmetric horizontal padding
                // Use symmetric horizontal padding on each item so gaps at start/end are balanced.
                return PageView.builder(
                  reverse: _isRTL,
                  controller: _pageController,
                  itemCount: totalItems,
                  onPageChanged: (page) {
                    setState(() => _currentIndex = page);
                  },
                  physics: totalItems > 1
                      ? const BouncingScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  itemBuilder: (context, index) {
                    if (index < widget.offers.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: _cardSpacing / 2),
                        child: SizedBox(
                          width: _cardVisualWidth,
                          child: CompactOfferCard(
                            offer: widget.offers[index],
                            showShadow: true,
                          ),
                        ),
                      );
                    } else {
                      final requestIndex = index - widget.offers.length;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: _cardSpacing / 2),
                        child: SizedBox(
                          width: _cardVisualWidth,
                          child: CompactRequestCard(
                            request: widget.requests[requestIndex],
                            showShadow: true,
                          ),
                        ),
                      );
                    }
                  },
                );
              }),
            ),
          ),

          // Page Indicator (only for >1)
          if (totalItems > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  totalItems > 5 ? 5 : totalItems,
                  (i) {
                    final isActive = i == (_currentIndex % 5);
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isActive ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isActive
                            ? colors.primary
                            : colors.onSurface.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
