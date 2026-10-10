import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:geocoding/geocoding.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/constants/location_colors.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/Views/Screens/home/map/map_filter_bar.dart';
import 'package:broker_wallet/src/Views/Screens/home/map/map_filter_status_line.dart';
import 'package:broker_wallet/src/Views/Screens/home/map/map_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/favorites/favorite_card_media.dart';
import 'package:broker_wallet/src/Views/Screens/home/search/search_card_media.dart';
import 'package:broker_wallet/src/Views/Widgets/private_card_media.dart';
import 'package:broker_wallet/src/services/map_camera.dart';
import 'package:broker_wallet/src/services/map_filter_controller.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:broker_wallet/src/services/phone_input_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/owner_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/office_service.dart';
import 'package:broker_wallet/src/services/ScreenServices/watchmen_service.dart';
import 'package:broker_wallet/src/common/utils/images.dart';

class MapViewScreen extends StatefulWidget {
  const MapViewScreen({super.key});

  @override
  State<MapViewScreen> createState() => _MapViewScreenState();
}

class _MapViewScreenState extends State<MapViewScreen> {
  bool _isLegendExpanded = false;
  final TextEditingController _searchController = TextEditingController();
  bool _hasCheckedPermission = false; // Check once, never ask

  // What the screen's own controls cover of the map, so the cities' frame it
  // opens on sits in what is left: the search bar and the filter row below the
  // status bar (76 + the row's 48 + a gap), and the my-location button above the
  // bottom edge.
  static const double _controlsBelowTop = 76 + 48 + 8;
  static const double _controlsAboveBottom = 16 + 40 + 16;
  static const double _controlsSideGap = 16;

  // The status line (the result count, and Reset while a filter is on) floats
  // over the map right under the filter row, and the "no matches" banner under
  // it. Like the banner always did, they sit on the map: they are not part of
  // what the opening frame leaves room for, so that frame is unchanged.
  static const double _statusLineTop = 76 + 52;
  static const double _bannerTop = _statusLineTop + MapFilterStatusLine.height;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// The my-location button. The person tapped it, so location may be asked for
  /// now (the system's own prompt; the app puts no dialog of its own before
  /// it). When the camera cannot move, a short non-blocking message says why.
  Future<void> _locateMe(
    MapViewViewModel vm,
    AppLocalizations localization,
  ) async {
    final fix = await vm.moveToCurrentLocation();
    if (!mounted || fix == null) return;
    final key = nearbyFixMessageKey(fix);
    if (key != null) _showToast(localization.translate(key), Colors.orange);
  }

  Future<void> _searchLocation(String query, MapViewViewModel vm) async {
    if (query.trim().isEmpty) return;

    final loc = AppLocalizations.of(context);
    try {
      List<Location> locations = await locationFromAddress(query);
      if (!mounted) return;
      if (locations.isNotEmpty) {
        Location location = locations.first;
        LatLng searchedLocation = LatLng(location.latitude, location.longitude);

        // Move camera to searched location
        vm.animateToLocation(searchedLocation);

        // Hide keyboard
        FocusScope.of(context).unfocus();

        // Show success toast
        _showToast(loc.translate('mapLocationFound'), Colors.green);
      } else {
        _showToast(loc.translate('mapLocationNotFound'), Colors.red);
      }
    } catch (e) {
      // The geocoder's own message is not for the person: it is English, and
      // it can quote what they typed.
      if (mounted) {
        _showToast(loc.translate('mapLocationNotFound'), Colors.red);
      }
    }
  }

  static void _showToast(String message, Color bgColor) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
      backgroundColor: bgColor,
      textColor: Colors.white,
    );
  }

  Future<void> _navigateToDetails(
      BuildContext context, LocationInfo locationInfo) async {
    final loc = AppLocalizations.of(context);
    try {
      switch (locationInfo.type) {
        case LocationFilter.offers:
          final offerId = locationInfo.id.trim();
          if (offerId.isNotEmpty && context.mounted) {
            context.push(
              '/offers-details-by-id/${Uri.encodeComponent(offerId)}',
            );
          }
          break;

        case LocationFilter.owners:
          final owner = await OwnerService().getOwner(locationInfo.id);
          if (owner != null && context.mounted) {
            context.push('/owners-details', extra: owner);
          } else if (context.mounted) {
            _showToast(loc.translate('ownerNotFound'), Colors.red);
          }
          break;

        case LocationFilter.offices:
          final office = await OfficeService().getOffice(locationInfo.id);
          if (office != null && context.mounted) {
            context.push('/offices-details', extra: office);
          } else if (context.mounted) {
            _showToast(loc.translate('officeNotFound'), Colors.red);
          }
          break;

        case LocationFilter.watchmen:
          final watchmen = await WatchmenService().getWatchmen(locationInfo.id);
          if (watchmen != null && context.mounted) {
            context.push('/watchmen-details', extra: watchmen);
          } else if (context.mounted) {
            _showToast(loc.translate('watchmanNotFound'), Colors.red);
          }
          break;

        case LocationFilter.all:
          // A place is never "all": nothing to open.
          break;
      }
    } catch (e) {
      // The error itself is not for the person: it is English and can quote
      // record data.
      if (context.mounted) {
        _showToast(loc.translate('mapDetailsLoadFailed'), Colors.red);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);

    return ChangeNotifierProvider(
      create: (_) => MapViewViewModel(),
      child: Consumer<MapViewViewModel>(
        builder: (context, vm, _) {
          vm.updateLocalization(localization);

          // Whether location is already allowed (to show the device's own dot).
          // Only a check: opening the map never asks for location. Location is
          // asked for when the person turns Nearby on, or taps "my location".
          if (!_hasCheckedPermission) {
            _hasCheckedPermission = true;
            // Use post-frame callback to avoid calling during build
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) unawaited(vm.checkLocationPermission());
            });
          }

          final colors = Theme.of(context).colorScheme;
          return Scaffold(
            backgroundColor: colors.surface,
            resizeToAvoidBottomInset:
                false, // Prevent keyboard from moving the map
            body: Stack(
              children: [
                // Full-screen Map - always display, no loading check
                vm.hasLoadError
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 64,
                                color: colors.error,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                localization.translate('mapLoadFailed'),
                                style: TextStyle(color: colors.error),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: vm.retry,
                                child: Text(localization.translate('retry')),
                              ),
                            ],
                          ),
                        ),
                      )
                    : LayoutBuilder(
                        // The map opens on the UAE's cities, framed for the room it
                        // really has (the search bar and filters cover the top,
                        // the location button the bottom). That is its starting
                        // camera, so nothing moves it afterwards.
                        builder: (context, constraints) => GoogleMap(
                          mapType: vm.mapType,
                          initialCameraPosition: vm.initialCameraFor(
                            MapViewport(
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              top: MediaQuery.of(context).padding.top +
                                  _controlsBelowTop,
                              bottom: _controlsAboveBottom,
                              left: _controlsSideGap,
                              right: _controlsSideGap,
                            ),
                          ),
                          onMapCreated: vm.onMapCreated,
                          markers: vm.filteredMarkers,
                          onTap: vm.onMapTap,
                          myLocationEnabled: vm
                              .hasLocationPermission, // Only enable if permission granted
                          myLocationButtonEnabled:
                              false, // Disable default button
                          zoomControlsEnabled: true,
                          mapToolbarEnabled: false,
                          compassEnabled: true,
                          trafficEnabled: false,
                          buildingsEnabled: true,
                        ),
                      ),

                // Floating Back Arrow Button (RTL/LTR aware)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  left: Directionality.of(context) == TextDirection.ltr
                      ? 16
                      : null,
                  right: Directionality.of(context) == TextDirection.rtl
                      ? 16
                      : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadow.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Directionality.of(context) == TextDirection.rtl
                            ? Icons.arrow_back_ios_new
                            : Icons.arrow_back_ios_new,
                        color: colors.onSurface,
                      ),
                      iconSize: 24,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                    ),
                  ),
                ),

                // Floating Search Bar (space for buttons on both sides)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  left: 72, // Space for back button (16 + 40 + 16)
                  right: 72, // Space for map toggle button (16 + 40 + 16)
                  child: _FloatingSearchBar(
                    controller: _searchController,
                    onSearchSubmitted: (query) => _searchLocation(query, vm),
                    onSearchChanged: (value) => setState(() {}),
                    localization: localization,
                    colors: colors,
                  ),
                ),

                // Map Toggle Button (RTL/LTR aware) - combines map type and location
                Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  left: Directionality.of(context) == TextDirection.rtl
                      ? 16
                      : null,
                  right: Directionality.of(context) == TextDirection.ltr
                      ? 16
                      : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadow.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: vm.toggleMapType,
                      icon: Icon(
                        vm.mapType == MapType.hybrid
                            ? Icons.map_outlined
                            : Icons.satellite_alt,
                        color: colors.onSurface,
                      ),
                      iconSize: 24,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                    ),
                  ),
                ),

                // The filters: one compact row under the search bar, scrolling
                // sideways on a small phone.
                Positioned(
                  top: MediaQuery.of(context).padding.top +
                      76, // Below search bar
                  left: 0,
                  right: 0,
                  child: MapFilterBar(
                    viewModel: vm,
                    localization: localization,
                    onMessage: (message) => _showToast(message, Colors.orange),
                  ),
                ),

                // How many places the map shows, and Reset while the filters
                // differ from the default. The count is the published draw's
                // own (the markers' places); Reset is the banner's action.
                PositionedDirectional(
                  top: MediaQuery.of(context).padding.top + _statusLineTop,
                  start: 16,
                  end: 16,
                  child: MapFilterStatusLine(
                    localization: localization,
                    resultCount: vm.resultCount,
                    canReset: vm.filtersActive,
                    onReset: vm.clearFilters,
                  ),
                ),

                // Places are loaded but the filters let none through: the map
                // stays, and says so. (Not a failed load.)
                if (vm.hasNoFilterMatches)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + _bannerTop,
                    left: 16,
                    right: 16,
                    child: MapNoMatchesBanner(
                      message: localization.translate('mapNoFilterMatches'),
                      actionLabel: localization.translate('mapResetFilters'),
                      onClear: vm.clearFilters,
                    ),
                  ),

                // My Location Button (Bottom Left) - Hidden when info panel is visible
                if (vm.selectedLocationInfo == null)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: colors.shadow.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        onPressed: () => _locateMe(vm, localization),
                        icon: Icon(
                          Icons.my_location,
                          color: colors.onSurface,
                        ),
                        iconSize: 24,
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                      ),
                    ),
                  ),
                // Floating Bottom Info Panel (when location is selected)
                if (vm.selectedCluster != null)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: _FloatingLocationCarousel(
                      cluster: vm.selectedCluster!,
                      onClose: vm.clearSelectedLocation,
                      localization: localization,
                      titleOf: vm.displayTitle,
                      cardMedia: vm.cardMedia,
                      onPageChanged: (index) {
                        vm.updateClusterActiveIndex(index);
                      },
                      onItemTap: (locationInfo) =>
                          _navigateToDetails(context, locationInfo),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// Floating Search Bar Widget
class _FloatingSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final Function(String) onSearchSubmitted;
  final Function(String) onSearchChanged;
  final AppLocalizations localization;
  final ColorScheme colors;

  const _FloatingSearchBar({
    required this.controller,
    required this.onSearchSubmitted,
    required this.onSearchChanged,
    required this.localization,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: localization.translate('mapSearchHint'),
          hintStyle: AppTextStyles.hintText,
          prefixIcon: Icon(Icons.search, color: colors.primary),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: colors.outline),
                  onPressed: () {
                    controller.clear();
                    FocusScope.of(context).unfocus();
                    onSearchChanged('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12, // Reduced from 16 to 12
          ),
          isDense: true, // Makes the TextField more compact
        ),
        style: AppTextStyles.bodyText,
        onSubmitted: onSearchSubmitted,
        onChanged: onSearchChanged,
      ),
    );
  }
}

// Floating Location Carousel (for clustered locations)
class _FloatingLocationCarousel extends StatefulWidget {
  final ClusteredLocationInfo cluster;
  final VoidCallback onClose;
  final AppLocalizations localization;
  final String Function(LocationInfo) titleOf;
  final SearchCardMediaResolver cardMedia;
  final Function(int) onPageChanged;
  final Function(LocationInfo) onItemTap;

  const _FloatingLocationCarousel({
    required this.cluster,
    required this.onClose,
    required this.localization,
    required this.titleOf,
    required this.cardMedia,
    required this.onPageChanged,
    required this.onItemTap,
  });

  @override
  State<_FloatingLocationCarousel> createState() =>
      _FloatingLocationCarouselState();
}

class _FloatingLocationCarouselState extends State<_FloatingLocationCarousel> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.cluster.activeIndex;
    _pageController = PageController(
      initialPage: _currentPage,
      viewportFraction: 0.92, // Slight peek of adjacent cards
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_FloatingLocationCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update page if cluster's active index changed externally
    if (oldWidget.cluster.activeIndex != widget.cluster.activeIndex &&
        _currentPage != widget.cluster.activeIndex) {
      _currentPage = widget.cluster.activeIndex;
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });
    widget.onPageChanged(index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      tween: Tween<double>(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 50 * (1 - value)), // Slide up animation
          child: Opacity(
            opacity: value,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Page indicators (if multiple items)
                if (widget.cluster.hasMultipleItems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CarouselIndicators(
                      itemCount: widget.cluster.itemCount,
                      currentIndex: _currentPage,
                      activeColor: widget.cluster.activeItem.color,
                    ),
                  ),
                // Carousel
                SizedBox(
                  height: 135,
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: _onPageChanged,
                    itemCount: widget.cluster.itemCount,
                    physics: const BouncingScrollPhysics(),
                    itemBuilder: (context, index) {
                      final locationInfo = widget.cluster.items[index];
                      final isActive = index == _currentPage;

                      return AnimatedScale(
                        scale: isActive ? 1.0 : 0.95,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: _LocationCarouselCard(
                          locationInfo: locationInfo,
                          title: widget.titleOf(locationInfo),
                          cardMedia: widget.cardMedia,
                          onClose: widget.onClose,
                          localization: widget.localization,
                          onTap: () => widget.onItemTap(locationInfo),
                          showCloseButton: index == _currentPage,
                          colors: colors,
                        ),
                      );
                    },
                  ),
                ),
                // Item counter (if multiple items)
                if (widget.cluster.hasMultipleItems)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: colors.shadow.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        '${_currentPage + 1} / ${widget.cluster.itemCount}',
                        style: AppTextStyles.hintText.copyWith(
                          color: widget.cluster.activeItem.color,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Carousel indicators (dots)
class _CarouselIndicators extends StatelessWidget {
  final int itemCount;
  final int currentIndex;
  final Color activeColor;

  const _CarouselIndicators({
    required this.itemCount,
    required this.currentIndex,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        itemCount > 8 ? 8 : itemCount, // Show max 8 dots
        (index) {
          if (itemCount > 8 && index == 7) {
            // Show "..." for many items
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              child: Text(
                '...',
                style: TextStyle(
                  color: colors.onSurface.withValues(alpha: 0.3),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          }

          final isActive = index == currentIndex;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: isActive ? 20 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive ? activeColor : colors.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        },
      ),
    );
  }
}

// Individual carousel card
class _LocationCarouselCard extends StatelessWidget {
  final LocationInfo locationInfo;

  /// What the place is called, in the app's language.
  final String title;
  final SearchCardMediaResolver cardMedia;
  final VoidCallback onClose;
  final AppLocalizations localization;
  final VoidCallback onTap;
  final bool showCloseButton;
  final ColorScheme colors;

  const _LocationCarouselCard({
    required this.locationInfo,
    required this.title,
    required this.cardMedia,
    required this.onClose,
    required this.localization,
    required this.onTap,
    required this.showCloseButton,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -5),
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(12), // Reduced from 16
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with media preview
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CompactMediaPreview(
                      locationInfo: locationInfo,
                      cardMedia: cardMedia,
                      colors: colors,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Type badge and close button
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: locationInfo.color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (locationInfo.iconAsset != null)
                                      SvgPicture.asset(
                                        locationInfo.iconAsset!,
                                        width: 14,
                                        height: 14,
                                        color: locationInfo.color,
                                      )
                                    else
                                      Icon(
                                        locationInfo.icon,
                                        size: 14,
                                        color: locationInfo.color,
                                      ),
                                    const SizedBox(width: 4),
                                    Text(
                                      localization.translate(
                                        locationInfo.type
                                            .toString()
                                            .split('.')
                                            .last,
                                      ),
                                      style: AppTextStyles.hintText.copyWith(
                                        color: locationInfo.color,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              if (showCloseButton)
                                GestureDetector(
                                  onTap: onClose,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: colors.onSurface.withValues(alpha: 0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 14,
                                      color: colors.onSurface.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4), // Reduced from 6
                          // Title
                          Text(
                            title,
                            style: AppTextStyles.bodyText.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14, // Reduced from 15
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2), // Reduced from 4
                          // Address
                          if (locationInfo.address.isNotEmpty)
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 12, // Reduced from 13
                                  color: colors.onSurface.withValues(alpha: 0.5),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    MapLocationMapper.areaAndCity(
                                        locationInfo.address),
                                    style: AppTextStyles.hintText.copyWith(
                                      color: colors.onSurface.withValues(alpha: 0.6),
                                      fontSize: 11, // Reduced from 12
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8), // Reduced spacing before buttons
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: _CompactActionButtons(
                        phoneNumber: locationInfo.phoneNumber,
                        colors: colors,
                        onClose: onClose,
                        loc: localization,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Compact media preview widget
///
/// An Offer's or an Owner's photo (or a video's still frame): the list reads
/// carry no media links, so the card asks for its own through the resolver
/// Search uses, only while it is shown. Anything else, or a record whose media
/// cannot be had, keeps the plain URL it carries, or its icon.
class _CompactMediaPreview extends StatefulWidget {
  final LocationInfo locationInfo;
  final SearchCardMediaResolver cardMedia;
  final ColorScheme colors;

  const _CompactMediaPreview({
    required this.locationInfo,
    required this.cardMedia,
    required this.colors,
  });

  @override
  State<_CompactMediaPreview> createState() => _CompactMediaPreviewState();
}

class _CompactMediaPreviewState extends State<_CompactMediaPreview> {
  /// The private photo or video frame, once there is one to draw.
  FavoriteCardMedia? _media;

  /// Identifies the place the media was asked for, so a late answer for a card
  /// that now shows another place is ignored.
  int _mediaRequest = 0;

  @override
  void initState() {
    super.initState();
    _bindMedia();
  }

  @override
  void didUpdateWidget(covariant _CompactMediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locationInfo.id != widget.locationInfo.id ||
        oldWidget.locationInfo.type != widget.locationInfo.type ||
        oldWidget.cardMedia != widget.cardMedia) {
      _bindMedia();
    }
  }

  /// Only Offers and Owners have private photos and videos.
  CardMediaKind? get _mediaKind {
    switch (widget.locationInfo.type) {
      case LocationFilter.offers:
        return CardMediaKind.offer;
      case LocationFilter.owners:
        return CardMediaKind.owner;
      case LocationFilter.offices:
      case LocationFilter.watchmen:
      case LocationFilter.all:
        return null;
    }
  }

  /// Draws what is known at once (an earlier answer, or what this device
  /// holds), then asks for the rest while the card is shown.
  void _bindMedia() {
    final request = ++_mediaRequest;
    final kind = _mediaKind;
    if (kind == null) {
      _media = null;
      return;
    }
    final resolver = widget.cardMedia;
    final id = widget.locationInfo.id;
    _media = resolver.current(kind, id);
    unawaited(resolver
        .resolve(
      kind,
      id,
      isWanted: () => mounted && request == _mediaRequest,
    )
        .then((media) {
      if (!mounted || request != _mediaRequest) return;
      if (_sameMedia(_media, media)) return;
      setState(() => _media = media);
    }));
  }

  static bool _sameMedia(FavoriteCardMedia? a, FavoriteCardMedia? b) {
    if (a == null || b == null) return a == null && b == null;
    return a.cacheKey == b.cacheKey &&
        a.isVideo == b.isVideo &&
        a.signedUrl == b.signedUrl &&
        a.posterPath == b.posterPath;
  }

  @override
  Widget build(BuildContext context) {
    final locationInfo = widget.locationInfo;
    final colors = widget.colors;
    final media = _media;

    // Check if media exists
    final firstMediaUrl = locationInfo.mediaUrl ??
        (locationInfo.mediaUrls.isNotEmpty
            ? locationInfo.mediaUrls.first
            : null);
    final hasUrl = firstMediaUrl != null && firstMediaUrl.isNotEmpty;
    final hasMedia = media != null || hasUrl;

    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: locationInfo.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: hasMedia
            ? Border.all(
                color: colors.outline.withValues(alpha: 0.2),
                width: 1,
              )
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: media != null
            ? PrivateCardMedia(
                cacheKey: media.cacheKey,
                isVideo: media.isVideo,
                signedUrl: media.signedUrl,
                posterPath: media.posterPath,
                fallback: _buildIconBadge(),
              )
            : hasUrl
                ? CachedNetworkImage(
                    imageUrl: firstMediaUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: locationInfo.color.withValues(alpha: 0.1),
                      child: Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: locationInfo.color,
                          ),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => _buildIconBadge(),
                  )
                : _buildIconBadge(),
      ),
    );
  }

  Widget _buildIconBadge() {
    final locationInfo = widget.locationInfo;
    return Center(
      child: locationInfo.iconAsset != null
          ? SvgPicture.asset(
              locationInfo.iconAsset!,
              width: 28,
              height: 28,
              color: locationInfo.color,
            )
          : Icon(
              locationInfo.icon,
              color: locationInfo.color,
              size: 28,
            ),
    );
  }
}

// Compact action buttons widget
class _CompactActionButtons extends StatelessWidget {
  final String? phoneNumber;
  final ColorScheme colors;
  final VoidCallback onClose;
  final AppLocalizations loc;

  const _CompactActionButtons({
    required this.phoneNumber,
    required this.colors,
    required this.onClose,
    required this.loc,
  });

  // The same dial form the detail screens use (+<digits>, no spaces), so a
  // stored number written either way reaches the phone.
  Future<void> _makePhoneCall(String phoneNumber) async {
    try {
      final dial = PhoneInputService.formatForDial(phoneNumber);
      final Uri phoneUri = Uri(scheme: 'tel', path: dial);
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
        return;
      }
    } catch (_) {
      // Told below, in the person's language.
    }
    _MapViewScreenState._showToast(
      loc.translate('unableToMakePhoneCall'),
      Colors.red,
    );
  }

  Future<void> _openWhatsApp(String phoneNumber) async {
    try {
      // wa.me wants the international number as digits only.
      final digits = PhoneInputService.formatForDial(phoneNumber)
          .replaceAll(RegExp(r'[^0-9]'), '');
      final template = loc.translate('whatsAppBusinessMessage').replaceAll(
            '{managerName}',
            loc.translate('propertyManager'),
          );
      final message = Uri.encodeComponent(template);
      final Uri whatsappUri = Uri.parse('https://wa.me/$digits?text=$message');
      if (digits.isNotEmpty && await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {
      // Told below, in the person's language.
    }
    _MapViewScreenState._showToast(
      loc.translate('couldNotOpenWhatsApp'),
      Colors.red,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = phoneNumber != null && phoneNumber!.isNotEmpty;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // WhatsApp button
        Expanded(
          child: Container(
            height: 36, // Reduced from 40
            decoration: BoxDecoration(
              color: hasPhone
                  ? const Color(0xFF25D366).withValues(alpha: 0.1)
                  : colors.onSurface.withValues(alpha: 
                      0.05), // Same gray as phone button when disabled
              borderRadius: BorderRadius.circular(10),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: hasPhone ? () => _openWhatsApp(phoneNumber!) : null,
                borderRadius: BorderRadius.circular(10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      hasPhone ? AppImages.whatsapp : AppImages.whatsAppDisable,
                      width: 22, // Reduced from 20
                      height: 22,
                      color: hasPhone
                          ? null
                          : colors.onSurface.withValues(alpha: 
                              0.3), // Apply gray tint when disabled
                    ),
                    const SizedBox(width: 6),
                    Text(
                      loc.translate('whatsapp'),
                      style: TextStyle(
                        color: hasPhone
                            ? const Color(0xFF25D366)
                            : colors.onSurface.withValues(alpha: 0.3),
                        fontWeight: FontWeight.w600,
                        fontSize: 12, // Reduced from 13
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Phone button
        Expanded(
          child: Container(
            height: 36, // Reduced from 40
            decoration: BoxDecoration(
              color: hasPhone
                  ? colors.primary.withValues(alpha: 0.1)
                  : colors.onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: hasPhone ? () => _makePhoneCall(phoneNumber!) : null,
                borderRadius: BorderRadius.circular(10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      hasPhone
                          ? Icons.phone_rounded
                          : Icons.phone_disabled_rounded,
                      color: hasPhone
                          ? colors.primary
                          : colors.onSurface.withValues(alpha: 0.3),
                      size: 18, // Reduced from 20
                    ),
                    const SizedBox(width: 6),
                    Text(
                      loc.translate('call'),
                      style: TextStyle(
                        color: hasPhone
                            ? colors.primary
                            : colors.onSurface.withValues(alpha: 0.3),
                        fontWeight: FontWeight.w600,
                        fontSize: 12, // Reduced from 13
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
