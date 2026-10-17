import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:open_filex/open_filex.dart';

import 'package:broker_wallet/src/Views/Screens/ViewDetails/widgets/full_screen_media_viewer.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/pdf_viewer_screen.dart';
import 'package:broker_wallet/src/Views/Widgets/plan_attachment_section.dart'
    show planKindLabel;
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/offer_media_cache_identity.dart'
    show OfferMediaRef;
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_files.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_models.dart';
import 'package:broker_wallet/src/services/plan_attachment/plan_attachment_transport.dart';
import 'package:broker_wallet/src/services/plan_attachment/r2_plan_attachment_service.dart';
import 'package:broker_wallet/src/services/share/share_live.dart';
import 'package:broker_wallet/src/services/share/share_preparer.dart'
    show ShareAttachmentKind;

/// How an attempt to open a local file in another app ended.
enum PlanOpenOutcome { opened, noApp, failed }

/// Opens a local file with the phone's own app for [contentType].
typedef PlanExternalOpener = Future<PlanOpenOutcome> Function(
  String path,
  String contentType,
);

/// The system's own opener. It is only ever given a file this app prepared and
/// verified on this phone, never a link.
Future<PlanOpenOutcome> openPlanWithSystem(
  String path,
  String contentType,
) async {
  try {
    final result = await OpenFilex.open(path, type: contentType);
    switch (result.type) {
      case ResultType.done:
        return PlanOpenOutcome.opened;
      case ResultType.noAppToOpen:
        return PlanOpenOutcome.noApp;
      default:
        return PlanOpenOutcome.failed;
    }
  } catch (_) {
    return PlanOpenOutcome.failed;
  }
}

/// What a person can do with a record's plan from its Details screen.
///
///  * an image opens in the app's full-screen image viewer, from a short-lived
///    signed link held only in memory;
///  * a PDF is downloaded to an app-controlled file and opened in Broker
///    Wallet's own PDF viewer;
///  * a Word file (DOC / DOCX) has no in-app renderer: it is downloaded to an
///    app-controlled file and opened by another app on the phone, if there is
///    one;
///  * sharing sends that same verified local file through the app's one share
///    boundary, never a link, a storage key or an id.
class PlanAttachmentActions {
  PlanAttachmentActions({
    PlanAttachmentTransport? transport,
    PlanAttachmentFiles? files,
    PlanExternalOpener? openExternal,
    DateTime Function()? now,
  })  : _transport = transport ?? R2PlanAttachmentService(),
        _filesOverride = files,
        _openExternal = openExternal ?? openPlanWithSystem,
        _now = now ?? DateTime.now;

  final PlanAttachmentTransport _transport;
  final PlanAttachmentFiles? _filesOverride;
  final PlanExternalOpener _openExternal;
  final DateTime Function() _now;

  late final PlanAttachmentFiles _files =
      _filesOverride ?? PlanAttachmentFiles(transport: _transport);

  /// Opens [plan] of the record [parentId]. Never throws: a failure is one short
  /// localized message.
  Future<void> open(
    BuildContext context, {
    required PlanParent parent,
    required String parentId,
    required PlanAttachmentRef plan,
  }) async {
    final loc = AppLocalizations.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final navigator = Navigator.of(context);
    final title = plan.displayName ?? planKindLabel(loc, plan.kind);
    try {
      switch (plan.kind) {
        case PlanAttachmentKind.image:
          final fresh = await _withFreshLink(parent, parentId, plan);
          if (!context.mounted) return;
          await navigator.push<void>(MaterialPageRoute<void>(
            builder: (_) => FullScreenMediaViewer(
              mediaRefs: <OfferMediaRef>[
                OfferMediaRef(
                  mediaObjectId: fresh.mediaObjectId,
                  cacheKey: null,
                  signedUrl: fresh.signedUrl,
                  displayName: fresh.displayName,
                ),
              ],
              title: title,
              onShareMedia: (_) => unawaited(share(context,
                  parent: parent, parentId: parentId, plan: plan)),
            ),
          ));
        case PlanAttachmentKind.pdf:
          final file = await _files.ensureLocal(
              parent: parent, parentId: parentId, ref: plan);
          if (!context.mounted) return;
          await navigator.push<void>(MaterialPageRoute<void>(
            builder: (_) => PdfViewerScreen(
              localFile: file,
              title: _stem(plan.displayName) ?? title,
            ),
          ));
        case PlanAttachmentKind.word:
          final file = await _files.ensureLocal(
              parent: parent, parentId: parentId, ref: plan);
          final outcome = await _openExternal(file.path, plan.contentType);
          if (outcome == PlanOpenOutcome.noApp) {
            _toast(loc.translate('planAttachmentNoAppToOpen'), errorColor);
          } else if (outcome == PlanOpenOutcome.failed) {
            _toast(loc.translate('planAttachmentOpenFailed'), errorColor);
          }
      }
    } on PlanAttachmentException catch (error) {
      _toast(
        loc.translate(_failureKey(error.failure, 'planAttachmentOpenFailed')),
        errorColor,
      );
    } catch (_) {
      _toast(loc.translate('planAttachmentOpenFailed'), errorColor);
    }
  }

  /// Shares [plan] as the file it is, through the app's one share sheet. Never
  /// throws.
  Future<void> share(
    BuildContext context, {
    required PlanParent parent,
    required String parentId,
    required PlanAttachmentRef plan,
  }) async {
    final loc = AppLocalizations.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    // Read before anything is awaited: it is the box the sheet anchors to on
    // an iPad.
    final origin = ShareLive.originOf(context);
    try {
      final file = await _files.ensureLocal(
          parent: parent, parentId: parentId, ref: plan);
      await ShareLive.sendNamedFile(
        file,
        kind: _shareKind(plan.kind),
        baseName: _stem(plan.displayName) ??
            loc.translate('planAttachmentDefaultName'),
        origin: origin,
      );
    } on PlanAttachmentException catch (error) {
      _toast(
        loc.translate(_failureKey(error.failure, 'planAttachmentShareFailed')),
        errorColor,
      );
    } catch (_) {
      _toast(loc.translate('planAttachmentShareFailed'), errorColor);
    }
  }

  /// [plan] with a read link good for a while: the one it has, or a new one.
  Future<PlanAttachmentRef> _withFreshLink(
    PlanParent parent,
    String parentId,
    PlanAttachmentRef plan,
  ) async {
    if (plan.hasFreshUrl(_now())) return plan;
    final current =
        await _transport.fetchCurrent(parent: parent, parentId: parentId);
    if (current == null ||
        current.mediaObjectId != plan.mediaObjectId ||
        current.signedUrl == null) {
      throw const PlanAttachmentException(
          PlanAttachmentFailure.staleReplacement);
    }
    return current;
  }

  static ShareAttachmentKind _shareKind(PlanAttachmentKind kind) =>
      switch (kind) {
        PlanAttachmentKind.image => ShareAttachmentKind.image,
        PlanAttachmentKind.pdf => ShareAttachmentKind.pdf,
        PlanAttachmentKind.word => ShareAttachmentKind.document,
      };

  /// A file name without its extension, or null when nothing is left.
  static String? _stem(String? name) {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final stem = trimmed.replaceAll(RegExp(r'\.[A-Za-z0-9]{1,5}$'), '').trim();
    return stem.isEmpty ? null : stem;
  }

  static String _failureKey(PlanAttachmentFailure failure, String fallback) =>
      failure == PlanAttachmentFailure.staleReplacement
          ? 'planAttachmentChangedElsewhere'
          : fallback;

  void _toast(String message, Color color) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: color,
      textColor: Colors.white,
    );
  }
}
