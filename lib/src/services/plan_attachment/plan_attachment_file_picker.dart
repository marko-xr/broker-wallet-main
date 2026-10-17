// The system file picker for a plan: a PDF, a Word file or an image already on
// the phone. It only hands back a file and its name; whether the file is an
// acceptable plan is decided afterwards from its own bytes.

import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_policy.dart';

/// A file the user chose, with the name it has in the picker.
class PickedPlanFile {
  const PickedPlanFile(this.file, this.name);

  final File file;
  final String name;
}

class PlanAttachmentFilePicker {
  const PlanAttachmentFilePicker();

  /// One file, or null when the user cancels.
  Future<PickedPlanFile?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: PlanAttachmentPolicy.pickerExtensions,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.first;
    final path = picked.path;
    if (path == null || path.isEmpty) return null;
    return PickedPlanFile(File(path), picked.name);
  }
}
