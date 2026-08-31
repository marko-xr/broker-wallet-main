import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:broker_wallet/src/Views/Widgets/map_picker_view.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/constants.dart';

// Abstract interface for ViewModels that support location
abstract class LocationCapableViewModel {
  bool get hasSelectedLocation;
  bool get isLocationLoading => false;
  LatLng? get selectedLocation;
  Future<void> setSelectedLocation(LatLng location, BuildContext context);
}

class PickUpInputWidget extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String hint;
  final AppLocalizations localization;
  final LocationCapableViewModel?
      viewModel; // Optional ViewModel for location features

  const PickUpInputWidget({
    required this.value,
    required this.onChanged,
    required this.hint,
    required this.localization,
    this.viewModel,
  });

  @override
  State<PickUpInputWidget> createState() => _PickUpInputWidgetState();
}

class _PickUpInputWidgetState extends State<PickUpInputWidget> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(PickUpInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final vm = widget.viewModel;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: vm?.hasSelectedLocation == true
            ? Border.all(color: colors.primary, width: 1.5)
            : null,
      ),
      child: Column(
        children: [
          // Text input row
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(
                  vm?.hasSelectedLocation == true
                      ? Icons.location_on
                      : Icons.location_on_outlined,
                  color: vm?.hasSelectedLocation == true
                      ? colors.primary
                      : const Color(0xFF8B959A),
                  size: 25,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    readOnly: true, // Make the text field read-only
                    enableInteractiveSelection: false, // Disable text selection
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: widget.hint,
                      hintStyle: AppTextStyles.hintText,
                    ),
                    style: AppTextStyles.bodyText,
                    // Remove onChanged since field is now read-only
                    onTap: vm != null
                        ? () => _openMapPicker(context, vm)
                        : null, // Open map when tapped
                  ),
                ),

                // Map button - only show if viewModel is provided
                if (vm != null) ...[
                  Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: vm.hasSelectedLocation
                          ? Color.fromARGB(
                              (0.1 * 255).round(),
                              colors.primary.red,
                              colors.primary.green,
                              colors.primary.blue)
                          : Color.fromARGB(
                              (0.05 * 255).round(),
                              colors.primary.red,
                              colors.primary.green,
                              colors.primary.blue),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: vm.hasSelectedLocation
                            ? colors.primary
                            : Color.fromARGB(
                                (0.3 * 255).round(),
                                colors.primary.red,
                                colors.primary.green,
                                colors.primary.blue),
                      ),
                    ),
                    child: TextButton.icon(
                      onPressed: vm.isLocationLoading
                          ? null
                          : () => _openMapPicker(context, vm),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: Size.zero,
                      ),
                      icon: vm.isLocationLoading
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.primary,
                              ),
                            )
                          : Icon(
                              vm.hasSelectedLocation
                                  ? Icons.edit_location
                                  : Icons.map,
                              size: 18,
                            ),
                      label: Text(
                        vm.hasSelectedLocation
                            ? widget.localization.translate('edit')
                            : widget.localization.translate('map'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Selected location indicator
          if (vm?.hasSelectedLocation == true) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Color.fromARGB(
                      (0.05 * 255).round(),
                      colors.primary.red,
                      colors.primary.green,
                      colors.primary.blue),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Color.fromARGB(
                        (0.2 * 255).round(),
                        colors.primary.red,
                        colors.primary.green,
                        colors.primary.blue),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.localization.translate('locationSelected'),
                            style: AppTextStyles.bodyText.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            vm?.selectedLocation != null
                                ? '${vm!.selectedLocation!.latitude.toStringAsFixed(6)}, ${vm.selectedLocation!.longitude.toStringAsFixed(6)}'
                                : '',
                            style: AppTextStyles.bodyText.copyWith(
                              color: Color.fromARGB(
                                  (0.7 * 255).round(),
                                  colors.onSurface.red,
                                  colors.onSurface.green,
                                  colors.onSurface.blue),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openMapPicker(
      BuildContext context, LocationCapableViewModel vm) async {
    final selectedLocation = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (context) => MapPickerView(
          initialLocation: vm.selectedLocation,
          title: widget.localization.translate('selectPickupLocation'),
        ),
      ),
    );

    if (selectedLocation != null) {
      await vm.setSelectedLocation(selectedLocation, context);
    }
  }
}
