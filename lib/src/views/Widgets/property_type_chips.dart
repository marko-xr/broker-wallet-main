import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/data/owner_property_types.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/app_control_sizes.dart';

import 'selectable_chip.dart';

/// Quick-pick property types for the Owner form, shown above its free-text
/// property-type field.
///
/// The chips are suggestions, not a list the owner must choose from. A tap
/// reports the suggestion's name in the app's current language, for the host to
/// put into its text field; the chip whose name — in either supported language —
/// the field's [value] currently says shows as selected. The text field stays
/// the single source of truth: this widget stores nothing, so custom text shows
/// no chip, clearing the field shows none, and a saved value is never changed.
class PropertyTypeChips extends StatelessWidget {
  const PropertyTypeChips({
    super.key,
    required this.value,
    required this.onSelected,
    required this.localization,
  });

  /// The property-type field's current text.
  final String value;

  /// Called with the tapped suggestion's name, in the current language.
  final ValueChanged<String> onSelected;

  final AppLocalizations localization;

  static const List<String> _languages = <String>['en', 'ar'];

  /// Every name [key] has: the current language's, then each supported one.
  Iterable<String> _labelsOfKey(String key) sync* {
    yield localization.translate(key);
    for (final language in _languages) {
      final text = AppLocalizations.translateFor(language, key);
      if (text != null) yield text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = OwnerPropertyTypes.match(value, labelsOfKey: _labelsOfKey);

    return Wrap(
      spacing: AppControlSizes.chipSpacing,
      runSpacing: AppControlSizes.chipSpacing,
      children: [
        for (final option in OwnerPropertyTypes.options)
          SelectableChip(
            key: ValueKey<String>('property-type-chip-${option.key}'),
            label: localization.translate(option.key),
            isSelected: selected?.key == option.key,
            onTap: () => onSelected(localization.translate(option.key)),
          ),
      ],
    );
  }
}
