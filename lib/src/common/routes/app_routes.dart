import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/Views/Widgets/action_bottom_sheet.dart';
import 'package:broker_wallet/src/Views/Widgets/bottom_nav_bar.dart';
import 'package:broker_wallet/src/Views/Widgets/glowing_fab.dart';
import 'package:broker_wallet/src/viewmodels/home_viewmodel.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';

class MainScaffold extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const MainScaffold({super.key, required this.navigationShell});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold>
    with TickerProviderStateMixin {
  DateTime? _lastBackPressed;
  late AnimationController _tabTransitionController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    // Initialize animation controller for smooth tab transitions
    _tabTransitionController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _tabTransitionController,
      curve: Curves.easeInOut,
    ));
    _tabTransitionController.forward();
  }

  @override
  void dispose() {
    _tabTransitionController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) async {
    final currentIndex = widget.navigationShell.currentIndex;

    // If tapping the same tab, do nothing to prevent unnecessary rebuilds
    if (currentIndex == index) {
      if (index == 0) {
        await Provider.of<HomeViewModel>(context, listen: false)
            .refreshCounts();
      }
      return;
    }

    // Clear home filters when navigating away from home tab
    if (currentIndex == 0 && index != 0) {
      final homeVM = Provider.of<HomeViewModel>(context, listen: false);
      homeVM.clearAllFilters();
    }

    // Animate transition for smoother visual feedback
    _tabTransitionController.reset();

    // Navigate to the selected branch with StatefulNavigationShell
    widget.navigationShell.goBranch(
      index,
      // Use true to maintain state when switching tabs
      initialLocation: index == widget.navigationShell.currentIndex,
    );

    if (index == 0) {
      await Provider.of<HomeViewModel>(context, listen: false).refreshCounts();
    }

    // Complete the animation
    _tabTransitionController.forward();
  }

  void _showActionBottomSheet() {
    GridBottomSheet.show(context, ActionItemsData.getDefaultItems());
  }

  Future<bool> _onWillPop() async {
    final loc = AppLocalizations.of(context);
    final currentIndex = widget.navigationShell.currentIndex;
    final currentLocation =
        widget.navigationShell.shellRouteContext.routerState.uri.path;

    // If we're not on a main tab (home, search, favorites, profile), go back normally
    if (!['/home', '/search', '/favorites', '/profile']
        .contains(currentLocation)) {
      return true; // Allow normal back navigation
    }

    // If we're on any main tab except home, navigate to home
    if (currentIndex != 0) {
      widget.navigationShell.goBranch(0);
      return false; // Prevent default back behavior
    }

    // If we're on home, handle double-tap to exit
    final now = DateTime.now();
    const exitTime = Duration(seconds: 2);

    if (_lastBackPressed == null ||
        now.difference(_lastBackPressed!) > exitTime) {
      _lastBackPressed = now;

      // Show toast message
      _showToast(
        loc.translate('pressBackAgainToExit'),
        Colors.black,
      );
      return false; // Don't exit yet
    }

    // Exit the app
    SystemNavigator.pop();
    return false;
  }

  void _showToast(String message, Color bgColor) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: bgColor,
      textColor: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (!didPop) {
          await _onWillPop();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: AnimatedBuilder(
          animation: _fadeAnimation,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: widget.navigationShell,
            );
          },
        ),
        bottomNavigationBar: BottomNavBar(
          selectedIndex: widget.navigationShell.currentIndex,
          onSelect: _onItemTapped,
        ),
        floatingActionButton: GlowingFab(
          heroTag: 'mainFab',
          onPressed: _showActionBottomSheet,
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      ),
    );
  }
}
