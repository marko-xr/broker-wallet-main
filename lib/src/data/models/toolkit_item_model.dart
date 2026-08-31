// lib/src/data/models/toolkit_item_model.dart
class ToolkitItemModel {
  final String fileName;
  final String fileType;
  final String date;
  final String avatarAsset;

  ToolkitItemModel({
    required this.fileName,
    required this.fileType,
    required this.date,
    this.avatarAsset = 'assets/icons/Toolkit-Avatar.svg',
  });
}
