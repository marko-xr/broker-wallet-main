import 'dart:async';

import 'package:flutter/foundation.dart';
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

class _MainScaffoldState extends State<MainScaffold> {
  DateTime? _lastBackPressed;

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

    // Navigate to the selected branch with StatefulNavigationShell
    widget.navigationShell.goBranch(
      index,
      // Keep each branch at its last location when switching tabs.
      initialLocation: false,
    );

    // Show Home immediately with its current counts; refresh them in place
    // without delaying the branch switch on a network round trip.
    if (index == 0) {
      _refreshHomeCounts();
    }
  }

  void _refreshHomeCounts() {
    final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
    final refresh =
        Provider.of<HomeViewModel>(context, listen: false).refreshCounts();
    if (stopwatch == null) {
      unawaited(refresh);
      return;
    }
    unawaited(refresh.whenComplete(() {
      debugPrint('[Home] counts refreshed after '
          '${stopwatch.elapsedMilliseconds} ms (tab already visible)');
    }));
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
        // Let tab content continue behind the physically transparent liquid
        // notch. This is what keeps the curved center treatment visually clean
        // instead of painting a rectangular surface behind the FAB.
        extendBody: true,
        resizeToAvoidBottomInset: false,
        body: widget.navigationShell,
        bottomNavigationBar: BottomNavBar(
          selectedIndex: widget.navigationShell.currentIndex,
          onSelect: _onItemTapped,
        ),
        floatingActionButton: Transform.translate(
          offset: const Offset(0, 8),
          child: GlowingFab(
            heroTag: 'mainFab',
            size: 75,
            iconSize: 26,
            onPressed: _showActionBottomSheet,
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      ),
    );
  }
}
