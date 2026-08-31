import 'package:broker_wallet/src/common/utils/svg_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

/// Model for each toolkit item
class ToolkitItem {
  final String iconAsset;
  final String titleKey;
  final String route;
  final Color? backgroundColor;
  final String? description;

  ToolkitItem({
    required this.iconAsset,
    required this.titleKey,
    required this.route,
    this.backgroundColor,
    this.description,
  });
}

class ToolkitView extends StatefulWidget {
  const ToolkitView({Key? key}) : super(key: key);

  @override
  _ToolkitViewState createState() => _ToolkitViewState();
}

class _ToolkitViewState extends State<ToolkitView>
    with TickerProviderStateMixin {
  late final List<ToolkitItem> _allItems;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _allItems = [
      ToolkitItem(
        iconAsset: SvgIcon.signatureIcon,
        titleKey: 'documentSignature',
        route: '/signature',
        backgroundColor: const Color(0xFFFFE6E6),
        description: 'signDocumentsDigitally',
      ),
      ToolkitItem(
        iconAsset: SvgIcon.scanIcon,
        titleKey: 'scanner',
        route: '/scanner',
        backgroundColor: const Color(0xFFE0F7F5),
        description: 'scanDocuments',
      ),
      ToolkitItem(
        iconAsset: SvgIcon.galleryIcon,
        titleKey: 'imageToPdf',
        route: '/imageToPdf',
        backgroundColor: const Color(0xFFE8F5E8),
        description: 'convertImagesToPdf',
      ),
      ToolkitItem(
        iconAsset: SvgIcon.combinePdfsIcon,
        titleKey: 'combinePdfs',
        route: '/combine-pdfs',
        backgroundColor: const Color(0xFFFFF2E6),
        description: 'mergeMultiplePdfs',
      ),
      ToolkitItem(
        iconAsset: SvgIcon.links,
        titleKey: 'uaeLinks',
        route: '/uae-links',
        backgroundColor: const Color(0xFFE6F3FF),
        description: 'quickAccessGovPortals',
      ),
    ];

    // Start animation after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animationController.forward();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = (width ~/ 200).clamp(2, 3);

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        leading: const BackArrowButton(),
        title: Column(
          children: [
            Text(
              localization.translate('toolkit'),
              style: AppTextStyles.appBarTitle.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              localization.translate('chooseYourTool'),
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colors.surface,
        toolbarHeight: 80,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors.surface,
              colors.surface.withValues(alpha: 0.95),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header section
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF02957D), Color(0xFF026B5A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF02957D).withValues(alpha: 0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            localization.translate('professionalTools'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            localization.translate('boostProductivity'),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.build_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // Tools section
              Text(
                localization.translate('availableTools'),
                style: AppTextStyles.bodyText.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 16),

              Expanded(
                child: _buildGrid(_allItems, crossAxisCount),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(List<ToolkitItem> items, int crossAxisCount) {
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 20,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (ctx, i) {
        final item = items[i];
        return AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            final animationValue = Curves.elasticOut.transform(
              (_animationController.value - (i * 0.1)).clamp(0.0, 1.0),
            );
            return Transform.scale(
              scale: animationValue,
              child: _ToolkitCard(
                item: item,
                onTap: () => context.push(
                    item.route), // Changed from context.go() to context.push()
                index: i,
              ),
            );
          },
        );
      },
    );
  }
}

class _ToolkitCard extends StatefulWidget {
  final ToolkitItem item;
  final VoidCallback onTap;
  final int index;

  const _ToolkitCard({
    Key? key,
    required this.item,
    required this.onTap,
    required this.index,
  }) : super(key: key);

  @override
  State<_ToolkitCard> createState() => _ToolkitCardState();
}

class _ToolkitCardState extends State<_ToolkitCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverController;
  bool _isHovered = false;

  // Helper method to get dark color from background color
  Color _getDarkColorFromBackground(Color? backgroundColor) {
    if (backgroundColor == null) return const Color(0xFF02957D);

    switch (backgroundColor.value) {
      case 0xFFFFE6E6: // Light red (signature)
        return const Color(0xFFD32F2F); // Dark red
      case 0xFFE8F5E8: // Light green (imageToPdf)
        return const Color(0xFF2E7D32); // Dark green
      case 0xFFFFF2E6: // Light orange (combinePdfs)
        return const Color(0xFFF57C00); // Dark orange
      case 0xFFE0F7F5: // Light teal (scanner)
        return const Color(0xFF02957D); // Dark teal
      case 0xFFE6F3FF: // Light blue (uaeLinks)
        return const Color(0xFF1976D2); // Dark blue
      default:
        return const Color(0xFF02957D); // Default dark teal
    }
  }

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final localization = AppLocalizations.of(context);
    final iconColor = _getDarkColorFromBackground(widget.item.backgroundColor);

    return Semantics(
      label: localization.translate(widget.item.titleKey),
      button: true,
      child: AnimatedBuilder(
        animation: _hoverController,
        builder: (context, child) {
          return Transform.scale(
            scale: 1.0 + (_hoverController.value * 0.05),
            child: GestureDetector(
              onTapDown: (_) {
                _hoverController.forward();
                setState(() => _isHovered = true);
              },
              onTapUp: (_) {
                _hoverController.reverse();
                setState(() => _isHovered = false);
                widget.onTap();
              },
              onTapCancel: () {
                _hoverController.reverse();
                setState(() => _isHovered = false);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: _isHovered
                          ? colors.primary.withValues(alpha: 0.25)
                          : colors.shadow.withValues(alpha: 0.08),
                      blurRadius: _isHovered ? 20 : 8,
                      offset: Offset(0, _isHovered ? 8 : 4),
                    ),
                  ],
                  border: Border.all(
                    color: _isHovered
                        ? colors.primary.withValues(alpha: 0.3)
                        : colors.outline.withValues(alpha: 0.1),
                    width: 1.5,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top section with icon
                      Hero(
                        tag: widget.item.titleKey,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: widget.item.backgroundColor ??
                                const Color(0xFFF0F9F7),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: (widget.item.backgroundColor ??
                                        const Color(0xFFF0F9F7))
                                    .withValues(alpha: 0.5),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Center(
                            child: SvgPicture.asset(
                              widget.item.iconAsset,
                              width: 32,
                              height: 32,
                              colorFilter: ColorFilter.mode(
                                iconColor,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Middle section with text
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 12),
                            Text(
                              localization.translate(widget.item.titleKey),
                              style: AppTextStyles.bodyText.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: colors.onSurface,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.item.description != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                localization
                                    .translate(widget.item.description!),
                                style: TextStyle(
                                  fontSize: 10,
                                  color:
                                      colors.onSurface.withValues(alpha: 0.6),
                                  fontWeight: FontWeight.w400,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Bottom section with arrow
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.arrow_forward_ios,
                          size: 10,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
