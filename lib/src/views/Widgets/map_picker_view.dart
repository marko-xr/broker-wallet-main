import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/clean_location_service.dart';

class MapPickerView extends StatefulWidget {
  final LatLng? initialLocation;
  final String title;
  final MapType? initialMapType;

  const MapPickerView({
    Key? key,
    this.initialLocation,
    required this.title,
    this.initialMapType,
  }) : super(key: key);

  @override
  State<MapPickerView> createState() => _MapPickerViewState();
}

class _MapPickerViewState extends State<MapPickerView> {
  GoogleMapController? _mapController;
  LatLng? _selectedLocation;
  String _selectedAddress = '';
  bool _isLoadingAddress = false;
  bool _isLoadingCurrentLocation = false;
  TextEditingController _searchController = TextEditingController();
  Set<Marker> _markers = {};
  MapType _mapType = MapType.normal;
  final CleanLocationService _locationService = CleanLocationService();

  // Default location (Dubai, UAE)
  static const LatLng _defaultLocation = LatLng(25.2048, 55.2708);

  // Default camera position (Dubai, UAE) - will be overridden if current location is available
  final CameraPosition initialCameraPosition = const CameraPosition(
    target: LatLng(25.2048, 55.2708), // Dubai coordinates
    zoom: 8.0, // Wider zoom level for better overview
  );

  @override
  void initState() {
    super.initState();
    _mapType = widget.initialMapType ?? MapType.normal;

    // Initialize with passed location or get current location
    if (widget.initialLocation != null) {
      _selectedLocation = widget.initialLocation;
      _updateMarker(_selectedLocation!);
      _getAddressFromLatLng(_selectedLocation!);
    } else {
      // Get current location as default
      _getCurrentLocationAsDefault();
    }
  }

  // Get current location as default with clean permission handling
  Future<void> _getCurrentLocationAsDefault() async {
    if (!mounted) return;

    setState(() {
      _isLoadingCurrentLocation = true;
    });

    try {
      // Use CleanLocationService for permission-aware location access
      final position = await _locationService.getCurrentPosition(context);

      if (!mounted) return;

      if (position != null) {
        LatLng currentLocation = LatLng(position.latitude, position.longitude);

        setState(() {
          _selectedLocation = currentLocation;
          _updateMarker(currentLocation);
          _isLoadingCurrentLocation = false;
        });

        _getAddressFromLatLng(currentLocation);

        // Animate to current location with wider zoom once map controller is ready
        if (_mapController != null) {
          _animateToLocation(currentLocation);
        }
      } else {
        // Permission denied or location unavailable, use default location
        setState(() {
          _isLoadingCurrentLocation = false;
        });
        _setDefaultLocation();
      }
    } catch (e) {
      setState(() {
        _isLoadingCurrentLocation = false;
      });
      _setDefaultLocation();
    }
  }

  // Fallback to default Dubai location
  void _setDefaultLocation() {
    if (!mounted) return;

    setState(() {
      _selectedLocation = _defaultLocation;
      _updateMarker(_defaultLocation);
    });
    _getAddressFromLatLng(_defaultLocation);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    // Only animate if we already have a selected location
    // If we're still getting current location, it will be handled in _getCurrentLocationAsDefault
    if (_selectedLocation != null && _mapController != null) {
      _animateToLocation(_selectedLocation!);
    }

    // If we don't have a selected location yet, it means we're getting current location
    // Check if we need to animate to it now that the controller is ready
    if (_selectedLocation == null && _mapController != null) {
      // This will trigger the animation once current location is obtained
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_selectedLocation != null && _mapController != null) {
          _animateToLocation(_selectedLocation!);
        }
      });
    }
  }

  void _onMapTapped(LatLng location) {
    // Dismiss keyboard when user taps on map
    FocusScope.of(context).unfocus();

    if (!mounted) return;

    setState(() {
      _selectedLocation = location;
      _updateMarker(location);
    });
    _getAddressFromLatLng(location);
  }

  void _updateMarker(LatLng location) {
    if (!mounted) return;

    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('selected_location'),
          position: location,
          draggable: true,
          onDragEnd: (LatLng newLocation) {
            if (mounted) {
              setState(() {
                _selectedLocation = newLocation;
              });
              _getAddressFromLatLng(newLocation);
            }
          },
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      };
    });
  }

  Future<void> _getAddressFromLatLng(LatLng location) async {
    if (!mounted) return;

    setState(() {
      _isLoadingAddress = true;
    });

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );

      if (!mounted) return;

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        setState(() {
          _selectedAddress = _formatAddress(place);
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _selectedAddress =
            '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAddress = false;
        });
      }
    }
  }

  // Move to current user location with zoom
  Future<void> moveToCurrentLocation() async {
    try {
      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final currentLocation = LatLng(position.latitude, position.longitude);

      // Animate camera to current location with zoom
      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
              currentLocation, 18.0), // Zoom level 18 for closer street view
        );
      }
    } catch (e) {
      // Show error to user if needed
    }
  }

  String _formatAddress(Placemark place) {
    List<String> addressParts = [];

    if (place.street?.isNotEmpty == true) addressParts.add(place.street!);
    if (place.subLocality?.isNotEmpty == true)
      addressParts.add(place.subLocality!);
    if (place.locality?.isNotEmpty == true) addressParts.add(place.locality!);
    if (place.administrativeArea?.isNotEmpty == true)
      addressParts.add(place.administrativeArea!);
    if (place.country?.isNotEmpty == true) addressParts.add(place.country!);

    return addressParts.join(', ');
  }

  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty) return;

    try {
      List<Location> locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        Location location = locations.first;
        LatLng searchedLocation = LatLng(location.latitude, location.longitude);

        if (!mounted) return;

        setState(() {
          _selectedLocation = searchedLocation;
          _updateMarker(searchedLocation);
        });

        _animateToLocation(searchedLocation); // This will use zoom level 12.0
        _getAddressFromLatLng(searchedLocation);

        // Hide keyboard
        FocusScope.of(context).unfocus();
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

  void _animateToLocation(LatLng location) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: location,
          zoom: 12.0, // Wider zoom level for better overview
        ),
      ),
    );
  }

  void _toggleMapType() {
    if (!mounted) return;

    setState(() {
      _mapType = _mapType == MapType.normal ? MapType.hybrid : MapType.normal;
    });
  }

  void _confirmSelection() {
    if (_selectedLocation != null) {
      Navigator.of(context).pop(_selectedLocation);
    }
  }

  void _clearSelection() {
    if (!mounted) return;

    setState(() {
      _selectedLocation = null;
      _selectedAddress = '';
      _markers.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      resizeToAvoidBottomInset: false, // Prevent keyboard from moving the map
      appBar: AppBar(
        title: Text(
          widget.title,
          style: AppTextStyles.appBarTitle,
        ),
        centerTitle: true,
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: colors.primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Full Screen Map - Takes entire available space
            GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: initialCameraPosition,
              onTap: _onMapTapped,
              markers: _markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: true,
              buildingsEnabled: true,
              mapType: _mapType,
            ),

            // Floating Search Bar - Top Center
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: localization.translate('searchLocation'),
                    hintStyle: AppTextStyles.hintText,
                    prefixIcon: Icon(Icons.search, color: colors.primary),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: colors.outline),
                            onPressed: () {
                              _searchController.clear();
                              FocusScope.of(context).unfocus();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  style: AppTextStyles.bodyText,
                  onSubmitted: _searchLocation,
                  onChanged: (value) => setState(() {}),
                ),
              ),
            ),

            // Floating Instruction Tooltip - Top Left (below search)
            Positioned(
              top: 85,
              left: 70,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.touch_app,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      localization.translate('tapOnTheMapToSelectLocation'),
                      style: AppTextStyles.bodyText.copyWith(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // My Location Button - Top Right (below search)
            Positioned(
              top: 80,
              right: 16,
              child: FloatingActionButton(
                heroTag: 'myLocation',
                mini: true,
                backgroundColor: colors.surface,
                foregroundColor: colors.primary,
                onPressed: moveToCurrentLocation,
                child: Icon(
                  Icons.my_location,
                  size: 20,
                ),
              ),
            ),

            // Map Type Toggle Button - Bottom Right
            Positioned(
              top: 80,
              left: 16,
              child: FloatingActionButton(
                heroTag: 'mapType',
                mini: true,
                backgroundColor: colors.surface,
                foregroundColor: colors.primary,
                onPressed: _toggleMapType,
                child: Icon(
                  _mapType == MapType.hybrid
                      ? Icons.map_outlined
                      : Icons.satellite_alt,
                  color: colors.primary,
                  size: 20,
                ),
                tooltip: _mapType == MapType.hybrid
                    ? localization.translate('normalView')
                    : localization.translate('satelliteView'),
              ),
            ),

            // Floating Bottom Panel
            Positioned(
              left: 16,
              right: 16,
              bottom: 16, // Fixed position - no keyboard offset
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Compact current location button
                      SizedBox(
                        width: double.infinity,
                        height: 44, // Reduced height
                        child: OutlinedButton.icon(
                          onPressed: _isLoadingCurrentLocation
                              ? null
                              : moveToCurrentLocation,
                          icon: _isLoadingCurrentLocation
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colors.primary,
                                  ),
                                )
                              : Icon(Icons.my_location, size: 18),
                          label: Text(
                            localization.translate('useCurrentLocation'),
                            style: TextStyle(
                                fontSize: 14), // Slightly smaller text
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.primary,
                            side: BorderSide(color: colors.primary),
                          ),
                        ),
                      ),

                      // Selected location info - more compact
                      if (_selectedLocation != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10), // Reduced padding
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: colors.primary.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: colors.primary,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    localization.translate('selectedLocation'),
                                    style: AppTextStyles.bodyText.copyWith(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13, // Smaller text
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              if (_isLoadingAddress) ...[
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: colors.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      localization.translate('loadingAddress'),
                                      style: AppTextStyles.bodyText.copyWith(
                                        color: colors.onSurface
                                            .withValues(alpha: 0.7),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                Text(
                                  _selectedAddress.isNotEmpty
                                      ? _selectedAddress
                                      : '${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                                  style: AppTextStyles.bodyText.copyWith(
                                    color:
                                        colors.onSurface.withValues(alpha: 0.8),
                                    fontSize: 12, // Smaller text
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),

                      // Compact action buttons
                      Row(
                        children: [
                          if (_selectedLocation != null) ...[
                            Expanded(
                              child: SizedBox(
                                height: 44, // Consistent button height
                                child: OutlinedButton(
                                  onPressed: _clearSelection,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: colors.outline,
                                    side: BorderSide(color: colors.outline),
                                  ),
                                  child: Text(
                                    localization.translate('clear'),
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: SizedBox(
                              height: 44, // Consistent button height
                              child: ElevatedButton(
                                onPressed: _selectedLocation != null
                                    ? _confirmSelection
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _selectedLocation != null
                                      ? colors.primary
                                      : colors.primary.withValues(alpha: 0.3),
                                ),
                                child: Text(
                                  localization.translate('confirm'),
                                  style: AppTextStyles.buttonText.copyWith(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
