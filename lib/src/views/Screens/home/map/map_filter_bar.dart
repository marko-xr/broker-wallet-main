import 'package:broker_wallet/src/Views/Screens/home/map/map_viewmodel.dart';
import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/location_colors.dart';
import 'package:broker_wallet/src/services/map_filter.dart';
import 'package:broker_wallet/src/services/map_filter_controller.dart';
import 'package:broker_wallet/src/services/map_layer_controls.dart';
import 'package:broker_wallet/src/services/map_location_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart' show NumberFormat;

/// The map's filters, in one compact row that scrolls sideways. The row is
/// contextual to the layer that is chosen (`MapLayerControls`): Layers,
/// Location and Near Me are always there, and the rest only where the kind of
/// place has something to filter by:
///
///  * All Layers, Offices, Watchmen: Layers, Location, Near Me.
///  * Owners: Layers, Location, Near Me, Property Type.
///  * Offers: Layers, Location, Near Me, Rent / Sale, Property Type, Price, Sort.
///
/// A control that is not in the row is not on: the layer's own filters (Rent /
/// Sale, Property Type, Price, Sort) go back to their defaults whenever the layer
/// changes (`MapFilterState.withEntityType`), so a choice never outlives the
/// row that offered it.
///
/// Each control is named for what it is, and a chip shows its own name until
/// something is chosen, then what was chosen:
///
///  * Layers: which kinds of place the map shows (Offers, Owners, Offices,
///    Watchmen). They are layers of the map, not categories of property.
///  * Location: where the map looks: all of the UAE, or one of the catalog's
///    cities (the cities the forms use, not just those that have places). It
///    is the place for the areas and the rest of the geographic scope later.
///  * Near Me: places within 5, 10 or 25 km of the device. A chip of its own: a
///    tap turns it on, and once it is on a tap opens its radius and the way to
///    turn it off.
///  * Rent / Sale and Property Type: what the place is.
///  * Price: inclusive minimum and maximum for Offers.
///  * Sort: how the places are ordered. Today that is by price, lowest or
///    highest first.
///
/// Location and Near Me are two ways of saying where to look, so one replaces
/// the other (`MapFilterState`): choosing a city or All UAE turns Near Me off,
/// and Near Me, once the device has answered, replaces the city.
///
/// Nothing is spread out: each chip opens a list. A filter is optional; the
/// default is everything. Resetting the filters is not in this row (it would
/// scroll out of sight): `MapFilterStatusLine` shows Reset under it, only while
/// a filter is on.
///
/// The chips only say what the person chose. The view model filters the places
/// already loaded, so choosing never reads anything from the backend.
class MapFilterBar extends StatelessWidget {
  const MapFilterBar({
    super.key,
    required this.viewModel,
    required this.localization,
    required this.onMessage,
  });

  final MapViewViewModel viewModel;
  final AppLocalizations localization;

  /// Tells the person something short (why Near Me could not be turned on).
  final void Function(String message) onMessage;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final loc = localization;
    final state = vm.filterState;
    final colors = Theme.of(context).colorScheme;
    final entity = state.entityType;
    final nearby = state.nearby;
    // The controls this layer's row has (Layers, Location and Near Me are in
    // every one).
    bool has(MapFilterControl control) =>
        MapLayerControls.shows(entity, control);

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          // Layers: one chip, whatever the number of kinds.
          _MapFilterChip(
            label: entity == LocationFilter.all
                ? loc.translate('mapFilterLayers')
                : loc.translate(_entityKey(entity)),
            icon: entity == LocationFilter.all ? Icons.layers_rounded : null,
            iconAsset:
                entity == LocationFilter.all ? null : _entityIcon(entity),
            color: entity == LocationFilter.all
                ? colors.primary
                : LocationColors.getColor(entity),
            active: entity != LocationFilter.all,
            dropdown: true,
            onTap: () => _chooseEntity(context),
          ),
          const SizedBox(width: 8),
          // Location: all of the UAE, or one of the cities of the catalog.
          _MapFilterChip(
            label: state.city == null
                ? loc.translate('mapFilterLocation')
                : _cityLabel(state.city!),
            icon: Icons.location_on_rounded,
            color: colors.primary,
            active: state.city != null,
            dropdown: true,
            onTap: () => _chooseLocation(context),
          ),
          const SizedBox(width: 8),
          // Near Me: the places around the device, a chip of its own.
          _MapFilterChip(
            label: nearby == null
                ? loc.translate('mapFilterNearby')
                : loc
                    .translate('mapNearbyActive')
                    .replaceAll('{km}', _number(nearby.radiusKm)),
            icon: Icons.near_me_rounded,
            color: colors.primary,
            active: nearby != null,
            loading: vm.isLocatingNearby,
            onTap: () => _tapNearby(context),
          ),
          // The rest of the row is the layer's own: only the controls its kind
          // of place has. Choosing another layer clears these choices, so one
          // that is not shown here is never on.
          if (has(MapFilterControl.transaction)) ...[
            const SizedBox(width: 8),
            _MapFilterChip(
              label: state.transaction == null
                  ? loc.translate('mapFilterTransaction')
                  : _transactionLabel(state.transaction!),
              icon: Icons.sell_rounded,
              color: colors.primary,
              active: state.transaction != null,
              dropdown: true,
              onTap: () => _chooseTransaction(context),
            ),
          ],
          if (has(MapFilterControl.propertyType)) ...[
            const SizedBox(width: 8),
            _MapFilterChip(
              label: state.propertyType == null
                  ? loc.translate('propertyType')
                  : _label(state.propertyType!),
              icon: Icons.home_work_rounded,
              color: colors.primary,
              active: state.propertyType != null,
              dropdown: true,
              onTap: () => _choosePropertyType(context),
            ),
          ],
          if (has(MapFilterControl.price)) ...[
            const SizedBox(width: 8),
            _MapFilterChip(
              label: _priceLabel(state.priceRange),
              icon: Icons.payments_outlined,
              color: colors.primary,
              active: state.priceRange != null,
              onTap: () => _choosePrice(context),
            ),
          ],
          if (has(MapFilterControl.sort)) ...[
            const SizedBox(width: 8),
            _MapFilterChip(
              label: state.priceMode == MapPriceMode.all
                  ? loc.translate('mapFilterSort')
                  : _sortLabel(state.priceMode),
              icon: Icons.sort_rounded,
              color: colors.primary,
              active: state.priceMode != MapPriceMode.all,
              dropdown: true,
              onTap: () => _chooseSort(context),
            ),
          ],
        ],
      ),
    );
  }

  // ---- words --------------------------------------------------------------

  /// The text of [key], or the key itself when the app has no text for it.
  String _label(String key) {
    final text = localization.translate(key);
    return text.startsWith('** ') ? key : text;
  }

  String _cityLabel(String city) => _label(UaeAreaCatalog.cityKey(city));

  String _transactionLabel(MapTransaction transaction) => localization
      .translate(transaction == MapTransaction.rent ? 'rent' : 'sale');

  /// How the places are ordered: as they are, or by price. The three words say
  /// the order they give; what the order does is [MapFilterEngine]'s.
  String _sortLabel(MapPriceMode mode) {
    switch (mode) {
      case MapPriceMode.all:
        return localization.translate('mapSortDefault');
      case MapPriceMode.lowest:
        return localization.translate('mapSortPriceLowToHigh');
      case MapPriceMode.highest:
        return localization.translate('mapSortPriceHighToLow');
    }
  }

  /// Numbers are written the way the app's language writes them.
  String _number(int value) =>
      NumberFormat.decimalPattern(localization.locale.languageCode)
          .format(value);

  String _km(int km) =>
      localization.translate('mapKmValue').replaceAll('{km}', _number(km));

  String _priceLabel(MapPriceRange? range) {
    if (range == null) return localization.translate('mapFilterPrice');
    final format =
        NumberFormat('#,##0.####################', localization.locale.languageCode);
    if (range.min != null && range.max != null) {
      return localization.translate('mapPriceBetween')
          .replaceAll('{min}', format.format(range.min))
          .replaceAll('{max}', format.format(range.max));
    }
    return range.min != null
        ? localization.translate('mapPriceFrom')
            .replaceAll('{amount}', format.format(range.min))
        : localization.translate('mapPriceUpTo')
            .replaceAll('{amount}', format.format(range.max));
  }

  static String _entityKey(LocationFilter type) {
    switch (type) {
      case LocationFilter.offers:
        return 'offers';
      case LocationFilter.owners:
        return 'owners';
      case LocationFilter.offices:
        return 'offices';
      case LocationFilter.watchmen:
        return 'watchmen';
      case LocationFilter.all:
        return 'all';
    }
  }

  static String _entityIcon(LocationFilter type) {
    switch (type) {
      case LocationFilter.offers:
        return 'assets/icons/offers-svg.svg';
      case LocationFilter.owners:
        return 'assets/icons/owners-svg.svg';
      case LocationFilter.offices:
        return 'assets/icons/offices-svg.svg';
      case LocationFilter.watchmen:
        return 'assets/icons/watchman-svg.svg';
      case LocationFilter.all:
        return 'assets/icons/offers-svg.svg';
    }
  }

  // ---- choosing -----------------------------------------------------------

  /// The Layers list: every kind of place the map shows, or all of them.
  Future<void> _chooseEntity(BuildContext context) async {
    final vm = viewModel;
    final counts = vm.entityCounts;
    final choice = await _showOptions<LocationFilter>(
      context,
      title: localization.translate('mapFilterLayers'),
      selected: vm.filterState.entityType,
      options: [
        _SheetOption(
          value: LocationFilter.all,
          label: localization.translate('all'),
          icon: Icons.layers_rounded,
          color: Theme.of(context).colorScheme.primary,
          trailing: _number(vm.totalLocationsCount),
        ),
        // Exactly the kinds the map shows.
        for (final type in MapEntityTypes.all)
          _SheetOption(
            value: type,
            label: localization.translate(_entityKey(type)),
            iconAsset: _entityIcon(type),
            color: LocationColors.getColor(type),
            trailing: _number(counts[type] ?? 0),
          ),
      ],
    );
    if (choice != null) vm.setEntityType(choice.value ?? LocationFilter.all);
  }

  /// The Location list: all of the UAE, then the cities of the catalog. A city
  /// replaces Near Me (the two are ways of saying where to look, never both),
  /// and so does All UAE, which puts the default back: no city and no Near Me.
  /// The list can be opened while the device is being asked for Near Me, and
  /// either choice then supersedes that request (the late position is ignored).
  Future<void> _chooseLocation(BuildContext context) async {
    final vm = viewModel;

    final chosen = vm.filterState;
    final chosenCity = chosen.city;
    // With Near Me on, the map is neither on a city nor on all of the UAE, so no
    // row is the chosen one.
    final _LocationChoice? current = chosenCity != null
        ? _LocationChoice.city(chosenCity)
        : chosen.nearby != null
            ? null
            : const _LocationChoice.allUae();

    final choice = await _showOptions<_LocationChoice>(
      context,
      title: localization.translate('mapFilterLocation'),
      selected: current,
      options: [
        _SheetOption(
          value: const _LocationChoice.allUae(),
          label: localization.translate('mapAllUae'),
          icon: Icons.public_rounded,
        ),
        for (final city in vm.cityOptions)
          _SheetOption(
            value: _LocationChoice.city(city),
            label: _cityLabel(city),
          ),
      ],
    );

    final picked = choice?.value;
    if (picked == null) return;
    final pickedCity = picked.city;
    if (pickedCity != null) {
      vm.setCity(pickedCity);
    } else {
      vm.setAllUae();
    }
  }

  Future<void> _choosePropertyType(BuildContext context) async {
    final vm = viewModel;
    final choice = await _showOptions<String>(
      context,
      title: localization.translate('propertyType'),
      selected: vm.filterState.propertyType,
      options: [
        _SheetOption(
          value: null,
          label: localization.translate('mapAllPropertyTypes'),
        ),
        for (final key in vm.propertyTypeOptions)
          _SheetOption(value: key, label: _label(key)),
      ],
    );
    if (choice != null) vm.setPropertyType(choice.value);
  }

  Future<void> _chooseTransaction(BuildContext context) async {
    final vm = viewModel;
    final choice = await _showOptions<MapTransaction>(
      context,
      title: localization.translate('mapFilterTransaction'),
      selected: vm.filterState.transaction,
      options: [
        _SheetOption(value: null, label: localization.translate('all')),
        for (final transaction in MapTransaction.values)
          _SheetOption(
            value: transaction,
            label: _transactionLabel(transaction),
          ),
      ],
    );
    if (choice != null) vm.setTransaction(choice.value);
  }

  Future<void> _choosePrice(BuildContext context) async {
    final choice = await showModalBottomSheet<_Choice<MapPriceRange>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _PriceRangeSheet(
        initial: viewModel.filterState.priceRange,
        localization: localization,
      ),
    );
    if (choice != null) viewModel.setPriceRange(choice.value);
  }

  /// One chip, three ways to order the places: as they are (Default), or by
  /// price, lowest or highest first. It orders what is loaded; nothing is read.
  /// Offers without usable prices remain visible after the priced Offers.
  Future<void> _chooseSort(BuildContext context) async {
    final vm = viewModel;
    final choice = await _showOptions<MapPriceMode>(
      context,
      title: localization.translate('mapFilterSort'),
      selected: vm.filterState.priceMode,
      options: [
        for (final mode in MapPriceMode.values)
          _SheetOption(value: mode, label: _sortLabel(mode)),
      ],
    );
    if (choice != null) vm.setPriceMode(choice.value ?? MapPriceMode.all);
  }

  /// Near Me off: turn it on (this chip and the my-location button are the only
  /// places the device is asked where it is, and neither shows a dialog of the
  /// app's own). Near Me on: choose the radius, or turn it off.
  Future<void> _tapNearby(BuildContext context) async {
    final vm = viewModel;
    if (vm.isLocatingNearby) return;

    final nearby = vm.filterState.nearby;
    if (nearby == null) {
      final fix = await vm.enableNearby();
      // Denied, blocked for good, services off or no position: Near Me stays off,
      // a chosen city stays, every place stays on the map, and one short message
      // says why.
      final key = fix == null ? null : nearbyFixMessageKey(fix);
      if (key != null) onMessage(localization.translate(key));
      return;
    }

    const turnOff = 0;
    final choice = await _showOptions<int>(
      context,
      title: localization.translate('mapNearbyRadius'),
      selected: nearby.radiusKm,
      options: [
        for (final km in NearbyFilter.radiusOptionsKm)
          _SheetOption(value: km, label: _km(km)),
        _SheetOption(
          value: turnOff,
          label: localization.translate('mapNearbyTurnOff'),
          icon: Icons.close_rounded,
        ),
      ],
    );
    if (choice == null) return;
    if (choice.value == turnOff) {
      vm.disableNearby();
    } else if (choice.value != null) {
      vm.setNearbyRadius(choice.value!);
    }
  }
}

class _PriceRangeSheet extends StatefulWidget {
  const _PriceRangeSheet({required this.initial, required this.localization});

  final MapPriceRange? initial;
  final AppLocalizations localization;

  @override
  State<_PriceRangeSheet> createState() => _PriceRangeSheetState();
}

class _PriceRangeSheetState extends State<_PriceRangeSheet> {
  late final TextEditingController _min;
  late final TextEditingController _max;
  String? _errorKey;

  String _entry(double? value) => value == null
      ? ''
      : value == value.roundToDouble()
          ? value.toStringAsFixed(0)
          : value.toString();

  @override
  void initState() {
    super.initState();
    _min = TextEditingController(text: _entry(widget.initial?.min));
    _max = TextEditingController(text: _entry(widget.initial?.max));
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _apply() {
    final minText = _min.text.trim();
    final maxText = _max.text.trim();
    final min = minText.isEmpty ? null : MapPriceRange.parseBound(minText);
    final max = maxText.isEmpty ? null : MapPriceRange.parseBound(maxText);
    if ((minText.isNotEmpty && min == null) ||
        (maxText.isNotEmpty && max == null)) {
      setState(() => _errorKey = 'mapPriceInvalid');
      return;
    }
    if (min != null && max != null && min > max) {
      setState(() => _errorKey = 'mapPriceOrder');
      return;
    }
    Navigator.of(context).pop(_Choice<MapPriceRange>(
      MapPriceRange.fromBounds(min: min, max: max),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = widget.localization;
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              loc.translate('mapFilterPrice'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _min,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: loc.translate('mapPriceMinimum'),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() => _errorKey = null),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _max,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _apply(),
                    decoration: InputDecoration(
                      labelText: loc.translate('mapPriceMaximum'),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() => _errorKey = null),
                  ),
                ),
              ],
            ),
            if (_errorKey != null) ...[
              const SizedBox(height: 8),
              Text(
                loc.translate(_errorKey!),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context)
                      .pop(const _Choice<MapPriceRange>(null)),
                  child: Text(loc.translate('mapPriceClear')),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _apply,
                  child: Text(loc.translate('mapPriceApply')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One chip of the bar: the style the map's chips have always had (a rounded
/// pill, the primary colour when chosen), with a small arrow when it opens a
/// list.
class _MapFilterChip extends StatelessWidget {
  const _MapFilterChip({
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
    this.icon,
    this.iconAsset,
    this.dropdown = false,
    this.loading = false,
  });

  final String label;
  final IconData? icon;
  final String? iconAsset;
  final Color color;
  final bool active;
  final bool dropdown;

  /// Shows a small spinner in place of the icon, and cannot be tapped meanwhile
  /// (the device is being asked: Near Me). Location is a chip of its own, so a
  /// city or All UAE can still be chosen, and then supersedes that request.
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = active ? Colors.white : color;

    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        onTap: loading ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? color : colors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? color : colors.outline.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: (active ? color : colors.shadow).withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              else if (icon != null)
                Icon(icon, size: 18, color: foreground)
              else if (iconAsset != null)
                SvgPicture.asset(
                  iconAsset!,
                  width: 18,
                  height: 18,
                  colorFilter: ColorFilter.mode(foreground, BlendMode.srcIn),
                ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              if (dropdown) ...[
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: foreground,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// What the person chose in a list. A null [value] is a real choice ("All
/// property types"), which is why the list's answer is wrapped: dismissing the
/// list answers null, and that changes nothing.
class _Choice<T> {
  const _Choice(this.value);

  final T? value;
}

/// One row of the Location list: all of the UAE, or one city. A city is set, or
/// it is not (all of the UAE).
class _LocationChoice {
  const _LocationChoice.allUae() : city = null;

  const _LocationChoice.city(String this.city);

  final String? city;

  @override
  bool operator ==(Object other) =>
      other is _LocationChoice && other.city == city;

  @override
  int get hashCode => city.hashCode;
}

class _SheetOption<T> {
  const _SheetOption({
    required this.value,
    required this.label,
    this.icon,
    this.iconAsset,
    this.color,
    this.trailing,
  });

  final T? value;
  final String label;
  final IconData? icon;
  final String? iconAsset;
  final Color? color;
  final String? trailing;
}

Future<_Choice<T>?> _showOptions<T>(
  BuildContext context, {
  required String title,
  required List<_SheetOption<T>> options,
  required T? selected,
}) {
  final colors = Theme.of(context).colorScheme;

  return showModalBottomSheet<_Choice<T>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  title,
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  final isSelected = option.value == selected;
                  final accent = option.color ?? colors.primary;
                  return ListTile(
                    selected: isSelected,
                    selectedColor: colors.primary,
                    leading: option.iconAsset != null
                        ? SvgPicture.asset(
                            option.iconAsset!,
                            width: 20,
                            height: 20,
                            colorFilter: ColorFilter.mode(
                              accent,
                              BlendMode.srcIn,
                            ),
                          )
                        : option.icon != null
                            ? Icon(option.icon, size: 20, color: accent)
                            : null,
                    title: Text(option.label),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // The check sits on the label's side of the count, so
                        // the counts stay in one column at the edge whichever
                        // row is chosen (a check outside the count pushed the
                        // chosen row's count out of line).
                        if (isSelected) ...[
                          Icon(Icons.check_rounded, color: colors.primary),
                          if (option.trailing != null) const SizedBox(width: 8),
                        ],
                        if (option.trailing != null)
                          Text(
                            option.trailing!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                    onTap: () => Navigator.of(sheetContext)
                        .pop(_Choice<T>(option.value)),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// Shown over the map when places are loaded and the filter lets none of them
/// through. The map stays visible; this is not a failed load.
class MapNoMatchesBanner extends StatelessWidget {
  const MapNoMatchesBanner({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onClear,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.surface.withValues(alpha: 0.95),
      elevation: 3,
      shadowColor: colors.shadow.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 6, 6),
        child: Row(
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 20,
              color: colors.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton(onPressed: onClear, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
