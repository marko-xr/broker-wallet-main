import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:mime/mime.dart' show lookupMimeType;
import 'package:path_provider/path_provider.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/offer_media_url_cache.dart';
import 'package:broker_wallet/src/services/offline_media_service.dart';
import 'package:broker_wallet/src/services/share/share_android_sink.dart';
import 'package:broker_wallet/src/services/share/share_clipboard.dart';
import 'package:broker_wallet/src/services/share/share_flow_controller.dart';
import 'package:broker_wallet/src/services/share/share_labels.dart';
import 'package:broker_wallet/src/services/share/share_launcher.dart';
import 'package:broker_wallet/src/services/share/share_media_fetcher.dart';
import 'package:broker_wallet/src/services/share/share_models.dart';
import 'package:broker_wallet/src/services/share/share_payload.dart';
import 'package:broker_wallet/src/services/share/share_plus_sink.dart';
import 'package:broker_wallet/src/services/share/share_preparer.dart';

/// The app's real share wiring: its one native share sheet, the folder shared
/// files are prepared in, and where private photos and videos are fetched from.
///
/// Everything with a platform behind it lives here, so the rest of the Share
/// code takes its collaborators as arguments and runs without a phone.
abstract final class ShareLive {
  /// The one place a share leaves the app. App-wide, so no screen can open a
  /// second share sheet over the first.
  static final ShareLauncher launcher = ShareLauncher(_transport());

  /// The platform's way of opening the share sheet. The system share (the
  /// `share_plus` plugin) takes everything on every platform; on Android a batch
  /// of two or more photos and videos goes to the app's own native adapter
  /// instead (see [AndroidMediaBatchSink]). This is the only place the platform
  /// is asked.
  static ShareSink _transport() => Platform.isAndroid
      ? AndroidMediaBatchSink(system: const SharePlusSink())
      : const SharePlusSink();

  /// Files prepared for sharing live here, one folder per share, in the
  /// system's temporary directory (never a public or media-store location, so
  /// sharing needs no storage permission).
  static const String _stagingFolder = 'broker_wallet_share';

  static final SharePreparer _preparer = SharePreparer(
    stagingRoot: () async {
      final temporary = await getTemporaryDirectory();
      return Directory(
        '${temporary.path}${Platform.pathSeparator}$_stagingFolder',
      );
    },
  );

  static final ShareMediaFetcher _fetcher = ShareMediaFetcher(
    // What this device already holds for a private photo, found by its durable
    // identity and with no network.
    localPath: (cacheKey) => OfflineMediaService.instance
        .ensureMediaIdCached(cacheKey: cacheKey, url: null),
    // A link from this session that is still safely valid. Memory only.
    cachedLink: (cacheKey) => OfferMediaUrlCache.instance.get(cacheKey)?.url,
  );

  static ShareEngine engine() => ShareEngine(
        preparer: _preparer,
        fetcher: _fetcher,
        launcher: launcher,
        clipboard: const SystemShareClipboard(),
        // Android hands media over in homogeneous batches; the other platforms
        // keep the whole choice and its message in one system share.
        delivery: Platform.isAndroid
            ? ShareDelivery.familyBatches
            : ShareDelivery.wholeSelection,
      );

  /// The words of a message in the language the app is showing.
  static ShareLabels labelsFor(AppLocalizations localizations) {
    final current = localizations.locale.languageCode;
    return ShareLabels(
      languageCode: current,
      lookup: (language, key) =>
          AppLocalizations.translateFor(language, key) ??
          (language == current ? localizations.translate(key) : null),
    );
  }

  /// The rectangle of the widget [context] belongs to, which iPad and Mac
  /// anchor the share sheet to. Falls back to the middle of the screen, which is
  /// valid on every device, when the widget cannot be measured.
  static ShareOrigin? originOf(BuildContext context) {
    if (!context.mounted) return null;
    final object = context.findRenderObject();
    if (object is RenderBox && object.attached && object.hasSize) {
      final size = object.size;
      if (size.width > 0 && size.height > 0) {
        final topLeft = object.localToGlobal(Offset.zero);
        return ShareOrigin(topLeft.dx, topLeft.dy, size.width, size.height);
      }
    }
    final screen = MediaQuery.maybeSizeOf(context);
    if (screen == null) return null;
    return ShareOrigin(screen.width / 2, screen.height / 2, 1, 1);
  }

  /// Shares files that already exist on this phone — the Toolkit's own scans,
  /// PDFs and signed documents — as they are named. Returns null when a share
  /// sheet was already open. Throws a [ShareFailure] when the sheet could not be
  /// opened. A closed sheet is [ShareOutcome.dismissed], not a failure.
  static Future<ShareOutcome?> sendFiles(
    BuildContext context,
    List<String> paths, {
    String? text,
    String? subject,
  }) {
    final origin = originOf(context);
    return launcher.launch(ShareRequest(
      text: text,
      subject: subject,
      origin: origin,
      files: <PreparedShareFile>[
        for (final path in paths)
          PreparedShareFile(
            path: path,
            name: path.split(RegExp(r'[\\/]')).last,
            mimeType: lookupMimeType(path) ?? 'application/octet-stream',
          ),
      ],
    ));
  }

  /// Shares one file under a professional name: the file is copied (or, when
  /// [isTemporary], moved) into the share's own folder as "baseName" plus the
  /// extension its bytes prove, so the receiving app never sees the name of a
  /// private cache file, an id or a random temporary name. Returns null when a
  /// share sheet was already open. Throws a [ShareFailure] when the file cannot
  /// be had or the sheet cannot be opened.
  static Future<ShareOutcome?> sendNamedFile(
    File file, {
    required ShareAttachmentKind kind,
    required String baseName,
    ShareOrigin? origin,
    bool isTemporary = false,
    String? text,
    String? subject,
  }) async {
    final bundle = await _preparer.prepare(<ShareAttachment>[
      ShareAttachment(
        key: 'file',
        kind: kind,
        baseName: baseName,
        fetch: (scratch, cancel) async =>
            FetchedShareFile(file, isTemporary: isTemporary),
      ),
    ], ShareCancelToken());
    try {
      final outcome = await launcher.launch(ShareRequest(
        text: text,
        subject: subject,
        files: bundle.files,
        origin: origin,
      ));
      // Nobody received the file when the sheet was closed or never opened.
      if (outcome == null || outcome == ShareOutcome.dismissed) {
        await bundle.discard();
      }
      return outcome;
    } catch (_) {
      await bundle.discard();
      rethrow;
    }
  }

  /// Shares a message alone.
  static Future<ShareOutcome?> sendText(
    BuildContext context,
    String text, {
    String? subject,
  }) {
    return launcher.launch(ShareRequest(
      text: text,
      subject: subject,
      origin: originOf(context),
    ));
  }
}
