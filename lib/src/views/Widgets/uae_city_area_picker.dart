import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/app_control_sizes.dart';

import 'expandable_area_chips.dart';
import 'selectable_chip.dart';

/// Choose a city, then its areas, from the shared UAE catalog.
///
/// With no city chosen it shows the [cities] as chips. Once one is chosen it
/// shows that city as a pill with a clear button, and below it the city's areas
/// in the catalog's priority order through [ExpandableAreaChips]: three rows
/// until "Show more". The look and the interaction are the Request and Offer
/// forms'.
///
/// The host owns the selection. How many areas it may hold is its own data
/// contract: pass [maxSelectedAreas] (3 for Request and Offer, 1 for Owner).
class UaeCityAreaPicker extends StatelessWidget {
  const UaeCityAreaPicker({
    super.key,
    required this.cities,
    required this.selectedCity,
    required this.onCityChanged,
    required this.selectedAreas,
    required this.onToggleArea,
    required this.localization,
    this.maxSelectedAreas = 3,
  });

  /// The cities to offer, in display order.
  final List<String> cities;

  /// The chosen city's name; empty when none is chosen.
  final String selectedCity;

  /// Called with a city's name when it is tapped, and with an empty string when
  /// the chosen city's clear button is tapped.
  final ValueChanged<String> onCityChanged;

  /// The chosen area keys of [selectedCity].
  final List<String> selectedAreas;

  /// Called with an area key to select or deselect it.
  final ValueChanged<String> onToggleArea;

  final AppLocalizations localization;

  final int maxSelectedAreas;

  @override
  Widget build(BuildContext context) {
    if (selectedCity.isEmpty) {
      return Wrap(
        spacing: AppControlSizes.chipSpacing,
        runSpacing: AppControlSizes.chipSpacing,
        children: [
          for (final city in cities)
            SelectableChip(
              key: ValueKey<String>('city-chip-$city'),
              label: localization.translate(UaeAreaCatalog.cityKey(city)),
              isSelected: false,
              onTap: () => onCityChanged(city),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClearableChip(
              key: const ValueKey<String>('city-pill'),
              clearKey: const ValueKey<String>('city-pill-clear'),
              label:
                  localization.translate(UaeAreaCatalog.cityKey(selectedCity)),
              onClear: () => onCityChanged(''),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ExpandableAreaChips(
          city: selectedCity,
          selectedAreas: selectedAreas,
          onToggleArea: onToggleArea,
          localization: localization,
          maxSelectedAreas: maxSelectedAreas,
        ),
      ],
    );
  }
}
