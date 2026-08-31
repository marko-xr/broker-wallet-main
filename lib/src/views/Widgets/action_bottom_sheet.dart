import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

// Add this model class definition
class BActionBottomSheetGridItemModel {
  final String asset;
  final String label;
  final String? labelKey;
  final Color? color;

  BActionBottomSheetGridItemModel({
    required this.asset,
    required this.label,
    this.labelKey,
    this.color,
  });
}

class GridBottomSheet extends StatelessWidget {
  final List<BActionBottomSheetGridItemModel> items;

  const GridBottomSheet({
    super.key,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: screenHeight * 0.75,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Enhanced handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 24),

          // Enhanced title section - Centered
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Text(
                  AppLocalizations.of(context).translate('quickActions'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context)
                      .translate('quickActionsSubtitle'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Enhanced grid with better spacing and animation
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GridView.builder(
                physics: const BouncingScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 20,
                  childAspectRatio: 0.85,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  return AnimatedContainer(
                    duration: Duration(milliseconds: 100 + (index * 50)),
                    child: _EnhancedActionGridCardWithText(
                      item: items[index],
                      index: index,
                      onTap: () {
                        _animateAndNavigate(context, items[index].label);
                      },
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _animateAndNavigate(BuildContext context, String label) async {
    // Add haptic feedback
    // HapticFeedback.lightImpact();

    // Small delay for animation
    await Future.delayed(const Duration(milliseconds: 150));

    if (context.mounted) {
      Navigator.pop(context);
      _handleNavigation(context, label);
    }
  }

  void _handleNavigation(BuildContext context, String label) {
    final routes = {
      'Requested': '/add-requested',
      'Offers': '/add-offers',
      'Owners': '/add-owners',
      'Offices': '/add-offices',
      'Watchmen': '/add-watchmen',
      'Brokers': '/add-brokers',
      'Quotation': '/add-quotation',
      'Map': '/map-view', // Updated to standalone route
    };

    final route = routes[label];
    if (route != null) {
      context.push(route);
    }
  }

  static void show(
      BuildContext context, List<BActionBottomSheetGridItemModel> items) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) => GridBottomSheet(items: items),
    );
  }

  static void showDefault(BuildContext context) {
    show(context, ActionItemsData.getDefaultItems());
  }
}

// Enhanced Action items data class with better organization
class ActionItemsData {
  static List<BActionBottomSheetGridItemModel> getDefaultItems() => [
        BActionBottomSheetGridItemModel(
          asset: 'assets/icons/requested-svg.svg',
          label: 'Requested',
          labelKey: 'requested',
        ),
        BActionBottomSheetGridItemModel(
          asset: 'assets/icons/offers-svg.svg',
          label: 'Offers',
          labelKey: 'offers',
        ),
        BActionBottomSheetGridItemModel(
          asset: 'assets/icons/owners-svg.svg',
          label: 'Owners',
          labelKey: 'owners',
        ),
        BActionBottomSheetGridItemModel(
          asset: 'assets/icons/offices-svg.svg',
          label: 'Offices',
          labelKey: 'offices',
        ),
        BActionBottomSheetGridItemModel(
          asset: 'assets/icons/brokers-svg.svg',
          label: 'Brokers',
          labelKey: 'brokers',
        ),
        BActionBottomSheetGridItemModel(
          asset: 'assets/icons/watchman-svg.svg',
          label: 'Watchmen',
          labelKey: 'watchmen',
        ),
        BActionBottomSheetGridItemModel(
          asset: 'assets/icons/quotation-svg.svg',
          label: 'Quotation',
          labelKey: 'quotation',
        ),
      ];
}

// Enhanced grid card with SVG support and better animations
class _EnhancedActionGridCardWithText extends StatefulWidget {
  final BActionBottomSheetGridItemModel item;
  final VoidCallback onTap;
  final int index;

  const _EnhancedActionGridCardWithText({
    required this.item,
    required this.onTap,
    required this.index,
  });

  @override
  State<_EnhancedActionGridCardWithText> createState() =>
      _EnhancedActionGridCardWithTextState();
}

class _EnhancedActionGridCardWithTextState
    extends State<_EnhancedActionGridCardWithText>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _animationController.forward();
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _animationController.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemColor = widget.item.color ?? theme.colorScheme.primary;

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: GestureDetector(
            onTapDown: _onTapDown,
            onTapUp: _onTapUp,
            onTapCancel: _onTapCancel,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: _isPressed
                    ? itemColor.withValues(alpha: 0.05)
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isPressed
                      ? itemColor.withValues(alpha: 0.3)
                      : theme.colorScheme.outline.withValues(alpha: 0.1),
                  width: _isPressed ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _isPressed
                        ? itemColor.withValues(alpha: 0.2)
                        : theme.colorScheme.shadow.withValues(alpha: 0.08),
                    blurRadius: _isPressed ? 12 : 8,
                    offset: Offset(0, _isPressed ? 6 : 4),
                  ),
                ],
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // SVG Icon container
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: itemColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: itemColor.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: SvgPicture.asset(
                          widget.item.asset,
                          width: 20,
                          height: 20,
                          colorFilter: ColorFilter.mode(
                            itemColor,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 6),

                    // Label
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          widget.item.labelKey != null
                              ? AppLocalizations.of(context)
                                  .translate(widget.item.labelKey!)
                              : widget.item.label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),

                    // "Add" text with subtle styling
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: itemColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.add,
                        color: itemColor,
                        size: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
