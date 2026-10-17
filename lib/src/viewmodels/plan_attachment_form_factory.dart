// The standard wiring of a plan form: the Media Worker client, the upload
// workflow and the gallery's own HEIC-to-JPEG converter. Kept apart from
// [PlanAttachmentFormController] so the controller itself depends only on its
// seams and can be exercised without a phone.

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:broker_wallet/src/services/offer_media_selection.dart'
    show HeifToJpegConverter;
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_screening.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_transport.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_workflow.dart';
import 'package:broker_wallet/src/services/plan_attachment/r2_plan_attachment_service.dart';
import 'package:broker_wallet/src/viewmodels/plan_attachment_form.dart';

/// Screening with the gallery's own HEIC-to-JPEG converter, so no plan image
/// depends on a platform being able to decode HEIF.
Future<PlanAttachmentScreening> _defaultScreen(
  File picked, {
  String? displayName,
}) =>
    screenPlanFile(
      picked,
      displayName: displayName,
      convertHeif: HeifToJpegConverter.toJpeg,
    );

/// A plan form for [parent]'s Add/Edit screen.
///
/// [transport] and [screen] are for tests; the app passes neither.
PlanAttachmentFormController createPlanAttachmentForm({
  required PlanParent parent,
  required VoidCallback onChanged,
  PlanAttachmentTransport? transport,
  PlanFileScreener? screen,
}) {
  final resolved = transport ?? R2PlanAttachmentService();
  return PlanAttachmentFormController(
    parent: parent,
    transport: resolved,
    workflow: PlanAttachmentWorkflow(resolved),
    screen: screen ?? _defaultScreen,
    onChanged: onChanged,
  );
}
