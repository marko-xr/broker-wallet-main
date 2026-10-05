import 'package:flutter/material.dart';
import 'package:broker_wallet/src/data/models/filter_model.dart';
import 'package:broker_wallet/src/views/Screens/home/search/widgets/search_filter_chips.dart'
    show FilterChips;
import 'package:broker_wallet/src/views/Widgets/home_filter_chips.dart';

/// The Favorites filters: the same compact chips Search and Home have, and the
/// same row Home uses, in which choosing or clearing a chip glides its
/// neighbours instead of making them jump.
///
/// Favorites draws no chip of its own. The size (36 dp, a 48 dp touch target),
/// the pill, the padding, the label, the colours from the theme and the spacing
/// that follows the reading direction all come from [HomeFilterChips], so the
/// three screens cannot drift apart.
class FavoriteFilterChips extends StatelessWidget {
  final List<FilterModel> filters;
  final void Function(int) onToggle;

  const FavoriteFilterChips({
    super.key,
    required this.filters,
    required this.onToggle,
  });

  /// The height the row takes: the touch target at normal text, more when a
  /// large font makes the chips taller. The screen pins the row to a bar this
  /// tall, as Search does.
  static double rowHeightOf(BuildContext context) =>
      FilterChips.rowHeightOf(context);

  @override
  Widget build(BuildContext context) {
    return HomeFilterChips(filters: filters, onToggle: onToggle);
  }
}
