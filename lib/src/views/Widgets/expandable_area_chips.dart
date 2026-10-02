import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:broker_wallet/src/common/data/uae_area_catalog.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/app_control_sizes.dart';
import 'package:broker_wallet/src/constants/constants.dart';

import 'selectable_chip.dart';

// The gap between chips. The collapsed layout is planned with it, so it must
// match the [Wrap] spacing used below: both read the one shared value.
const double _chipSpacing = AppControlSizes.chipSpacing;

// Measured widths are rounded up by this much per chip, so the plan can only
// ever be more cautious than the real [Wrap]: the collapsed section never shows
// more rows than asked for, whatever the font or text scale.
const double _measureSlack = 1;

// The tolerance [Wrap] itself applies when deciding whether a chip still fits.
const double _fitTolerance = 1e-10;

/// The city's area chips for the Add Request, Add Offer and Add Owner forms.
///
/// Shows the catalog's most important areas first and, until expanded, only the
/// first [collapsedRowCount] *visual* rows of chips — the number of chips
/// depends on the screen width, the text scale and the language, never on a
/// fixed count. When more areas exist it offers a localized "Show more" /
/// "Show less" toggle. Expanding or collapsing never changes the selection.
///
/// A selected area that the collapsed rows would hide (a saved record's area
/// further down the catalog, or an older picker's key the catalog no longer
/// lists) stays visible: it is shown at the end of the last collapsed row.
///
/// How many areas may be selected belongs to the form's own data, not to the
/// catalog: Request and Offer allow three, Owner one. With [maxSelectedAreas]
/// of 1, selecting another area *replaces* the current one, so no chip is ever
/// disabled; with more, the other chips are disabled once the limit is reached.
/// Either way the host owns the selection and receives every tap.
class ExpandableAreaChips extends StatefulWidget {
  const ExpandableAreaChips({
    super.key,
    required this.city,
    required this.selectedAreas,
    required this.onToggleArea,
    required this.localization,
    this.maxSelectedAreas = 3,
    this.collapsedRowCount = 3,
  });

  /// The selected city's name, as the forms store it (e.g. `Abu Dhabi`).
  final String city;

  /// The selected area keys, in selection order.
  final List<String> selectedAreas;

  /// Called with an area key to select or deselect it.
  final ValueChanged<String> onToggleArea;

  final AppLocalizations localization;

  /// How many areas the form may hold. At 1, any area can be tapped to replace
  /// the selection; above 1, the other areas are disabled once it is reached.
  final int maxSelectedAreas;

  /// How many rows of chips the collapsed section shows.
  final int collapsedRowCount;

  @override
  State<ExpandableAreaChips> createState() => _ExpandableAreaChipsState();
}

class _ExpandableAreaChipsState extends State<ExpandableAreaChips> {
  bool _expanded = false;

  @override
  void didUpdateWidget(ExpandableAreaChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different city starts collapsed again, with its own priority areas.
    if (oldWidget.city != widget.city) _expanded = false;
  }

  String _labelOf(String key) {
    final text = widget.localization.translate(key);
    // An unknown stored value (free text from an older record) shows as is.
    return text == '** $key not found' ? key : text;
  }

  @override
  Widget build(BuildContext context) {
    final catalogAreas = UaeAreaCatalog.areasFor(widget.city);
    final selected = widget.selectedAreas;

    // A saved selection the catalog does not list must still be shown.
    final listed = catalogAreas.toSet();
    final unlisted = <String>[];
    for (final key in selected) {
      if (!listed.contains(key) && !unlisted.contains(key)) unlisted.add(key);
    }
    final areas = <String>[...catalogAreas, ...unlisted];
    if (areas.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final allIndexes = List<int>.generate(areas.length, (i) => i);

        var collapsed = allIndexes;
        if (maxWidth.isFinite && widget.collapsedRowCount > 0) {
          final measure = _chipWidthMeasurer(context, maxWidth);
          final widths = List<double?>.filled(areas.length, null);
          collapsed = planCollapsedAreaChips(
            count: areas.length,
            widthOf: (i) => widths[i] ??= measure(_labelOf(areas[i])),
            selected: {
              for (var i = 0; i < areas.length; i++)
                if (selected.contains(areas[i])) i,
            },
            maxWidth: maxWidth,
            spacing: _chipSpacing,
            maxRows: widget.collapsedRowCount,
          );
        }
        final canExpand = collapsed.length < areas.length;
        final shown = _expanded ? allIndexes : collapsed;
        final theme = Theme.of(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: _chipSpacing,
              runSpacing: _chipSpacing,
              children: [
                for (final i in shown)
                  SelectableChip(
                    key: ValueKey<String>('area-chip-${areas[i]}'),
                    label: _labelOf(areas[i]),
                    isSelected: selected.contains(areas[i]),
                    isEnabled: widget.maxSelectedAreas == 1 ||
                        selected.length < widget.maxSelectedAreas ||
                        selected.contains(areas[i]),
                    onTap: () => widget.onToggleArea(areas[i]),
                  ),
              ],
            ),
            if (canExpand)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Semantics(
                  button: true,
                  child: GestureDetector(
                    key: const ValueKey<String>('area-chips-toggle'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _expanded = !_expanded),
                    // A compact inline action: at least the shared compact
                    // height to tap, with the label centred in it.
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: AppControlSizes.compactButtonHeight,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(2, 0, 8, 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.localization.translate(
                                  _expanded ? 'showLess' : 'showMore'),
                              style: AppTextStyles.chipText.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _expanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              color: theme.colorScheme.primary,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Measures a chip's width exactly as the [Text] inside a [SelectableChip]
  /// will lay it out: same style, text scale, language and available width, on
  /// the one line the chip gives its label (a label wider than the room is
  /// ellipsized, so it can only ever take the whole row).
  double Function(String label) _chipWidthMeasurer(
    BuildContext context,
    double maxWidth,
  ) {
    final defaultStyle = DefaultTextStyle.of(context);
    var style = defaultStyle.style.merge(SelectableChip.textStyle);
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    final heightBehavior = defaultStyle.textHeightBehavior ??
        DefaultTextHeightBehavior.maybeOf(context);

    return (label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
        maxLines: SelectableChip.labelMaxLines,
        ellipsis: '\u2026',
        textWidthBasis: defaultStyle.textWidthBasis,
        textHeightBehavior: heightBehavior,
      )..layout(
          maxWidth: math.max(0.0, maxWidth - SelectableChip.horizontalInset),
        );
      final width =
          painter.width + SelectableChip.horizontalInset + _measureSlack;
      painter.dispose();
      return width;
    };
  }
}

/// Which chips the collapsed section shows, as indexes into the full ordered
/// list.
///
/// Chips flow left to right (or right to left) in [maxRows] rows exactly as a
/// [Wrap] would place them, using [widthOf] and [spacing]. The result is the
/// longest prefix that fits in [maxRows] rows. If an index in [selected] falls
/// outside that prefix, it is kept visible after it, and the prefix shrinks as
/// far as needed so the rows still fit. When every chip fits, all indexes are
/// returned and nothing is hidden.
@visibleForTesting
List<int> planCollapsedAreaChips({
  required int count,
  required double Function(int index) widthOf,
  required Set<int> selected,
  required double maxWidth,
  required double spacing,
  required int maxRows,
}) {
  assert(maxRows >= 1);
  final all = List<int>.generate(count, (i) => i);

  var rows = 0;
  var rowWidth = 0.0;
  var fit = count;
  for (var i = 0; i < count; i++) {
    final width = math.min(widthOf(i), maxWidth);
    if (rows == 0) {
      rows = 1;
      rowWidth = width;
    } else if (rowWidth + spacing + width <= maxWidth + _fitTolerance) {
      rowWidth += spacing + width;
    } else if (rows == maxRows) {
      fit = i;
      break;
    } else {
      rows++;
      rowWidth = width;
    }
  }
  if (fit == count) return all;

  final pinnedCandidates = selected.toList()..sort();
  for (var prefix = fit; prefix >= 0; prefix--) {
    final shown = <int>[
      for (var i = 0; i < prefix; i++) i,
      for (final i in pinnedCandidates)
        if (i >= prefix) i,
    ];
    if (prefix == 0 ||
        _rowCount(shown.map(widthOf), maxWidth, spacing) <= maxRows) {
      return shown;
    }
  }
  return const <int>[];
}

/// The number of rows [widths] occupy in a wrapping row of [maxWidth].
int _rowCount(Iterable<double> widths, double maxWidth, double spacing) {
  var rows = 0;
  var rowWidth = 0.0;
  for (final raw in widths) {
    final width = math.min(raw, maxWidth);
    if (rows == 0) {
      rows = 1;
      rowWidth = width;
    } else if (rowWidth + spacing + width <= maxWidth + _fitTolerance) {
      rowWidth += spacing + width;
    } else {
      rows++;
      rowWidth = width;
    }
  }
  return rows;
}
