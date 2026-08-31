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
import 'package:broker_wallet/src/Views/Screens/home/map/map_viewmodel.dart';
import 'package:broker_wallet/src/services/ScreenServices/offer_service.dart';
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
  bool _hasRequestedPermission =
      false; // Track if we've already requested permission

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchLocation(String query, MapViewViewModel vm) async {
    if (query.trim().isEmpty) return;

    try {
      List<Location> locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        Location location = locations.first;
        LatLng searchedLocation = LatLng(location.latitude, location.longitude);

        // Move camera to searched location
        vm.animateToLocation(searchedLocation);

        // Hide keyboard
        FocusScope.of(context).unfocus();

        // Show success toast
        _showToast('Location found!', Colors.green);
      }
    } catch (e) {
      _showToast('Location not found: ${e.toString()}', Colors.red);
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
    try {
      // // Show loading indicator
      // _showToast('Loading...', Colors.blue);

      switch (locationInfo.type) {
        case LocationFilter.offers:
          final offer = await OfferService().getOffer(locationInfo.id);
          if (offer != null && context.mounted) {
            context.push('/offers-details', extra: offer);
          } else if (context.mounted) {
            _showToast('Offer not found', Colors.red);
          }
          break;

        case LocationFilter.owners:
          final owner = await OwnerService().getOwner(locationInfo.id);
          if (owner != null && context.mounted) {
            context.push('/owners-details', extra: owner);
          } else if (context.mounted) {
            _showToast('Owner not found', Colors.red);
          }
          break;

        case LocationFilter.offices:
          final office = await OfficeService().getOffice(locationInfo.id);
          if (office != null && context.mounted) {
            context.push('/offices-details', extra: office);
          } else if (context.mounted) {
            _showToast('Office not found', Colors.red);
          }
          break;

        case LocationFilter.watchmen:
          final watchmen = await WatchmenService().getWatchmen(locationInfo.id);
          if (watchmen != null && context.mounted) {
            context.push('/watchmen-details', extra: watchmen);
          } else if (context.mounted) {
            _showToast('Watchman not found', Colors.red);
          }
          break;

        case LocationFilter.all:
          // Should not happen, but handle gracefully
          _showToast('Please select a specific location', Colors.orange);
          break;
      }
    } catch (e) {
      if (context.mounted) {
        _showToast('Error loading details: ${e.toString()}', Colors.red);
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
          // Request location permission after map loads (only once)
          if (vm.error == null && !_hasRequestedPermission) {
            _hasRequestedPermission = true;
            // Use post-frame callback to avoid calling during build
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                vm.requestLocationPermission(context);
              }
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
                vm.error != null
                    ? Center(
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
                              vm.error!,
                              style: TextStyle(color: colors.error),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: vm.loadLocations,
                              child: Text(localization.translate('retry')),
                            ),
                          ],
                        ),
                      )
                    : GoogleMap(
                        mapType: vm.mapType,
                        initialCameraPosition: vm.initialCameraPosition,
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

                // Floating Filter Chips (full screen width)
                Positioned(
                  top: MediaQuery.of(context).padding.top +
                      80, // Below search bar
                  left: 16, // Full width from left
                  right: 16, // Full width to right
                  child: _FloatingFilterChips(
                    viewModel: vm,
                    localization: localization,
                    colors: colors,
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
                        onPressed: () => vm.moveToCurrentLocation(context),
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
          hintText: localization.translate('searchLocation'),
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

// Floating Filter Chips Widget
class _FloatingFilterChips extends StatefulWidget {
  final MapViewViewModel viewModel;
  final AppLocalizations localization;
  final ColorScheme colors;

  const _FloatingFilterChips({
    required this.viewModel,
    required this.localization,
    required this.colors,
  });

  @override
  State<_FloatingFilterChips> createState() => _FloatingFilterChipsState();
}

class _FloatingFilterChipsState extends State<_FloatingFilterChips> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.colors.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: widget.colors.shadow.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with toggle
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.localization.translate('filterByType'),
                  style: AppTextStyles.sectionLabel.copyWith(fontSize: 14),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!widget.viewModel.selectedFilters
                        .contains(LocationFilter.all))
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: widget.colors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${widget.viewModel.selectedFilters.length} • ${widget.viewModel.currentFilteredCount}',
                          style: TextStyle(
                            color: widget.colors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    GestureDetector(
                      onTap: () => setState(() => _isExpanded = !_isExpanded),
                      child: Icon(
                        _isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: widget.colors.onSurface.withValues(alpha: 0.6),
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Filter chips (collapsible)
          if (_isExpanded)
            Container(
              height: 50,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: widget.localization.translate('all'),
                      icon: Icons.view_list,
                      isSelected:
                          widget.viewModel.isFilterSelected(LocationFilter.all),
                      onTap: () =>
                          widget.viewModel.setFilter(LocationFilter.all),
                      count: widget.viewModel.totalLocationsCount,
                      color: LocationColors.getColor(LocationFilter.all),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: widget.localization.translate('offers'),
                      iconAsset: 'assets/icons/offers-svg.svg',
                      isSelected: widget.viewModel
                          .isFilterSelected(LocationFilter.offers),
                      onTap: () =>
                          widget.viewModel.setFilter(LocationFilter.offers),
                      count: widget.viewModel.offersCount,
                      color: LocationColors.getColor(LocationFilter.offers),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: widget.localization.translate('owners'),
                      iconAsset: 'assets/icons/owners-svg.svg',
                      isSelected: widget.viewModel
                          .isFilterSelected(LocationFilter.owners),
                      onTap: () =>
                          widget.viewModel.setFilter(LocationFilter.owners),
                      count: widget.viewModel.ownersCount,
                      color: LocationColors.getColor(LocationFilter.owners),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: widget.localization.translate('offices'),
                      iconAsset: 'assets/icons/offices-svg.svg',
                      isSelected: widget.viewModel
                          .isFilterSelected(LocationFilter.offices),
                      onTap: () =>
                          widget.viewModel.setFilter(LocationFilter.offices),
                      count: widget.viewModel.officesCount,
                      color: LocationColors.getColor(LocationFilter.offices),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: widget.localization.translate('watchmen'),
                      iconAsset: 'assets/icons/watchman-svg.svg',
                      isSelected: widget.viewModel
                          .isFilterSelected(LocationFilter.watchmen),
                      onTap: () =>
                          widget.viewModel.setFilter(LocationFilter.watchmen),
                      count: widget.viewModel.watchmenCount,
                      color: LocationColors.getColor(LocationFilter.watchmen),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Filter Chip Widget
class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final String? iconAsset;
  final bool isSelected;
  final VoidCallback onTap;
  final int count;
  final Color? color;

  const _FilterChip({
    required this.label,
    this.icon,
    this.iconAsset,
    required this.isSelected,
    required this.onTap,
    required this.count,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final chipColor = color ?? colors.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? chipColor : colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? chipColor : colors.outline.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: chipColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(
                icon!,
                size: 18,
                color: isSelected ? Colors.white : chipColor,
              )
            else if (iconAsset != null)
              SvgPicture.asset(
                iconAsset!,
                width: 18,
                height: 18,
                color: isSelected ? Colors.white : chipColor,
              ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : chipColor,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.2)
                      : chipColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: isSelected ? Colors.white : chipColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Floating Location Carousel (for clustered locations)
class _FloatingLocationCarousel extends StatefulWidget {
  final ClusteredLocationInfo cluster;
  final VoidCallback onClose;
  final AppLocalizations localization;
  final Function(int) onPageChanged;
  final Function(LocationInfo) onItemTap;

  const _FloatingLocationCarousel({
    required this.cluster,
    required this.onClose,
    required this.localization,
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
  final VoidCallback onClose;
  final AppLocalizations localization;
  final VoidCallback onTap;
  final bool showCloseButton;
  final ColorScheme colors;

  const _LocationCarouselCard({
    required this.locationInfo,
    required this.onClose,
    required this.localization,
    required this.onTap,
    required this.showCloseButton,
    required this.colors,
  });

  String _extractAreaAndCity(String fullAddress) {
    if (fullAddress.isEmpty) return '';

    final parts = fullAddress
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (parts.isEmpty) return fullAddress;

    final meaningfulParts = parts.where((part) {
      final lowerPart = part.toLowerCase();
      return !lowerPart.contains('united arab emirates') &&
          !lowerPart.contains('uae') &&
          !lowerPart.contains('emirates') &&
          !lowerPart.contains('street') &&
          !lowerPart.contains('st') &&
          !RegExp(r'^\d+').hasMatch(part) &&
          part.length > 2;
    }).toList();

    if (meaningfulParts.length >= 2) {
      return meaningfulParts.skip(meaningfulParts.length - 2).join(', ');
    } else if (meaningfulParts.length == 1) {
      return meaningfulParts.first;
    }

    if (parts.length >= 2) {
      return parts.skip(parts.length - 2).join(', ');
    }

    return parts.isNotEmpty ? parts.last : fullAddress;
  }

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
                            locationInfo.title,
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
                                    _extractAreaAndCity(locationInfo.address),
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
class _CompactMediaPreview extends StatelessWidget {
  final LocationInfo locationInfo;
  final ColorScheme colors;

  const _CompactMediaPreview({
    required this.locationInfo,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    // Check if media exists
    final hasMedia =
        (locationInfo.mediaUrl != null && locationInfo.mediaUrl!.isNotEmpty) ||
            locationInfo.mediaUrls.isNotEmpty;
    final firstMediaUrl = locationInfo.mediaUrl ??
        (locationInfo.mediaUrls.isNotEmpty
            ? locationInfo.mediaUrls.first
            : null);

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
        child: hasMedia && firstMediaUrl != null
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

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    }
  }

  Future<void> _openWhatsApp(String phoneNumber) async {
    final String message = Uri.encodeComponent('Hello');
    final Uri whatsappUri =
        Uri.parse('https://wa.me/$phoneNumber?text=$message');
    if (await canLaunchUrl(whatsappUri)) {
      await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
    }
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
