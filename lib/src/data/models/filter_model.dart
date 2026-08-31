// lib/src/data/models/filter_model.dart
class FilterModel {
  final String label;
  final String? labelKey; // Translation key
  bool selected;

  FilterModel({required this.label, this.labelKey, this.selected = false});
}
