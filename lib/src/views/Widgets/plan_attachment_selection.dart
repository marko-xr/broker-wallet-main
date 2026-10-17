import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;

import 'package:broker_wallet/src/Views/Widgets/plan_attachment_section.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/offer_media_picker.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_file_picker.dart';
import 'package:broker_wallet/src/viewmodels/plan_attachment_form.dart';

/// The "+" of the plan section: the source sheet (Camera, Gallery, Files), the
/// chosen system picker, then the same screening as ever before the file
/// becomes the form's plan. Dismissing the sheet or cancelling a picker changes
/// nothing; a refused file is explained and changes nothing.
///
/// The phone's own camera and the system Photo Picker are used, exactly as for
/// the photo and video gallery: no app-made permission dialog. The plan's
/// pickers are opened with no recovery origin, so if Android stops the app
/// while one is open, what it hands back is not adopted by the gallery form of
/// the same record: a plan is its own attachment and never becomes a gallery
/// item.
///
/// [chooseSource], [mediaPicker] and [filePicker] are for tests.
Future<void> selectPlanAttachment(
  BuildContext context,
  PlanAttachmentFormController controller, {
  Future<PlanAttachmentSource?> Function(BuildContext context)? chooseSource,
  OfferMediaPicker? mediaPicker,
  PlanAttachmentFilePicker? filePicker,
}) async {
  final loc = AppLocalizations.of(context);
  File? picked;
  String? name;
  try {
    final source =
        await (chooseSource ?? showPlanAttachmentSourceSheet)(context);
    if (source == null || !context.mounted) return;
    switch (source) {
      case PlanAttachmentSource.camera:
        picked = await (mediaPicker ?? OfferMediaPicker())
            .capturePhoto(origin: null);
      case PlanAttachmentSource.gallery:
        picked = await (mediaPicker ?? OfferMediaPicker())
            .pickGalleryImage(origin: null);
      case PlanAttachmentSource.files:
        final file =
            await (filePicker ?? const PlanAttachmentFilePicker()).pickFile();
        picked = file?.file;
        name = file?.name;
    }
  } on OfferMediaPickerException catch (error) {
    if (context.mounted) _explainCameraRefusal(context, error.failure);
    return;
  } catch (_) {
    if (context.mounted) {
      _toast(loc.translate('planAttachmentPickerFailed'), Colors.red);
    }
    return;
  }
  if (picked == null) return; // Cancelled in the picker.

  final rejection = await controller.addPicked(picked, displayName: name);
  if (rejection != null && context.mounted) {
    _toast(loc.translate(rejection.messageKey), Colors.red);
  }
}

/// The camera permission was refused: say so in words, and when only the system
/// settings can change it, offer to open them (as the gallery's camera does).
void _explainCameraRefusal(
    BuildContext context, OfferMediaPickerFailure failure) {
  final loc = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (failure == OfferMediaPickerFailure.cameraPermanentlyDenied &&
      messenger != null) {
    messenger.showSnackBar(SnackBar(
      content: Text(loc.translate('cameraPermissionPermanentlyDenied')),
      action: SnackBarAction(
        label: loc.translate('openSettings'),
        onPressed: () => unawaited(openAppSettings()),
      ),
    ));
    return;
  }
  _toast(loc.translate('cameraPermissionDenied'), Colors.red);
}

void _toast(String message, Color color) {
  Fluttertoast.showToast(
    msg: message,
    toastLength: Toast.LENGTH_SHORT,
    gravity: ToastGravity.BOTTOM,
    timeInSecForIosWeb: 1,
    backgroundColor: color,
    textColor: Colors.white,
  );
}
