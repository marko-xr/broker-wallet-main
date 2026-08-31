// lib/src/data/models/grid_item_model.dart
class GridItemModel {
  final String asset;
  final String label;
  final String? labelKey;
  final int? count;

  GridItemModel(
      {required this.asset, required this.label, this.labelKey, this.count});
}
