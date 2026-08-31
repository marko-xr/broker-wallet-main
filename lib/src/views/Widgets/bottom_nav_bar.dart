// lib/src/widgets/bottom_nav_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/utils/images.dart';

class BottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final void Function(int) onSelect;

  const BottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);

    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin:
          6.0, // this is the space between the FAB and the bottom of the screen
      child: Row(
        children: [
          _NavItem(
            selectedIndex: selectedIndex,
            index: 0,
            onTap: onSelect,
            label: localization.translate('home'),
            selectedIcon: AppImages.home,
            unselectedIcon: AppImages.homeNotSelect,
          ),
          _NavItem(
            selectedIndex: selectedIndex,
            index: 1,
            onTap: onSelect,
            label: localization.translate('search'),
            selectedIcon: AppImages.search,
            unselectedIcon: AppImages.searchNotSelect,
          ),
          const SizedBox(width: 56), // Space for FAB
          _NavItem(
            selectedIndex: selectedIndex,
            index: 2,
            onTap: onSelect,
            label: localization.translate('favorites'),
            selectedIcon: AppImages.favorites,
            unselectedIcon: AppImages.favoritesNotSelect,
          ),
          _NavItem(
            selectedIndex: selectedIndex,
            index: 3,
            onTap: onSelect,
            label: localization.translate('profile'),
            selectedIcon: AppImages.profile,
            unselectedIcon: AppImages.profileNotSelect,
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final int selectedIndex;
  final int index;
  final String label;
  final String selectedIcon;
  final String unselectedIcon;
  final void Function(int) onTap;

  const _NavItem({
    required this.selectedIndex,
    required this.index,
    required this.label,
    required this.selectedIcon,
    required this.unselectedIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedIndex == index;
    final color =
        isSelected ? Theme.of(context).colorScheme.primary : Colors.grey;
    final asset = isSelected ? selectedIcon : unselectedIcon;

    // Check if current locale is Arabic
    final locale = Localizations.localeOf(context);
    final isArabic = locale.languageCode == 'ar';

    return Expanded(
      child: InkWell(
        onTap: () {
          // Add haptic feedback for better UX
          HapticFeedback.lightImpact();
          onTap(index);
        },
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: isSelected ? 1.1 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: Image.asset(
                    asset,
                    width: 24,
                    height: 24,
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    color: color,
                    fontSize:
                        isArabic ? 9 : 10, // Slightly smaller font for Arabic
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2, // Allow text to wrap to 2 lines if needed
                    overflow: TextOverflow.ellipsis,
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
