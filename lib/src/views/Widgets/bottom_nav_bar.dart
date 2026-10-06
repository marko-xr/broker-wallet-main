// lib/src/widgets/bottom_nav_bar.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/images.dart';
import 'package:broker_wallet/src/constants/app_colors.dart';

/// Broker Wallet's four-destination bottom navigation.
///
/// The geometry mirrors the proven liquid-notch treatment used by INTLAQ Hub,
/// while Broker Wallet keeps its own icons, labels, colors, and navigation
/// callbacks. The notch is painted as real transparent space instead of being
/// simulated by a standard [BottomAppBar] cutout, which keeps the center FAB
/// visually stable and avoids blocky artifacts around the curve.
class BottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final void Function(int) onSelect;

  const BottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
  });

  static const double _barHeight = 80;
  static const double _centerGap = 80;

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final items = <_NavItemData>[
      _NavItemData(
        index: 0,
        label: localization.translate('home'),
        selectedIcon: AppImages.home,
        unselectedIcon: AppImages.homeNotSelect,
      ),
      _NavItemData(
        index: 1,
        label: localization.translate('search'),
        selectedIcon: AppImages.search,
        unselectedIcon: AppImages.searchNotSelect,
      ),
      _NavItemData(
        index: 2,
        label: localization.translate('favorites'),
        selectedIcon: AppImages.favorites,
        unselectedIcon: AppImages.favoritesNotSelect,
      ),
      _NavItemData(
        index: 3,
        label: localization.translate('profile'),
        selectedIcon: AppImages.profile,
        unselectedIcon: AppImages.profileNotSelect,
      ),
    ];

    // Match the proven mobile safe-area behavior from INTLAQ Hub: Android's
    // system navigation inset is kept outside the painted bar, while iOS lets
    // the home-indicator region remain part of the bottom surface.
    final shouldApplyBottomSafeArea =
        defaultTargetPlatform != TargetPlatform.iOS;

    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: shouldApplyBottomSafeArea,
      child: SizedBox(
        height: _barHeight,
        child: CustomPaint(
          painter: _CurvedBarPainter(
            backgroundColor:
                isDark ? AppColors.darkSurface : AppColors.white,
            shadowColor: isDark
                ? Colors.black.withValues(alpha: 0.4)
                : Colors.black.withValues(alpha: 0.1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _NavItem(
                        item: items[0],
                        isSelected: selectedIndex == 0,
                        onTap: onSelect,
                      ),
                      _NavItem(
                        item: items[1],
                        isSelected: selectedIndex == 1,
                        onTap: onSelect,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: _centerGap),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _NavItem(
                        item: items[2],
                        isSelected: selectedIndex == 2,
                        onTap: onSelect,
                      ),
                      _NavItem(
                        item: items[3],
                        isSelected: selectedIndex == 3,
                        onTap: onSelect,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItemData {
  final int index;
  final String label;
  final String selectedIcon;
  final String unselectedIcon;

  const _NavItemData({
    required this.index,
    required this.label,
    required this.selectedIcon,
    required this.unselectedIcon,
  });
}

class _CurvedBarPainter extends CustomPainter {
  final Color backgroundColor;
  final Color shadowColor;

  const _CurvedBarPainter({
    required this.backgroundColor,
    required this.shadowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = _liquidCurvePath(size);

    canvas.drawShadow(
      path,
      shadowColor,
      12,
      true,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = backgroundColor
        ..style = PaintingStyle.fill,
    );
  }

  Path _liquidCurvePath(Size size) {
    final path = Path();
    final centerX = size.width / 2;

    const cornerRadius = 24.0;
    const curveHalfWidth = 75.0;
    const curveHeight = 48.0;
    const firstControl = 37.5;
    const secondControl = 42.5;

    path.moveTo(0, cornerRadius);
    path.quadraticBezierTo(0, 0, cornerRadius, 0);
    path.lineTo(centerX - curveHalfWidth, 0);
    path.cubicTo(
      centerX - firstControl,
      0,
      centerX - secondControl,
      curveHeight,
      centerX,
      curveHeight,
    );
    path.cubicTo(
      centerX + secondControl,
      curveHeight,
      centerX + firstControl,
      0,
      centerX + curveHalfWidth,
      0,
    );
    path.lineTo(size.width - cornerRadius, 0);
    path.quadraticBezierTo(size.width, 0, size.width, cornerRadius);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    return path;
  }

  @override
  bool shouldRepaint(covariant _CurvedBarPainter oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.shadowColor != shadowColor;
  }
}

class _NavItem extends StatelessWidget {
  final _NavItemData item;
  final bool isSelected;
  final void Function(int) onTap;

  const _NavItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final locale = Localizations.localeOf(context);
    final isArabic = locale.languageCode == 'ar';

    final selectedColor = theme.colorScheme.primary;
    final unselectedColor = isDark
        ? AppColors.textSecondary.withValues(alpha: 0.7)
        : AppColors.textSecondary;

    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: item.label,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap(item.index);
          },
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  isSelected ? item.selectedIcon : item.unselectedIcon,
                  width: 24,
                  height: 24,
                  filterQuality: FilterQuality.medium,
                ),
                const SizedBox(height: 4),
                Text(
                  item.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isArabic ? 10 : 11,
                    height: 1.05,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? selectedColor : unselectedColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
